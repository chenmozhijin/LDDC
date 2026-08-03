import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 歌词保存路径模板格式化器。
///
/// 统一处理：
/// - `%<title>/%<artist>/%<id>/%<album>/%<langs>` 占位符替换
/// - 文件名与目录非法字符转义
/// - Windows 盘符前缀保留
/// - `id` 缺失时移除 `(%<id>)` 与 `（%<id>）`
final class LyricsPathTemplateFormatter {
  LyricsPathTemplateFormatter._();

  static const Set<String> _windowsReservedNames = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  /// 构建建议文件名。
  static String buildFileName({
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
  }) {
    return sanitizeFileName(
      _replacePlaceholders(fileNameFormat, songInfo, lyricLangs),
    );
  }

  /// 构建建议保存路径。
  static String buildPath({
    required String folder,
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
  }) {
    final String formattedFolder = sanitizePath(
      _replacePlaceholders(folder, songInfo, lyricLangs).trim(),
    );
    final String fileName = buildFileName(
      fileNameFormat: fileNameFormat,
      songInfo: songInfo,
      lyricLangs: lyricLangs,
    );
    return p.normalize(p.join(formattedFolder, fileName));
  }

  /// 转义目录路径中的非法字符，并保留 Windows 盘符前缀。
  static String sanitizePath(String value) {
    String drivePrefix = '';
    String pathBody = value;
    final RegExpMatch? driveMatch = RegExp(
      r'^[A-Za-z]:[\\/]',
    ).firstMatch(pathBody);
    if (driveMatch != null) {
      // Windows 路径允许小写盘符和正斜杠分隔符。这里只保留盘符前缀，
      // 后续非法字符替换仍会作用在目录主体，避免把 `c:` 改成全角冒号。
      drivePrefix = driveMatch.group(0)!;
      pathBody = pathBody.substring(drivePrefix.length);
    }
    const Map<String, String> replacement = <String, String>{
      ':': '：',
      '*': '＊',
      '?': '？',
      '"': '＂',
      '<': '＜',
      '>': '＞',
      '|': '｜',
      '\n': '',
    };
    replacement.forEach((String oldValue, String newValue) {
      pathBody = pathBody.replaceAll(oldValue, newValue);
    });
    pathBody = _removeControlCharacters(pathBody);
    return '$drivePrefix$pathBody';
  }

  /// 转义文件名中的非法字符。
  static String sanitizeFileName(String value) {
    String output = value;
    const Map<String, String> replacement = <String, String>{
      '/': '／',
      r'\': '＼',
      ':': '：',
      '*': '＊',
      '?': '？',
      '"': '＂',
      '<': '＜',
      '>': '＞',
      '|': '｜',
      '\n': '',
    };
    replacement.forEach((String oldValue, String newValue) {
      output = output.replaceAll(oldValue, newValue);
    });
    output = _removeControlCharacters(output);

    // Windows 不允许文件名以空格或点结尾，也禁止 CON/NUL/COM1 等设备名。
    // 即使当前运行在其他平台，也生成可跨平台移动的文件名，避免同步到 Windows
    // 后无法创建、覆盖或删除。
    output = output.replaceFirstMapped(
      RegExp(r'[. ]+$'),
      (Match match) =>
          match.group(0)!.replaceAll('.', '．').replaceAll(' ', '　'),
    );
    if (output.isEmpty) {
      return '未命名';
    }
    final String stem = output.split('.').first.toUpperCase();
    if (_windowsReservedNames.contains(stem)) {
      output = '＿$output';
    }
    return output;
  }

  static String _replacePlaceholders(
    String text,
    SongInfo info,
    List<String> lyricLangs,
  ) {
    String output = text;
    if ((info.id == null || info.id!.isEmpty) && output.contains('%<id>')) {
      output = output
          .replaceAll(RegExp(r'[ \t]*\(%<id>\)'), '')
          .replaceAll(RegExp(r'[ \t]*（%<id>）'), '');
    }
    final Map<String, String> mapping = <String, String>{
      '%<title>': sanitizeFileName(info.title ?? '?'),
      '%<artist>': sanitizeFileName(
        info.artistText.isNotEmpty ? info.artistText : '?',
      ),
      '%<id>': sanitizeFileName(info.id ?? '?'),
      '%<album>': sanitizeFileName(info.album ?? '?'),
      '%<langs>': sanitizeFileName(lyricLangs.join('-')),
    };
    mapping.forEach((String placeholder, String value) {
      output = output.replaceAll(placeholder, value);
    });
    return output;
  }

  static String _removeControlCharacters(String value) {
    return value.replaceAll(RegExp(r'[\u0000-\u001F]'), '');
  }
}
