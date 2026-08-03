import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../app_metadata.dart';
import 'app_config.dart';

/// 将 LDDC 宿主配置映射为共享歌词转换库的能力级配置。
extension LyricsConvertOptionsMapper on AppConfig {
  LyricsConvertOptions toLyricsConvertOptions() {
    return LyricsConvertOptions(
      languageOrder: lyrics.langOrder,
      addEndTimestampLine: lyrics.addEndTimestamp,
      millisecondDigits: lyrics.msDigits,
      lastReferenceLineStyle: lyrics.lastRefStyle,
      generatorVersion: kLddcVersion,
    );
  }
}
