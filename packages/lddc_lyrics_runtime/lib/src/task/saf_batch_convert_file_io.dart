import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'android_saf_ports.dart';
import 'android_saf_save_paths.dart';
import 'batch_convert_locations.dart';
import 'batch_convert_usecase.dart';
import 'lyrics_mime_types.dart';

/// Android 端批量转换的文件 IO：本地缓存副本照旧走 dart:io，SAF 文档走授权树/内容端口。
///
/// 刻意**组合** [DefaultBatchConvertFileIo] 而不是自己再写一份本地读写：未选择保存树时
/// （写到插件缓存副本旁）必须与桌面端行为完全一致，包括"同文件覆盖""目标已存在"这两条判定。
final class SafBatchConvertFileIo implements BatchConvertFileIo {
  SafBatchConvertFileIo({
    required this.treePort,
    required this.contentPort,
    BatchConvertFileIo? localFileIo,
  }) : _localFileIo = localFileIo ?? const DefaultBatchConvertFileIo();

  /// 单页枚举上限：与本地匹配的存在性检查保持同量级，避免大目录一次拉满。
  static const int _pageLimit = 128;

  final AndroidSafTreePort treePort;
  final AndroidSafContentPort contentPort;
  final BatchConvertFileIo _localFileIo;

  @override
  Future<Uint8List> readBytes(BatchConvertSource source) {
    return switch (source) {
      LocalFileSource() => _localFileIo.readBytes(source),
      // SAF 文档不能交给 dart:io：必须由平台层按 URI 打开内容流。
      SafDocumentSource() => contentPort.readBytes(source.documentUri),
    };
  }

  @override
  Future<void> writeText({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String text,
    required bool allowOverwrite,
  }) async {
    if (target is LocalFileTarget) {
      await _localFileIo.writeText(
        source: source,
        target: target,
        text: text,
        allowOverwrite: allowOverwrite,
      );
      return;
    }

    final SafDocumentTarget safTarget = target as SafDocumentTarget;
    if (!allowOverwrite) {
      final bool? exists = await targetExists(safTarget);
      if (exists == null) {
        // 无法确认时宁可失败：把权限/枚举问题当成"不存在"会写出用户没确认过的覆盖。
        throw StateError(
          '无法确认目标是否已存在，已停止写入：${safTarget.target.displayPathFor(safTarget.fileName)}',
        );
      }
      if (exists) {
        throw LddcApiParamsException(
          '导出目标已存在: ${safTarget.target.displayPathFor(safTarget.fileName)}',
        );
      }
    }

    // 目标目录由原生逐级定位/创建，且不会越出授权树；这里只传树内相对层级。
    await treePort.writeDocument(
      treeUri: safTarget.target.treeUri,
      directorySegments: safTarget.target.directorySegments,
      displayName: safTarget.fileName,
      mimeType: lyricsMimeTypeForName(safTarget.fileName),
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
  }

  @override
  Future<bool?> targetExists(BatchConvertTarget target) {
    if (target is LocalFileTarget) {
      return _localFileIo.targetExists(target);
    }
    return _safTargetExists(target as SafDocumentTarget);
  }

  Future<bool?> _safTargetExists(SafDocumentTarget target) async {
    final String? directoryUri = safDirectoryUri(
      treeUri: target.target.treeUri,
      directorySegments: target.target.directorySegments,
    );
    if (directoryUri == null) {
      // 树 URI 或层级不合法：无法枚举，交由调用方按失败处理。
      return null;
    }
    try {
      int offset = 0;
      while (true) {
        final AndroidSafTreePage page = await treePort.listChildrenPage(
          uri: directoryUri,
          offset: offset,
          limit: _pageLimit,
        );
        for (final AndroidSafTreeEntry entry in page.entries) {
          // 同名目录同样会让原生按 displayName 定位文件失败，因此目录也算"已存在"。
          if (entry.displayName == target.fileName) {
            return true;
          }
        }
        final int? nextOffset = page.nextOffset;
        if (nextOffset == null) {
          return false;
        }
        offset = nextOffset;
      }
    } catch (_) {
      // 枚举失败无法证明"不存在"：返回 null 让上层报错，而不是当作无冲突继续。
      return null;
    }
  }
}
