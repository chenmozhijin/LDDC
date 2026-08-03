import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_projection_runtime.dart';
import '../projection/desktop_lyrics_scene.dart';
import 'desktop_panel_host.dart';
import 'desktop_window_interaction.dart';

/// 桌面窗口后端聚合口。
///
/// 所有窗口都按 `instanceId` 分片治理，具体应用只负责注入三类 host 实现。
abstract interface class DesktopWindowBackend {
  DesktopFloatingWindowHostPort get floatingHost;

  DesktopSelectorWindowHostPort get selectorHost;

  DesktopPanelWindowHostPort get panelHost;
}

/// 默认的窗口后端组合实现，不包含额外状态或业务逻辑。
class DesktopWindowBackendPorts implements DesktopWindowBackend {
  const DesktopWindowBackendPorts({
    required this.floatingHost,
    required this.selectorHost,
    required this.panelHost,
  });

  @override
  final DesktopFloatingWindowHostPort floatingHost;

  @override
  final DesktopSelectorWindowHostPort selectorHost;

  @override
  final DesktopPanelWindowHostPort panelHost;
}

/// 桌面歌词浮窗的窗口壳配置。
class DesktopFloatingWindowFlags {
  const DesktopFloatingWindowFlags({
    this.visible = false,
    this.alwaysOnTop = true,
    this.clickThrough = false,
    this.frameless = true,
    this.opacity = 1.0,
  });

  final bool visible;
  final bool alwaysOnTop;
  final bool clickThrough;
  final bool frameless;
  final double opacity;
}

/// 浮窗低频会话快照。
class DesktopFloatingSessionSnapshot {
  factory DesktopFloatingSessionSnapshot({
    String? songId,
    String? songTitle,
    String? artistText,
    List<String> enabledLangs = const <String>[],
    List<RgbColor> playedColors = const <RgbColor>[
      RgbColor(0, 255, 255),
      RgbColor(0, 128, 255),
    ],
    List<RgbColor> unplayedColors = const <RgbColor>[
      RgbColor(255, 0, 0),
      RgbColor(255, 128, 128),
    ],
    String fontFamily = '',
    double fontSize = 30.0,
    bool showFurigana = true,
    bool isPlaying = false,
    bool isInstrumental = false,
    bool hasStaticDisplay = false,
    int refreshRate = -1,
    DesktopWindowActionSnapshot actions =
        const DesktopWindowActionSnapshot.empty(),
    DesktopLyricsInfoBadgeSnapshot infoBadge =
        const DesktopLyricsInfoBadgeSnapshot(),
  }) {
    return DesktopFloatingSessionSnapshot._(
      songId: songId,
      songTitle: songTitle,
      artistText: artistText,
      enabledLangs: List<String>.unmodifiable(enabledLangs),
      playedColors: List<RgbColor>.unmodifiable(playedColors),
      unplayedColors: List<RgbColor>.unmodifiable(unplayedColors),
      fontFamily: fontFamily,
      fontSize: fontSize,
      showFurigana: showFurigana,
      isPlaying: isPlaying,
      isInstrumental: isInstrumental,
      hasStaticDisplay: hasStaticDisplay,
      refreshRate: refreshRate,
      actions: actions,
      infoBadge: infoBadge,
    );
  }

  const DesktopFloatingSessionSnapshot.empty()
    : songId = null,
      songTitle = null,
      artistText = null,
      enabledLangs = const <String>[],
      playedColors = const <RgbColor>[
        RgbColor(0, 255, 255),
        RgbColor(0, 128, 255),
      ],
      unplayedColors = const <RgbColor>[
        RgbColor(255, 0, 0),
        RgbColor(255, 128, 128),
      ],
      fontFamily = '',
      fontSize = 30.0,
      showFurigana = true,
      isPlaying = false,
      isInstrumental = false,
      hasStaticDisplay = false,
      refreshRate = -1,
      actions = const DesktopWindowActionSnapshot.empty(),
      infoBadge = const DesktopLyricsInfoBadgeSnapshot();

  const DesktopFloatingSessionSnapshot._({
    required this.songId,
    required this.songTitle,
    required this.artistText,
    required this.enabledLangs,
    required this.playedColors,
    required this.unplayedColors,
    required this.fontFamily,
    required this.fontSize,
    required this.showFurigana,
    required this.isPlaying,
    required this.isInstrumental,
    required this.hasStaticDisplay,
    required this.refreshRate,
    required this.actions,
    required this.infoBadge,
  });

  final String? songId;
  final String? songTitle;
  final String? artistText;
  final List<String> enabledLangs;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final String fontFamily;
  final double fontSize;
  final bool showFurigana;
  final bool isPlaying;
  final bool isInstrumental;
  final bool hasStaticDisplay;
  final int refreshRate;
  final DesktopWindowActionSnapshot actions;
  final DesktopLyricsInfoBadgeSnapshot infoBadge;

