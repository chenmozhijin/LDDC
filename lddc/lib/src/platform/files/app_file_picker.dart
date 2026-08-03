import 'dart:convert';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show
        AppFilePicker,
        PickedAudioFileHandle,
        PickedFileHandle,
        SavedTextFileResult,
        SavedTextFileResultKind,
        normalizePickedLocalFilePath;

final class _XFilePickedFileHandle extends PickedFileHandle {
  _XFilePickedFileHandle(selector.XFile file)
    : _file = file,
      super(name: file.name, path: normalizePickedLocalFilePath(file.path));

  final selector.XFile _file;

  @override
  Future<int?> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

final class _XFilePickedAudioFileHandle extends PickedAudioFileHandle {
  _XFilePickedAudioFileHandle(selector.XFile file)
    : _file = file,
      super(name: file.name, path: normalizePickedLocalFilePath(file.path));

  final selector.XFile _file;

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();
}

/// 文件对话框抽象，便于测试替换。
abstract interface class AppFileDialog {
  Future<String?> pickDirectory({String? initialDirectory});

  Future<selector.XFile?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  });

  Future<List<selector.XFile>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  });

  Future<selector.FileSaveLocation?> pickSaveLocation({
    required String fileName,
    List<String>? allowedExtensions,
    String? initialDirectory,
  });
}

/// 基于 `file_selector` 的默认实现。
final class AppFileDialogImpl implements AppFileDialog {
  const AppFileDialogImpl();

  @override
  Future<String?> pickDirectory({String? initialDirectory}) {
    return selector.getDirectoryPath(initialDirectory: initialDirectory);
  }

  @override
  Future<selector.XFile?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) {
    return selector.openFile(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
      acceptedTypeGroups: <selector.XTypeGroup>[
        selector.XTypeGroup(label: label, extensions: allowedExtensions),
      ],
    );
  }

  @override
  Future<List<selector.XFile>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) {
    return selector.openFiles(
      initialDirectory: initialDirectory,
      confirmButtonText: confirmButtonText,
      acceptedTypeGroups: <selector.XTypeGroup>[
        selector.XTypeGroup(label: label, extensions: allowedExtensions),
      ],
    );
  }

  @override
  Future<selector.FileSaveLocation?> pickSaveLocation({
    required String fileName,
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) {
    final List<selector.XTypeGroup> acceptedTypeGroups =
        allowedExtensions == null || allowedExtensions.isEmpty
        ? const <selector.XTypeGroup>[]
        : <selector.XTypeGroup>[
            selector.XTypeGroup(label: 'lyrics', extensions: allowedExtensions),
          ];
    return selector.getSaveLocation(
      suggestedName: fileName,
      initialDirectory: initialDirectory,
      acceptedTypeGroups: acceptedTypeGroups,
    );
  }
}

/// 公用文件选择实现：普通文件走 `file_selector`，音频文件保留移动端专用桥。
final class AppFilePickerImpl implements AppFilePicker {
  const AppFilePickerImpl({
    MethodChannel? iosAudioFileChannel,
    MethodChannel? androidSearchFileChannel,
    AppFileDialog? fileDialog,
  }) : _iosAudioFileChannel =
           iosAudioFileChannel ?? _defaultIosAudioFileChannel,
       _androidSearchFileChannel =
           androidSearchFileChannel ?? _defaultAndroidSearchFileChannel,
       _fileDialog = fileDialog ?? const AppFileDialogImpl();

  static const MethodChannel _defaultIosAudioFileChannel = MethodChannel(
    'lddc/ios_search_audio_tag',
  );
  static const MethodChannel _defaultAndroidSearchFileChannel = MethodChannel(
    'lddc/android_search_file',
  );

  final MethodChannel _iosAudioFileChannel;
  final MethodChannel _androidSearchFileChannel;
  final AppFileDialog _fileDialog;

