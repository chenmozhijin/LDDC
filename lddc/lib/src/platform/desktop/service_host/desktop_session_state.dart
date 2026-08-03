import 'dart:collection';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../ipc/desktop_ipc.dart';

Map<String, Object?> _freezeObjectMap(
  Map<String, Object?> raw, {
  required String argumentName,
}) {
  if (raw.isEmpty) {
    return const <String, Object?>{};
  }
  final Set<Object> ancestors = HashSet<Object>.identity();
  return Map<String, Object?>.unmodifiable(
    _freezeStringMap(raw, ancestors, argumentName),
  );
}

Map<String, Object?> _freezeStringMap(
  Map<String, Object?> raw,
  Set<Object> ancestors,
  String argumentName,
) {
  if (!ancestors.add(raw)) {
    throw ArgumentError.value(raw, argumentName, '数据不能包含循环 Map/List');
  }
  try {
    return <String, Object?>{
      for (final MapEntry<String, Object?> entry in raw.entries)
        entry.key: _freezeObject(entry.value, ancestors, argumentName),
    };
  } finally {
    ancestors.remove(raw);
  }
}

Object? _freezeObject(
  Object? value,
  Set<Object> ancestors,
  String argumentName,
) {
  if (value is Map) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, argumentName, '数据不能包含循环 Map/List');
    }
    try {
      return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
        for (final MapEntry<Object?, Object?> entry
            in value.entries.cast<MapEntry<Object?, Object?>>())
          entry.key: _freezeObject(entry.value, ancestors, argumentName),
      });
    } finally {
      ancestors.remove(value);
    }
  }
  if (value is List) {
    if (!ancestors.add(value)) {
      throw ArgumentError.value(value, argumentName, '数据不能包含循环 Map/List');
    }
    try {
      return List<Object?>.unmodifiable(
        value.map(
          (Object? item) => _freezeObject(item, ancestors, argumentName),
        ),
      );
    } finally {
      ancestors.remove(value);
    }
  }
  return value;
}

/// 客户端会话信息：对齐Python版 `pid/available_tasks/info`。
final class DesktopSessionClientState {
  const DesktopSessionClientState._({
    this.pid,
    this.name,
    this.version,
    this.availableTasks = const <DesktopControlCommandTask>{},
    this.extraInfo = const <String, Object?>{},
  });

  static const DesktopSessionClientState empty = DesktopSessionClientState._();

  final int? pid;
  final String? name;
  final String? version;
  final Set<DesktopControlCommandTask> availableTasks;
  final Map<String, Object?> extraInfo;

  factory DesktopSessionClientState.fromHello(DesktopHelloMessage message) {
    return DesktopSessionClientState._(
      pid: message.pid,
      name: message.clientInfo.name,
      version: message.clientInfo.version,
      availableTasks: Set<DesktopControlCommandTask>.unmodifiable(
        message.availableControlTasks,
      ),
      extraInfo: _freezeObjectMap(
        message.clientInfo.extra,
        argumentName: 'extraInfo',
      ),
    );
  }

  bool supports(DesktopControlCommandTask task) =>
      availableTasks.contains(task);

  DesktopSessionClientState copyWith({
    int? pid,
    String? name,
    String? version,
    Set<DesktopControlCommandTask>? availableTasks,
    Map<String, Object?>? extraInfo,
  }) {
    return DesktopSessionClientState._(
      pid: pid ?? this.pid,
      name: name ?? this.name,
      version: version ?? this.version,
      availableTasks: availableTasks == null
          ? this.availableTasks
          : Set<DesktopControlCommandTask>.unmodifiable(availableTasks),
      extraInfo: extraInfo == null
          ? this.extraInfo
          : _freezeObjectMap(extraInfo, argumentName: 'extraInfo'),
    );
  }
}

/// 最近一次插件时间同步载荷。
final class DesktopPlaybackSyncState {
  const DesktopPlaybackSyncState({
    this.pluginPlaybackTimeMs = 0,
    this.pluginSendTimeMs,
    this.hostReceivedAtMs = 0,
    this.isPlaying = false,
    this.syncRevision = 0,
    this.task,
    this.sceneId,
    this.songToken,
  });

