import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../core/logging/logging.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

export 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart'
    show
        DragDropFailure,
        DragDropItemDescriptor,
        DragDropItemKind,
        DragDropParseResult,
        DragDropPort,
        DragDropSongDescriptor,
        UnsupportedDragDropPort;

const String kDesktopDragDropChannelName = 'lddc/desktop_drag_drop';
const String kFoobarDropFormat =
    'application/x-qt-windows-mime;value="foobar2000_playable_location_format"';
const String kFoobarDropRawFormat = 'foobar2000_playable_location_format';
const String kAimpDropFormat =
    'application/x-qt-windows-mime;value="ACL.FileURIs"';
const String kAimpDropRawFormat = 'ACL.FileURIs';
const String kAimpDropTextFormat = 'text/aimp-uri-list';
const int kDesktopDropPrivateDataMaxBytes = 1024 * 1024;

final AppLogger _dragDropLogger = AppLogger.scope('drag-drop');

DesktopDragDropPayload _desktopDragDropPayloadFromMethodCall(Object? raw) {
  final Map<Object?, Object?> data = raw is Map<Object?, Object?>
      ? raw
      : const <Object?, Object?>{};
  return DesktopDragDropPayload(
    platform: _readString(data['platform']) ?? 'unknown',
    x: _readDouble(data['x']),
    y: _readDouble(data['y']),
    coordinateSpace: _readString(data['coordinateSpace']) ?? 'logical',
    formats: _readStringSet(data['formats']),
    files: _readStringList(data['files']),
    privateData: _readPrivateData(data['privateData']),
    text: _readString(data['text']),
  );
}

class DragDropPortImpl implements DesktopDragDropPort {
  const DragDropPortImpl({this.enableDiagnostics = false, this.debugLogger});

  final bool enableDiagnostics;
  final void Function(String message)? debugLogger;

  @override
  bool get isSupported => true;

  @override
  Stream<DesktopDragDropEvent> get events => _DesktopDragDropChannelHub.events;

  @override
  DragDropParseResult parsePayload(DesktopDragDropPayload payload) {
    final Set<String> platformFormats = <String>{...payload.formats};
    platformFormats.addAll(payload.privateData.keys);
    final _ParsedDragItemResult privateMimeResult = _parsePrivateMime(payload);
    if (privateMimeResult.items.isNotEmpty) {
      return DragDropParseResult(
        items: _deduplicate(privateMimeResult.items),
        platformFormats: platformFormats,
        failure: privateMimeResult.failure,
      );
    }

    final List<DragDropItemDescriptor> fileItems = <DragDropItemDescriptor>[];
    DragDropFailure? firstFailure = privateMimeResult.failure;
    for (final String rawPath in payload.files) {
      final String? path = _normalizePath(rawPath);
      if (path == null) {
        continue;
      }
      // 这里不做同步 stat，避免网络盘、失效盘符或权限探测阻塞 UI isolate。
      // 目录/文件的精确判定交给业务入口的异步文件系统能力完成。
      fileItems.add(DragDropItemDescriptor.file(path));
    }

    _logDiagnostic(
      'parsePayload platform=${payload.platform} '
      'formats=${platformFormats.toList()..sort()} files=${payload.files.length} '
      'items=${fileItems.length} failure=${firstFailure?.name ?? 'none'}',
    );

    if (fileItems.isNotEmpty) {
      return DragDropParseResult(
        items: _deduplicate(fileItems),
        platformFormats: platformFormats,
        failure: firstFailure,
      );
    }

    return DragDropParseResult(
      items: const <DragDropItemDescriptor>[],
      platformFormats: platformFormats,
      failure: firstFailure ?? DragDropFailure.unsupportedItem,
    );
  }

  _ParsedDragItemResult _parsePrivateMime(DesktopDragDropPayload payload) {
    final Uint8List? aimpBytes = _firstPrivateData(
      payload.privateData,
      <String>[kAimpDropFormat, kAimpDropRawFormat, kAimpDropTextFormat],
    );
    if (aimpBytes != null) {
      try {
        final List<DragDropItemDescriptor> items = parseAimpDropData(aimpBytes);
        _logDiagnostic(
          'privateMime format=AIMP bytes=${aimpBytes.length} '
          'items=${_summarizeItems(items)}',
        );
        if (items.isEmpty) {
          return const _ParsedDragItemResult(
            failure: DragDropFailure.unreadablePrivateMime,
          );
        }
        return _ParsedDragItemResult(items: items);
      } on LddcDropException catch (error) {
        _logPrivateMimeFailure('AIMP', aimpBytes.length, error);
        return const _ParsedDragItemResult(
          failure: DragDropFailure.unreadablePrivateMime,
        );
      }
    }

    final Uint8List? foobarBytes = _firstPrivateData(
      payload.privateData,
      <String>[kFoobarDropFormat, kFoobarDropRawFormat],
    );
    if (foobarBytes != null) {
      try {
        final List<DragDropItemDescriptor> items = parseFoobarDropData(
          foobarBytes,
          payload.text ?? '',
        );
        _logDiagnostic(
          'privateMime format=foobar bytes=${foobarBytes.length} '
          'items=${_summarizeItems(items)}',
        );
        if (items.isEmpty) {
          return const _ParsedDragItemResult(
            failure: DragDropFailure.unreadablePrivateMime,
          );
        }
        return _ParsedDragItemResult(items: items);
      } on LddcDropException catch (error) {
        _logPrivateMimeFailure('foobar2000', foobarBytes.length, error);
        return const _ParsedDragItemResult(
          failure: DragDropFailure.unreadablePrivateMime,
        );
      }
    }

    return const _ParsedDragItemResult();
  }

