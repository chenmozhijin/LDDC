import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../translate/translation_options.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../translate/translation_progress.dart';
import '../json_api_reader.dart';
import 'translate_http_client.dart';
import 'translate_http_client_stub.dart'
    if (dart.library.io) 'translate_http_client_io.dart'
    if (dart.library.html) 'translate_http_client_web.dart'
    as client_factory;

/// OpenAI 文本翻译请求执行器。
typedef OpenAiRequestExecutor =
    Future<String> Function({
      required String baseUrl,
      required String apiKey,
      required String model,
      required OpenAiProfile profile,
      required String prompt,
      required int totalLines,
      OpenAiTranslationProgressCallback? onProgress,
    });

/// OpenAI 请求执行器实现：负责聊天接口请求与响应解包。
class OpenAiRequestExecutorImpl {
  OpenAiRequestExecutorImpl({
    TranslateHttpClient? client,
    this._timeout = const Duration(seconds: 120),
    this._userAgent = 'LDDC-Flutter',
  }) : _client = client ?? client_factory.createDefaultTranslateHttpClient();

  final TranslateHttpClient _client;
  final Duration _timeout;
  final String _userAgent;

  Future<void> close() => _client.close();

  Future<String> execute({
    required String baseUrl,
    required String apiKey,
    required String model,
    required OpenAiProfile profile,
    required String prompt,
    int totalLines = 0,
    OpenAiTranslationProgressCallback? onProgress,
  }) async {
    if (onProgress != null) {
      try {
        return await _executeStream(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          profile: profile,
          prompt: prompt,
          totalLines: totalLines,
          onProgress: onProgress,
        );
      } on UnsupportedError {
        // 当前平台或 HTTP 适配器无法提供真实字节流时回落到普通请求。
        // UI 会继续显示不确定进度，避免用完整响应伪造逐行进度。
        onProgress(
          OpenAiTranslationProgress(
            completedLines: 0,
            totalLines: totalLines,
            isIndeterminate: true,
          ),
        );
      }
    }
    return _executeBuffered(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      profile: profile,
      prompt: prompt,
    );
  }

  Future<String> _executeBuffered({
    required String baseUrl,
    required String apiKey,
    required String model,
    required OpenAiProfile profile,
    required String prompt,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'model': model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': prompt},
      ],
      'stream': false,
    };
    _applyDisableThinkingFields(profile, body);