  final int pluginPlaybackTimeMs;
  final int? pluginSendTimeMs;
  final int hostReceivedAtMs;
  final bool isPlaying;
  final int syncRevision;
  final DesktopIpcTask? task;
  final String? sceneId;
  final String? songToken;

  DesktopPlaybackSyncState copyWith({
    int? pluginPlaybackTimeMs,
    int? pluginSendTimeMs,
    int? hostReceivedAtMs,
    bool? isPlaying,
    int? syncRevision,
    DesktopIpcTask? task,
    String? sceneId,
    String? songToken,
    bool clearPluginSendTimeMs = false,
    bool clearTask = false,
    bool clearSceneId = false,
    bool clearSongToken = false,
  }) {
    return DesktopPlaybackSyncState(
      pluginPlaybackTimeMs: pluginPlaybackTimeMs ?? this.pluginPlaybackTimeMs,
      pluginSendTimeMs: clearPluginSendTimeMs
          ? null
          : (pluginSendTimeMs ?? this.pluginSendTimeMs),
      hostReceivedAtMs: hostReceivedAtMs ?? this.hostReceivedAtMs,
      isPlaying: isPlaying ?? this.isPlaying,
      syncRevision: syncRevision ?? this.syncRevision,
      task: clearTask ? null : (task ?? this.task),
      sceneId: clearSceneId ? null : (sceneId ?? this.sceneId),
      songToken: clearSongToken ? null : (songToken ?? this.songToken),
    );
  }
}

/// 歌词运行态：保留当前歌曲、歌词、静态显示与路径信息。
final class DesktopLyricsRuntimeState {
  factory DesktopLyricsRuntimeState({
    SongInfo? song,
    Lyrics? lyrics,
    String? lyricsPath,
    int? durationMs,
    MultiLyricsData multiLyricsData = const <String, LyricsData>{},
    DesktopLyricsMapping lyricsMapping = const <String, Map<int, LyricsLine>>{},
    DesktopAssignedLyricsSlots assignedLyricsSlots =
        const <(Direction, int), List<(int, LyricsLine)>>{},
    DesktopRubyMapping rubyMapping = const <int, List<RubySpan>>{},
    DesktopLyricsSceneDocument? sceneDocument,
    DesktopSceneRef? sceneRef,
    int sceneRevision = 0,
    int selectionRevision = 0,
    int lyricsRevision = 0,
    List<String> staticDisplayLines = const <String>[],
  }) {
    return DesktopLyricsRuntimeState._(
      song: song,
      lyrics: lyrics,
      lyricsPath: lyricsPath,
      durationMs: durationMs,
      multiLyricsData: _freezeMultiLyricsData(multiLyricsData),
      lyricsMapping: _freezeLyricsMapping(lyricsMapping),
      assignedLyricsSlots: _freezeAssignedLyricsSlots(assignedLyricsSlots),
      rubyMapping: _freezeRubyMapping(rubyMapping),
      sceneDocument: sceneDocument,
      sceneRef: sceneRef,
      sceneRevision: sceneRevision,
      selectionRevision: selectionRevision,
      lyricsRevision: lyricsRevision,
      staticDisplayLines: List<String>.unmodifiable(staticDisplayLines),
    );
  }

  const DesktopLyricsRuntimeState._({
    this.song,
    this.lyrics,
    this.lyricsPath,
    this.durationMs,
    this.multiLyricsData = const <String, LyricsData>{},
    this.lyricsMapping = const <String, Map<int, LyricsLine>>{},
    this.assignedLyricsSlots =
        const <(Direction, int), List<(int, LyricsLine)>>{},
    this.rubyMapping = const <int, List<RubySpan>>{},
    this.sceneDocument,
    this.sceneRef,
    this.sceneRevision = 0,
    this.selectionRevision = 0,
    this.lyricsRevision = 0,
    this.staticDisplayLines = const <String>[],
  });

  static const DesktopLyricsRuntimeState empty = DesktopLyricsRuntimeState._();

