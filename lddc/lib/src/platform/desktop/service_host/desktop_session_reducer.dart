import 'package:flutter/foundation.dart' show listEquals;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../../core/config/config.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../../../core/library_link/library_link.dart';
import '../ipc/desktop_ipc.dart';
import '../window/desktop_panel_snapshot_host_mapper.dart';
import 'desktop_selector_context_builder.dart';
import 'desktop_session_state.dart';

const LyricsLineMatcher _lyricsLineMatcher = LyricsLineMatcher();
const LyricsTrackAssigner _lyricsTrackAssigner = LyricsTrackAssigner();

/// 桌面服务 reducer 的静态配置。
final class DesktopSessionReducerConfig {
  DesktopSessionReducerConfig({
    List<String> defaultLangs = const <String>['orig', 'ts'],
    List<RgbColor> playedColors = const <RgbColor>[
      RgbColor(0, 255, 255),
      RgbColor(0, 128, 255),
    ],
    List<RgbColor> unplayedColors = const <RgbColor>[
      RgbColor(255, 0, 0),
      RgbColor(255, 128, 128),
    ],
    List<String> langOrder = const <String>['roma', 'orig', 'ts'],
    List<Source> autoFetchSources = const <Source>[
      Source.qm,
      Source.kg,
      Source.ne,
    ],
    this.fontFamily = '',
    this.fontSize = 30.0,
    this.panelFontSize = 12.0,
    this.showFurigana = true,
    this.refreshRate = -1,
    this.windowRect,
    this.autoFetchMessage = '自动获取歌词中...',
    this.autoFetchPlainTextMessage = '自动获取的歌词为纯文本，无法显示',
    this.instrumentalMessage = '纯音乐，请欣赏',
    this.missingSongInfoMessage = '没有获取到标题或文件名信息, 无法自动获取歌词',
  }) : defaultLangs = List<String>.unmodifiable(defaultLangs),
       playedColors = List<RgbColor>.unmodifiable(playedColors),
       unplayedColors = List<RgbColor>.unmodifiable(unplayedColors),
       langOrder = List<String>.unmodifiable(langOrder),
       autoFetchSources = List<Source>.unmodifiable(autoFetchSources);

  final List<String> defaultLangs;
  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final List<String> langOrder;
  final List<Source> autoFetchSources;
  final String fontFamily;
  final double fontSize;
  final double panelFontSize;
  final bool showFurigana;
  final int refreshRate;
  final WindowRect? windowRect;
  final String autoFetchMessage;
  final String autoFetchPlainTextMessage;
  final String instrumentalMessage;
  final String missingSongInfoMessage;

  DesktopSessionReducerConfig copyWithInitialWindowRect(WindowRect windowRect) {
    return DesktopSessionReducerConfig(
      defaultLangs: defaultLangs,
      playedColors: playedColors,
      unplayedColors: unplayedColors,
      langOrder: langOrder,
      autoFetchSources: autoFetchSources,
      fontFamily: fontFamily,
      fontSize: fontSize,
      panelFontSize: panelFontSize,
      showFurigana: showFurigana,
      refreshRate: refreshRate,
      windowRect: windowRect,
      autoFetchMessage: autoFetchMessage,
      autoFetchPlainTextMessage: autoFetchPlainTextMessage,
      instrumentalMessage: instrumentalMessage,
      missingSongInfoMessage: missingSongInfoMessage,
    );
  }

  factory DesktopSessionReducerConfig.fromAppConfig(AppConfig config) {
    final List<Source> sources = <Source>[];
    for (final String raw in config.desktop.sources) {
      try {
        final Source source = Source.fromValue(raw);
        if (source != Source.local &&
            source != Source.multi &&
            !sources.contains(source)) {
          sources.add(source);
        }
      } on ArgumentError {
        continue;
      }
    }
    return DesktopSessionReducerConfig(
      defaultLangs: config.desktop.defaultLangs.toList(growable: false),
      playedColors: config.desktop.playedColors.toList(growable: false),
      unplayedColors: config.desktop.unplayedColors.toList(growable: false),
      langOrder: config.desktop.langOrder.toList(growable: false),
      autoFetchSources: sources.isEmpty
          ? const <Source>[Source.qm, Source.kg, Source.ne]
          : sources,
      fontFamily: config.desktop.fontFamily,
      fontSize: config.desktop.fontSize,
      panelFontSize: config.desktop.panelFontSize,
      showFurigana: config.desktop.showFurigana,
      refreshRate: config.desktop.refreshRate,
      windowRect: config.desktop.windowRect,
    );
  }
}

/// reducer 配置差异摘要。
final class DesktopSessionReducerConfigDiff {
  const DesktopSessionReducerConfigDiff({
    required this.previous,
    required this.current,
    required this.defaultLangsChanged,
    required this.playedColorsChanged,
    required this.unplayedColorsChanged,
    required this.langOrderChanged,
    required this.autoFetchSourcesChanged,
    required this.fontFamilyChanged,
    required this.fontSizeChanged,
    required this.panelFontSizeChanged,
    required this.showFuriganaChanged,
    required this.refreshRateChanged,
  });

  final DesktopSessionReducerConfig previous;
  final DesktopSessionReducerConfig current;
  final bool defaultLangsChanged;
  final bool playedColorsChanged;
  final bool unplayedColorsChanged;
  final bool langOrderChanged;
  final bool autoFetchSourcesChanged;
  final bool fontFamilyChanged;
  final bool fontSizeChanged;
  final bool panelFontSizeChanged;
  final bool showFuriganaChanged;
  final bool refreshRateChanged;

  bool get hasAnyChange =>
      defaultLangsChanged ||
      playedColorsChanged ||
      unplayedColorsChanged ||
      langOrderChanged ||
      autoFetchSourcesChanged ||
      fontFamilyChanged ||
      fontSizeChanged ||
      panelFontSizeChanged ||
      showFuriganaChanged ||
      refreshRateChanged;

  bool get affectsSelectorContext => defaultLangsChanged || langOrderChanged;

  bool get affectsLyricsLayout =>
      defaultLangsChanged || langOrderChanged || showFuriganaChanged;

