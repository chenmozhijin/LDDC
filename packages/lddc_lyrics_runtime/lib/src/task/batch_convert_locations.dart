import 'package:path/path.dart' as p;

import 'android_saf_save_paths.dart';

/// 批量转换的**读源**：本地文件路径，或 Android SAF 授权树内的文档。
///
/// 安卓端"从 SAF 目录树导入"之后，源不再是文件系统路径而是 `content://` 文档 URI；读取必须由
/// 平台层走 `AndroidSafContentPort`，因此这里把两类源做成显式类型，禁止把 URI 交给 `dart:io`。
sealed class BatchConvertSource {
  const BatchConvertSource();

  /// 进度提示与日志用的可读名（不含编码 URI）。
  String get displayName;

  /// 交给解析器做扩展名路由的路径提示。
  ///
  /// SAF 文档没有文件系统路径，用可读名（含扩展名）即可让同一套解析入口继续工作。
  String get parserPath;
}

/// 本地文件系统上的源（桌面端；安卓端未选树时导入的插件缓存副本）。
final class LocalFileSource extends BatchConvertSource {
  const LocalFileSource(this.path);

  final String path;

  @override
  String get displayName => p.basename(path);

  @override
  String get parserPath => path;

  @override
  bool operator ==(Object other) =>
      other is LocalFileSource && other.path == path;

  @override
  int get hashCode => Object.hash('local', path);
}

/// SAF 授权树内的文档源。
///
/// 必须同时携带 [documentUri] 与 [treeUri]：保存到"镜像"位置时，树内相对目录层级要靠
/// 文档 id 与树文档 id 反推（见 [resolveAndroidSafSaveTarget]），缺任一个都无法推导。
final class SafDocumentSource extends BatchConvertSource {
  const SafDocumentSource({
    required this.documentUri,
    required this.treeUri,
    required this.treeLabel,
    required this.displayPath,
  });

  /// 文档 URI（读取内容用）。
  final String documentUri;

  /// 该文档所属的授权树 URI（推导树内相对目录用）。
  final String treeUri;

  /// 树显示名，可读落点的第一段。
  final String treeLabel;

  /// 扫描阶段算好的可读落点，例如 `内部存储 / Album / a.lrc`。
  final String displayPath;

  @override
  String get displayName => p.basename(displayPath);

  @override
  String get parserPath => displayName;

  @override
  bool operator ==(Object other) =>
      other is SafDocumentSource && other.documentUri == documentUri;

  @override
  int get hashCode => Object.hash('saf', documentUri);
}

/// 批量转换的**写目标**：本地文件路径，或 SAF 授权树内的新文档。
sealed class BatchConvertTarget {
  const BatchConvertTarget();

  /// 启动前预检"目标是否已存在"所需的信息；本地目标直接用路径，SAF 目标用树 + 目录层级 + 文件名。
  String get fileName;
}

/// 写到本地文件系统路径（桌面端；安卓端未选择保存树时写到缓存副本旁）。
final class LocalFileTarget extends BatchConvertTarget {
  const LocalFileTarget(this.path);

  final String path;

  /// 写到哪个具体文件（含扩展名）。
  String get targetPath => path;

  @override
  String get fileName => p.basename(path);
}

/// 写到 SAF 授权树内的文档。
///
/// 复用 [AndroidSafSaveTarget] 表达"哪棵树 + 树内哪一级目录"，写入侧据此逐级定位/创建目录后写入，
/// 不允许把整条 `content://` 当成本地路径处理。
final class SafDocumentTarget extends BatchConvertTarget {
  const SafDocumentTarget({required this.target, required this.fileName});

  /// 目标树与树内目录层级（含可读树名）。
  final AndroidSafSaveTarget target;

  /// 目标文件名（含转换后的扩展名）。
  @override
  final String fileName;
}