  final SongInfo? song;
  final Lyrics? lyrics;
  final String? lyricsPath;
  final int? durationMs;
  final MultiLyricsData multiLyricsData;
  final DesktopLyricsMapping lyricsMapping;
  final DesktopAssignedLyricsSlots assignedLyricsSlots;
  final DesktopRubyMapping rubyMapping;
  final DesktopLyricsSceneDocument? sceneDocument;
  final DesktopSceneRef? sceneRef;
  final int sceneRevision;
  final int selectionRevision;
  final int lyricsRevision;
  final List<String> staticDisplayLines;

  bool get hasLyrics => lyrics != null;

  bool get hasRenderedLyricsData => multiLyricsData.isNotEmpty;

  bool get hasStaticDisplay => staticDisplayLines.isNotEmpty;

  DesktopLyricsRuntimeState copyWith({
    SongInfo? song,
    Lyrics? lyrics,
    String? lyricsPath,
    int? durationMs,
    MultiLyricsData? multiLyricsData,
    DesktopLyricsMapping? lyricsMapping,
    DesktopAssignedLyricsSlots? assignedLyricsSlots,
    DesktopRubyMapping? rubyMapping,
    DesktopLyricsSceneDocument? sceneDocument,
    DesktopSceneRef? sceneRef,
    int? sceneRevision,
    int? selectionRevision,
    int? lyricsRevision,
    List<String>? staticDisplayLines,
    bool clearSong = false,
    bool clearLyrics = false,
    bool clearLyricsPath = false,
    bool clearDurationMs = false,
    bool clearMultiLyricsData = false,
    bool clearLyricsMapping = false,
    bool clearAssignedLyricsSlots = false,
    bool clearRubyMapping = false,
    bool clearSceneDocument = false,
    bool clearSceneRef = false,
    bool clearStaticDisplay = false,
  }) {
    final MultiLyricsData resolvedMultiLyricsData = clearMultiLyricsData
        ? const <String, LyricsData>{}
        : multiLyricsData == null
        ? this.multiLyricsData
        : _freezeMultiLyricsData(multiLyricsData);
    final DesktopLyricsMapping resolvedLyricsMapping = clearLyricsMapping
        ? const <String, Map<int, LyricsLine>>{}
        : lyricsMapping == null
        ? this.lyricsMapping
        : _freezeLyricsMapping(lyricsMapping);
    final DesktopAssignedLyricsSlots resolvedAssignedLyricsSlots =
        clearAssignedLyricsSlots
        ? const <(Direction, int), List<(int, LyricsLine)>>{}
        : assignedLyricsSlots == null
        ? this.assignedLyricsSlots
        : _freezeAssignedLyricsSlots(assignedLyricsSlots);
    final DesktopRubyMapping resolvedRubyMapping = clearRubyMapping
        ? const <int, List<RubySpan>>{}
        : rubyMapping == null
        ? this.rubyMapping
        : _freezeRubyMapping(rubyMapping);
    final List<String> resolvedStaticDisplayLines = clearStaticDisplay
        ? const <String>[]
        : staticDisplayLines == null
        ? this.staticDisplayLines
        : List<String>.unmodifiable(staticDisplayLines);
    return DesktopLyricsRuntimeState._(
      song: clearSong ? null : (song ?? this.song),
      lyrics: clearLyrics ? null : (lyrics ?? this.lyrics),
      lyricsPath: clearLyricsPath ? null : (lyricsPath ?? this.lyricsPath),
      durationMs: clearDurationMs ? null : (durationMs ?? this.durationMs),
      multiLyricsData: resolvedMultiLyricsData,
      lyricsMapping: resolvedLyricsMapping,
      assignedLyricsSlots: resolvedAssignedLyricsSlots,
      rubyMapping: resolvedRubyMapping,
      sceneDocument: clearSceneDocument
          ? null
          : (sceneDocument ?? this.sceneDocument),
      sceneRef: clearSceneRef ? null : (sceneRef ?? this.sceneRef),
      sceneRevision: sceneRevision ?? this.sceneRevision,
      selectionRevision: selectionRevision ?? this.selectionRevision,
      lyricsRevision: lyricsRevision ?? this.lyricsRevision,
      staticDisplayLines: resolvedStaticDisplayLines,
    );
  }