  bool get affectsFloatingPaint =>
      playedColorsChanged ||
      unplayedColorsChanged ||
      fontFamilyChanged ||
      fontSizeChanged;

  bool get affectsPanelSnapshot =>
      playedColorsChanged ||
      unplayedColorsChanged ||
      fontFamilyChanged ||
      panelFontSizeChanged ||
      showFuriganaChanged ||
      refreshRateChanged;

  factory DesktopSessionReducerConfigDiff.between({
    required DesktopSessionReducerConfig previous,
    required DesktopSessionReducerConfig current,
  }) {
    return DesktopSessionReducerConfigDiff(
      previous: previous,
      current: current,
      defaultLangsChanged: !listEquals(
        previous.defaultLangs,
        current.defaultLangs,
      ),
      playedColorsChanged: !_rgbColorListEquals(
        previous.playedColors,
        current.playedColors,
      ),
      unplayedColorsChanged: !_rgbColorListEquals(
        previous.unplayedColors,
        current.unplayedColors,
      ),
      langOrderChanged: !listEquals(previous.langOrder, current.langOrder),
      autoFetchSourcesChanged: !listEquals(
        previous.autoFetchSources,
        current.autoFetchSources,
      ),
      fontFamilyChanged: previous.fontFamily != current.fontFamily,
      fontSizeChanged: previous.fontSize != current.fontSize,
      panelFontSizeChanged: previous.panelFontSize != current.panelFontSize,
      showFuriganaChanged: previous.showFurigana != current.showFurigana,
      refreshRateChanged: previous.refreshRate != current.refreshRate,
    );
  }

  static bool _rgbColorListEquals(List<RgbColor> left, List<RgbColor> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int i = 0; i < left.length; i++) {
      if (left[i].r != right[i].r ||
          left[i].g != right[i].g ||
          left[i].b != right[i].b) {
        return false;
      }
    }
    return true;
  }
}

/// `select_lyrics` 输入载荷。
final class DesktopSelectedLyricsPayload {
  DesktopSelectedLyricsPayload({
    required this.lyrics,
    this.path,
    List<String>? langs,
    this.offsetMs = 0,
    this.isInstrumental = false,
  }) : langs = langs == null ? null : List<String>.unmodifiable(langs);

  final Lyrics lyrics;
  final String? path;
  final List<String>? langs;
  final int offsetMs;
  final bool isInstrumental;
}

/// reducer 执行结果：状态 + 副作用计划。
final class DesktopReducerResult {
  DesktopReducerResult({
    required this.state,
    Iterable<DesktopSessionEffect> effects = const <DesktopSessionEffect>[],
  }) : effects = List<DesktopSessionEffect>.unmodifiable(effects);

  final DesktopSessionState state;
  final List<DesktopSessionEffect> effects;
}

/// 桌面服务副作用基类。
sealed class DesktopSessionEffect {
  const DesktopSessionEffect();
}

/// 清理在途任务，当前用于 `auto_fetch`。
final class DesktopClearTaskEffect extends DesktopSessionEffect {
  const DesktopClearTaskEffect({required this.taskKey});

  final String taskKey;
}

/// 延时恢复为仅显示 `artist-title` 的静态默认文本。
final class DesktopRestoreArtistTitleEffect extends DesktopSessionEffect {
  const DesktopRestoreArtistTitleEffect({
    required this.song,
    required this.delayMs,
    required this.lyricsRevision,
    this.taskKey = _restoreArtistTitleTaskKey,
  });

  final SongInfo song;
  final int delayMs;
  final int lyricsRevision;
  final String taskKey;
}

/// 刷新桌面歌词选择器上下文。
final class DesktopRefreshSelectorEffect extends DesktopSessionEffect {
  DesktopRefreshSelectorEffect({
    required this.instanceId,
    required this.context,
    required this.onlyIfVisible,
  });

  final int instanceId;
  final DesktopSelectorWindowContext context;
  final bool onlyIfVisible;
}

/// 查询关联库。
final class DesktopQueryLibraryLinkEffect extends DesktopSessionEffect {
  const DesktopQueryLibraryLinkEffect({
    required this.song,
    required this.selectionRevision,
  });

  final SongInfo song;
  final int selectionRevision;
}

/// 从关联库路径读取歌词。
final class DesktopLoadLinkedLyricsEffect extends DesktopSessionEffect {
  const DesktopLoadLinkedLyricsEffect({
    required this.song,
    required this.lyricsPath,
    required this.selectionRevision,
  });

  final SongInfo song;
  final String lyricsPath;
  final int selectionRevision;
}

/// 发起自动搜索。
final class DesktopStartAutoFetchEffect extends DesktopSessionEffect {
  const DesktopStartAutoFetchEffect({
    required this.request,
    required this.selectionRevision,
  });

  final AutoFetchRequest request;
  final int selectionRevision;
}

/// 持久化歌曲级关联信息。
final class DesktopPersistLibraryLinkEffect extends DesktopSessionEffect {
  DesktopPersistLibraryLinkEffect({
    required this.song,
    required this.lyricsPath,
    required Map<String, Object?> configSnapshot,
  }) : configSnapshot = Map<String, Object?>.unmodifiable(configSnapshot);

  final SongInfo song;
  final String? lyricsPath;
  final Map<String, Object?> configSnapshot;
}

/// 将远端歌词另存为 JSON。
final class DesktopSaveRemoteLyricsEffect extends DesktopSessionEffect {
  const DesktopSaveRemoteLyricsEffect({
    required this.lyrics,
    required this.suggestedFileName,
    required this.lyricsRevision,
  });

  final Lyrics lyrics;
  final String suggestedFileName;
  final int lyricsRevision;
}

/// 向一个或多个面板同步当前歌词快照。
final class DesktopSyncPanelsEffect extends DesktopSessionEffect {
  DesktopSyncPanelsEffect({
    required this.instanceId,
    required List<int> panelIds,
    required this.snapshot,
  }) : panelIds = List<int>.unmodifiable(panelIds);

  final int instanceId;
  final List<int> panelIds;
  final DesktopPanelWindowSnapshot snapshot;
}