  DesktopFloatingSessionSnapshot copyWith({bool? isPlaying}) {
    return DesktopFloatingSessionSnapshot(
      songId: songId,
      songTitle: songTitle,
      artistText: artistText,
      enabledLangs: enabledLangs,
      playedColors: playedColors,
      unplayedColors: unplayedColors,
      fontFamily: fontFamily,
      fontSize: fontSize,
      showFurigana: showFurigana,
      isPlaying: isPlaying ?? this.isPlaying,
      isInstrumental: isInstrumental,
      hasStaticDisplay: hasStaticDisplay,
      refreshRate: refreshRate,
      actions: actions,
      infoBadge: infoBadge,
    );
  }
}

/// 浮窗进度锚点快照。
class DesktopFloatingAnchorSnapshot {
  const DesktopFloatingAnchorSnapshot({
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

/// 浮窗窗口壳消费的统一快照。
class DesktopFloatingWindowSnapshot {
  DesktopFloatingWindowSnapshot({
    required this.session,
    this.initialWindowRect,
    this.contentRevision = 0,
    this.sceneRef,
    this.anchor,
    this.flags = const DesktopFloatingWindowFlags(),
  });

  final DesktopFloatingSessionSnapshot session;

  /// 仅供 host 首次创建子窗口时写入 launch，不能进入 content 热更新。
  final WindowRect? initialWindowRect;
  final int contentRevision;
  final DesktopSceneRef? sceneRef;
  final DesktopFloatingAnchorSnapshot? anchor;
  final DesktopFloatingWindowFlags flags;
}

/// 主窗口原子发送给浮窗的一次内容更新。
///
/// `sceneBytes` 只在场景身份变化时携带；仅样式或信息区变化时，子窗口会
/// 复用当前 revision 已解码的场景文档，避免重复复制和解码大对象。
class DesktopFloatingContentPayload {
  const DesktopFloatingContentPayload({
    required this.contentRevision,
    required this.session,
    required this.sceneRef,
    required this.sceneBytes,
  });

  final int contentRevision;
  final DesktopFloatingSessionSnapshot session;
  final DesktopSceneRef? sceneRef;
  final Uint8List? sceneBytes;
}

/// 子窗口可观察的不可变内容状态。
///
/// session、sceneRef 与解码后的 sceneDocument 必须通过同一个 notifier
/// 一次发布，任何 Widget 都不能观察到新会话与旧场景混合的中间状态。
class DesktopFloatingContentState {
  const DesktopFloatingContentState({
    required this.snapshot,
    required this.sceneDocument,
  });

  final DesktopFloatingWindowSnapshot snapshot;
  final DesktopLyricsSceneDocument? sceneDocument;
}

/// 带单调 revision 的浮窗 flags 载荷。
class DesktopFloatingFlagsPayload {
  const DesktopFloatingFlagsPayload({
    required this.revision,
    required this.flags,
  });

  final int revision;
  final DesktopFloatingWindowFlags flags;
}

/// 桌面歌词选择器上下文。
class DesktopSelectorWindowContext {
  factory DesktopSelectorWindowContext({
    String? keyword,
    Lyrics? lyrics,
    required List<String> langs,
    required int offsetMs,
    int refreshToken = 0,
  }) {
    return DesktopSelectorWindowContext._(
      keyword: keyword,
      lyrics: lyrics,
      langs: List<String>.unmodifiable(langs),
      offsetMs: offsetMs,
      refreshToken: refreshToken,
    );
  }

  const DesktopSelectorWindowContext._({
    required this.keyword,
    required this.lyrics,
    required this.langs,
    required this.offsetMs,
    required this.refreshToken,
  });

  final String? keyword;
  final Lyrics? lyrics;
  final List<String> langs;
  final int offsetMs;
  final int refreshToken;
}

/// 选择器搜索工作流的只读生命周期快照。
///
/// 该 DTO 只用于宿主资源验收，不携带 controller、Future 或平台对象；正常窗口
/// 交互不依赖它，也不会改变选择器的创建/显隐复用语义。
class DesktopSelectorRuntimeDiagnostics {
  const DesktopSelectorRuntimeDiagnostics({
    required this.available,
    required this.hasActiveBatch,
    required this.hasActiveRequest,
    required this.hasPendingRequest,
    required this.hasDebounceTimer,
    required this.isSearching,
    required this.isLoadingMore,
    required this.searchBatchStartedCount,
    required this.searchBatchSettledCount,
    required this.sourceRequestStartedCount,
    required this.sourceRequestSettledCount,
  });

  const DesktopSelectorRuntimeDiagnostics.unavailable()
    : available = false,
      hasActiveBatch = false,
      hasActiveRequest = false,
      hasPendingRequest = false,
      hasDebounceTimer = false,
      isSearching = false,
      isLoadingMore = false,
      searchBatchStartedCount = 0,
      searchBatchSettledCount = 0,
      sourceRequestStartedCount = 0,
      sourceRequestSettledCount = 0;

  final bool available;
  final bool hasActiveBatch;
  final bool hasActiveRequest;
  final bool hasPendingRequest;
  final bool hasDebounceTimer;
  final bool isSearching;
  final bool isLoadingMore;
  final int searchBatchStartedCount;
  final int searchBatchSettledCount;
  final int sourceRequestStartedCount;
  final int sourceRequestSettledCount;

  bool get isIdle =>
      available &&
      !hasActiveBatch &&
      !hasActiveRequest &&
      !hasPendingRequest &&
      !hasDebounceTimer &&
      !isSearching &&
      !isLoadingMore;
}

/// 选择器窗口回传给主机的意图。
sealed class DesktopSelectorWindowIntent {
  const DesktopSelectorWindowIntent({required this.instanceId});

  final int instanceId;
}

class DesktopSelectorLyricsSelectedIntent extends DesktopSelectorWindowIntent {
  factory DesktopSelectorLyricsSelectedIntent({
    required int instanceId,
    required Lyrics lyrics,
    String? path,
    List<String>? langs,
    int offsetMs = 0,
    bool isInstrumental = false,
  }) {
    return DesktopSelectorLyricsSelectedIntent._(
      instanceId: instanceId,
      lyrics: lyrics,
      path: path,
      langs: langs == null ? null : List<String>.unmodifiable(langs),
      offsetMs: offsetMs,
      isInstrumental: isInstrumental,
    );
  }

  const DesktopSelectorLyricsSelectedIntent._({
    required super.instanceId,
    required this.lyrics,
    required this.path,
    required this.langs,
    required this.offsetMs,
    required this.isInstrumental,
  });

  final Lyrics lyrics;
  final String? path;
  final List<String>? langs;
  final int offsetMs;
  final bool isInstrumental;
}

class DesktopSelectorWindowHiddenIntent extends DesktopSelectorWindowIntent {
  const DesktopSelectorWindowHiddenIntent({required super.instanceId});
}

/// 浮窗窗口回传给主机的意图。
sealed class DesktopFloatingWindowIntent {
  const DesktopFloatingWindowIntent({required this.instanceId});

  final int instanceId;
}

class DesktopFloatingMetricsCommittedIntent
    extends DesktopFloatingWindowIntent {
  const DesktopFloatingMetricsCommittedIntent({
    required super.instanceId,
    required this.windowRect,
    required this.fontSize,
  });

  final WindowRect windowRect;
  final double fontSize;
}

class DesktopFloatingActionWindowIntent extends DesktopFloatingWindowIntent {
  const DesktopFloatingActionWindowIntent({
    required super.instanceId,
    required this.action,
    this.controlTask,
  });

  final DesktopWindowActionType action;
  final DesktopPlaybackControlTask? controlTask;
}

/// 浮窗窗口宿主抽象。
abstract interface class DesktopFloatingWindowHostPort {
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler);

  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  });