  static MultiLyricsData _freezeMultiLyricsData(MultiLyricsData raw) {
    if (raw.isEmpty) {
      return const <String, LyricsData>{};
    }
    return Map<String, LyricsData>.unmodifiable(<String, LyricsData>{
      for (final MapEntry<String, LyricsData> entry in raw.entries)
        entry.key: List<LyricsLine>.unmodifiable(entry.value),
    });
  }

  static DesktopLyricsMapping _freezeLyricsMapping(DesktopLyricsMapping raw) {
    if (raw.isEmpty) {
      return const <String, Map<int, LyricsLine>>{};
    }
    return Map<String, Map<int, LyricsLine>>.unmodifiable(
      <String, Map<int, LyricsLine>>{
        for (final MapEntry<String, Map<int, LyricsLine>> entry in raw.entries)
          entry.key: Map<int, LyricsLine>.unmodifiable(entry.value),
      },
    );
  }

  static DesktopAssignedLyricsSlots _freezeAssignedLyricsSlots(
    DesktopAssignedLyricsSlots raw,
  ) {
    if (raw.isEmpty) {
      return const <(Direction, int), List<(int, LyricsLine)>>{};
    }
    return Map<(Direction, int), List<(int, LyricsLine)>>.unmodifiable(
      <(Direction, int), List<(int, LyricsLine)>>{
        for (final MapEntry<(Direction, int), List<(int, LyricsLine)>> entry
            in raw.entries)
          entry.key: List<(int, LyricsLine)>.unmodifiable(entry.value),
      },
    );
  }

  static DesktopRubyMapping _freezeRubyMapping(DesktopRubyMapping raw) {
    if (raw.isEmpty) {
      return const <int, List<RubySpan>>{};
    }
    return Map<int, List<RubySpan>>.unmodifiable(<int, List<RubySpan>>{
      for (final MapEntry<int, List<RubySpan>> entry in raw.entries)
        entry.key: List<RubySpan>.unmodifiable(entry.value),
    });
  }
}

/// 歌曲级配置运行态。
final class DesktopSessionConfigState {
  factory DesktopSessionConfigState({
    Map<String, Object?> songConfig = const <String, Object?>{},
    List<String> defaultLangs = const <String>['orig', 'ts'],
    List<String> langOrder = const <String>['roma', 'orig', 'ts'],
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
    double panelFontSize = 12.0,
    bool showFurigana = true,
    int refreshRate = -1,
    WindowRect? windowRect,
  }) {
    return DesktopSessionConfigState._(
      songConfig: _freezeObjectMap(songConfig, argumentName: 'songConfig'),
      defaultLangs: List<String>.unmodifiable(defaultLangs),
      langOrder: List<String>.unmodifiable(langOrder),
      playedColors: List<RgbColor>.unmodifiable(playedColors),
      unplayedColors: List<RgbColor>.unmodifiable(unplayedColors),
      fontFamily: fontFamily,
      fontSize: fontSize,
      panelFontSize: panelFontSize,
      showFurigana: showFurigana,
      refreshRate: refreshRate,
      windowRect: windowRect,
    );
  }

  const DesktopSessionConfigState._({
    this.songConfig = const <String, Object?>{},
    this.defaultLangs = const <String>['orig', 'ts'],
    this.langOrder = const <String>['roma', 'orig', 'ts'],
    this.playedColors = const <RgbColor>[
      RgbColor(0, 255, 255),
      RgbColor(0, 128, 255),
    ],
    this.unplayedColors = const <RgbColor>[
      RgbColor(255, 0, 0),
      RgbColor(255, 128, 128),
    ],
    this.fontFamily = '',
    this.fontSize = 30.0,
    this.panelFontSize = 12.0,
    this.showFurigana = true,
    this.refreshRate = -1,
    this.windowRect,
  });

  static const DesktopSessionConfigState defaults =
      DesktopSessionConfigState._();

  final Map<String, Object?> songConfig;
  final List<String> defaultLangs;
  final List<String> langOrder;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final String fontFamily;
  final double fontSize;
  final double panelFontSize;
  final bool showFurigana;
  final int refreshRate;
  final WindowRect? windowRect;

