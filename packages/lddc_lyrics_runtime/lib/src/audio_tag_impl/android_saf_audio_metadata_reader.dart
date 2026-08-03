import 'package:dart_taglib/dart_taglib.dart' hide TaglibBackend;
import 'package:path/path.dart' as p;

import '../task/android_saf_ports.dart';
import 'dart_taglib_backend.dart';

/// Android SAF 音频元数据读取实现。
///
/// `content://` 文件需要先由 platform 层打开 fd，再交给 taglib 读取。这个类集中管理
/// fd 和 taglib session 的关闭顺序，避免 core 用例在取消、异常或解析失败时遗漏资源释放。
final class AndroidSafAudioMetadataReader
    implements AndroidSafAudioMetadataPort {
  AndroidSafAudioMetadataReader({
    required this._safFdPort,
    TaglibBackend? taglibBackend,
  }) : _taglibBackend = taglibBackend ?? DartTaglibBackend();

  final AndroidSafFdPort _safFdPort;
  final TaglibBackend _taglibBackend;

  @override
  Future<AndroidSafAudioMetadata> readMetadata({
    required String uri,
    required String? nameHint,
  }) async {
    int? fileDescriptor;
    TaglibBackendSession? session;
    try {
      final AndroidSafOpenedFileDescriptor opened = await _safFdPort
          .openReadOnlyFd(uri);
      fileDescriptor = opened.fileDescriptor;
      final String resolvedNameHint = opened.nameHint?.trim().isNotEmpty == true
          ? opened.nameHint!.trim()
          : (nameHint ?? p.basename(uri));
      session = _taglibBackend.openSessionFromFileDescriptor(
        fileDescriptor,
        nameHint: resolvedNameHint,
      );
      final BasicTags tags = session.readBasicTags();
      final AudioProperties? properties = session.readAudioProperties();
      final PropertyMap propertyMap = session.readPropertyMap();
      return AndroidSafAudioMetadata(
        nameHint: resolvedNameHint,
        title: _trimOrNull(tags.title),
        artist: _trimOrNull(tags.artist),
        album: _trimOrNull(tags.album),
        durationMs: properties == null ? null : properties.lengthSeconds * 1000,
        trackNumber: tags.track <= 0 ? null : tags.track,
        cuesheet: _readCuesheet(propertyMap),
      );
    } finally {
      session?.close();
      if (fileDescriptor != null) {
        try {
          await _safFdPort.closeFd(fileDescriptor);
        } catch (_) {
          // fd 关闭失败不能覆盖读取结果；泄漏风险由测试断言 closedFds 兜底。
        }
      }
    }
  }

  String? _readCuesheet(PropertyMap propertyMap) {
    for (final PropertyItem item in propertyMap.items) {
      if (item.key.toLowerCase() != 'cuesheet') {
        continue;
      }
      for (final String value in item.values) {
        if (value.trim().isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  String? _trimOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
