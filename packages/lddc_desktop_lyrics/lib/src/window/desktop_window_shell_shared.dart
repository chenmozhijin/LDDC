import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../logging/desktop_lyrics_logger.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_window_backend.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_strings.dart';

class DesktopWindowDragSurface extends StatelessWidget {
  const DesktopWindowDragSurface({
    super.key,
    required this.child,
    this.onSetBounds,
    this.logger = const DesktopLyricsLogger(),
  });

  final Widget child;
  final Future<void> Function(Rect bounds)? onSetBounds;
  final DesktopLyricsLogger logger;

  @override
  Widget build(BuildContext context) {
    return DesktopWindowDragSurfaceBody(
      onSetBounds: onSetBounds,
      logger: logger,
      child: child,
    );
  }
}

class DesktopWindowDragSurfaceBody extends StatefulWidget {
  const DesktopWindowDragSurfaceBody({
    super.key,
    required this.child,
    this.onSetBounds,
    this.logger = const DesktopLyricsLogger(),
  });

  final Widget child;
  final Future<void> Function(Rect bounds)? onSetBounds;
  final DesktopLyricsLogger logger;

  @override
  State<DesktopWindowDragSurfaceBody> createState() =>
      DesktopWindowDragSurfaceBodyState();
}

class DesktopWindowDragSurfaceBodyState
    extends State<DesktopWindowDragSurfaceBody> {
  static const double _kDirectDragSlop = 3;
  static const Duration _kNativeDoubleClickInterval = Duration(
    milliseconds: 320,
  );
  static const double _kNativeDoubleClickSlop = 18;

  int? _activeDirectPointer;
  int? _nativeDragSuppressedPointer;
  Duration? _lastMouseDownTime;
  Offset? _lastMouseDownGlobalPosition;
  Offset? _directDragStartGlobal;
  Offset? _latestDirectDragGlobal;
  Rect? _directDragStartBounds;
  bool _setBoundsInFlight = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (DragStartDetails details) {
          if (_usesNativeWindowDrag(details.kind) &&
              _nativeDragSuppressedPointer == null) {
            unawaited(windowManager.startDragging());
          }
        },
        child: widget.child,
      ),
    );
  }

  bool _usesNativeWindowDrag(ui.PointerDeviceKind? kind) {
    return kind == null || kind == ui.PointerDeviceKind.mouse;
  }

  bool _usesDirectWindowDrag(ui.PointerDeviceKind kind) {
    return kind == ui.PointerDeviceKind.touch ||
        kind == ui.PointerDeviceKind.stylus ||
        kind == ui.PointerDeviceKind.invertedStylus;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _updateNativeDragSuppression(event);
    if (!_usesDirectWindowDrag(event.kind) || _activeDirectPointer != null) {
      return;
    }
    _activeDirectPointer = event.pointer;
    _directDragStartGlobal = event.position;
    _latestDirectDragGlobal = event.position;
    _directDragStartBounds = null;
    unawaited(_loadDirectDragStartBounds(event.pointer));
  }

  void _updateNativeDragSuppression(PointerDownEvent event) {
    if (!_usesNativeWindowDrag(event.kind)) {
      return;
    }
    final Duration? previousTime = _lastMouseDownTime;
    final Offset? previousPosition = _lastMouseDownGlobalPosition;
    final bool isDoubleClick =
        previousTime != null &&
        previousPosition != null &&
        event.timeStamp - previousTime <= _kNativeDoubleClickInterval &&
        (event.position - previousPosition).distance <= _kNativeDoubleClickSlop;
    // 浮窗拖拽面会把鼠标拖动交给原生窗口系统，行为上接近标题栏。
    // 第二次快速点击如果继续触发 startDragging，Windows 可能把它解释为
    // 标题栏双击并最大化/还原窗口。这里只屏蔽当前鼠标指针的原生拖动，
    // 不使用 onDoubleTap，避免 Flutter 双击识别器额外创建短生命周期计时器。
    _nativeDragSuppressedPointer = isDoubleClick ? event.pointer : null;
    _lastMouseDownTime = event.timeStamp;
    _lastMouseDownGlobalPosition = event.position;
  }

  Future<void> _loadDirectDragStartBounds(int pointer) async {
    late final Rect bounds;
    try {
      bounds = await windowManager.getBounds();
    } on Object catch (error) {
      widget.logger
          .child('desktop-window-drag')
          .warning(
            'direct drag getBounds failed',
            fields: <String, Object?>{'error': error.toString()},
          );
      return;
    }
    if (!mounted || _activeDirectPointer != pointer) {
      return;
    }
    _directDragStartBounds = bounds;
    _scheduleDirectBoundsApply();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_activeDirectPointer != event.pointer) {
      return;
    }
    _latestDirectDragGlobal = event.position;
    _scheduleDirectBoundsApply();
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_nativeDragSuppressedPointer == event.pointer) {
      _nativeDragSuppressedPointer = null;
    }
    if (_activeDirectPointer != event.pointer) {
      return;
    }
    _activeDirectPointer = null;
    _directDragStartGlobal = null;
    _latestDirectDragGlobal = null;
    _directDragStartBounds = null;
  }

  void _scheduleDirectBoundsApply() {
    if (_setBoundsInFlight) {
      return;
    }
    final Rect? target = _resolveDirectDragBounds();
    if (target == null) {
      return;
    }
    _setBoundsInFlight = true;
    unawaited(_applyDirectDragBounds(target));
  }

  Future<void> _applyDirectDragBounds(Rect target) async {
    try {
      final Future<void> Function(Rect bounds)? onSetBounds =
          widget.onSetBounds;
      if (onSetBounds == null) {
        await windowManager.setBounds(target);
      } else {
        await onSetBounds(target);
      }
    } on Object catch (error) {
      widget.logger
          .child('desktop-window-drag')
          .warning(
            'direct drag setBounds failed',
            fields: <String, Object?>{'error': error.toString()},
          );
    } finally {
      if (mounted) {
        _setBoundsInFlight = false;
        final Rect? nextTarget = _resolveDirectDragBounds();
        if (nextTarget != null && !_rectEquals(nextTarget, target)) {
          _scheduleDirectBoundsApply();
        }
      }
    }
  }

  Rect? _resolveDirectDragBounds() {
    final Rect? startBounds = _directDragStartBounds;
    final Offset? startGlobal = _directDragStartGlobal;
    final Offset? currentGlobal = _latestDirectDragGlobal;
    if (startBounds == null || startGlobal == null || currentGlobal == null) {
      return null;
    }
    final Offset delta = currentGlobal - startGlobal;
    if (delta.distance < _kDirectDragSlop) {
      return null;
    }
    return startBounds.shift(delta);
  }

  bool _rectEquals(Rect left, Rect right) {
    return left.left == right.left &&
        left.top == right.top &&
        left.width == right.width &&
        left.height == right.height;
  }
}

