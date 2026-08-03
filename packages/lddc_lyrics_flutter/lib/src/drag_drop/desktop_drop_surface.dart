import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'drag_drop.dart';

typedef DesktopDropOverlayBuilder =
    Widget Function(BuildContext context, bool isDragging);

/// 桌面拖放 UI 表面，只处理命中测试、遮罩和事件订阅。
///
/// MethodChannel、平台 MIME 与私有字节解码仍由宿主 adapter 负责，因此该组件
/// 可以被不同 Flutter 宿主复用，也不会把平台实现反向带入 feature/shared 层。
class DesktopDropSurface extends StatefulWidget {
  const DesktopDropSurface({
    super.key,
    required this.dragDropPort,
    required this.onDrop,
    required this.child,
    this.overlayBuilder,
  });

  final DragDropPort dragDropPort;
  final Future<void> Function(DragDropParseResult result) onDrop;
  final Widget child;
  final DesktopDropOverlayBuilder? overlayBuilder;

  @override
  State<DesktopDropSurface> createState() => _DesktopDropSurfaceState();
}

class _DesktopDropSurfaceState extends State<DesktopDropSurface> {
  StreamSubscription<DesktopDragDropEvent>? _subscription;
  bool _isDragOver = false;

  DesktopDragDropPort? get _desktopPort {
    final DragDropPort port = widget.dragDropPort;
    if (port is DesktopDragDropPort && port.isSupported) {
      return port;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _bindPort();
  }

  @override
  void didUpdateWidget(covariant DesktopDropSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dragDropPort, widget.dragDropPort)) {
      _bindPort();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_desktopPort == null) {
      return widget.child;
    }
    return Stack(
      children: <Widget>[
        Positioned.fill(child: widget.child),
        if (_isDragOver && widget.overlayBuilder != null)
          Positioned.fill(child: widget.overlayBuilder!(context, true)),
      ],
    );
  }

  void _bindPort() {
    _subscription?.cancel();
    _subscription = null;
    final DesktopDragDropPort? port = _desktopPort;
    if (port == null) {
      _setDragOver(false);
      return;
    }
    _subscription = port.events.listen((DesktopDragDropEvent event) {
      _handleEvent(port, event);
    });
  }

  void _handleEvent(DesktopDragDropPort port, DesktopDragDropEvent event) {
    if (!mounted) {
      return;
    }
    if (event.phase == DesktopDragDropEventPhase.leave) {
      _setDragOver(false);
      return;
    }
    final bool inside = _containsEvent(event.payload);
    switch (event.phase) {
      case DesktopDragDropEventPhase.enter:
      case DesktopDragDropEventPhase.update:
        _setDragOver(inside);
      case DesktopDragDropEventPhase.drop:
        _setDragOver(false);
        if (inside) {
          unawaited(widget.onDrop(port.parsePayload(event.payload)));
        }
      case DesktopDragDropEventPhase.leave:
        break;
    }
  }

  bool _containsEvent(DesktopDragDropPayload payload) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        !_isPainted(renderObject)) {
      return false;
    }
    final double scale = payload.coordinateSpace == 'physical'
        ? View.of(context).devicePixelRatio
        : 1;
    final Offset globalPosition = Offset(payload.x / scale, payload.y / scale);
    final Offset localPosition = renderObject.globalToLocal(globalPosition);
    return (Offset.zero & renderObject.size).contains(localPosition);
  }

  bool _isPainted(RenderObject renderObject) {
    RenderObject current = renderObject;
    RenderObject? parent = _renderParent(current);
    while (parent != null) {
      if (parent is RenderOffstage && parent.offstage) {
        return false;
      }
      if (parent is RenderIndexedStack &&
          !_isCurrentIndexedStackChild(parent, current)) {
        return false;
      }
      current = parent;
      parent = _renderParent(current);
    }
    return true;
  }

  RenderObject? _renderParent(RenderObject renderObject) {
    final Object? parent = renderObject.parent;
    return parent is RenderObject ? parent : null;
  }

  bool _isCurrentIndexedStackChild(
    RenderIndexedStack stack,
    RenderObject child,
  ) {
    bool isCurrent = false;
    int childIndex = 0;
    stack.visitChildren((RenderObject candidate) {
      if (identical(candidate, child)) {
        isCurrent = stack.index == childIndex;
      }
      childIndex += 1;
    });
    return isCurrent;
  }

  void _setDragOver(bool value) {
    if (_isDragOver == value) {
      return;
    }
    setState(() {
      _isDragOver = value;
    });
  }
}
