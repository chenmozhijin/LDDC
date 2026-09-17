import 'package:flutter/services.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

const List<String> kLocalMatchSongFileExtensions = <String>[
  ...audioFileExtensions,
  'cue',
];

abstract interface class LocalMatchInputPicker {
  Future<List<PickedFileHandle>> pickSongFiles({String? initialDirectory});

  Future<List<String>> pickSongDirectories({String? initialDirectory});

  Future<String?> pickSaveRootDirectory({String? initialDirectory});

  Future<AndroidSafTreeToken?> pickAndroidTree({String? initialUri});
}

class LocalMatchInputPickerImpl implements LocalMatchInputPicker {
  const LocalMatchInputPickerImpl({
    required AppFilePicker filePicker,
    required AndroidSafTreePort treePort,
  }) : _filePicker = filePicker,
       _treePort = treePort;

  final AppFilePicker _filePicker;
  final AndroidSafTreePort _treePort;

  @override
  Future<List<PickedFileHandle>> pickSongFiles({String? initialDirectory}) {
    return _filePicker.pickFiles(
      allowedExtensions: kLocalMatchSongFileExtensions,
      initialDirectory: initialDirectory,
      label: 'audio',
    );
  }

  @override
  Future<List<String>> pickSongDirectories({String? initialDirectory}) async {
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
  Future<AndroidSafTreeToken?> pickAndroidTree({String? initialUri}) async {
    try {
      final AndroidSafTreeToken tree = await _treePort.pickTree(
        initialUri: initialUri,
      );
      // 目录树后续会用于扫描和歌词保存，必须在进入业务队列前完成持久授权；
      // 否则应用重启或系统回收后可能拿着已失效 URI 继续批量写入。
      await _treePort.persistTreePermission(tree.uri);
      return tree;
    } on PlatformException catch (error) {
      // 用户在系统目录选择器里取消是正常操作，不是失败：本接口用 null 表示
      // "没有选到目录"，否则控制器会把取消当成错误弹提示。
      if (error.code == 'cancelled') {
        return null;
      }
      rethrow;
    }
  }
}
