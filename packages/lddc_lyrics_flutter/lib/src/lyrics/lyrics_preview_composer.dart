import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 歌词预览生成器：统一收口格式转换与有效语言筛选。
final class LyricsPreviewComposer {
  const LyricsPreviewComposer._();

  static String buildPreviewText({
    required Lyrics lyrics,
    required List<String> selectedLangs,
    required LyricsFormat lyricsFormat,
    required int offsetMs,
    required LyricsConvertOptions options,
  }) {
    final List<String> langs =
        LyricsLanguageRegistry.normalizeTokenList(selectedLangs)
            .where((String lang) {
              return LyricsLanguageRegistry.resolveDataKey(lyrics, lang) !=
                  null;
            })
            .toList(growable: false);
    if (langs.isEmpty) {
      return '';
    }
    return convert2(
      lyrics: lyrics,
      langs: langs,
      lyricsFormat: lyricsFormat,
      offsetMs: offsetMs,
      options: options,
    );
  }
}
