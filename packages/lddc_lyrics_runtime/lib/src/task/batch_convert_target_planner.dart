import 'package:path/path.dart' as p;

import 'android_saf_save_paths.dart';
import 'batch_convert_locations.dart';
import 'lyrics_path_template_formatter.dart';

/// 一条批量转换任务的写目标规划结果。
class BatchConvertTargetPlan {
  const BatchConvertTargetPlan({
    required this.target,
    required this.displayPath,
  });

  final BatchConvertTarget target;

  /// 可直接展示的落点：SAF 为"树名 / 层级 / 文件名"，本地为规范化路径。
  final String displayPath;
}

/// 规划批量转换的写目标。
///
/// - [saveTreeUri] 非空（安卓端已选 SAF 保存树）：写到该树内；源在树内时**镜像**源的相对目录，
///   源是本地缓存副本（无层级信息）时平铺到树根；
/// - [saveTreeUri] 为空：写到本地（[localSaveRootPath]，未设置时写在源文件所在目录）——桌面端历史行为。
///
/// 组合不合法时直接抛 [ArgumentError]，**不做静默退化**：SAF 源缺少保存树、或源在树外无法推导层级，
/// 都属于"会写错位置"的情形，必须让调用方先修好状态，而不是悄悄写到缓存副本旁。
BatchConvertTargetPlan planBatchConvertTarget({
  required BatchConvertSource source,
  required String targetFileName,
  String? localSaveRootPath,
  String? saveTreeUri,
  String? saveTreeLabel,
}) {
  final String fileName = targetFileName.trim();
  if (fileName.isEmpty) {
    throw ArgumentError('批量转换目标文件名不能为空');
  }

  final String treeUri = saveTreeUri?.trim() ?? '';
  if (treeUri.isNotEmpty) {
    final List<String> segments = switch (source) {
      LocalFileSource() => const <String>[],
      SafDocumentSource(:final String documentUri, :final String treeUri) =>
        safSourceRelativeDirectorySegments(
              documentUri: documentUri,
              treeUri: treeUri,
            ) ??
            (throw ArgumentError('无法推导 SAF 源在树内的相对目录: $documentUri')),
    };
    // 复用既有的 SAF 目标模型（树 URI + 树内层级 + 可读树名），不另造一套。
    final AndroidSafSaveTarget target = AndroidSafSaveTarget(
      treeUri: treeUri,
      directorySegments: segments,
      treeLabel: saveTreeLabel?.trim() ?? '',
    );
    return BatchConvertTargetPlan(
      target: SafDocumentTarget(target: target, fileName: fileName),
      displayPath: '${target.directoryLabel} / $fileName',
    );
  }

  if (source is! LocalFileSource) {
    throw ArgumentError('SAF 文档源必须提供保存树，否则会写到用户看不到的位置');
  }
  final String root = localSaveRootPath?.trim() ?? '';
  final String folder = root.isEmpty ? p.dirname(source.path) : root;
  final String path = p.normalize(
    p.join(LyricsPathTemplateFormatter.sanitizePath(folder), fileName),
  );
  return BatchConvertTargetPlan(
    target: LocalFileTarget(path),
    displayPath: path,
  );
}
