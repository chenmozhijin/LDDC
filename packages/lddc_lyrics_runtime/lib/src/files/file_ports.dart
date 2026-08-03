import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

enum SavedTextFileResultKind { localPath, contentUri, externalUri }

/// 文本保存结果。
///
/// UI 只能直接展示 [displayPath]；只有 [kind] 为 [SavedTextFileResultKind.localPath]
/// 时才允许把 [localPath] 交给 `File(...)`。Android SAF / iOS 外部 provider 返回的
/// URI 不是本地路径，不能再被调用方当成普通文件路径二次写入。
class SavedTextFileResult {
  const SavedTextFileResult._({
    required this.kind,
    required this.displayPath,
    this.localPath,
    this.uri,
  });

  factory SavedTextFileResult.localPath(String path) {
    final String normalized = _requireNonEmpty(path, 'path');
    return SavedTextFileResult._(
      kind: SavedTextFileResultKind.localPath,
      displayPath: normalized,
      localPath: normalized,
    );
  }

  factory SavedTextFileResult.uri(String uri) {
    final String normalized = _requireNonEmpty(uri, 'uri');
    return SavedTextFileResult._(
      kind: normalized.startsWith('content://')
          ? SavedTextFileResultKind.contentUri
          : SavedTextFileResultKind.externalUri,
      displayPath: normalized,
      uri: normalized,
    );
  }

  final SavedTextFileResultKind kind;
  final String displayPath;
  final String? localPath;
  final String? uri;
}

/// 公用文件句柄：只描述业务层需要的文件名称、路径和按需读取能力。
///
/// 具体文件来自桌面文件选择器、Android content uri 还是 iOS fd，由 platform
/// 实现负责。feature 层只依赖这个端口，避免把平台插件类型带入业务代码。
class PickedFileHandle {
  const PickedFileHandle({required this.name, this.path});

  final String name;
  final String? path;

  Future<int?> length() async => null;

  Future<Uint8List> readAsBytes() {
    throw UnsupportedError('当前句柄不支持直接读取字节');
  }
}

/// 选中的音频文件句柄：保留移动端 fd/content uri 语义，但不暴露平台插件对象。
class PickedAudioFileHandle extends PickedFileHandle {
  const PickedAudioFileHandle({
    required super.name,
    super.path,
    this.identifier,
    this.fileDescriptor,
    this.fileDescriptorNameHint,
    this.canRead = true,
    this.canWrite = false,
  });

  final String? identifier;
  final int? fileDescriptor;
  final String? fileDescriptorNameHint;
  final bool canRead;
  final bool canWrite;

  factory PickedAudioFileHandle.fromAndroidMap(Map<Object?, Object?> data) {
    final String identifier = _readRequiredString(data, 'identifier');
    if (!identifier.startsWith('content://')) {
      throw FormatException('Android 音频选择结果 identifier 必须是 content:// URI');
    }
    final String? name = _readString(data, 'name');
    return PickedAudioFileHandle(
      name: name ?? _fallbackNameFromPath(identifier) ?? 'audio',
      identifier: identifier,
      canRead: true,
      canWrite: true,
    );
  }

  factory PickedAudioFileHandle.fromIosMap(Map<Object?, Object?> data) {
    final String? path = _readString(data, 'path');
    final String? fileDescriptorNameHint =
        _readString(data, 'fileDescriptorNameHint') ??
        _readString(data, 'nameHint');
    final int fileDescriptor =
        _readInt(data, 'fileDescriptor') ?? _readInt(data, 'fd') ?? -1;
    if (fileDescriptor < 0) {
      throw FormatException('iOS 音频选择结果缺少有效 fd');
    }
    if (fileDescriptorNameHint == null && path == null) {
      throw FormatException('iOS 音频选择结果缺少 nameHint/path');
    }
    return PickedAudioFileHandle(
      name:
          _readString(data, 'name') ??
          fileDescriptorNameHint ??
          _fallbackNameFromPath(path) ??
          'audio',
      path: path,
      identifier: _readString(data, 'identifier'),
      fileDescriptor: fileDescriptor,
      fileDescriptorNameHint: fileDescriptorNameHint,
      canRead: _readBool(data, 'canRead') ?? true,
      canWrite: _readBool(data, 'canWrite') ?? false,
    );
  }

  /// Android 优先返回原始 `content://`，其余平台回退到普通文件路径。
  String? get targetPath {
    final String? normalizedIdentifier = identifier?.trim();
    if (normalizedIdentifier != null && normalizedIdentifier.isNotEmpty) {
      if (normalizedIdentifier.startsWith('content://')) {
        return normalizedIdentifier;
      }
      if (normalizedIdentifier.startsWith('file://')) {
        return Uri.parse(normalizedIdentifier).toFilePath();
      }
    }
    final String? normalizedPath = normalizePickedLocalFilePath(path);
    if (normalizedPath == null || normalizedPath.isEmpty) {
      return null;
    }
    return normalizedPath;
  }

  static String? _readString(Map<Object?, Object?> data, String key) {
    final String? normalized = DynamicReader.asString(data[key])?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int? _readInt(Map<Object?, Object?> data, String key) {
    final int? value = DynamicReader.asInt(data[key]);
    if (value != null && value < 0) {
      throw FormatException('$key 不能为负数');
    }
    return value;
  }

  static bool? _readBool(Map<Object?, Object?> data, String key) {
    final Object? value = data[key];
    if (value == null) {
      return null;
    }
    if (value is! bool) {
      throw FormatException('$key 字段必须是 bool');
    }
    return value;
  }

  static String? _fallbackNameFromPath(String? path) {
    final String? normalized = normalizePickedLocalFilePath(path);
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    final List<String> parts = normalized
        .split(RegExp(r'[\\/]'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return null;
    }
    return parts.last;
  }
}

/// 公用文件选择端口。
abstract interface class AppFilePicker {
  Future<String?> pickDirectory({String? initialDirectory});

  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label,
  });

  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label,
  });

  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory});

  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  );

  Future<void> releaseAudioFile(PickedAudioFileHandle file);

  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  });
}

/// 通用路径打开端口：用于在桌面端打开文件或所在目录。
abstract interface class AppPathOpener {
  Future<void> openFile(String path);

  Future<void> openDirectory(String path);
}

String _requireNonEmpty(String value, String name) {
  final String normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '不能为空');
  }
  return normalized;
}

String _readRequiredString(Map<Object?, Object?> data, String key) {
  final String? value = PickedAudioFileHandle._readString(data, key);
  if (value == null) {
    throw FormatException('$key 字段缺失或为空');
  }
  return value;
}

String? normalizePickedLocalFilePath(String? rawPath) {
  final String? normalized = rawPath?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (normalized.startsWith('file://')) {
    return Uri.parse(normalized).toFilePath();
  }
  return normalized;
}
