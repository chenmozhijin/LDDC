import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'lyrics_ui_strings.dart';

/// 把歌词中固定的语言键和时间轴类型转换为当前宿主语言下的展示摘要。
///
/// controller 只保存结构化歌词，避免把 `orig`、`ts` 等内部键提前拼成字符串；
/// 这样宿主切换语言后可以直接重建正确文案，也不会在状态中长期保留重复摘要。
String lyricsLanguageSummaryText({
  required Lyrics lyrics,
  required LyricsUiStrings strings,
}) {
  final List<String> parts = <String>[];
  for (final String key in LyricsLanguageRegistry.previewOrder) {
    final String? dataKey = LyricsLanguageRegistry.resolveDataKey(lyrics, key);
    if (dataKey == null) {
      continue;
    }
    final LyricsType type =
        LyricsLanguageRegistry.resolveType(lyrics, key) ??
        judgeLyricsType(lyrics.data[dataKey]!);
    parts.add(
      strings.text(
        LyricsUiTextKey.languageTypeSummary,
        arguments: LyricsUiTextArguments(
          language: strings.languageLabel(key),
          type: strings.typeLabel(type),
        ),
      ),
    );
  }
  return parts.join(' · ');
}