bool desktopShellFloatingStyleEquals(
  DesktopFloatingWindowFlags? left,
  DesktopFloatingWindowFlags? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.alwaysOnTop == right.alwaysOnTop &&
      left.clickThrough == right.clickThrough &&
      left.frameless == right.frameless &&
      left.opacity == right.opacity;
}

bool desktopShellFloatingInfoBadgeEquals(
  DesktopLyricsInfoBadgeSnapshot left,
  DesktopLyricsInfoBadgeSnapshot right,
) {
  return left.source == right.source &&
      left.lyricsType == right.lyricsType &&
      left.isInstrumental == right.isInstrumental;
}

List<PopupMenuEntry<DesktopWindowActionType>> buildFloatingMenuEntries(
  DesktopLyricsWindowStrings strings,
  DesktopWindowActionSnapshot actions,
) {
  return <PopupMenuEntry<DesktopWindowActionType>>[
    if (actions.canOpenSelector)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.openSelector,
        child: Text(strings.selectLyrics),
      ),
    CheckedPopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleInstrumental,
      checked: actions.isInstrumental,
      child: Text(strings.markInstrumental),
    ),
    CheckedPopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleAutoSearchDisabled,
      checked: actions.isAutoSearchDisabled,
      child: Text(strings.disableAutoSearch),
    ),
    if (actions.canUnlinkLyrics)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.unlinkLyrics,
        child: Text(strings.unlinkLyrics),
      ),
    if (actions.canOpenAssociationManager)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.openAssociationManager,
        child: Text(strings.openAssociationManager),
      ),
    PopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleFloatingVisibility,
      child: Text(strings.toggleFloating),
    ),
    if (actions.canShowMainWindow)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.showMainWindow,
        child: Text(strings.showMainWindow),
      ),
    CheckedPopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleClickThrough,
      checked: actions.clickThroughEnabled,
      child: Text(strings.clickThrough),
    ),
  ];
}

