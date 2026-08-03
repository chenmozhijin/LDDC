import 'dart:io';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('默认工厂只返回稳定端口类型且翻译客户端可幂等关闭', () async {
    final LyricsLocalSourceProvider local = createDefaultLocalLyricsProvider();
    final LocalMatchMediaGateway media = createDefaultLocalMatchMediaGateway();
    final TranslationClient translation = createDefaultTranslationClient(
      optionsResolver: _translationOptions,
    );

    expect(local, isA<LyricsLocalSourceProvider>());
    expect(media, isA<LocalMatchMediaGateway>());
    final Future<void> firstClose = translation.close();
    final Future<void> secondClose = translation.close();
    expect(identical(firstClose, secondClose), isTrue);
    await firstClose;
  });

  test('正式 barrel 不导出 executor、adapter、协议 reader 和具体实现', () {
    final File workspacePath = File(
      'packages/lddc_lyrics_runtime/lib/lddc_lyrics_runtime.dart',
    );
    final File barrelFile = workspacePath.existsSync()
        ? workspacePath
        : File('lib/lddc_lyrics_runtime.dart');
    final String barrel = barrelFile.readAsStringSync();
    for (final String hiddenPath in <String>[
      'json_api_reader.dart',
      'kg_request_executor.dart',
      'bing_request_executor.dart',
      'translate_runtime_cache.dart',
      'persistent_cache_store.dart',
      'local_match_media_gateway.dart',
    ]) {
      expect(barrel, isNot(contains(hiddenPath)), reason: hiddenPath);
    }
  });
}

TranslationOptions _translationOptions() {
  return const TranslationOptions(
    source: TranslateSource.bing,
    targetLang: TranslateTargetLang.simplifiedChinese,
    openAi: OpenAiConfig(
      profile: OpenAiProfile.custom,
      baseUrl: '',
      apiKey: '',
      model: '',
    ),
  );
}
