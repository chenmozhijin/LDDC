import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_projection_runtime.dart';
import '../projection/desktop_lyrics_scene.dart';
import 'desktop_window_interaction.dart';

/// 外部 foobar IPC 上报的面板尺寸坐标空间。
///
/// 宽高字段只用于保持既有插件协议兼容，embedded 原生宿主始终重新查询
/// foobar panel HWND 的客户区物理尺寸，禁止把协议值当成几何真源。
enum PanelSizeSpace {
  hostPhysicalPx,
  hostLogicalPx,
  flutterLogicalPx,
  unknownRaw,
}

class PanelSurfaceUpdate {
  const PanelSurfaceUpdate({
    required this.width,
    required this.height,
    required this.sizeSpace,
    required this.visible,
  });

  final int width;
  final int height;
  final PanelSizeSpace sizeSpace;
  final bool visible;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PanelSurfaceUpdate &&
            other.width == width &&
            other.height == height &&
            other.sizeSpace == sizeSpace &&
            other.visible == visible;
  }

  @override
  int get hashCode => Object.hash(width, height, sizeSpace, visible);
}

/// foobar panel HWND 当前存在，但客户区尚未形成可创建的非零表面。
class DesktopPanelSurfaceUnavailable implements Exception {
  const DesktopPanelSurfaceUnavailable();

  @override
  String toString() => 'DesktopPanelSurfaceUnavailable';
}

/// 原生 embedded root 当前已经提交的最小表面状态。
///
/// 这里只保留渲染事务真正需要的身份、尺寸和可见性。窗口句柄与旧的多组
/// generation 属于原生测试信息，不再进入生产 Dart 状态。
class DesktopPanelSurfaceState {
  const DesktopPanelSurfaceState({
    required this.surfaceRevision,
    required this.attached,
    required this.visible,
    required this.clientSizePx,
    required this.dpi,
  });

  final int surfaceRevision;
  final bool attached;
  final bool visible;
  final Size clientSizePx;
  final int dpi;

  bool get surfaceReady =>
      attached && clientSizePx.width > 0 && clientSizePx.height > 0;

  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'surfaceRevision': surfaceRevision,
      'attached': attached,
      'visible': visible,
      'clientWidthPx': clientSizePx.width,
      'clientHeightPx': clientSizePx.height,
      'dpi': dpi,
    };
  }

  static DesktopPanelSurfaceState? fromPayload(Object? payload) {
    final Map<Object?, Object?> map = DynamicReader.asMap(payload);
    if (map.isEmpty) {
      return null;
    }
    final double width = DynamicReader.asDouble(map['clientWidthPx']) ?? 0;
    final double height = DynamicReader.asDouble(map['clientHeightPx']) ?? 0;
    return DesktopPanelSurfaceState(
      surfaceRevision: DynamicReader.asInt(map['surfaceRevision']) ?? 0,
      attached: DynamicReader.asBool(map['attached']) ?? false,
      visible: DynamicReader.asBool(map['visible']) ?? false,
      clientSizePx: Size(
        width.isFinite && width >= 0 ? width : 0,
        height.isFinite && height >= 0 ? height : 0,
      ),
      dpi: (DynamicReader.asInt(map['dpi']) ?? 96).clamp(1, 960),
    );
  }
}

/// 主窗口原子发送给 Panel 子引擎的一次内容更新。
class DesktopPanelContentPayload {
  const DesktopPanelContentPayload({
    required this.contentRevision,
    required this.session,
    required this.sceneRef,
    required this.sceneBytes,
  });

  final int contentRevision;
  final DesktopPanelSessionSnapshot session;
  final DesktopSceneRef? sceneRef;
  final Uint8List? sceneBytes;
}

/// Panel 页面唯一可观察的内容状态。
///
/// session、sceneRef 和解码后的 sceneDocument 必须一次发布，杜绝切歌时
/// 出现新会话与旧歌词场景混合的可渲染中间状态。
class DesktopPanelContentState {
  const DesktopPanelContentState({
    required this.snapshot,
    required this.sceneDocument,
  });

  final DesktopPanelWindowSnapshot snapshot;
  final DesktopLyricsSceneDocument? sceneDocument;
}

/// Panel 子引擎确认当前内容与表面组合已经完成一帧提交。
class DesktopPanelPresentationReady {
  const DesktopPanelPresentationReady({
    required this.contentRevision,
    required this.surfaceRevision,
  });

  final int contentRevision;
  final int surfaceRevision;
}

class DesktopPanelCreateRequest {
  const DesktopPanelCreateRequest({
    required this.instanceId,
    required this.panelId,
    required this.hostWindowId,
    required this.channelName,
    required this.generation,
    this.initialSurface,
  });

  final int instanceId;
  final int panelId;
  final int hostWindowId;
  final String channelName;
  final int generation;
  final PanelSurfaceUpdate? initialSurface;
}