/// 桌面歌词会话 reducer。
///
/// 目标：
/// - 只承载Python版顺序语义
/// - IO、自动搜索、文件落盘、关联库写入都下沉为 effect
///
/// reducer 必须保持“输入状态 + 消息 => 新状态 + effect”的纯状态机形状。
/// 这样桌面服务、主窗口和面板窗口可以共享同一套顺序语义，测试也能直接断言
/// effect 列表，而不需要真的打开窗口、发网络请求或写数据库。
final class DesktopSessionReducer {
  DesktopSessionReducer({
    DesktopSessionReducerConfig? config,
    int Function()? nowMsFactory,
    DesktopLyricsSceneCodec? sceneCodec,
  }) : _config = config ?? DesktopSessionReducerConfig(),
       _sceneCodec = sceneCodec ?? const DesktopLyricsSceneCodec(),
       _nowMsFactory =
           nowMsFactory ?? (() => DateTime.now().millisecondsSinceEpoch);

  DesktopSessionReducerConfig _config;
  final DesktopLyricsSceneCodec _sceneCodec;
  final int Function() _nowMsFactory;

  DesktopSessionReducerConfig get config => _config;

  void updateInitialWindowRect(WindowRect windowRect) {
    _config = _config.copyWithInitialWindowRect(windowRect);
  }

  DesktopSessionReducerConfigDiff reconfigure(
    DesktopSessionReducerConfig nextConfig,
  ) {
    final DesktopSessionReducerConfig previous = _config;
    final DesktopSessionReducerConfigDiff diff =
        DesktopSessionReducerConfigDiff.between(
          previous: previous,
          current: nextConfig,
        );
    _config = nextConfig;
    return diff;
  }

  DesktopSessionReducerConfigDiff reconfigureFromAppConfig(AppConfig config) {
    return reconfigure(DesktopSessionReducerConfig.fromAppConfig(config));
  }

  DesktopReducerResult applyConfigDiff(
    DesktopSessionState state,
    DesktopSessionReducerConfigDiff diff,
  ) {
    if (!diff.hasAnyChange) {
      return DesktopReducerResult(state: state);
    }

    final DesktopSessionState nextState = state.copyWith(
      config: state.config.copyWith(
        defaultLangs: _config.defaultLangs,
        langOrder: _config.langOrder,
        playedColors: _config.playedColors,
        unplayedColors: _config.unplayedColors,
        fontFamily: _config.fontFamily,
        fontSize: _config.fontSize,
        panelFontSize: _config.panelFontSize,
        showFurigana: _config.showFurigana,
        refreshRate: _config.refreshRate,
        songConfig: _normalizeSongConfig(state.config.songConfig),
      ),
    );

    if (diff.affectsLyricsLayout && nextState.lyricsRuntime.lyrics != null) {
      return setLyrics(nextState, nextState.lyricsRuntime.lyrics!);
    }

    final List<DesktopSessionEffect> effects = <DesktopSessionEffect>[];
    final DesktopSyncPanelsEffect? panelSyncEffect = diff.affectsPanelSnapshot
        ? _buildPanelSyncEffect(nextState)
        : null;
    if (panelSyncEffect != null) {
      effects.add(panelSyncEffect);
    }

    final SongInfo? song = nextState.lyricsRuntime.song;
    if (!diff.affectsSelectorContext ||
        song == null ||
        nextState.instanceId == null) {
      return _result(nextState, effects: effects);
    }

    effects.add(_buildSelectorRefreshEffect(nextState, onlyIfVisible: true));
    return _result(nextState, effects: effects);
  }

  DesktopReducerResult handleChangMusic(
    DesktopSessionState state,
    DesktopChangMusicMessage message,
  ) {
    // 插件协议沿用 Python 版语义，path 可能已经是 file:// URL。统一通过
    // SongInfo.fromMap 归一化，避免 url getter 再次添加前缀并使旧关联失效。
    final SongInfo song = SongInfo.fromMap(<String, Object?>{
      'source': Source.local.value,
      'title': message.title,
      'artist': message.artist,
      'album': message.album,
      'duration': message.durationMs,
      'path': message.path,
      'id': message.normalizedTrack,
    });
    final DesktopSessionState nextState = state.copyWith(
      instanceId: state.instanceId ?? message.instanceId,
      playbackSync: state.playbackSync.copyWith(
        sceneId: null,
        songToken: _songTokenForSong(song),
        clearSceneId: true,
      ),
      lyricsRuntime: DesktopLyricsRuntimeState(
        song: song,
        selectionRevision: state.lyricsRuntime.selectionRevision + 1,
        lyricsRevision: state.lyricsRuntime.lyricsRevision + 1,
      ),
      config: DesktopSessionConfigState(
        defaultLangs: state.config.defaultLangs,
        langOrder: state.config.langOrder,
        playedColors: state.config.playedColors,
        unplayedColors: state.config.unplayedColors,
        fontFamily: state.config.fontFamily,
        fontSize: state.config.fontSize,
        panelFontSize: state.config.panelFontSize,
        showFurigana: state.config.showFurigana,
        refreshRate: state.config.refreshRate,
        windowRect: state.config.windowRect,
      ),
      lastTask: DesktopIpcTask.changMusic,
    );
    return _result(
      nextState,
      effects: <DesktopSessionEffect>[
        ..._buildTaskClearEffects(autoFetch: true, restoreArtistTitle: true),
        // 切歌会先清空当前歌词场景；立即同步面板可以避免旧 scene
        // 继续用新歌播放进度渲染，等关联歌词加载完成后再下发新 scene。
        ..._optionalEffect(_buildPanelSyncEffect(nextState)),
        _buildSelectorRefreshEffect(nextState, onlyIfVisible: true),
        DesktopQueryLibraryLinkEffect(
          song: song,
          selectionRevision: nextState.lyricsRuntime.selectionRevision,
        ),
      ],
    );
  }