    final TranslateHttpResponse response = await _client.post(
      uri: _buildEndpoint(baseUrl),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'User-Agent': _userAgent,
        'Accept-Charset': 'utf-8',
        'Accept-Encoding': 'gzip, deflate, br',
      },
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      timeout: _timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LddcTranslateException('OpenAI 翻译请求失败: ${response.statusCode}');
    }

    final Map<String, Object?> payload = asJsonMap(
      decodeJsonBody(
        response.body,
        onParseError: () => const LddcTranslateException('OpenAI 翻译响应解析失败'),
      ),
    );
    final List<Object?> choices = asJsonList(payload['choices']);
    if (choices.isEmpty) {
      throw const LddcTranslateException('OpenAI 翻译响应缺少 choices');
    }
    final Map<String, Object?> message = asJsonMap(
      asJsonMap(choices.first)['message'],
    );
    final String? content = message['content']?.toString();
    if (content == null) {
      throw const LddcTranslateException('OpenAI 翻译响应缺少 content');
    }
    return content;
  }

  Future<String> _executeStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required OpenAiProfile profile,
    required String prompt,
    required int totalLines,
    required OpenAiTranslationProgressCallback onProgress,
  }) async {
    final Map<String, Object?> body = <String, Object?>{
      'model': model,
      'messages': <Map<String, String>>[
        <String, String>{'role': 'user', 'content': prompt},
      ],
      'stream': true,
    };
    _applyDisableThinkingFields(profile, body);

    final response = await _client.postStream(
      uri: _buildEndpoint(baseUrl),
      headers: <String, String>{
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'User-Agent': _userAgent,
        'Accept-Charset': 'utf-8',
        'Accept': 'text/event-stream',
      },
      body: Uint8List.fromList(utf8.encode(jsonEncode(body))),
      timeout: _timeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String bodyText = await _readStreamText(response.body);
      if (_looksLikeStreamUnsupported(response.statusCode, bodyText)) {
        // 只有服务端明确表示流式能力不可用时才回落普通请求。
        // 鉴权、模型名、额度等真实错误必须继续抛出，避免把配置问题伪装成成功。
        throw UnsupportedError('当前端点不支持 OpenAI 流式响应');
      }
      throw LddcTranslateException(
        'OpenAI 流式翻译请求失败: ${response.statusCode}'
        '${bodyText.trim().isEmpty ? '' : ' $bodyText'}',
      );
    }

    final StringBuffer content = StringBuffer();
    int reportedLines = 0;
    await for (final String data in _sseDataEvents(response.body)) {
      if (data.trim() == '[DONE]') {
        break;
      }
      final Object? decoded = jsonDecode(data);
      if (decoded is! Map<String, Object?>) {
        continue;
      }
      final Object? error = decoded['error'];
      if (error != null) {
        throw LddcTranslateException('OpenAI 流式翻译返回错误: $error');
      }
      final List<Object?> choices = asJsonList(decoded['choices']);
      if (choices.isEmpty) {
        continue;
      }
      final Map<String, Object?> choice = asJsonMap(choices.first);
      if (choice['finish_reason'] == 'error') {
        throw const LddcTranslateException('OpenAI 流式翻译被服务端中断');
      }
      final Object? deltaRaw = choice['delta'];
      if (deltaRaw is! Map<String, Object?>) {
        continue;
      }
      final Map<String, Object?> delta = deltaRaw;
      final String? chunk = delta['content']?.toString();
      if (chunk == null || chunk.isEmpty) {
        continue;
      }
      content.write(chunk);
      final int completed = _countCompletedLines(
        content.toString(),
        includeTrailingLine: false,
      ).clamp(0, totalLines);
      if (completed > reportedLines) {
        reportedLines = completed;
        onProgress(
          OpenAiTranslationProgress(
            completedLines: reportedLines,
            totalLines: totalLines,
            isIndeterminate: false,
          ),
        );
      }
    }
    final int finalCompleted = _countCompletedLines(
      content.toString(),
      includeTrailingLine: true,
    ).clamp(0, totalLines);
    if (finalCompleted > reportedLines) {
      onProgress(
        OpenAiTranslationProgress(
          completedLines: finalCompleted,
          totalLines: totalLines,
          isIndeterminate: false,
        ),
      );
    }
    return content.toString();
  }

  static Uri _buildEndpoint(String baseUrl) {
    final String normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$normalized/chat/completions');
  }

  /// 供应商私有字段只由请求执行器维护，宿主设置页不再复制网络协议策略。
  static void _applyDisableThinkingFields(
    OpenAiProfile profile,
    Map<String, Object?> body,
  ) {
    switch (profile) {
      case OpenAiProfile.custom || OpenAiProfile.kimi:
        return;
      case OpenAiProfile.openRouter:
        body['reasoning'] = <String, Object?>{
          'effort': 'none',
          'exclude': true,
        };
      case OpenAiProfile.siliconFlow:
        body['enable_thinking'] = false;
      case OpenAiProfile.deepSeek:
        body['thinking'] = <String, Object?>{'type': 'disabled'};
    }
  }

  static Stream<String> _sseDataEvents(Stream<List<int>> bytes) async* {
    final List<String> dataLines = <String>[];
    await for (final String line
        in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          yield dataLines.join('\n');
          dataLines.clear();
        }
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isNotEmpty) {
      yield dataLines.join('\n');
    }
  }

  static Future<String> _readStreamText(Stream<List<int>> bytes) {
    return utf8.decoder.bind(bytes).join();
  }

  static bool _looksLikeStreamUnsupported(int statusCode, String bodyText) {
    if (statusCode != 400 && statusCode != 404 && statusCode != 422) {
      return false;
    }
    final String normalized = bodyText.toLowerCase();
    return normalized.contains('stream') &&
        (normalized.contains('not support') ||
            normalized.contains('unsupported') ||
            normalized.contains('not implemented') ||
            normalized.contains('sse'));
  }

  static int _countCompletedLines(
    String content, {
    required bool includeTrailingLine,
  }) {
    String normalized = content.trimLeft();
    if (normalized.startsWith('```')) {
      final int lineBreak = normalized.indexOf('\n');
      if (lineBreak < 0) {
        return 0;
      }
      normalized = normalized.substring(lineBreak + 1);
    }
    final List<String> lines = normalized.split('\n');
    if (!includeTrailingLine &&
        normalized.isNotEmpty &&
        !normalized.endsWith('\n')) {
      lines.removeLast();
    }
    return lines
        .where((String line) => RegExp(r'^\s*\d+\|').hasMatch(line))
        .length;
  }
}
