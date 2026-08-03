import '../models/models.dart';
import 'converter_facade.dart';
import 'lyrics_convert_options.dart';

/// 面向包消费者的歌词转换入口。
///
/// 所有转换仍由唯一的 `convert2` 实现完成；此对象只提供稳定、可注入的能力级 API。
final class LyricsConverter {
  const LyricsConverter();

  String convert({
    required Lyrics lyrics,
    List<String>? langs,
    LyricsFormat format = LyricsFormat.verbatimLrc,
    int offsetMs = 0,
    LyricsConvertOptions? options,
  }) {
    return convert2(
      lyrics: lyrics,
      langs: langs,
      lyricsFormat: format,
      offsetMs: offsetMs,
      options: options,
    );
  }
}
