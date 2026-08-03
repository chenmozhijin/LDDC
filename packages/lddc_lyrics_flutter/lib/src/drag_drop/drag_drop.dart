import 'dart:async';
import 'dart:typed_data';

/// 拖拽条目的业务分类。
///
/// 页面只需要知道“这是可解析的歌曲条目、本地文件还是目录”。具体平台 MIME、
/// 私有剪贴板格式和字节解码都留在 platform 实现里，避免 feature 层被平台细节污染。
enum DragDropItemKind { songInfoLike, localFile, directory }

/// 拖拽解析失败的稳定分类。
///
/// 这里只保存业务可判断的错误码，不携带平台异常文本。UI 根据当前页面语境和语言
/// 生成提示，既避免把底层解析细节暴露给用户，也不会让 platform 层依赖本地化代码。
enum DragDropFailure { unsupportedItem, unreadablePrivateMime }

/// 从播放器拖拽数据中解析出的歌曲描述。
final class DragDropSongDescriptor {
  DragDropSongDescriptor({required String path, this.track, this.index})
    : path = _requireDropPath(path);

  final String path;
  final String? track;
  final String? index;
}

/// 拖拽输入在业务层可消费的最小描述。
final class DragDropItemDescriptor {
  DragDropItemDescriptor.song(DragDropSongDescriptor value)
    : kind = DragDropItemKind.songInfoLike,
      path = value.path,
      song = value;

  DragDropItemDescriptor.file(String path)
    : kind = DragDropItemKind.localFile,
      path = _requireDropPath(path),
      song = null;

  DragDropItemDescriptor.directory(String path)
    : kind = DragDropItemKind.directory,
      path = _requireDropPath(path),
      song = null;

  final DragDropItemKind kind;
  final String path;
  final DragDropSongDescriptor? song;
}

/// 拖拽解析结果。
final class DragDropParseResult {
  DragDropParseResult({
    required List<DragDropItemDescriptor> items,
    required Set<String> platformFormats,
    this.failure,
  }) : items = List<DragDropItemDescriptor>.unmodifiable(items),
       platformFormats = Set<String>.unmodifiable(platformFormats);

  final List<DragDropItemDescriptor> items;
  final Set<String> platformFormats;
  final DragDropFailure? failure;

  bool get hasItems => items.isNotEmpty;
}

String _requireDropPath(String path) {
  if (path.trim().isEmpty) {
    throw ArgumentError.value(path, 'path', '拖拽条目的路径不能为空');
  }
  return path;
}

/// 拖拽端口标记。
///
/// shared 层只暴露平台无关的解析结果模型。系统拖放事件、平台 MIME 和原生
/// payload 都留在 platform adapter 内，避免 feature 页面和业务状态被桌面实现绑定。
abstract interface class DragDropPort {}

enum DesktopDragDropEventPhase { enter, update, leave, drop }

/// 桌面原生拖放事件的跨宿主载荷；平台 adapter 负责从 MethodChannel 解码。
class DesktopDragDropPayload {
  const DesktopDragDropPayload({
    required this.platform,
    required this.x,
    required this.y,
    required this.coordinateSpace,
    required this.formats,
    required this.files,
    required this.privateData,
    this.text,
  });

  final String platform;
  final double x;
  final double y;
  final String coordinateSpace;
  final Set<String> formats;
  final List<String> files;
  final Map<String, Uint8List> privateData;
  final String? text;
}

class DesktopDragDropEvent {
  const DesktopDragDropEvent({required this.phase, required this.payload});

  final DesktopDragDropEventPhase phase;
  final DesktopDragDropPayload payload;
}

/// 桌面事件端口。共享 Flutter 表面只消费该端口，不接触 MethodChannel 或 MIME。
abstract interface class DesktopDragDropPort implements DragDropPort {
  bool get isSupported;

  Stream<DesktopDragDropEvent> get events;

  DragDropParseResult parsePayload(DesktopDragDropPayload payload);
}

final class UnsupportedDragDropPort implements DragDropPort {
  const UnsupportedDragDropPort();
}