  Future<bool> flushFloatingGeometry({required int instanceId});

  Future<void> destroyFloatingWindow({required int instanceId});
}

/// 选择器窗口宿主抽象。
abstract interface class DesktopSelectorWindowHostPort {
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler);

  Future<void> publishConfigRevision({required int revision});

  Future<void> ensureSelectorWindow({required int instanceId});

  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  });

  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  });

  Future<void> hideSelectorWindow({required int instanceId});

  Future<void> destroySelectorWindow({required int instanceId});
}

/// 非主窗口 engine 使用的空宿主，避免子窗口再次创建应用自有窗口。
class DesktopNoopFloatingWindowHost implements DesktopFloatingWindowHostPort {
  const DesktopNoopFloatingWindowHost();

  @override
  void setIntentHandler(DesktopFloatingWindowIntentHandler? handler) {}

  @override
  Future<void> destroyFloatingWindow({required int instanceId}) async {}

  @override
  Future<void> applyFloatingSnapshot({
    required int instanceId,
    required DesktopFloatingWindowSnapshot snapshot,
  }) async {}

  @override
  Future<bool> flushFloatingGeometry({required int instanceId}) async => true;
}

/// 非主窗口 engine 使用的空宿主，避免子窗口再次创建选择器窗口。
class DesktopNoopSelectorWindowHost implements DesktopSelectorWindowHostPort {
  const DesktopNoopSelectorWindowHost();

  @override
  void setIntentHandler(DesktopSelectorWindowIntentHandler? handler) {}

  @override
  Future<void> publishConfigRevision({required int revision}) async {}

  @override
  Future<void> destroySelectorWindow({required int instanceId}) async {}

  @override
  Future<void> ensureSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> hideSelectorWindow({required int instanceId}) async {}

  @override
  Future<void> refreshSelectorContext({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {}

  @override
  Future<void> showSelectorWindow({
    required int instanceId,
    required DesktopSelectorWindowContext context,
  }) async {}
}

typedef DesktopFloatingWindowIntentHandler =
    Future<bool> Function(DesktopFloatingWindowIntent intent);

typedef DesktopSelectorWindowIntentHandler =
    Future<bool> Function(DesktopSelectorWindowIntent intent);
