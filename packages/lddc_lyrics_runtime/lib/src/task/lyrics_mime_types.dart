import 'package:path/path.dart' as p;

/// 歌词文件的 MIME 类型。
///
/// SAF 的 `createDocument` 需要调用方显式给出 MIME 类型；本地匹配与批量转换共用这一份映射，
/// 避免两处各写一遍（此前本地匹配的持久化实现里有一份私有 switch）。
///
/// **约束：返回的 MIME 不得带"与目标扩展名不同的规范扩展名"。** 原生
/// `DocumentsContract.createDocument( resolver, parent, mimeType, displayName )` 会按 MIME 的规范
/// 扩展名**补全文件名**：真机实测（Redmi K50 / Android 14）把 `.lrc` 报成 `text/plain`（规范扩展名
/// `.txt`）时，新建的目标文档会落成 `c.lrc.txt`——已有同名文件走覆盖分支则不受影响，因此这个坑只在
/// "新建"时出现。所以这里对没有公认歌词 MIME 的扩展名一律给自定义类型（系统不认识即不补扩展名）。
String lyricsMimeTypeForName(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.json':
      // 规范扩展名就是 `.json`，与目标名一致，可以安全使用。
      return 'application/json';
    case '.txt':
      // 同上：`text/plain` 的规范扩展名是 `.txt`，与目标名一致。
      return 'text/plain';
    case '.ass':
    case '.ssa':
      return 'text/x-ssa';
    case '.srt':
      return 'application/x-subrip';
    case '.lrc':
      return 'application/x-lrc';
    default:
      // 未知扩展名：给自定义类型，确保系统不会追加任何扩展名。
      return 'application/x-lddc-lyrics';
  }
}