  Uint8List? _firstPrivateData(
    Map<String, Uint8List> privateData,
    List<String> formats,
  ) {
    for (final String format in formats) {
      final Uint8List? value = privateData[format];
      if (value != null) {
        return value;
      }
    }
    for (final MapEntry<String, Uint8List> entry in privateData.entries) {
      final String normalized = _normalizeFormatKey(entry.key);
      for (final String format in formats) {
        if (normalized == _normalizeFormatKey(format)) {
          return entry.value;
        }
      }
    }
    return null;
  }

  static List<DragDropItemDescriptor> parseAimpDropData(Uint8List data) {
    if (data.length <= 24) {
      throw const LddcDropException('AIMP 拖拽数据长度无效');
    }
    final ByteData rawContent = ByteData.sublistView(data, 20, data.length - 4);
    if (rawContent.lengthInBytes.isOdd) {
      throw const LddcDropException('AIMP 拖拽正文不是完整的 UTF-16LE 数据');
    }
    final StringBuffer buffer = StringBuffer();
    for (int offset = 0; offset < rawContent.lengthInBytes; offset += 2) {
      buffer.writeCharCode(rawContent.getUint16(offset, Endian.little));
    }
    final String decoded = buffer.toString();
    final List<DragDropItemDescriptor> items = <DragDropItemDescriptor>[];
    for (final String entry in decoded.split('\x00')) {
      final String normalized = entry.trim();
      if (normalized.isEmpty) {
        continue;
      }
      final int lastColon = normalized.lastIndexOf(':');
      if (lastColon <= 1 || lastColon >= normalized.length - 1) {
        continue;
      }
      final String suffix = normalized.substring(lastColon + 1);
      if (int.tryParse(suffix) == null) {
        continue;
      }
      final String path = normalized.substring(0, lastColon);
      if (path.trim().isEmpty) {
        continue;
      }
      items.add(
        DragDropItemDescriptor.song(
          DragDropSongDescriptor(path: path, index: suffix),
        ),
      );
    }
    return items;
  }

  static List<DragDropItemDescriptor> parseFoobarDropData(
    Uint8List data,
    String plainText,
  ) {
    if (data.length < 8) {
      throw const LddcDropException('foobar2000 拖拽数据长度无效');
    }
    final List<String?> tracks = _parseFoobarTracks(plainText);
    final List<DragDropItemDescriptor> items = <DragDropItemDescriptor>[];
    final ByteData byteData = ByteData.sublistView(data);
    int offset = 0;
    int index = 0;
    while (offset < data.length - 4) {
      offset += 4;
      if (offset + 4 > data.length) {
        break;
      }
      final int length = byteData.getUint32(offset, Endian.little);
      offset += 4;
      if (length <= 0 || offset + length > data.length) {
        break;
      }
      final String rawPath;
      try {
        rawPath = utf8.decode(
          data.sublist(offset, offset + length),
          allowMalformed: false,
        );
      } on FormatException {
        throw const LddcDropException('foobar2000 拖拽路径不是合法 UTF-8');
      }
      offset += length;
      String path = _decodeFoobarPath(rawPath);
      if (RegExp(r'^/[A-Za-z]:/').hasMatch(path)) {
        path = path.substring(1);
      }
      if (path.trim().isEmpty) {
        continue;
      }
      items.add(
        DragDropItemDescriptor.song(
          DragDropSongDescriptor(
            path: path,
            track: index < tracks.length ? tracks[index] : null,
          ),
        ),
      );
      index += 1;
    }
    return items;
  }

  static String _decodeFoobarPath(String rawPath) {
    final String stripped = rawPath.startsWith('file://')
        ? rawPath.substring(7)
        : rawPath;
    final String sanitized = stripped.replaceAllMapped(
      RegExp(r'%(?![0-9A-Fa-f]{2})'),
      (_) => '%25',
    );
    try {
      return Uri.decodeFull(sanitized);
    } on ArgumentError {
      return stripped;
    }
  }

  static List<String?> _parseFoobarTracks(String plainText) {
    final RegExp pattern = RegExp(
      r'(?:(?<artist>.*?) - )?\[(?<album>.*?) (?:CD\d+/\d+ )?#(?<track>\d+)\] (?<title>.*)',
    );
    return plainText
        .split(RegExp(r'\r?\n'))
        .where((String line) => line.trim().isNotEmpty)
        .map((String line) => pattern.firstMatch(line)?.namedGroup('track'))
        .toList(growable: false);
  }

