import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 路径与文件名格式化工具。
///
/// 语义对齐Python版：
/// - `%<title>/%<artist>/%<id>/%<album>/%<langs>` 占位符替换
/// - 非法字符转义
/// - 当 `id` 缺失时移除 `(%<id>)` 与 `（%<id>）`
final class SearchPathFormatter {
  SearchPathFormatter._();

  /// 生成建议文件名（不含目录）。
  static String buildFileName({
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
  }) {
    final _SearchTemplateParts? parts = _splitTemplateExtension(fileNameFormat);
    if (parts == null) {
      return LyricsPathTemplateFormatter.buildFileName(
        fileNameFormat: fileNameFormat,
        songInfo: songInfo,
        lyricLangs: lyricLangs,
      );
    }
    return LyricsSavePlanner.planSearch(
      folder: '',
      fileNameFormat: parts.templateWithoutExtension,
      songInfo: songInfo,
      lyricLangs: lyricLangs,
      lyricsFormat: parts.lyricsFormat,
    ).fileName;
  }

  /// 生成保存路径（不落盘）。
  static String buildSavePath({
    required String folder,
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
  }) {
    final _SearchTemplateParts? parts = _splitTemplateExtension(fileNameFormat);
    if (parts == null) {
      return LyricsPathTemplateFormatter.buildPath(
        folder: folder,
        fileNameFormat: fileNameFormat,
        songInfo: songInfo,
        lyricLangs: lyricLangs,
      );
    }
    return LyricsSavePlanner.planSearch(
      folder: folder,
      fileNameFormat: parts.templateWithoutExtension,
      songInfo: songInfo,
      lyricLangs: lyricLangs,
      lyricsFormat: parts.lyricsFormat,
    ).displayPath;
  }

  static _SearchTemplateParts? _splitTemplateExtension(String template) {
    for (final LyricsFormat format in LyricsFormat.values.reversed) {
      if (template.toLowerCase().endsWith(format.ext)) {
        return _SearchTemplateParts(
          templateWithoutExtension: template.substring(
            0,
            template.length - format.ext.length,
          ),
          lyricsFormat: format,
        );
      }
    }
    return null;
  }
}

class _SearchTemplateParts {
  const _SearchTemplateParts({
    required this.templateWithoutExtension,
    required this.lyricsFormat,
  });

  final String templateWithoutExtension;
  final LyricsFormat lyricsFormat;
}