  DesktopReducerResult applyLibraryLinkResult(
    DesktopSessionState state, {
    required LibraryLinkItem? libraryLink,
    bool skipLinkedLyricsLoad = false,
  }) {
    final SongInfo? song = state.lyricsRuntime.song;
    if (song == null) {
      return DesktopReducerResult(state: state);
    }

    DesktopSessionState nextState = state;
    if (libraryLink != null) {
      final Map<String, Object?> mergedConfig = Map<String, Object?>.from(
        nextState.config.songConfig,
      )..addAll(libraryLink.configSnapshot);
      final Map<String, Object?> normalizedConfig = _normalizeSongConfig(
        mergedConfig,
      );
      nextState = nextState.copyWith(
        config: nextState.config.copyWith(songConfig: normalizedConfig),
      );
    }

    if (nextState.config.isInstrumental) {
      return setInstrumental(nextState, enable: true);
    }

    final String? linkedLyricsPath = _normalizeText(libraryLink?.lyricsPath);
    if (!skipLinkedLyricsLoad && linkedLyricsPath != null) {
      return DesktopReducerResult(
        state: nextState,
        effects: <DesktopSessionEffect>[
          DesktopLoadLinkedLyricsEffect(
            song: song,
            lyricsPath: linkedLyricsPath,
            selectionRevision: nextState.lyricsRuntime.selectionRevision,
          ),
        ],
      );
    }

    if (!nextState.config.isAutoSearchDisabled) {
      if (_canAutoFetch(song)) {
        final DesktopSessionState displayState = _setDisplayTextState(
          nextState,
          <String>[_config.autoFetchMessage],
        );
        return _resultWithPanelSync(
          displayState,
          after: <DesktopSessionEffect>[
            DesktopStartAutoFetchEffect(
              request: AutoFetchRequest(
                info: song,
                sources: _config.autoFetchSources,
              ),
              selectionRevision: displayState.lyricsRuntime.selectionRevision,
            ),
          ],
        );
      }
      return showArtistTitle(
        nextState,
        message: _config.missingSongInfoMessage,
      );
    }

    return showArtistTitle(nextState);
  }

  DesktopReducerResult applyLinkedLyricsLoaded(
    DesktopSessionState state, {
    required Lyrics lyrics,
    required String lyricsPath,
  }) {
    final DesktopReducerResult result = setLyrics(
      state.copyWith(
        lyricsRuntime: state.lyricsRuntime.copyWith(lyricsPath: lyricsPath),
      ),
      lyrics,
    );
    return _result(
      result.state.copyWith(lastTask: DesktopIpcTask.changMusic),
      effects: <DesktopSessionEffect>[
        ..._buildTaskClearEffects(restoreArtistTitle: true),
        ...result.effects,
      ],
    );
  }

  DesktopReducerResult applyAutoFetchResult(
    DesktopSessionState state, {
    required AutoFetchResult result,
  }) {
    if (result.lyrics.types['orig'] == LyricsType.plainText) {
      final DesktopReducerResult displayResult = showArtistTitle(
        state,
        message: _config.autoFetchPlainTextMessage,
      );
      return _result(
        displayResult.state,
        effects: <DesktopSessionEffect>[
          ..._buildTaskClearEffects(restoreArtistTitle: true),
          ...displayResult.effects,
          if (state.lyricsRuntime.song != null)
            DesktopRestoreArtistTitleEffect(
              song: state.lyricsRuntime.song!,
              delayMs: 3000,
              lyricsRevision: displayResult.state.lyricsRuntime.lyricsRevision,
            ),
        ],
      );
    }
    return applySelectedLyrics(
      state,
      DesktopSelectedLyricsPayload(
        lyrics: result.lyrics,
        isInstrumental: result.lyrics.isInstrumental(),
      ),
    );
  }

  DesktopReducerResult applyAutoFetchFailure(
    DesktopSessionState state, {
    required String message,
    required bool treatAsInstrumental,
  }) {
    if (treatAsInstrumental) {
      return setInstrumental(state, enable: true);
    }
    final DesktopReducerResult displayResult = showArtistTitle(
      state,
      message: message,
    );
    return _result(
      displayResult.state,
      effects: <DesktopSessionEffect>[
        ..._buildTaskClearEffects(restoreArtistTitle: true),
        ...displayResult.effects,
        if ((message.trim().isNotEmpty) && state.lyricsRuntime.song != null)
          DesktopRestoreArtistTitleEffect(
            song: state.lyricsRuntime.song!,
            delayMs: 3000,
            lyricsRevision: displayResult.state.lyricsRuntime.lyricsRevision,
          ),
      ],
    );
  }

  DesktopReducerResult applySelectedLyrics(
    DesktopSessionState state,
    DesktopSelectedLyricsPayload payload,
  ) {
    if (state.lyricsRuntime.song == null) {
      return DesktopReducerResult(state: state);
    }

    final DesktopSessionState configState = state.copyWith(
      config: state.config.copyWith(
        songConfig: _applySelectionConfig(
          raw: state.config.songConfig,
          defaultLangs: state.config.defaultLangs,
          langs: payload.langs,
          offsetMs: payload.offsetMs,
        ),
      ),
    );

    if (payload.isInstrumental || payload.lyrics.isInstrumental()) {
      return setInstrumental(configState, enable: true);
    }

    final Map<String, Object?> nextConfig = Map<String, Object?>.from(
      configState.config.songConfig,
    )..['inst'] = false;
    final DesktopSessionState nextState = configState.copyWith(
      config: configState.config.copyWith(songConfig: nextConfig),
    );

    final DesktopReducerResult lyricsResult = setLyrics(
      nextState,
      payload.lyrics,
    );
    final List<DesktopSessionEffect> effects = <DesktopSessionEffect>[
      ..._buildTaskClearEffects(autoFetch: true, restoreArtistTitle: true),
      ...lyricsResult.effects,
    ];

    if (payload.lyrics.source != Source.local) {
      effects.add(
        DesktopSaveRemoteLyricsEffect(
          lyrics: payload.lyrics,
          suggestedFileName: _buildRemoteLyricsFileName(payload.lyrics),
          lyricsRevision: lyricsResult.state.lyricsRuntime.lyricsRevision,
        ),
      );
      return _result(lyricsResult.state, effects: effects);
    }

    final DesktopSessionState persistedState = lyricsResult.state.copyWith(
      lyricsRuntime: lyricsResult.state.lyricsRuntime.copyWith(
        lyricsPath: payload.path,
      ),
    );
    final DesktopPersistLibraryLinkEffect? persistEffect = _buildPersistEffect(
      persistedState,
    );
    if (persistEffect != null) {
      effects.add(persistEffect);
    }
    return _result(persistedState, effects: effects);
  }

