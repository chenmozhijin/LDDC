import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  late TranslateRuntimeCache cache;

  setUp(() {
    cache = TranslateRuntimeCache();
  });

  tearDown(() => cache.close());

  group('Translate Providers', () {
    test('BingTranslateProvider 对齐语言映射与时间轴回填', () async {
      String? capturedTarget;
      String? capturedSource;
      List<String>? capturedTexts;
      int requestCalls = 0;
      final BingTranslateProvider provider = BingTranslateProvider(
        cache: cache,
        requestExecutor:
            ({
              required List<String> texts,
              required String targetLang,
              String sourceLang = 'auto',
            }) async {
              requestCalls += 1;
              capturedTarget = targetLang;
              capturedSource = sourceLang;
              capturedTexts = texts;
              return <String>['你好', '世界'];
            },
      );

      final LyricsData translated = await provider.translateLyrics(
        _buildLyrics(),
        options: _buildOptions(
          targetLang: TranslateTargetLang.simplifiedChinese,
        ),
      );

      expect(capturedTarget, 'zh-Hans');
      expect(capturedSource, 'auto');
      expect(capturedTexts, <String>['line-1', 'line-2']);
      expect(translated[0].text, '你好');
      expect(translated[0].startMs, 100);
      expect(translated[0].endMs, 200);
      expect(translated[1].text, '世界');
      expect(translated[1].startMs, 300);
      expect(translated[1].endMs, 400);

      final LyricsData translatedCached = await provider.translateLyrics(
        _buildLyrics(),
        options: _buildOptions(
          targetLang: TranslateTargetLang.simplifiedChinese,
        ),
      );
      expect(translatedCached[0].text, '你好');
      expect(translatedCached[1].text, '世界');
      expect(requestCalls, 1);
    });

    test('GoogleTranslateProvider 对齐语言映射与时间轴回填', () async {
      String? capturedTarget;
      int requestCalls = 0;
      final GoogleTranslateProvider provider = GoogleTranslateProvider(
        cache: cache,
        requestExecutor:
            ({
              required List<String> texts,
              required String targetLang,
              String sourceLang = 'auto',
            }) async {
              requestCalls += 1;
              capturedTarget = targetLang;
              return <String>['一', '二'];
            },
      );

      final LyricsData translated = await provider.translateLyrics(
        _buildLyrics(),
        options: _buildOptions(targetLang: TranslateTargetLang.japanese),
      );

      expect(capturedTarget, 'ja');
      expect(translated[0].text, '一');
      expect(translated[1].text, '二');
      expect(translated[0].startMs, 100);
      expect(translated[1].startMs, 300);

      final LyricsData translatedCached = await provider.translateLyrics(
        _buildLyrics(),
        options: _buildOptions(targetLang: TranslateTargetLang.japanese),
      );
      expect(translatedCached[0].text, '一');
      expect(translatedCached[1].text, '二');
      expect(requestCalls, 1);
    });

    test('OpenAiTranslateProvider isAvailable 与输出解析对齐Python版', () async {
      String? capturedPrompt;
      int requestCalls = 0;
      final OpenAiTranslateProvider provider = OpenAiTranslateProvider(
        cache: cache,
        requestExecutor:
            ({
              required String baseUrl,
              required String apiKey,
              required String model,
              required OpenAiProfile profile,
              required String prompt,
              required int totalLines,
              OpenAiTranslationProgressCallback? onProgress,
            }) async {
              requestCalls += 1;
              capturedPrompt = prompt;
              return '```text\n01|译文1\n02|译文2\n```';
            },
      );

      final TranslationOptions options = _buildOptions(
        source: TranslateSource.openai,
        targetLang: TranslateTargetLang.russian,
        openAiBaseUrl: 'https://api.example.com/v1',
        openAiApiKey: 'sk-demo',
        openAiModel: 'gpt-4o-mini',
      );
      expect(provider.isAvailable(options), isTrue);

      final LyricsData translated = await provider.translateLyrics(
        _buildLyrics(),
        options: options,
      );

      expect(capturedPrompt, isNotNull);
      expect(capturedPrompt!, contains('Translate these lyrics to Русский'));
      expect(capturedPrompt!, contains('01|line-1'));
      expect(capturedPrompt!, contains('02|line-2'));
      expect(translated[0].text, '译文1');
      expect(translated[1].text, '译文2');
      expect(translated[0].startMs, 100);
      expect(translated[1].startMs, 300);

      final LyricsData translatedCached = await provider.translateLyrics(
        _buildLyrics(),
        options: options,
      );
      expect(translatedCached[0].text, '译文1');
      expect(translatedCached[1].text, '译文2');
      expect(requestCalls, 1);

      final TranslationOptions optionsWithNewModel = _buildOptions(
        source: TranslateSource.openai,
        targetLang: TranslateTargetLang.russian,
        openAiBaseUrl: 'https://api.example.com/v1',
        openAiApiKey: 'sk-demo',
        openAiModel: 'gpt-4o',
      );
      await provider.translateLyrics(
        _buildLyrics(),
        options: optionsWithNewModel,
      );
      expect(requestCalls, 2);
    });

    test('OpenAiTranslateProvider 不可用与行数不匹配异常可解释', () async {
      final OpenAiTranslateProvider provider = OpenAiTranslateProvider(
        cache: cache,
        requestExecutor:
            ({
              required String baseUrl,
              required String apiKey,
              required String model,
              required OpenAiProfile profile,
              required String prompt,
              required int totalLines,
              OpenAiTranslationProgressCallback? onProgress,
            }) async {
              return '01|only-one-line';
            },
      );

      final TranslationOptions unavailableOptions = _buildOptions(
        source: TranslateSource.openai,
      );
      expect(provider.isAvailable(unavailableOptions), isFalse);
      await expectLater(
        () => provider.translateLyrics(
          _buildLyrics(),
          options: unavailableOptions,
        ),
        throwsA(isA<LddcTranslateException>()),
      );

      final TranslationOptions availableOptions = _buildOptions(
        source: TranslateSource.openai,
        openAiBaseUrl: 'https://api.example.com/v1',
        openAiApiKey: 'sk-demo',
        openAiModel: 'gpt-4o-mini',
      );
      await expectLater(
        () =>
            provider.translateLyrics(_buildLyrics(), options: availableOptions),
        throwsA(
          isA<LddcTranslateException>().having(
            (LddcTranslateException error) => error.message,
            'message',
            contains('行数与输入的行数不匹配'),
          ),
        ),
      );
    });
  });
}

Lyrics _buildLyrics() {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: 'song'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 100,
          endMs: 200,
          words: const <LyricsWord>[
            LyricsWord(startMs: 100, endMs: 200, text: 'line-1'),
          ],
        ),
        LyricsLine(
          startMs: 300,
          endMs: 400,
          words: const <LyricsWord>[
            LyricsWord(startMs: 300, endMs: 400, text: 'line-2'),
          ],
        ),
      ],
    },
  );
}

TranslationOptions _buildOptions({
  TranslateSource source = TranslateSource.bing,
  TranslateTargetLang targetLang = TranslateTargetLang.simplifiedChinese,
  String openAiBaseUrl = '',
  String openAiApiKey = '',
  String openAiModel = '',
  OpenAiProfile openAiProfile = OpenAiProfile.custom,
}) {
  return TranslationOptions(
    source: source,
    targetLang: targetLang,
    openAi: OpenAiConfig(
      profile: openAiProfile,
      baseUrl: openAiBaseUrl,
      apiKey: openAiApiKey,
      model: openAiModel,
    ),
  );
}
