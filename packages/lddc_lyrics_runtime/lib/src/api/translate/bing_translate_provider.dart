import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../translate/translate.dart';
import 'bing_request_executor.dart';
import 'translate_runtime_cache.dart';

/// Bing 翻译 provider，对齐Python版 `core/api/translate/bing.py`。
class BingTranslateProvider extends BaseTranslateProvider {
  factory BingTranslateProvider({
    required TranslateRuntimeCache cache,
    BingRequestExecutor? requestExecutor,
    Future<void> Function()? close,
  }) {
    if (requestExecutor != null) {
      return BingTranslateProvider._(
        requestExecutor: requestExecutor,
        cache: cache,
        close: close ?? _noopClose,
      );
    }
    final BingRequestExecutorImpl executor = BingRequestExecutorImpl();
    return BingTranslateProvider._(
      requestExecutor: executor.execute,
      cache: cache,
      close: close ?? executor.close,
    );
  }

  BingTranslateProvider._({
    required this._requestExecutor,
    required this._cache,
    required this._close,
  });

  static Future<void> _noopClose() async {}

  final BingRequestExecutor _requestExecutor;
  final TranslateRuntimeCache _cache;
  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();

  @override
  TranslateSource get source => TranslateSource.bing;

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    required TranslationOptions options,
  }) async {
    final List<String> texts = getOrigLines(lyrics);
    if (texts.isEmpty) {
      return const <LyricsLine>[];
    }

    final String targetLang = _langMap[options.targetLang]!;
    final List<Object?> cacheKey = <Object?>[
      'translate',
      'bing',
      'auto',
      targetLang,
      texts,
    ];
    final List<String>? cachedTexts = _cache.get<List<String>>(cacheKey);
    if (cachedTexts != null) {
      return textsToData(cachedTexts, lyrics);
    }

    try {
      final List<String> translated = await _requestExecutor(
        texts: texts,
        targetLang: targetLang,
      );
      _cache.set<List<String>>(cacheKey, translated);
      return textsToData(translated, lyrics);
    } on LddcTranslateException {
      rethrow;
    } catch (error) {
      throw LddcTranslateException('Bing 翻译失败: $error');
    }
  }

  static const Map<TranslateTargetLang, String> _langMap =
      <TranslateTargetLang, String>{
        TranslateTargetLang.simplifiedChinese: 'zh-Hans',
        TranslateTargetLang.traditionalChinese: 'zh-Hant',
        TranslateTargetLang.english: 'en',
        TranslateTargetLang.japanese: 'ja',
        TranslateTargetLang.korean: 'ko',
        TranslateTargetLang.spanish: 'es',
        TranslateTargetLang.french: 'fr',
        TranslateTargetLang.german: 'de',
        TranslateTargetLang.portuguese: 'pt',
        TranslateTargetLang.russian: 'ru',
      };
}
