import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../translate/translate.dart';
import 'openai_request_executor.dart';
import 'translate_runtime_cache.dart';

/// OpenAI 翻译 provider，对齐Python版 `core/api/translate/openai.py`。
class OpenAiTranslateProvider extends BaseTranslateProvider
    implements OpenAiProgressTranslateProvider {
  factory OpenAiTranslateProvider({
    required TranslateRuntimeCache cache,
    OpenAiRequestExecutor? requestExecutor,
    Future<void> Function()? close,
  }) {
    if (requestExecutor != null) {
      return OpenAiTranslateProvider._(
        requestExecutor: requestExecutor,
        cache: cache,
        close: close ?? _noopClose,
      );
    }
    final OpenAiRequestExecutorImpl executor = OpenAiRequestExecutorImpl();
    return OpenAiTranslateProvider._(
      requestExecutor: executor.execute,
      cache: cache,
      close: close ?? executor.close,
    );
  }

  OpenAiTranslateProvider._({
    required this._requestExecutor,
    required this._cache,
    required this._close,
  });

  static Future<void> _noopClose() async {}

  final OpenAiRequestExecutor _requestExecutor;
  final TranslateRuntimeCache _cache;
  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();

  @override
  TranslateSource get source => TranslateSource.openai;

  @override
  bool isAvailable(TranslationOptions options) {
    final OpenAiConfig openAi = options.openAi;
    return openAi.apiKey.trim().isNotEmpty &&
        openAi.model.trim().isNotEmpty &&
        openAi.baseUrl.trim().isNotEmpty;
  }

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    required TranslationOptions options,
  }) {
    return translateLyricsWithProgress(lyrics, options: options);
  }

  @override
  Future<LyricsData> translateLyricsWithProgress(
    Lyrics lyrics, {
    required TranslationOptions options,
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    if (!isAvailable(options)) {
      throw const LddcTranslateException('OpenAI API不可用。请检查您的配置。');
    }

    final List<String> texts = getOrigLines(lyrics);
    if (texts.isEmpty) {
      return const <LyricsLine>[];
    }

    final String targetLang = _langMap[options.targetLang]!;
    final List<Object?> cacheKey = <Object?>[
      'translate',
      'openai',
      targetLang,
      texts,
      options.openAi.profile.value,
      options.openAi.baseUrl,
      options.openAi.model,
    ];
    final LyricsData? cachedData = _cache.get<LyricsData>(cacheKey);
    if (cachedData != null) {
      return cachedData;
    }
    onOpenAiProgress?.call(
      OpenAiTranslationProgress(
        completedLines: 0,
        totalLines: texts.length,
        isIndeterminate: true,
      ),
    );

    final String origLines = _formatIndexedLyrics(texts);
    final String prompt = _promptTemplate
        .replaceAll('{target_lang}', targetLang)
        .replaceAll('{orig_lines}', origLines);

    try {
      final String content = await _requestExecutor(
        baseUrl: options.openAi.baseUrl,
        apiKey: options.openAi.apiKey,
        model: options.openAi.model,
        profile: options.openAi.profile,
        prompt: prompt,
        totalLines: texts.length,
        onProgress: onOpenAiProgress,
      );
      final List<String> translatedTexts = _parseTranslatedLines(
        _stripCodeFence(content),
        expectedLineCount: texts.length,
      );
      final LyricsData translatedData = textsToData(translatedTexts, lyrics);
      _cache.set<LyricsData>(cacheKey, translatedData);
      return translatedData;
    } on LddcTranslateException {
      rethrow;
    } catch (error) {
      throw LddcTranslateException('OpenAI 翻译失败: $error');
    }
  }

  static String _formatIndexedLyrics(List<String> texts) {
    return List<String>.generate(
      texts.length,
      (int index) =>
          '${(index + 1).toString().padLeft(2, '0')}|${texts[index]}',
      growable: false,
    ).join('\n');
  }

  static String _stripCodeFence(String content) {
    String normalized = content.trim();
    if (normalized.startsWith('```')) {
      final int lineBreak = normalized.indexOf('\n');
      if (lineBreak >= 0) {
        normalized = normalized.substring(lineBreak + 1);
      } else {
        normalized = normalized.substring(3);
      }
    }
    if (normalized.endsWith('```')) {
      normalized = normalized.substring(0, normalized.lastIndexOf('```'));
    }
    return normalized.trim();
  }

  static List<String> _parseTranslatedLines(
    String content, {
    required int expectedLineCount,
  }) {
    final List<String> lines = content
        .split('\n')
        .where((String line) => line.contains('|'))
        .toList(growable: false);
    if (lines.length != expectedLineCount) {
      throw LddcTranslateException(
        '模型输出的行数与输入的行数不匹配, 输入行数: '
        '$expectedLineCount, 输出行数: ${lines.length}',
      );
    }
    return lines
        .map((String line) {
          final int separator = line.indexOf('|');
          if (separator < 0) {
            return '';
          }
          return line.substring(separator + 1);
        })
        .toList(growable: false);
  }

  static const Map<TranslateTargetLang, String> _langMap =
      <TranslateTargetLang, String>{
        TranslateTargetLang.simplifiedChinese: '简体中文',
        TranslateTargetLang.traditionalChinese: '繁体中文',
        TranslateTargetLang.english: 'English',
        TranslateTargetLang.japanese: '日本語',
        TranslateTargetLang.korean: '한국어',
        TranslateTargetLang.spanish: 'Español',
        TranslateTargetLang.french: 'Français',
        TranslateTargetLang.german: 'Deutsch',
        TranslateTargetLang.portuguese: 'Português',
        TranslateTargetLang.russian: 'Русский',
      };

  static const String _promptTemplate =
      'You are a professional lyric translator with exceptional skills in preserving meaning, '
      'rhythm, and emotional nuance.\n'
      'Translate the following lyrics into {target_lang} while maintaining:\n\n'
      '1.  **Semantic Fidelity :** Translate the explicit and implicit meanings with the utmost '
      'accuracy. The core message and intent must be perfectly preserved.\n'
      '2.  **Emotional and Stylistic Consistency :** Retain the original\'s tone '
      '(e.g., melancholic, joyful, sarcastic), imagery, and literary devices. '
      'The translation should evoke the same feelings as the original.\n'
      '3.  **Natural Phrasing :** The translated lyrics must read as natural, idiomatic '
      '{target_lang}. Avoid literal, awkward, or machine-like phrasing. '
      'The goal is clarity and elegance, not necessarily singability.\n'
      '4.  **Contextual Awareness :** Retain proper nouns, specific cultural references, and '
      'unique terms. Only adapt them if they are completely incomprehensible or culturally '
      'inappropriate in the target language.\n\n'
      '**Input Format**\n'
      '```\n'
      '01|Original line 1\n'
      '02|Original line 2\n'
      '...\n'
      '```\n\n'
      '**Requirements**\n'
      '- Translate line-by-line while maintaining original numbering\n'
      '- Output each completed translated line immediately followed by a newline\n'
      '- Never combine or split lines\n'
      '- Keep special symbols/formatting (e.g., ~, *, etc.)\n'
      '- Retain proper nouns/terms unless culturally inappropriate\n'
      '- Output only translated content in specified format\n\n'
      '**Output Format**\n'
      '```\n'
      '01|Translated line 1\n'
      '02|Translated line 2\n'
      '...\n'
      '```\n\n'
      '**Current Task**\n'
      'Translate these lyrics to {target_lang}:\n'
      '```\n'
      '{orig_lines}\n'
      '```\n\n'
      'Begin your translation now, responding ONLY with the formatted translated lyrics.';
}