typedef DesktopPanelWindowIntentHandler =
    Future<bool> Function(DesktopPanelWindowIntent intent);

/// foobar embedded Panel 宿主抽象。
abstract interface class DesktopPanelWindowHostPort {
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler);

  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  });

  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  });

  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  });

  Future<void> destroyPanel({required int instanceId, required int panelId});
}

/// Windows 原生 embedded root 壳接口。
abstract interface class DesktopWindowsPanelShellPort {
  void dispose();

  Future<DesktopPanelSurfaceState> createPanel({
    required DesktopPanelCreateRequest request,
  });

  Future<DesktopPanelSurfaceState> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  });

  Future<void> setPanelVisibility({
    required int instanceId,
    required int panelId,
    required bool visible,
  });

  Future<void> destroyPanel({required int instanceId, required int panelId});
}

class DesktopNoopPanelWindowHost implements DesktopPanelWindowHostPort {
  const DesktopNoopPanelWindowHost();

  @override
  void setIntentHandler(DesktopPanelWindowIntentHandler? handler) {}

  @override
  Future<void> createPanel({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    DesktopPanelWindowSnapshot? initialSnapshot,
    PanelSurfaceUpdate? initialSurface,
  }) async {}

  @override
  Future<void> syncPanelSnapshot({
    required int instanceId,
    required List<int> panelIds,
    required DesktopPanelWindowSnapshot snapshot,
  }) async {}

  @override
  Future<void> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {}

  @override
  Future<void> destroyPanel({
    required int instanceId,
    required int panelId,
  }) async {}
}

class DesktopPanelSessionSnapshot {
  factory DesktopPanelSessionSnapshot({
    String? songId,
    List<String> enabledLangs = const <String>['orig'],
    List<RgbColor> playedColors = const <RgbColor>[
      RgbColor(0, 255, 255),
      RgbColor(0, 128, 255),
    ],
    List<RgbColor> unplayedColors = const <RgbColor>[
      RgbColor(255, 0, 0),
      RgbColor(255, 128, 128),
    ],
    String fontFamily = '',
    double fontSize = 12,
    bool showFurigana = true,
    int refreshRate = -1,
    bool visible = true,
    DesktopWindowActionSnapshot actions =
        const DesktopWindowActionSnapshot.empty(),
  }) {
    return DesktopPanelSessionSnapshot._(
      songId: songId,
      enabledLangs: List<String>.unmodifiable(enabledLangs),
      playedColors: List<RgbColor>.unmodifiable(playedColors),
      unplayedColors: List<RgbColor>.unmodifiable(unplayedColors),
      fontFamily: fontFamily,
      fontSize: fontSize,
      showFurigana: showFurigana,
      refreshRate: refreshRate,
      visible: visible,
      actions: actions,
    );
  }

  const DesktopPanelSessionSnapshot.empty()
    : songId = null,
      enabledLangs = const <String>['orig'],
      playedColors = const <RgbColor>[
        RgbColor(0, 255, 255),
        RgbColor(0, 128, 255),
      ],
      unplayedColors = const <RgbColor>[
        RgbColor(255, 0, 0),
        RgbColor(255, 128, 128),
      ],
      fontFamily = '',
      fontSize = 12,
      showFurigana = true,
      refreshRate = -1,
      visible = true,
      actions = const DesktopWindowActionSnapshot.empty();

  const DesktopPanelSessionSnapshot._({
    required this.songId,
    required this.enabledLangs,
    required this.playedColors,
    required this.unplayedColors,
    required this.fontFamily,
    required this.fontSize,
    required this.showFurigana,
    required this.refreshRate,
    required this.visible,
    required this.actions,
  });

  final String? songId;
  final List<String> enabledLangs;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final String fontFamily;
  final double fontSize;
  final bool showFurigana;
  final int refreshRate;
  final bool visible;
  final DesktopWindowActionSnapshot actions;
}

class DesktopPanelAnchorSnapshot {
  const DesktopPanelAnchorSnapshot({
    this.pluginPlaybackTimeMs = 0,
    this.pluginSendTimeMs,
    this.hostReceivedAtMs = 0,
    this.isPlaying = false,
    this.syncRevision = 0,
    this.eventKind = DesktopPlaybackEventKind.other,
    this.sceneId,
    this.songToken,
  });

  final int pluginPlaybackTimeMs;
  final int? pluginSendTimeMs;
  final int hostReceivedAtMs;
  final bool isPlaying;
  final int syncRevision;
  final DesktopPlaybackEventKind eventKind;
  final String? sceneId;
  final String? songToken;
}

class DesktopPanelWindowSnapshot {
  const DesktopPanelWindowSnapshot({
    required this.session,
    required this.anchor,
    this.contentRevision = 0,
    this.sceneRef,
  });

  final DesktopPanelSessionSnapshot session;
  final DesktopPanelAnchorSnapshot anchor;
  final int contentRevision;
  final DesktopSceneRef? sceneRef;
}
