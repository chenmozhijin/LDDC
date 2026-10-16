import 'package:flutter/services.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 批量转换页选定的 SAF 目录（保存根或导入源）。
///
/// [treeLabel] 用目录选择器给出的显示名；平台不给显示名时**留空**，由展示层用
/// 统一占位文案补齐——绝不退回 URI，界面一旦出现 `content://` 用户就读不懂了。
typedef PickedBatchConvertSaveTree = ({String treeUri, String treeLabel});

/// 批量转换"导入文件夹"选定的 SAF 导入树。
typedef PickedBatchConvertImportTree = ({String treeUri, String treeLabel});

abstract interface class BatchConvertInputPicker {
  Future<List<PickedFileHandle>> pickLyricsFiles({String? initialDirectory});

  Future<List<String>> pickLyricsDirectories({String? initialDirectory});

  /// 桌面端的保存目录选择；安卓端没有本地目录选择能力。
  Future<String?> pickSaveRootDirectory({String? initialDirectory});

  /// 安卓端的保存树选择，内部完成持久授权；用户取消时返回 null。
  Future<PickedBatchConvertSaveTree?> pickSaveTree({String? initialUri});

  /// 安卓端的"导入文件夹"选择，同样内部完成持久授权；用户取消时返回 null。
  ///
  /// 复用 [pickSaveTree] 的实现：两端都是"选一棵 SAF 树 + 持久授权 + 取消转 null"，
  /// 只是语义不同，没必要维护第二份平台调用。
  Future<PickedBatchConvertImportTree?> pickImportTree({String? initialUri});
}

class BatchConvertInputPickerImpl implements BatchConvertInputPicker {
  const BatchConvertInputPickerImpl({
    required AppFilePicker filePicker,
    required AndroidSafTreePort treePort,
  }) : _filePicker = filePicker,
       _treePort = treePort;

  final AppFilePicker _filePicker;
  final AndroidSafTreePort _treePort;

  @override
  Future<List<PickedFileHandle>> pickLyricsFiles({String? initialDirectory}) {
    return _filePicker.pickFiles(
      allowedExtensions: localLyricsInputSupportedExtensions,
      initialDirectory: initialDirectory,
      label: 'lyrics',
    );
  }

  @override
  Future<List<String>> pickLyricsDirectories({String? initialDirectory}) async {
    final String? directory = await _filePicker.pickDirectory(
      initialDirectory: initialDirectory,
    );
    if (directory == null || directory.trim().isEmpty) {
      return const <String>[];
    }
    return <String>[directory.trim()];
  }

  @override
  Future<String?> pickSaveRootDirectory({String? initialDirectory}) {
    return _filePicker.pickDirectory(initialDirectory: initialDirectory);
  }

  @override
  Future<PickedBatchConvertSaveTree?> pickSaveTree({String? initialUri}) {
    return _pickTree(initialUri: initialUri);
  }

  @override
  Future<PickedBatchConvertImportTree?> pickImportTree({String? initialUri}) {
    return _pickTree(initialUri: initialUri);
  }

  /// 选择一棵 SAF 授权树并完成持久授权；用户取消返回 null。
  ///
  /// 保存树与导入树只差语义，平台调用（选树 → 持久授权 → 取消转 null）完全相同，
  /// 因此收敛在这里一份实现。
  Future<PickedBatchConvertSaveTree?> _pickTree({String? initialUri}) async {
    try {
      final AndroidSafTreeToken tree = await _treePort.pickTree(
        initialUri: initialUri,
      );
      // 授权树会在后续扫描与批量写入中反复使用；进入队列前必须先持久授权，否则应用
      // 重启或系统回收权限后，批量转换会带着已失效的 URI 继续读/写并整批失败。
      await _treePort.persistTreePermission(tree.uri);
      // 目录选择器偶尔不给显示名：此时**留空**，由展示层用统一的占位文案补齐。
      // 绝不退回 URI——界面一旦出现 `content://` 就违反了"展示层不出现编码 URI"的硬规则。
      return (treeUri: tree.uri, treeLabel: tree.displayName?.trim() ?? '');
    } on PlatformException catch (error) {
      // 用户在系统目录选择器里取消是正常操作：用 null 表示"没有选到目录"，
      // 否则控制器会把取消当成失败并弹出错误提示。
      if (error.code == 'cancelled') {
        return null;
      }
      rethrow;
    }
  }
}