  static String _normalizeFormatKey(String format) {
    const String prefix = 'application/x-qt-windows-mime;value="';
    if (format.startsWith(prefix) && format.endsWith('"')) {
      return format.substring(prefix.length, format.length - 1);
    }
    return format;
  }

  String? _normalizePath(String? path) {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return p.normalize(path.trim());
  }

  List<DragDropItemDescriptor> _deduplicate(
    List<DragDropItemDescriptor> items,
  ) {
    final Set<String> seen = <String>{};
    final List<DragDropItemDescriptor> deduplicated =
        <DragDropItemDescriptor>[];
    for (final DragDropItemDescriptor item in items) {
      final String key = switch (item.kind) {
        DragDropItemKind.songInfoLike =>
          'song:${item.song!.path}:${item.song!.track ?? ''}:${item.song!.index ?? ''}',
        DragDropItemKind.localFile => 'file:${item.path}',
        DragDropItemKind.directory => 'dir:${item.path}',
      };
      if (seen.add(key)) {
        deduplicated.add(item);
      }
    }
    return deduplicated;
  }

  String _summarizeItems(List<DragDropItemDescriptor> items) {
    return items
        .map((DragDropItemDescriptor item) {
          final String detail = switch (item.kind) {
            DragDropItemKind.songInfoLike =>
              'track=${item.song?.track ?? '-'},index=${item.song?.index ?? '-'}',
            _ => '-',
          };
          return '${item.kind.name}(${p.basename(item.path)},$detail)';
        })
        .join(', ');
  }

  void _logDiagnostic(String message) {
    if (!enableDiagnostics || !kDebugMode) {
      return;
    }
    final String line = '[DragDropPort] $message';
    final void Function(String message)? logger = debugLogger;
    if (logger != null) {
      logger(line);
      return;
    }
    _dragDropLogger.debug(message);
  }

  void _logPrivateMimeFailure(
    String format,
    int byteLength,
    LddcDropException error,
  ) {
    // 解析细节只进入诊断日志，返回给 UI 的结果仅保留稳定错误码。
    _logDiagnostic(
      'privateMime format=$format bytes=$byteLength '
      'error=${error.runtimeType} detail=${error.message}',
    );
  }
}

class _DesktopDragDropChannelHub {
  _DesktopDragDropChannelHub._();

  static const MethodChannel _channel = MethodChannel(
    kDesktopDragDropChannelName,
  );
  static final StreamController<DesktopDragDropEvent> _controller =
      StreamController<DesktopDragDropEvent>.broadcast();
  static bool _isInitialized = false;

  static Stream<DesktopDragDropEvent> get events {
    _ensureInitialized();
    return _controller.stream;
  }

  static void _ensureInitialized() {
    if (_isInitialized) {
      return;
    }
    _isInitialized = true;
    // native 侧只负责采集平台拖放 payload，业务解析统一留在 Dart 端。
    _channel.setMethodCallHandler((MethodCall call) async {
      final DesktopDragDropEventPhase? phase = switch (call.method) {
        'dragEnter' => DesktopDragDropEventPhase.enter,
        'dragUpdate' => DesktopDragDropEventPhase.update,
        'dragLeave' => DesktopDragDropEventPhase.leave,
        'performDrop' => DesktopDragDropEventPhase.drop,
        _ => null,
      };
      if (phase == null) {
        return;
      }
      _controller.add(
        DesktopDragDropEvent(
          phase: phase,
          payload: _desktopDragDropPayloadFromMethodCall(call.arguments),
        ),
      );
    });
  }
}

class _ParsedDragItemResult {
  const _ParsedDragItemResult({
    this.items = const <DragDropItemDescriptor>[],
    this.failure,
  });

  final List<DragDropItemDescriptor> items;
  final DragDropFailure? failure;
}

String? _readString(Object? value) {
  if (value is String) {
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
  return null;
}

double _readDouble(Object? value) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return 0;
}

List<String> _readStringList(Object? value) {
  if (value is! Iterable<Object?>) {
    return const <String>[];
  }
  return value.map(_readString).whereType<String>().toList(growable: false);
}

Set<String> _readStringSet(Object? value) {
  return _readStringList(value).toSet();
}

Map<String, Uint8List> _readPrivateData(Object? value) {
  if (value is! Map<Object?, Object?>) {
    return const <String, Uint8List>{};
  }
  final Map<String, Uint8List> result = <String, Uint8List>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final String? key = _readString(entry.key);
    final Uint8List? bytes = _coerceBytes(entry.value);
    if (key == null ||
        bytes == null ||
        bytes.length > kDesktopDropPrivateDataMaxBytes) {
      continue;
    }
    result[key] = bytes;
  }
  return result;
}

Uint8List? _coerceBytes(Object? value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is ByteData) {
    return value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  return null;
}