  DesktopReducerResult applyRemoteLyricsSaved(
    DesktopSessionState state, {
    required String lyricsPath,
  }) {
    final DesktopSessionState nextState = state.copyWith(
      lyricsRuntime: state.lyricsRuntime.copyWith(lyricsPath: lyricsPath),
    );
    final DesktopPersistLibraryLinkEffect? persistEffect = _buildPersistEffect(
      nextState,
    );
    return _result(nextState, effects: _optionalEffect(persistEffect));
  }

  DesktopReducerResult setLyrics(DesktopSessionState state, Lyrics lyrics) {
    final DesktopLyricsRuntimeState currentRuntime = state.lyricsRuntime;
    final SongInfo? song = currentRuntime.song;

    if (song == null) {
      return DesktopReducerResult(state: state);
    }

    final int durationMs = song.durationMs != null && song.durationMs! > 0
        ? song.durationMs!
        : lyrics.getDurationMs();
    final int nextLyricsRevision = currentRuntime.lyricsRevision + 1;
    if (lyrics.isEmpty) {
      return _resultWithSelectorRefresh(
        _buildEmptyLyricsState(
          state,
          currentRuntime: currentRuntime,
          lyrics: lyrics,
          durationMs: durationMs,
          lyricsRevision: nextLyricsRevision,
        ),
      );
    }

    final Lyrics fullTimestampLyrics = _buildFullTimestampLyrics(
      lyrics,
      durationMs: durationMs,
    );
    final Lyrics offsetLyrics = fullTimestampLyrics.withOffset(
      state.config.offsetMs,
    );
    final MultiLyricsData multiLyricsData = _buildMultiLyricsData(offsetLyrics);
    final LyricsData filteredOrig =
        multiLyricsData['orig'] ?? const <LyricsLine>[];
    if (filteredOrig.isEmpty) {
      return _resultWithSelectorRefresh(
        _buildEmptyLyricsState(
          state,
          currentRuntime: currentRuntime,
          lyrics: lyrics,
          durationMs: durationMs,
          lyricsRevision: nextLyricsRevision,
        ),
      );
    }
    final DesktopLyricsMapping lyricsMapping = _buildLyricsMapping(
      multiLyricsData: multiLyricsData,
      source: lyrics.source,
    );
    final DesktopAssignedLyricsSlots assignedLyricsSlots = _lyricsTrackAssigner
        .assignPositions(multiLyricsData['orig']!);
    final DesktopRubyMapping rubyMapping = _buildRubyMapping(
      multiLyricsData: multiLyricsData,
      lyricsMapping: lyricsMapping,
    );
    final DesktopLyricsSceneDocument sceneDocument = _buildLyricsSceneDocument(
      durationMs: durationMs,
      multiLyricsData: multiLyricsData,
      lyricsMapping: lyricsMapping,
      assignedLyricsSlots: assignedLyricsSlots,
      rubyMapping: rubyMapping,
      selectedLangs: state.config.selectedLangs,
    );
    final DesktopSessionState nextState = _applySceneDocument(
      state.copyWith(
        lyricsRuntime: currentRuntime.copyWith(
          lyrics: lyrics,
          durationMs: durationMs,
          lyricsRevision: nextLyricsRevision,
          multiLyricsData: multiLyricsData,
          lyricsMapping: lyricsMapping,
          assignedLyricsSlots: assignedLyricsSlots,
          rubyMapping: rubyMapping,
          clearStaticDisplay: true,
        ),
      ),
      sceneDocument,
    );
    return _resultWithPanelAndSelectorRefresh(nextState);
  }

  DesktopReducerResult setInstrumental(
    DesktopSessionState state, {
    bool enable = true,
  }) {
    if (!enable) {
      if (!state.config.isInstrumental) {
        return DesktopReducerResult(state: state);
      }
      return unlinkLyrics(state);
    }

    final DesktopSessionState clearedState = _clearLyricsAssociationState(
      state,
    );
    final Map<String, Object?> nextConfig = Map<String, Object?>.from(
      clearedState.config.songConfig,
    )..['inst'] = true;
    final DesktopSessionState instrumentalState = _setDisplayTextState(
      clearedState.copyWith(
        config: clearedState.config.copyWith(songConfig: nextConfig),
      ),
      _buildArtistTitleLines(
        clearedState.lyricsRuntime.song,
        message: _config.instrumentalMessage,
      ),
    );

    final DesktopPersistLibraryLinkEffect? persistEffect = _buildPersistEffect(
      instrumentalState,
    );
    return _resultWithPanelSync(
      instrumentalState,
      before: _buildTaskClearEffects(autoFetch: true, restoreArtistTitle: true),
      after: _optionalEffect(persistEffect),
    );
  }

  DesktopReducerResult setAutoSearch(
    DesktopSessionState state, {
    bool? isDisable,
  }) {
    if (state.lyricsRuntime.song == null) {
      return DesktopReducerResult(state: state);
    }

    final bool nextValue = isDisable ?? !state.config.isAutoSearchDisabled;
    final Map<String, Object?> nextConfig = Map<String, Object?>.from(
      state.config.songConfig,
    )..['disable_auto_search'] = nextValue;
    final DesktopSessionState nextState = state.copyWith(
      config: state.config.copyWith(songConfig: nextConfig),
    );
    final DesktopPersistLibraryLinkEffect? persistEffect = _buildPersistEffect(
      nextState,
    );
    return _result(nextState, effects: _optionalEffect(persistEffect));
  }

  DesktopReducerResult unlinkLyrics(
    DesktopSessionState state, {
    String message = '',
  }) {
    if (state.lyricsRuntime.song == null) {
      return DesktopReducerResult(state: state);
    }

    final DesktopSessionState nextState = _setDisplayTextState(
      _clearLyricsAssociationState(state),
      _buildArtistTitleLines(state.lyricsRuntime.song, message: message),
    );
    final DesktopPersistLibraryLinkEffect? persistEffect = _buildPersistEffect(
      nextState,
    );
    return _resultWithPanelSync(
      nextState,
      before: _buildTaskClearEffects(autoFetch: true, restoreArtistTitle: true),
      after: _optionalEffect(persistEffect),
    );
  }

