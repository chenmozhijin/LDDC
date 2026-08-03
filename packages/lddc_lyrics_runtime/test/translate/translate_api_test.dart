import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:test/test.dart';

void main() {
  group('TranslateApi', () {
    test('init 幂等且只执行一次注册', () async {
      int initCount = 0;
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateApi api = TranslateApi(
        registry: registry,
        optionsResolver: () => _options(TranslateSource.bing),
        initializer: (TranslateRegistry current, _) async {
          initCount += 1;
          current.registerProviders(<TranslateProvider>[
            _FakeTranslateProvider(source: TranslateSource.bing, prefix: 'B'),
            _FakeTranslateProvider(source: TranslateSource.google, prefix: 'G'),
          ]);
        },
      );

      await Future.wait(<Future<void>>[api.init(), api.init(), api.init()]);
      await api.init();

      expect(initCount, 1);
      expect(registry.hasProvider(TranslateSource.bing), isTrue);
      expect(registry.hasProvider(TranslateSource.google), isTrue);
    });

    test('registry.close 释放可关闭 provider 并清空注册表', () async {
      final TranslateRegistry registry = TranslateRegistry();
      final _FakeTranslateProvider provider = _FakeTranslateProvider(
        source: TranslateSource.bing,
        prefix: 'B',
      );
      registry.registerProvider(provider);

      await registry.close();

      expect(provider.closeCalls, 1);
      expect(registry.providers, isEmpty);
    });

    test('重复注册同一翻译源会拒绝覆盖并保留原 provider 所有权', () async {
      final TranslateRegistry registry = TranslateRegistry();
      final _FakeTranslateProvider first = _FakeTranslateProvider(
        source: TranslateSource.bing,
        prefix: 'first',
      );
      final _FakeTranslateProvider duplicate = _FakeTranslateProvider(
        source: TranslateSource.bing,
        prefix: 'duplicate',
      );
      registry.registerProvider(first);

      expect(
        () => registry.registerProvider(duplicate),
        throwsA(isA<LddcTranslateException>()),
      );

      expect(registry.requireProvider(TranslateSource.bing), same(first));
      await registry.close();
      expect(first.closeCalls, 1);
      expect(duplicate.closeCalls, 0);
    });

    test('初始化失败会清除单飞状态并允许重试', () async {
      int attempts = 0;
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateApi api = TranslateApi(
        registry: registry,
        optionsResolver: () => _options(TranslateSource.bing),
        initializer: (TranslateRegistry current, _) async {
          attempts += 1;
          if (attempts == 1) {
            throw StateError('temporary init failure');
          }
          current.registerProvider(
            _FakeTranslateProvider(source: TranslateSource.bing, prefix: 'B'),
          );
        },
      );

      await expectLater(api.init(), throwsStateError);
      await api.init();

      expect(attempts, 2);
      expect(registry.hasProvider(TranslateSource.bing), isTrue);
      await registry.close();
    });

    test('按当前配置源分派翻译，并支持配置热切换', () async {
      TranslationOptions options = _options(TranslateSource.bing);
      final _FakeTranslateProvider bing = _FakeTranslateProvider(
        source: TranslateSource.bing,
        prefix: 'B',
      );
      final _FakeTranslateProvider google = _FakeTranslateProvider(
        source: TranslateSource.google,
        prefix: 'G',
      );
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateApi api = TranslateApi(
        registry: registry,
        optionsResolver: () => options,
        initializer: (TranslateRegistry current, _) async {
          current.registerProviders(<TranslateProvider>[bing, google]);
        },
      );

      final LyricsData first = await api.translateLyrics(_buildLyrics());
      expect(first.length, 2);
      expect(first[0].text, 'B:line-1');
      expect(first[1].text, 'B:line-2');
      expect(bing.calls, 1);
      expect(google.calls, 0);

      options = _options(TranslateSource.google);
      final LyricsData second = await api.translateLyrics(_buildLyrics());
      expect(second.length, 2);
      expect(second[0].text, 'G:line-1');
      expect(second[1].text, 'G:line-2');
      expect(bing.calls, 1);
      expect(google.calls, 1);
    });

    test('provider 不可用时抛出可解释异常', () async {
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateApi api = TranslateApi(
        registry: registry,
        optionsResolver: () => _options(TranslateSource.openai),
        initializer: (TranslateRegistry current, _) async {
          current.registerProvider(
            _FakeTranslateProvider(
              source: TranslateSource.openai,
              prefix: 'O',
              available: false,
            ),
          );
        },
      );

      await expectLater(
        () => api.translateLyrics(_buildLyrics()),
        throwsA(isA<LddcTranslateException>()),
      );
    });

    test('未注册配置对应 provider 时抛出异常', () async {
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateApi api = TranslateApi(
        registry: registry,
        optionsResolver: () => _options(TranslateSource.google),
        initializer: (TranslateRegistry current, _) async {
          current.registerProvider(
            _FakeTranslateProvider(source: TranslateSource.bing, prefix: 'B'),
          );
        },
      );

      await expectLater(
        () => api.translateLyrics(_buildLyrics()),
        throwsA(isA<LddcTranslateException>()),
      );
    });

    test('不同 TranslationClient 的相同缓存键完全隔离', () async {
      int firstRequests = 0;
      int secondRequests = 0;
      TranslateApi buildApi({
        required String translatedText,
        required void Function() onRequest,
      }) {
        return TranslateApi(
          registry: TranslateRegistry(),
          optionsResolver: () => _options(TranslateSource.bing),
          initializer: (TranslateRegistry registry, cache) async {
            registry.registerProvider(
              BingTranslateProvider(
                cache: cache,
                requestExecutor:
                    ({
                      required List<String> texts,
                      required String targetLang,
                      String sourceLang = 'auto',
                    }) async {
                      onRequest();
                      return List<String>.filled(texts.length, translatedText);
                    },
              ),
            );
          },
        );
      }

      final TranslateApi first = buildApi(
        translatedText: 'first',
        onRequest: () => firstRequests += 1,
      );
      final TranslateApi second = buildApi(
        translatedText: 'second',
        onRequest: () => secondRequests += 1,
      );
      addTearDown(first.close);
      addTearDown(second.close);

      expect((await first.translateLyrics(_buildLyrics())).first.text, 'first');
      expect((await first.translateLyrics(_buildLyrics())).first.text, 'first');
      expect(
        (await second.translateLyrics(_buildLyrics())).first.text,
        'second',
      );
      expect(firstRequests, 1);
      expect(secondRequests, 1);
    });

    test('TranslationClient.close 幂等并按 provider 后缓存的顺序释放', () async {
      final TranslateRegistry registry = TranslateRegistry();
      final TranslateRuntimeCache cache = TranslateRuntimeCache();
      final _FakeTranslateProvider provider = _FakeTranslateProvider(
        source: TranslateSource.bing,
        prefix: 'B',
      );
      final TranslateApi api = TranslateApi(
        registry: registry,
        cache: cache,
        optionsResolver: () => _options(TranslateSource.bing),
        initializer: (TranslateRegistry current, _) async {
          current.registerProvider(provider);
        },
      );
      await api.init();
      cache.set<String>(const <Object?>['sentinel'], 'value');

      final Future<void> firstClose = api.close();
      final Future<void> secondClose = api.close();

      expect(identical(firstClose, secondClose), isTrue);
      await firstClose;
      expect(provider.closeCalls, 1);
      expect(
        () => cache.get<String>(const <Object?>['sentinel']),
        throwsStateError,
      );
    });
  });
}

TranslationOptions _options(TranslateSource source) {
  return TranslationOptions(
    source: source,
    targetLang: TranslateTargetLang.simplifiedChinese,
    openAi: const OpenAiConfig(
      profile: OpenAiProfile.custom,
      baseUrl: '',
      apiKey: '',
      model: '',
    ),
  );
}

class _FakeTranslateProvider extends BaseTranslateProvider {
  _FakeTranslateProvider({
    required this.source,
    required this.prefix,
    this.available = true,
  });

  @override
  final TranslateSource source;
  final String prefix;
  final bool available;
  int calls = 0;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  bool isAvailable(TranslationOptions options) => available;

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    required TranslationOptions options,
  }) async {
    calls += 1;
    final List<String> translated = getOrigLines(
      lyrics,
    ).map((String text) => '$prefix:$text').toList(growable: false);
    return textsToData(translated, lyrics);
  }
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