  static bool get _isIosPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get _isDesktopPlatform {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    if (!_isDesktopPlatform) {
      throw UnsupportedError('当前平台不支持目录选择');
    }
    return _fileDialog.pickDirectory(
      initialDirectory: _normalizeInitialDirectory(initialDirectory),
    );
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('当前平台不支持选择文件');
    }
    final selector.XFile? file = await _fileDialog.pickFile(
      allowedExtensions: allowedExtensions,
      initialDirectory: _normalizeInitialDirectory(initialDirectory),
      confirmButtonText: confirmButtonText,
      label: label,
    );
    if (file == null) {
      return null;
    }
    return _XFilePickedFileHandle(file);
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('当前平台不支持选择文件');
    }
    final List<selector.XFile> files = await _fileDialog.pickFiles(
      allowedExtensions: allowedExtensions,
      initialDirectory: _normalizeInitialDirectory(initialDirectory),
      confirmButtonText: confirmButtonText,
      label: label,
    );
    return files.map(_XFilePickedFileHandle.new).toList(growable: false);
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
    final String? normalizedInitialDirectory = _normalizeInitialDirectory(
      initialDirectory,
    );
    if (_isIosPlatform) {
      return _pickIosAudioFile(initialDirectory: normalizedInitialDirectory);
    }
    if (_isAndroidPlatform) {
      return _pickAndroidAudioFile(
        initialDirectory: normalizedInitialDirectory,
      );
    }
    if (!_isDesktopPlatform) {
      throw UnsupportedError('当前平台不支持选择音频文件');
    }
    final selector.XFile? file = await _fileDialog.pickFile(
      allowedExtensions: audioFileExtensions,
      initialDirectory: normalizedInitialDirectory,
      label: 'audio',
    );
    if (file == null) {
      return null;
    }
    return _XFilePickedAudioFileHandle(file);
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async {
    if (!_isIosPlatform || file.canWrite) {
      return file;
    }
    final Map<Object?, Object?>? result = await _iosAudioFileChannel
        .invokeMapMethod<Object?, Object?>(
          'openAudioFileForWrite',
          <String, Object?>{
            'identifier': file.identifier,
            'path': file.path,
            'nameHint': file.fileDescriptorNameHint ?? file.name,
          },
        );
    if (result == null || result.isEmpty) {
      throw StateError('iOS 打开音频写入 fd 失败：返回结果为空');
    }
    return PickedAudioFileHandle.fromIosMap(result);
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {
    final int? fileDescriptor = file.fileDescriptor;
    if (!_isIosPlatform || fileDescriptor == null || fileDescriptor < 0) {
      return;
    }
    await _iosAudioFileChannel.invokeMethod<void>('closeFd', <String, Object?>{
      'fd': fileDescriptor,
    });
  }

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    final String? normalizedInitialDirectory = _normalizeInitialDirectory(
      initialDirectory,
    );
    if (_isAndroidPlatform) {
      return _saveAndroidTextFile(
        fileName: fileName,
        bytes: _encodeUtf8(text),
        initialDirectory: normalizedInitialDirectory,
        mimeType: _resolveMimeType(allowedExtensions),
      );
    }
    if (_isIosPlatform) {
      return _saveIosTextFile(
        fileName: fileName,
        bytes: _encodeUtf8(text),
        initialDirectory: normalizedInitialDirectory,
      );
    }
    if (!_isDesktopPlatform) {
      throw UnsupportedError('当前平台不支持保存到文件');
    }
    final selector.FileSaveLocation? location = await _fileDialog
        .pickSaveLocation(
          fileName: fileName,
          allowedExtensions: allowedExtensions,
          initialDirectory: normalizedInitialDirectory,
        );
    if (location == null) {
      return null;
    }
    // 桌面对话框可能被用户取消；确认目标后再编码，避免为取消操作创建整份文本副本。
    await BackgroundFileIo.writeBytes(
      path: location.path,
      bytes: _encodeUtf8(text),
    );
    return SavedTextFileResult.localPath(location.path);
  }

  static String? _normalizeInitialDirectory(String? initialDirectory) {
    final String? normalized = initialDirectory?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static Uint8List _encodeUtf8(String text) {
    return Uint8List.fromList(utf8.encode(text));
  }

  static String _resolveMimeType(List<String>? allowedExtensions) {
    final String? extension = switch (allowedExtensions) {
      <String>[final String first, ...] => first.trim().toLowerCase(),
      _ => null,
    };
    return switch (extension) {
      'json' => 'application/json',
      // Android DocumentsUI 会把 text/* 的未知扩展名统一规范化为 .txt，导致
      // 用户输入 lyrics.lrc 后实际得到 lyrics.lrc.txt。LRC 没有注册的标准
      // MIME，使用明确的实验类型可保留格式语义与用户确认的 .lrc 文件名；不能
      // 回退到 application/octet-stream 后再让调用方猜测实际格式。
      'lrc' => 'application/x-lrc',
      'ass' || 'ssa' => 'text/x-ssa',
      'srt' => 'application/x-subrip',
      _ => 'text/plain',
    };
  }

  Future<PickedAudioFileHandle?> _pickAndroidAudioFile({
    String? initialDirectory,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _androidSearchFileChannel
          .invokeMapMethod<Object?, Object?>('pickAudioFile', <String, Object?>{
            'initialDirectory': initialDirectory,
          });
      if (result == null || result.isEmpty) {
        return null;
      }
      return PickedAudioFileHandle.fromAndroidMap(result);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return null;
      }
      if (error.code == 'unsupported' || error.code == 'unavailable') {
        throw UnsupportedError(error.message ?? '当前平台不支持选择音频文件');
      }
      rethrow;
    }
  }

  Future<PickedAudioFileHandle?> _pickIosAudioFile({
    String? initialDirectory,
  }) async {
    try {
      final Map<Object?, Object?>? result = await _iosAudioFileChannel
          .invokeMapMethod<Object?, Object?>('pickAudioFile', <String, Object?>{
            'initialDirectory': initialDirectory,
          });
      if (result == null || result.isEmpty) {
        return null;
      }
      // iOS 默认只打开只读 fd；写标签前再显式升级到读写 fd。
      return PickedAudioFileHandle.fromIosMap(result);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return null;
      }
      if (error.code == 'unsupported' || error.code == 'unavailable') {
        throw UnsupportedError(error.message ?? '当前平台不支持选择音频文件');
      }
      rethrow;
    }
  }

  Future<SavedTextFileResult?> _saveAndroidTextFile({
    required String fileName,
    required Uint8List bytes,
    required String? initialDirectory,
    required String mimeType,
  }) async {
    try {
      final String? result = await _androidSearchFileChannel
          .invokeMethod<String>('saveTextFile', <String, Object?>{
            'fileName': fileName,
            'bytes': bytes,
            'initialDirectory': initialDirectory,
            'mimeType': mimeType,
          });
      final String? normalized = _normalizeInitialDirectory(result);
      return normalized == null ? null : SavedTextFileResult.uri(normalized);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return null;
      }
      if (error.code == 'unsupported' || error.code == 'unavailable') {
        throw UnsupportedError(error.message ?? '当前平台不支持保存到文件');
      }
      rethrow;
    }
  }

  Future<SavedTextFileResult?> _saveIosTextFile({
    required String fileName,
    required Uint8List bytes,
    required String? initialDirectory,
  }) async {
    try {
      final String? result = await _iosAudioFileChannel.invokeMethod<String>(
        'saveTextFile',
        <String, Object?>{
          'fileName': fileName,
          'bytes': bytes,
          'initialDirectory': initialDirectory,
        },
      );
      final String? normalized = _normalizeInitialDirectory(result);
      if (normalized == null) {
        return null;
      }
      if (normalized.startsWith('file://')) {
        // 这里运行在 iOS 语义分支，即使测试宿主是 Windows，也必须保留
        // iOS file URL 的 POSIX path，避免 `toFilePath()` 转成反斜杠。
        return SavedTextFileResult.localPath(Uri.parse(normalized).path);
      }
      if (normalized.startsWith('content://')) {
        return SavedTextFileResult.uri(normalized);
      }
      return SavedTextFileResult.localPath(normalized);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        return null;
      }
      if (error.code == 'unsupported' || error.code == 'unavailable') {
        throw UnsupportedError(error.message ?? '当前平台不支持保存到文件');
      }
      rethrow;
    }
  }
}