  DesktopReducerResult setDisplayText(
    DesktopSessionState state,
    List<String> lines,
  ) {
    final DesktopSessionState nextState = _setDisplayTextState(state, lines);
    return _resultWithPanelSync(nextState);
  }

  /// 播放同步锚点已由调用方写入 state；reducer 只负责广播新锚点。
  /// 逐字进度在子窗口的投影运行时按本地时钟计算，主机不保存第二份进度。
  DesktopReducerResult applyPlaybackSync(DesktopSessionState state) {
    return _resultWithPanelSync(state);
  }

  DesktopReducerResult applyStop(DesktopSessionState state) {
    final DesktopSessionState stoppedState = state.copyWith(
      isPlaying: false,
      lastTask: DesktopIpcTask.stop,
      playbackSync: state.playbackSync.copyWith(
        pluginPlaybackTimeMs: 0,
        hostReceivedAtMs: _nowMsFactory(),
        isPlaying: false,
        syncRevision: state.playbackSync.syncRevision + 1,
        task: DesktopIpcTask.stop,
        clearPluginSendTimeMs: true,
        clearSceneId: true,
        clearSongToken: true,
      ),
      config: state.config.copyWith(songConfig: const <String, Object?>{}),
      lyricsRuntime: state.lyricsRuntime.copyWith(
        clearSong: true,
        clearLyrics: true,
        clearLyricsPath: true,
        clearDurationMs: true,
        clearMultiLyricsData: true,
        clearLyricsMapping: true,
        clearAssignedLyricsSlots: true,
        clearRubyMapping: true,
        clearSceneDocument: true,
        clearSceneRef: true,
        clearStaticDisplay: true,
      ),
    );
    return _resultWithPanelAndSelectorRefresh(
      stoppedState,
      before: _buildTaskClearEffects(autoFetch: true, restoreArtistTitle: true),
    );
  }

  DesktopReducerResult showArtistTitle(
    DesktopSessionState state, {
    String message = '',
  }) {
    return setDisplayText(
      state,
      _buildArtistTitleLines(state.lyricsRuntime.song, message: message),
    );
  }

  DesktopSessionState _clearLyricsAssociationState(DesktopSessionState state) {
    final Map<String, Object?> nextConfig =
        Map<String, Object?>.from(state.config.songConfig)
          ..remove('offset')
          ..remove('inst')
          ..remove('langs');
    return state.copyWith(
      config: state.config.copyWith(songConfig: nextConfig),
      playbackSync: state.playbackSync.copyWith(clearSceneId: true),
      lyricsRuntime: state.lyricsRuntime.copyWith(
        clearLyrics: true,
        clearLyricsPath: true,
        clearDurationMs: true,
        clearMultiLyricsData: true,
        clearLyricsMapping: true,
        clearAssignedLyricsSlots: true,
        clearRubyMapping: true,
        clearSceneDocument: true,
        clearSceneRef: true,
        lyricsRevision: state.lyricsRuntime.lyricsRevision + 1,
      ),
    );
  }