  int get offsetMs {
    return DynamicReader.asInt(songConfig['offset']) ?? 0;
  }

  List<String> get effectiveDefaultLangs => _orderLangs(defaultLangs);

  List<String> get effectiveSelectedLangs {
    final Object? raw = songConfig['langs'];
    if (raw is List<Object?>) {
      return _orderLangs(DynamicReader.asStringList(raw));
    }
    return effectiveDefaultLangs;
  }

  List<String> get selectedLangs {
    return effectiveSelectedLangs;
  }

  bool get isInstrumental => songConfig['inst'] == true;

  bool get isAutoSearchDisabled => songConfig['disable_auto_search'] == true;

  DesktopSessionConfigState copyWith({
    Map<String, Object?>? songConfig,
    List<String>? defaultLangs,
    List<String>? langOrder,
    List<RgbColor>? playedColors,
    List<RgbColor>? unplayedColors,
    String? fontFamily,
    double? fontSize,
    double? panelFontSize,
    bool? showFurigana,
    int? refreshRate,
    WindowRect? windowRect,
  }) {
    return DesktopSessionConfigState._(
      songConfig: songConfig == null
          ? this.songConfig
          : _freezeObjectMap(songConfig, argumentName: 'songConfig'),
      defaultLangs: defaultLangs == null
          ? this.defaultLangs
          : List<String>.unmodifiable(defaultLangs),
      langOrder: langOrder == null
          ? this.langOrder
          : List<String>.unmodifiable(langOrder),
      playedColors: playedColors == null
          ? this.playedColors
          : List<RgbColor>.unmodifiable(playedColors),
      unplayedColors: unplayedColors == null
          ? this.unplayedColors
          : List<RgbColor>.unmodifiable(unplayedColors),
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      panelFontSize: panelFontSize ?? this.panelFontSize,
      showFurigana: showFurigana ?? this.showFurigana,
      refreshRate: refreshRate ?? this.refreshRate,
      windowRect: windowRect ?? this.windowRect,
    );
  }

  List<String> _orderLangs(List<String> raw) {
    if (raw.isEmpty) {
      return const <String>[];
    }
    final List<String> ordered = <String>[];
    for (final String lang in langOrder) {
      if (raw.contains(lang) && !ordered.contains(lang)) {
        ordered.add(lang);
      }
    }
    return List<String>.unmodifiable(ordered);
  }
}

/// 单个歌词面板实例运行态。
final class DesktopPanelState {
  const DesktopPanelState({
    required this.panelId,
    this.hostWindowId,
    this.width,
    this.height,
    this.visible = false,
  });

  final int panelId;
  final int? hostWindowId;
  final int? width;
  final int? height;
  final bool visible;

  DesktopPanelState copyWith({
    int? hostWindowId,
    int? width,
    int? height,
    bool? visible,
    bool clearHostWindowId = false,
    bool clearWidth = false,
    bool clearHeight = false,
  }) {
    return DesktopPanelState(
      panelId: panelId,
      hostWindowId: clearHostWindowId
          ? null
          : (hostWindowId ?? this.hostWindowId),
      width: clearWidth ? null : (width ?? this.width),
      height: clearHeight ? null : (height ?? this.height),
      visible: visible ?? this.visible,
    );
  }
}

/// 桌面窗口交互运行态。
final class DesktopWindowUiState {
  const DesktopWindowUiState({
    this.floatingVisibilityMode = DesktopFloatingVisibilityMode.auto,
    this.clickThrough = false,
  });

  final DesktopFloatingVisibilityMode floatingVisibilityMode;
  final bool clickThrough;

  DesktopWindowUiState copyWith({
    DesktopFloatingVisibilityMode? floatingVisibilityMode,
    bool? clickThrough,
  }) {
    return DesktopWindowUiState(
      floatingVisibilityMode:
          floatingVisibilityMode ?? this.floatingVisibilityMode,
      clickThrough: clickThrough ?? this.clickThrough,
    );
  }
}

