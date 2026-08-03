import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../support/internal_runtime_test_api.dart';

import 'live_api_cases.dart';

// KG 备用搜索接口真实请求用于验证生产故障切换链路：
// - 默认测试链离线，不访问酷狗旧接口；
// - 需要验证旧接口仍可用时同时设置 RUN_LIVE_API=1 与 LIVE_API_KG_LEGACY=1；
// - 该接口是当前搜索失败回退路径，不属于配置、文件或插件协议兼容，也不阻塞发布构建。
final bool _runKgLegacyLiveSmoke =
    Platform.environment['RUN_LIVE_API'] == '1' &&
    Platform.environment['LIVE_API_KG_LEGACY'] == '1';

void main() {
  test(
    'KG 旧接口真实请求协议兼容性',
    () async {
      final _LegacyLiveConfig config = _LegacyLiveConfig.fromEnvironment();

      final KgRequestExecutorImpl executor = KgRequestExecutorImpl();
      final Stopwatch allStopwatch = Stopwatch()..start();
      final List<LiveApiStepResult> steps = <LiveApiStepResult>[];

      await _runLegacyStep(
        steps: steps,
        step: 'legacy_song',
        action: () {
          return executor.legacySearch(
            keyword: 'アルカテイル',
            searchType: SearchType.song,
            page: 1,
          );
        },
      );
      await _runLegacyStep(
        steps: steps,
        step: 'legacy_songlist',
        action: () {
          return executor.legacySearch(
            keyword: 'Kud Wafter',
            searchType: SearchType.songlist,
            page: 1,
          );
        },
      );

      bool albumSuccess = false;
      for (final String keyword in config.albumKeywords) {
        final LiveApiStepResult step = await _runLegacyStep(
          steps: steps,
          step: 'legacy_album[$keyword]',
          action: () {
            return executor.legacySearch(
              keyword: keyword,
              searchType: SearchType.album,
              page: 1,
            );
          },
        );
        if (step.success) {
          albumSuccess = true;
          break;
        }
      }

      allStopwatch.stop();
      final bool songSuccess = _stepSuccess(steps, 'legacy_song');
      final bool songlistSuccess = _stepSuccess(steps, 'legacy_songlist');
      final bool allSuccess = songSuccess && songlistSuccess && albumSuccess;
      final LiveApiSourceReport report = LiveApiSourceReport(
        source: Source.kg,
        success: allSuccess,
        elapsedMs: allStopwatch.elapsedMilliseconds,
        steps: steps,
      );

      final Map<String, Object?> payload = <String, Object?>{
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'runConfig': <String, Object?>{
          'enabled': config.enabled,
          'albumKeywords': config.albumKeywords,
          'reportPath': config.reportPath,
        },
        'summary': <String, Object?>{
          'success': allSuccess,
          'songSuccess': songSuccess,
          'songlistSuccess': songlistSuccess,
          'albumSuccess': albumSuccess,
          'elapsedMs': allStopwatch.elapsedMilliseconds,
        },
        'source': report.toMap(),
      };
      await _writeReport(path: config.reportPath, payload: payload);
      _printSummary(
        report: report,
        songSuccess: songSuccess,
        songlistSuccess: songlistSuccess,
        albumSuccess: albumSuccess,
        reportPath: config.reportPath,
      );

      if (!songSuccess || !songlistSuccess || !albumSuccess) {
        fail(
          'KG 旧接口冒烟失败：song=$songSuccess, songlist=$songlistSuccess, '
          'album=$albumSuccess；详见 ${config.reportPath}',
        );
      }
    },
    skip: _runKgLegacyLiveSmoke
        ? false
        : '设置 RUN_LIVE_API=1 且 LIVE_API_KG_LEGACY=1 后手动运行 KG 旧接口冒烟测试。',
    tags: 'live',
  );
}