  DesktopSessionState _setDisplayTextState(
    DesktopSessionState state,
    List<String> lines,
  ) {
    final List<String> rawLines = desktopLyricsRetainStaticDisplayLines(lines);
    final bool hasRenderableLines = rawLines.any(
      desktopLyricsHasRenderableContent,
    );
    final DesktopSessionState nextState = state.copyWith(
      lyricsRuntime: state.lyricsRuntime.copyWith(
        staticDisplayLines: rawLines,
        lyricsRevision: state.lyricsRuntime.lyricsRevision + 1,
      ),
    );
    if (!hasRenderableLines) {
      return nextState.copyWith(
        playbackSync: nextState.playbackSync.copyWith(clearSceneId: true),
        lyricsRuntime: nextState.lyricsRuntime.copyWith(
          clearSceneDocument: true,
          clearSceneRef: true,
        ),
      );
    }
    return _applySceneDocument(
      nextState,
      DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: const <String>['orig'],
        langOrder: _config.langOrder,
        durationMs: 0,
        staticDisplayLines: rawLines,
      ),
    );
  }

  DesktopLyricsSceneDocument _buildLyricsSceneDocument({
    required int durationMs,
    required MultiLyricsData multiLyricsData,
    required DesktopLyricsMapping lyricsMapping,
    required DesktopAssignedLyricsSlots assignedLyricsSlots,
    required DesktopRubyMapping rubyMapping,
    required List<String> selectedLangs,
  }) {
    return DesktopLyricsSceneDocument(
      mode: DesktopLyricsSceneMode.lyrics,
      selectedLangs: selectedLangs,
      langOrder: _config.langOrder,
      durationMs: durationMs,
      multiLyricsData: multiLyricsData,
      lyricsMapping: lyricsMapping,
      assignedLyricsSlots: assignedLyricsSlots,
      rubyMapping: rubyMapping,
    );
  }

  DesktopSessionState _applySceneDocument(
    DesktopSessionState state,
    DesktopLyricsSceneDocument sceneDocument,
  ) {
    final int nextRevision = state.lyricsRuntime.sceneRevision + 1;
    final String owner = (state.instanceId ?? 0).toString();
    final String checksum = _sceneCodec.checksumForBytes(
      _sceneCodec.encode(sceneDocument),
    );
    final DesktopSceneRef sceneRef = DesktopSceneRef(
      sceneId: '$owner:$nextRevision',
      sceneRevision: nextRevision,
      checksum: checksum,
    );
    return state.copyWith(
      playbackSync: state.playbackSync.copyWith(sceneId: sceneRef.sceneId),
      lyricsRuntime: state.lyricsRuntime.copyWith(
        sceneDocument: sceneDocument,
        sceneRef: sceneRef,
        sceneRevision: nextRevision,
      ),
    );
  }

  DesktopSyncPanelsEffect? _buildPanelSyncEffect(
    DesktopSessionState state, {
    Iterable<int>? panelIds,
  }) {
    final int? instanceId = state.instanceId;
    if (instanceId == null) {
      return null;
    }
    final List<int> targetPanelIds = (panelIds ?? state.panels.keys)
        .where((int panelId) => state.panels.containsKey(panelId))
        .toList(growable: false);
    if (targetPanelIds.isEmpty) {
      return null;
    }
    return DesktopSyncPanelsEffect(
      instanceId: instanceId,
      panelIds: targetPanelIds,
      snapshot: buildDesktopPanelWindowSnapshot(state),
    );
  }

  DesktopReducerResult _result(
    DesktopSessionState state, {
    Iterable<DesktopSessionEffect> effects = const <DesktopSessionEffect>[],
  }) {
    return DesktopReducerResult(state: state, effects: effects);
  }

  DesktopReducerResult _resultWithPanelSync(
    DesktopSessionState state, {
    Iterable<DesktopSessionEffect> before = const <DesktopSessionEffect>[],
    Iterable<DesktopSessionEffect> after = const <DesktopSessionEffect>[],
  }) {
    return _result(
      state,
      effects: _composeEffects(
        state: state,
        before: before,
        includePanelSync: true,
        after: after,
      ),
    );
  }

  DesktopReducerResult _resultWithSelectorRefresh(
    DesktopSessionState state, {
    bool onlyIfVisible = true,
    Iterable<DesktopSessionEffect> before = const <DesktopSessionEffect>[],
    Iterable<DesktopSessionEffect> after = const <DesktopSessionEffect>[],
  }) {
    return _result(
      state,
      effects: _composeEffects(
        state: state,
        before: before,
        includeSelectorRefresh: true,
        selectorOnlyIfVisible: onlyIfVisible,
        after: after,
      ),
    );
  }

  DesktopReducerResult _resultWithPanelAndSelectorRefresh(
    DesktopSessionState state, {
    bool onlyIfVisible = true,
    Iterable<DesktopSessionEffect> before = const <DesktopSessionEffect>[],
    Iterable<DesktopSessionEffect> after = const <DesktopSessionEffect>[],
  }) {
    return _result(
      state,
      effects: _composeEffects(
        state: state,
        before: before,
        includePanelSync: true,
        includeSelectorRefresh: true,
        selectorOnlyIfVisible: onlyIfVisible,
        after: after,
      ),
    );
  }

  List<DesktopSessionEffect> _composeEffects({
    required DesktopSessionState state,
    Iterable<DesktopSessionEffect> before = const <DesktopSessionEffect>[],
    bool includePanelSync = false,
    bool includeSelectorRefresh = false,
    bool selectorOnlyIfVisible = true,
    Iterable<DesktopSessionEffect> after = const <DesktopSessionEffect>[],
  }) {
    return <DesktopSessionEffect>[
      ...before,
      if (includePanelSync) ..._optionalEffect(_buildPanelSyncEffect(state)),
      if (includeSelectorRefresh)
        _buildSelectorRefreshEffect(
          state,
          onlyIfVisible: selectorOnlyIfVisible,
        ),
      ...after,
    ];
  }

  List<DesktopSessionEffect> _buildTaskClearEffects({
    bool autoFetch = false,
    bool restoreArtistTitle = false,
  }) {
    return <DesktopSessionEffect>[
      if (autoFetch) const DesktopClearTaskEffect(taskKey: _autoFetchTaskKey),
      if (restoreArtistTitle)
        const DesktopClearTaskEffect(taskKey: _restoreArtistTitleTaskKey),
    ];
  }

  List<DesktopSessionEffect> _optionalEffect(DesktopSessionEffect? effect) {
    return effect == null
        ? const <DesktopSessionEffect>[]
        : <DesktopSessionEffect>[effect];
  }

  DesktopSessionState _buildEmptyLyricsState(
    DesktopSessionState state, {
    required DesktopLyricsRuntimeState currentRuntime,
    required Lyrics lyrics,
    required int durationMs,
    required int lyricsRevision,
  }) {
    return state.copyWith(
      lyricsRuntime: currentRuntime.copyWith(
        lyrics: lyrics,
        durationMs: durationMs,
        lyricsRevision: lyricsRevision,
        clearStaticDisplay: true,
        clearMultiLyricsData: true,
        clearLyricsMapping: true,
        clearAssignedLyricsSlots: true,
        clearRubyMapping: true,
        clearSceneDocument: true,
        clearSceneRef: true,
      ),
    );
  }

  String? _songTokenForSong(SongInfo? song) {
    return song?.id ?? song?.mid ?? song?.path;
  }

  Map<String, Object?> _applySelectionConfig({
    required Map<String, Object?> raw,
    required List<String> defaultLangs,
    required List<String>? langs,
    required int offsetMs,
  }) {
    final Map<String, Object?> next = Map<String, Object?>.from(raw);
    if (offsetMs != 0 || raw.containsKey('offset')) {
      next['offset'] = offsetMs;
    }
    if (langs != null && langs.isNotEmpty) {
      final List<String> orderedLangs = _orderedLangs(langs);
      if (listEquals(orderedLangs, _orderedLangs(defaultLangs))) {
        next.remove('langs');
      } else {
        next['langs'] = orderedLangs;
      }
    }
    return _normalizeSongConfig(next);
  }

  Map<String, Object?> _normalizeSongConfig(Map<String, Object?> raw) {
    final Map<String, Object?> normalized = Map<String, Object?>.from(raw);
    final Object? langsRaw = normalized['langs'];
    if (langsRaw is Iterable) {
      normalized['langs'] = _orderedLangs(
        langsRaw.whereType<String>().toList(growable: false),
      );
    }
    return normalized;
  }

  List<String> _orderedLangs(List<String> raw) {
    if (raw.isEmpty) {
      return const <String>[];
    }
    final List<String> ordered = <String>[];
    for (final String lang in _config.langOrder) {
      if (raw.contains(lang) && !ordered.contains(lang)) {
        ordered.add(lang);
      }
    }
    return List<String>.unmodifiable(ordered);
  }

  MultiLyricsData _buildMultiLyricsData(Lyrics lyrics) {
    final MultiLyricsData multiLyricsData = <String, LyricsData>{
      for (final MapEntry<String, LyricsData> entry in lyrics.data.entries)
        LyricsLanguageRegistry.normalizeKey(entry.key) ?? entry.key:
            List<LyricsLine>.unmodifiable(entry.value.toList(growable: false)),
    };
    final LyricsData? origLines = multiLyricsData['orig'];
    if (origLines == null) {
      throw StateError('桌面歌词运行态缺少 orig 语言');
    }
    multiLyricsData['orig'] = List<LyricsLine>.unmodifiable(
      origLines.map(_normalizeOrigLine).toList(growable: false),
    );
    return multiLyricsData;
  }

  Lyrics _buildFullTimestampLyrics(Lyrics lyrics, {required int durationMs}) {
    final Map<String, LyricsData> fullTimestampData = <String, LyricsData>{};
    for (final MapEntry<String, LyricsData> entry in lyrics.data.entries) {
      fullTimestampData[entry.key] = List<LyricsLine>.unmodifiable(
        getFullTimestampsLyricsData(
          entry.value,
          durationMs: durationMs,
          skipNone: true,
        ),
      );
    }
    return lyrics.copyWith(data: fullTimestampData);
  }

  LyricsLine _normalizeOrigLine(LyricsLine line) {
    if (line.words.isEmpty) {
      return line;
    }
    final LyricsWord firstWord = line.words.first;
    final LyricsWord lastWord = line.words.last;
    if (firstWord.startMs == line.startMs && lastWord.endMs == line.endMs) {
      return line;
    }
    return LyricsLine(
      startMs: firstWord.startMs,
      endMs: lastWord.endMs,
      words: line.words,
    );
  }

  DesktopLyricsMapping _buildLyricsMapping({
    required MultiLyricsData multiLyricsData,
    required Source source,
  }) {
    final LyricsData orig = multiLyricsData['orig']!;
    final LyricsData? origLrc = multiLyricsData['orig_lrc'];
    final DesktopLyricsMapping mapping = <String, Map<int, LyricsLine>>{};
    for (final MapEntry<String, LyricsData> entry in multiLyricsData.entries) {
      final String lang = entry.key;
      if (lang == 'orig' || lang == 'orig_lrc') {
        continue;
      }
      final Map<int, int> indexMapping = _lyricsLineMatcher.findClosestMatch(
        orig,
        entry.value,
        data3: origLrc,
        source: source,
      );
      mapping[lang] = <int, LyricsLine>{
        for (final MapEntry<int, int> item in indexMapping.entries)
          item.key: entry.value[item.value],
      };
    }
    return mapping;
  }

  DesktopRubyMapping _buildRubyMapping({
    required MultiLyricsData multiLyricsData,
    required DesktopLyricsMapping lyricsMapping,
  }) {
    if (!_config.showFurigana || !lyricsMapping.containsKey('roma')) {
      return const <int, List<RubySpan>>{};
    }

    final DesktopRubyMapping mapping = <int, List<RubySpan>>{};
    final Map<int, LyricsLine> romaLines = lyricsMapping['roma']!;
    final LyricsData origLines = multiLyricsData['orig']!;
    for (int index = 0; index < origLines.length; index += 1) {
      final LyricsLine origLine = origLines[index];
      final LyricsLine? romaLine = romaLines[index];
      if (romaLine != null) {
        // 注音是否可生成应由当前行的原文/罗马音决定，不能依赖“前面是否出现过假名”，
        // 否则开头纯汉字日文行会被跳过，后续行又会受整首歌顺序影响。
        final List<RubySpan> spans = generateRuby(origLine, romaLine);
        if (spans.isNotEmpty) {
          mapping[index] = spans;
        }
      }
    }
    return mapping;
  }

  DesktopRefreshSelectorEffect _buildSelectorRefreshEffect(
    DesktopSessionState state, {
    required bool onlyIfVisible,
  }) {
    final int instanceId =
        state.instanceId ?? (throw StateError('桌面选择器刷新缺少 instanceId'));
    return DesktopRefreshSelectorEffect(
      instanceId: instanceId,
      context: buildDesktopSelectorContext(state: state, refreshToken: 0),
      onlyIfVisible: onlyIfVisible,
    );
  }

  List<String> _buildArtistTitleLines(SongInfo? song, {String message = ''}) {
    final String title = song?.artistTitle(replaceMissing: true) ?? '? - ?';
    return <String>[title, if (message.isNotEmpty) message];
  }

  bool _canAutoFetch(SongInfo song) {
    return (song.title?.trim().isNotEmpty ?? false) ||
        (song.path?.trim().isNotEmpty ?? false);
  }

  DesktopPersistLibraryLinkEffect? _buildPersistEffect(
    DesktopSessionState state,
  ) {
    final SongInfo? song = state.lyricsRuntime.song;
    if (song == null) {
      return null;
    }
    return DesktopPersistLibraryLinkEffect(
      song: song,
      lyricsPath: state.lyricsRuntime.lyricsPath,
      configSnapshot: _buildPersistedSongConfig(state.config),
    );
  }

  Map<String, Object?> _buildPersistedSongConfig(
    DesktopSessionConfigState config,
  ) {
    return <String, Object?>{
      if (!listEquals(config.selectedLangs, config.effectiveDefaultLangs))
        'langs': config.selectedLangs,
      if (config.offsetMs != 0) 'offset': config.offsetMs,
      if (config.isInstrumental) 'inst': true,
      if (config.isAutoSearchDisabled) 'disable_auto_search': true,
    };
  }

  String _buildRemoteLyricsFileName(Lyrics lyrics) {
    final String artist = lyrics.songInfo.artistText;
    final String title = lyrics.songInfo.title ?? '';
    String fileName = <String>[
      if (artist.isNotEmpty) artist,
      if (title.isNotEmpty) title,
    ].join(' - ');
    if (lyrics.source != Source.local) {
      fileName += '｜${lyrics.source.value}';
    }
    if (lyrics.id != null && lyrics.id!.isNotEmpty) {
      fileName += '(${lyrics.id})';
    } else if (lyrics.mid != null && lyrics.mid!.isNotEmpty) {
      fileName += '(${lyrics.mid})';
    } else {
      fileName += '(time:${_nowMsFactory()})';
    }
    return '${LyricsPathTemplateFormatter.sanitizeFileName(fileName)}.json';
  }

  String? _normalizeText(String? value) {
    if (value == null) {
      return null;
    }
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

const String _autoFetchTaskKey = 'auto_fetch';
const String _restoreArtistTitleTaskKey = 'restore_artist_title';