/// Flutter 端桌面歌词会话真源。
///
/// 说明：
/// - 该模型是 Flutter 侧对Python版 `DesktopLyricsInstance` 运行态的投影
/// - Python版并不存在同名类
final class DesktopSessionState {
  const DesktopSessionState._({
    this.instanceId,
    this.apiVersion,
    this.client = DesktopSessionClientState.empty,
    this.playbackSync = const DesktopPlaybackSyncState(),
    this.lyricsRuntime = DesktopLyricsRuntimeState.empty,
    this.config = DesktopSessionConfigState.defaults,
    this.uiState = const DesktopWindowUiState(),
    this.panels = const <int, DesktopPanelState>{},
    this.isPlaying = false,
    this.lastTask,
  });

  final int? instanceId;
  final int? apiVersion;
  final DesktopSessionClientState client;
  final DesktopPlaybackSyncState playbackSync;
  final DesktopLyricsRuntimeState lyricsRuntime;
  final DesktopSessionConfigState config;
  final DesktopWindowUiState uiState;
  final Map<int, DesktopPanelState> panels;
  final bool isPlaying;
  final DesktopIpcTask? lastTask;

  factory DesktopSessionState.initial({
    List<String> defaultLangs = const <String>['orig', 'ts'],
    List<String> langOrder = const <String>['roma', 'orig', 'ts'],
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
    double panelFontSize = 12.0,
    bool showFurigana = true,
    int refreshRate = -1,
    WindowRect? windowRect,
  }) {
    return DesktopSessionState._(
      config: DesktopSessionConfigState(
        defaultLangs: defaultLangs,
        langOrder: langOrder,
        playedColors: playedColors,
        unplayedColors: unplayedColors,
        fontFamily: fontFamily,
        fontSize: fontSize,
        panelFontSize: panelFontSize,
        showFurigana: showFurigana,
        refreshRate: refreshRate,
        windowRect: windowRect,
      ),
    );
  }

  bool supportsControlTask(DesktopControlCommandTask task) {
    return client.supports(task);
  }

  DesktopSessionState attachHello({
    required DesktopHelloMessage hello,
    required int apiVersion,
    required int instanceId,
  }) {
    return copyWith(
      apiVersion: apiVersion,
      instanceId: instanceId,
      client: DesktopSessionClientState.fromHello(hello),
      lastTask: hello.task,
    );
  }

  DesktopSessionState upsertPanel(DesktopPanelState panel) {
    final Map<int, DesktopPanelState> nextPanels =
        Map<int, DesktopPanelState>.from(panels);
    nextPanels[panel.panelId] = panel;
    return copyWith(panels: nextPanels);
  }

  DesktopSessionState removePanel(int panelId) {
    if (!panels.containsKey(panelId)) {
      return this;
    }
    final Map<int, DesktopPanelState> nextPanels =
        Map<int, DesktopPanelState>.from(panels);
    nextPanels.remove(panelId);
    return copyWith(panels: nextPanels);
  }

  DesktopSessionState copyWith({
    int? instanceId,
    int? apiVersion,
    DesktopSessionClientState? client,
    DesktopPlaybackSyncState? playbackSync,
    DesktopLyricsRuntimeState? lyricsRuntime,
    DesktopSessionConfigState? config,
    DesktopWindowUiState? uiState,
    Map<int, DesktopPanelState>? panels,
    bool? isPlaying,
    DesktopIpcTask? lastTask,
    bool clearInstanceId = false,
    bool clearApiVersion = false,
    bool clearLastTask = false,
  }) {
    return DesktopSessionState._(
      instanceId: clearInstanceId ? null : (instanceId ?? this.instanceId),
      apiVersion: clearApiVersion ? null : (apiVersion ?? this.apiVersion),
      client: client ?? this.client,
      playbackSync: playbackSync ?? this.playbackSync,
      lyricsRuntime: lyricsRuntime ?? this.lyricsRuntime,
      config: config ?? this.config,
      uiState: uiState ?? this.uiState,
      panels: panels == null
          ? this.panels
          : Map<int, DesktopPanelState>.unmodifiable(panels),
      isPlaying: isPlaying ?? this.isPlaying,
      lastTask: clearLastTask ? null : (lastTask ?? this.lastTask),
    );
  }
}