Future<LiveApiStepResult> _runLegacyStep({
  required List<LiveApiStepResult> steps,
  required String step,
  required Future<Map<String, Object?>> Function() action,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  try {
    final Map<String, Object?> data = await action();
    final Map<String, Object?> payload = _asMap(data['data']);
    final List<Object?> items = _asList(payload['info']);
    if (items.isEmpty) {
      throw const _LegacyEmptyResultException('旧接口返回空结果');
    }
    final Map<String, Object?> first = _asMap(items.first);
    final bool hasTitle =
        (first['songname']?.toString().trim().isNotEmpty ?? false) ||
        (first['specialname']?.toString().trim().isNotEmpty ?? false) ||
        (first['albumname']?.toString().trim().isNotEmpty ?? false);
    if (!hasTitle) {
      throw const _LegacyEmptyResultException('旧接口首条缺少标题字段');
    }
    stopwatch.stop();
    final LiveApiStepResult result = LiveApiStepResult(
      step: step,
      success: true,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
    steps.add(result);
    return result;
  } catch (error) {
    stopwatch.stop();
    final LiveApiStepResult result = LiveApiStepResult(
      step: step,
      success: false,
      elapsedMs: stopwatch.elapsedMilliseconds,
      errorCategory: _classifyError(error),
      errorMessage: error.toString(),
    );
    steps.add(result);
    return result;
  }
}

bool _stepSuccess(List<LiveApiStepResult> steps, String name) {
  return steps.any(
    (LiveApiStepResult step) => step.step == name && step.success,
  );
}

Future<void> _writeReport({
  required String path,
  required Map<String, Object?> payload,
}) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
}

void _printSummary({
  required LiveApiSourceReport report,
  required bool songSuccess,
  required bool songlistSuccess,
  required bool albumSuccess,
  required String reportPath,
}) {
  debugPrint('--- kg legacy live summary ---');
  debugPrint('song=$songSuccess songlist=$songlistSuccess album=$albumSuccess');
  for (final LiveApiStepResult step in report.steps) {
    debugPrint(
      '${step.step}: ${step.success ? 'PASS' : 'FAIL'} '
      '(${step.elapsedMs}ms) ${step.errorMessage ?? ''}',
    );
  }
  debugPrint('report=$reportPath');
}

String _classifyError(Object error) {
  if (error is _LegacyEmptyResultException) {
    return 'data';
  }
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return 'network';
  }
  if (error is FormatException) {
    return 'parse';
  }
  return 'business';
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return value.map<String, Object?>(
      (Object? key, Object? value) =>
          MapEntry<String, Object?>(key?.toString() ?? '', value),
    );
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List<dynamic>) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

class _LegacyLiveConfig {
  const _LegacyLiveConfig({
    required this.enabled,
    required this.albumKeywords,
    required this.reportPath,
  });

  final bool enabled;
  final List<String> albumKeywords;
  final String reportPath;

  static _LegacyLiveConfig fromEnvironment() {
    final Map<String, String> env = Platform.environment;
    final bool enabled =
        env['RUN_LIVE_API'] == '1' && env['LIVE_API_KG_LEGACY'] == '1';
    final String rawKeywords =
        env['LIVE_API_KG_LEGACY_ALBUM_KEYWORDS'] ?? 'Taylor Swift,周杰伦,Adele';
    final String reportPath =
        env['LIVE_API_KG_LEGACY_REPORT_PATH'] ??
        'build/live_api_kg_legacy_report.json';
    return _LegacyLiveConfig(
      enabled: enabled,
      albumKeywords: _parseKeywords(rawKeywords),
      reportPath: reportPath,
    );
  }

  static List<String> _parseKeywords(String raw) {
    final List<String> parsed = raw
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    if (parsed.isEmpty) {
      return const <String>['Taylor Swift', '周杰伦', 'Adele'];
    }
    return parsed;
  }
}

class _LegacyEmptyResultException implements Exception {
  const _LegacyEmptyResultException(this.message);

  final String message;

  @override
  String toString() => message;
}