List<PopupMenuEntry<DesktopWindowActionType>> buildPanelMenuEntries(
  DesktopLyricsWindowStrings strings,
  DesktopWindowActionSnapshot actions,
) {
  return <PopupMenuEntry<DesktopWindowActionType>>[
    if (actions.canOpenSelector)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.openSelector,
        child: Text(strings.selectLyrics),
      ),
    if (actions.canUnlinkLyrics)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.unlinkLyrics,
        child: Text(strings.unlinkLyrics),
      ),
    CheckedPopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleInstrumental,
      checked: actions.isInstrumental,
      child: Text(strings.markInstrumental),
    ),
    CheckedPopupMenuItem<DesktopWindowActionType>(
      value: DesktopWindowActionType.toggleAutoSearchDisabled,
      checked: actions.isAutoSearchDisabled,
      child: Text(strings.disableAutoSearch),
    ),
    if (actions.canShowMainWindow)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.showMainWindow,
        child: Text(strings.showMainWindow),
      ),
    if (actions.canOpenAssociationManager)
      PopupMenuItem<DesktopWindowActionType>(
        value: DesktopWindowActionType.openAssociationManager,
        child: Text(strings.openAssociationManager),
      ),
  ];
}

String? buildInfoBadgeText(
  DesktopLyricsWindowStrings strings,
  DesktopLyricsInfoBadgeSnapshot snapshot,
) {
  if (snapshot.isInstrumental) {
    return strings.instrumental;
  }
  final List<String> parts = <String>[
    if (snapshot.source != null) strings.sourceLabel(snapshot.source!),
    if (snapshot.lyricsType != null)
      strings.lyricsTypeLabel(snapshot.lyricsType!),
  ];
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' - ');
}

class DesktopFloatingControlBar extends StatelessWidget {
  const DesktopFloatingControlBar({
    super.key,
    required this.infoText,
    required this.strings,
    required this.actions,
    required this.isPlaying,
    required this.onSelectLyrics,
    required this.onHide,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
  });

  final String? infoText;
  final DesktopLyricsWindowStrings strings;
  final DesktopWindowActionSnapshot actions;
  final bool isPlaying;
  final VoidCallback? onSelectLyrics;
  final VoidCallback? onHide;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayPause;

  @override
  Widget build(BuildContext context) {
    final Color foreground = Colors.white;
    return Material(
      color: const Color(0xAA101418),
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (infoText != null) ...<Widget>[
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  infoText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground),
                ),
              ),
              const SizedBox(width: 8),
            ],
            DesktopFloatingControlButton(
              tooltip: strings.selectLyrics,
              icon: Icons.queue_music_outlined,
              onPressed: onSelectLyrics,
            ),
            if (onPrevious != null) ...<Widget>[
              const SizedBox(width: 4),
              DesktopFloatingControlButton(
                tooltip: strings.previous,
                icon: Icons.skip_previous_rounded,
                onPressed: onPrevious,
              ),
            ],
            if (onPlayPause != null) ...<Widget>[
              const SizedBox(width: 4),
              DesktopFloatingControlButton(
                tooltip: isPlaying ? strings.pause : strings.play,
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: onPlayPause,
              ),
            ],
            if (onNext != null) ...<Widget>[
              const SizedBox(width: 4),
              DesktopFloatingControlButton(
                tooltip: strings.next,
                icon: Icons.skip_next_rounded,
                onPressed: onNext,
              ),
            ],
            const SizedBox(width: 4),
            DesktopFloatingControlButton(
              tooltip: strings.hide,
              icon: Icons.visibility_off_outlined,
              onPressed: onHide,
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopFloatingControlButton extends StatelessWidget {
  const DesktopFloatingControlButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          hoverColor: Colors.white.withValues(alpha: 0.16),
          highlightColor: Colors.white.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}
