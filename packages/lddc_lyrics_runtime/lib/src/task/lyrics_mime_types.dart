import 'package:path/path.dart' as p;

/// 歌词文件的 MIME 类型。
///
/// SAF 的 `createDocument` 需要调用方显式给出 MIME 类型；本地匹配与批量转换共用这一份映射，
/// 避免两处各写一遍（此前本地匹配的持久化实现里有一份私有 switch）。
String lyricsMimeTypeForName(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.json':
      return 'application/json';
    case '.ass':
      return 'text/x-ssa';
    case '.srt':
      return 'application/x-subrip';
    default:
      return 'text/plain';
  }
}
