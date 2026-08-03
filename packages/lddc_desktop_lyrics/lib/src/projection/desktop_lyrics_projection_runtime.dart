import 'package:characters/characters.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../render/desktop_render.dart';
import 'desktop_lyrics_scene.dart';
import 'desktop_lyrics_timing_math.dart';

typedef _DesktopActiveProgressMap = Map<int, Map<String, CharProgress>>;

/// 与具体播放器协议无关的播放事件类型。
enum DesktopPlaybackEventKind {
  start,
  pause,
  resume,
  stop,
  sync,
  trackChanged,
  other,
}

/// 浮窗或面板投影真正需要的最小样式快照。
final class DesktopLyricsProjectionStyle {
  DesktopLyricsProjectionStyle({
    List<String> enabledLangs = const <String>[],
    this.showFurigana = true,
  }) : enabledLangs = List<String>.unmodifiable(enabledLangs);

  final List<String> enabledLangs;
  final bool showFurigana;
}

/// 子窗口侧播放同步事件。
///
/// 这是桌面歌词插件协议的正式时间语义。宿主进程收到插件消息后，会把插件给出的
/// 播放时间、发送时间和宿主接收时间一起传进子窗口；子窗口再用这些时间计算当前
/// 歌词进度。三个时间点不能合并，否则进程间传输延迟会被错误计入播放进度。
class DesktopLyricsPlaybackSyncEvent {
  const DesktopLyricsPlaybackSyncEvent({
    required this.pluginPlaybackTimeMs,
    required this.pluginSendTimeMs,
    required this.hostReceivedAtMs,
    required this.isPlaying,
    required this.syncRevision,
    required this.task,
    required this.sceneId,
    required this.songToken,
  });

  final int pluginPlaybackTimeMs;
  final int? pluginSendTimeMs;
  final int hostReceivedAtMs;
  final bool isPlaying;
  final int syncRevision;
  final DesktopPlaybackEventKind task;
  final String? sceneId;
  final String? songToken;
}

/// 子窗口唯一歌词投影运行时。
///
/// “投影”指的是：宿主只负责保存桌面歌词会话快照和插件同步锚点，真正的
/// active line、逐字进度、罗马音/假名展示都在子窗口按当前时间重新计算。
/// 这样可以避免宿主和子窗口各维护一份进度状态，降低跨进程同步延迟造成的
/// 闪烁和状态不一致风险。这里刻意对齐桌面歌词插件协议的时间语义，所以
/// 修改前必须先跑对应的向量测试和 timing parity 测试。
class DesktopLyricsProjectionRuntime {
  DesktopLyricsProjectionRuntime({int Function()? nowMsFactory})
    : _nowMsFactory =
          nowMsFactory ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _nowMsFactory;

  DesktopLyricsSceneDocument? _scene;
  DesktopLyricsProjectionStyle? _floatingStyle;
  DesktopLyricsProjectionStyle? _panelStyle;
  DesktopLyricsPlaybackSyncEvent? _lastSyncEvent;
  final Map<String, int> _graphemeLengthCache = <String, int>{};
  int _startTimeMs = 0;
  int _currentTimeMs = 0;
  bool _isPlaying = false;
  int _lastProgressTimeMs = -1;
  List<String> _lastProgressLangs = const <String>[];
  _DesktopProgressSnapshot? _lastProgressSnapshot;
  String? _lastSyncBasisKey;
  int? _lastSyncBasisNowMs;

  bool get isPlaying => _isPlaying;

  int get currentTimeMs => _currentTimeMs;

  void bindScene(DesktopLyricsSceneDocument? scene) {
    if (_scene == scene) {
      return;
    }
    _scene = scene;
    // scene 不可变且自带容量边界；缓存只保存当前 scene 实际访问过的单词，
    // 换 scene 时整体清空，避免 60Hz 投影反复解析同一组 grapheme。
    _graphemeLengthCache.clear();
    _resetComputedState();
  }

  void updateFloatingStyle(DesktopLyricsProjectionStyle? style) {
    _floatingStyle = style;
  }

  void updatePanelStyle(DesktopLyricsProjectionStyle? style) {
    _panelStyle = style;
  }

  int syncEvent(DesktopLyricsPlaybackSyncEvent? event, {int? nowMs}) {
    if (event == null) {
      return _currentTimeMs;
    }
    final int resolvedNowMs = nowMs ?? _nowMsFactory();
    final String replayKey = _buildReplayKey(event);
    final DesktopLyricsPlaybackSyncEvent? previous = _lastSyncEvent;
    if (previous != null && event.syncRevision < previous.syncRevision) {
      return _currentTimeMs;
    }
    _lastSyncEvent = event;
    if (event.task == DesktopPlaybackEventKind.stop) {
      _startTimeMs = resolvedNowMs;
      _currentTimeMs = 0;
      _isPlaying = false;
    } else if (event.task == DesktopPlaybackEventKind.pause) {
      _syncClockFromEvent(
        event,
        nowMs: resolvedNowMs,
        basisNowMs: _resolveSyncBasisNowMs(replayKey, resolvedNowMs),
      );
      _isPlaying = false;
    } else {
      _syncClockFromEvent(
        event,
        nowMs: resolvedNowMs,
        basisNowMs: _resolveSyncBasisNowMs(replayKey, resolvedNowMs),
      );
    }
    _resetComputedState();
    return _currentTimeMs;
  }

  int tick({int? nowMs}) {
    if (!_isPlaying) {
      return _currentTimeMs;
    }
    final int resolvedNowMs = nowMs ?? _nowMsFactory();
    _currentTimeMs = (resolvedNowMs - _startTimeMs).clamp(0, 1 << 31);
    return _currentTimeMs;
  }

  DesktopFloatingRenderPlan? buildFloatingRenderPlan({int? currentTimeMs}) {
    final DesktopLyricsSceneDocument? scene = _scene;
    final DesktopLyricsProjectionStyle? style = _floatingStyle;
    if (scene == null || style == null) {
      return null;
    }
    if (scene.isStaticText) {
      return _buildStaticFloatingPlan(scene);
    }
    final List<String> enabledLangs = _resolveEnabledLangs(
      preferred: style.enabledLangs,
      fallback: scene.selectedLangs,
    );
    if (enabledLangs.isEmpty || scene.assignedLyricsSlots.isEmpty) {
      return null;
    }
    final _DesktopProgressSnapshot progressSnapshot = _resolveProgressSnapshot(
      currentTimeMs: currentTimeMs,
      enabledLangs: enabledLangs,
    );
    final int resolvedCurrentTimeMs = _resolveCurrentTimeMs(currentTimeMs);
    final int resolvedDurationMs = _resolveDurationMs(
      durationMs: scene.durationMs,
      assignedLyricsSlots: scene.assignedLyricsSlots,
    );
    final List<DesktopRenderTrackPlan> leftTracks = <DesktopRenderTrackPlan>[];
    final List<DesktopRenderTrackPlan> rightTracks = <DesktopRenderTrackPlan>[];

    final List<MapEntry<(Direction, int), List<(int, LyricsLine)>>>
    slotEntries = scene.assignedLyricsSlots.entries.toList(growable: false)
      ..sort((left, right) {
        final int trackCompare = left.key.$2.compareTo(right.key.$2);
        if (trackCompare != 0) {
          return trackCompare;
        }
        return left.key.$1.code.compareTo(right.key.$1.code);
      });

    for (final MapEntry<(Direction, int), List<(int, LyricsLine)>> entry
        in slotEntries) {
      final Direction side = entry.key.$1;
      final int track = entry.key.$2;
      final _ResolvedSlotWindow? slotWindow = _resolveSlotWindow(
        slotLines: entry.value,
        currentTimeMs: resolvedCurrentTimeMs,
        durationMs: resolvedDurationMs,
      );
      if (slotWindow == null) {
        continue;
      }

      final double opacity = _computeOpacity(
        slotWindow: slotWindow,
        currentTimeMs: resolvedCurrentTimeMs,
        track: track,
      );
      final List<DesktopRenderLinePlan> lines = <DesktopRenderLinePlan>[];
      for (final String lang in enabledLangs) {
        final _ResolvedDisplayLine? displayLine = _resolveFloatingDisplayLine(
          lang: lang,
          origIndex: slotWindow.origIndex,
          origLine: slotWindow.origLine,
          lyricsMapping: scene.lyricsMapping,
          rubyMapping: style.showFurigana
              ? scene.rubyMapping
              : const <int, List<RubySpan>>{},
        );
        if (displayLine == null) {
          continue;
        }

        DesktopRenderLineState state = DesktopRenderLineState.unplayed;
        CharProgress activeProgress = const CharProgress(
          charIndex: 0,
          charRatio: 0,
        );
        switch (slotWindow.focusKind) {
          case DesktopLyricsSlotFocusKind.previous:
            state = DesktopRenderLineState.played;
          case DesktopLyricsSlotFocusKind.current:
            state = DesktopRenderLineState.active;
            final CharProgress? progress =
                progressSnapshot.activeProgressMap[slotWindow.origIndex]?[lang];
            if (progress != null) {
              activeProgress = progress;
            } else if (resolvedCurrentTimeMs >= slotWindow.lineEndMs) {
              state = DesktopRenderLineState.played;
            }
          case DesktopLyricsSlotFocusKind.next:
            state = DesktopRenderLineState.unplayed;
        }

        lines.add(
          DesktopRenderLinePlan(
            origIndex: slotWindow.origIndex,
            lang: lang,
            text: displayLine.text,
            state: state,
            activeProgress: activeProgress,
            opacity: opacity,
            transitionStartMs: _resolveTransitionStartMs(slotWindow),
            transitionEndMs: _resolveTransitionEndMs(slotWindow),
            align: side,
            rubies: displayLine.rubies ?? const <RubySpan>[],
            words: displayLine.words,
          ),
        );
      }
      if (lines.isEmpty) {
        continue;
      }
      final DesktopRenderTrackPlan trackPlan = DesktopRenderTrackPlan(
        side: side,
        track: track,
        focusedOrigIndex: slotWindow.origIndex,
        lines: lines,
      );
      if (side == Direction.left) {
        leftTracks.add(trackPlan);
      } else if (side == Direction.right) {
        rightTracks.add(trackPlan);
      }
    }

    if (leftTracks.isEmpty && rightTracks.isEmpty) {
      return null;
    }
    return DesktopFloatingRenderPlan(
      leftTracks: leftTracks,
      rightTracks: rightTracks,
      hasRubiesGlobally: scene.rubyMapping.isNotEmpty,
    );
  }

  DesktopPanelRenderPlan? buildPanelRenderPlan({int? currentTimeMs}) {
    final DesktopLyricsSceneDocument? scene = _scene;
    final DesktopLyricsProjectionStyle? style = _panelStyle;
    if (scene == null || style == null) {
      return null;
    }
    if (scene.isStaticText) {
      return _buildStaticPanelPlan(scene);
    }
    final LyricsData origLines =
        scene.multiLyricsData['orig'] ?? const <LyricsLine>[];
    if (origLines.isEmpty) {
      return null;
    }
    final List<String> enabledLangs = _resolveEnabledLangs(
      preferred: style.enabledLangs,
      fallback: scene.selectedLangs,
    );
    if (enabledLangs.isEmpty) {
      return null;
    }
    final _DesktopProgressSnapshot progressSnapshot = _resolveProgressSnapshot(
      currentTimeMs: currentTimeMs,
      enabledLangs: enabledLangs,
    );
    final List<DesktopRenderBlockPlan> blocks = <DesktopRenderBlockPlan>[
      for (int index = 0; index < origLines.length; index += 1)
        DesktopRenderBlockPlan(
          origIndex: index,
          state: _resolveBlockState(
            activeIndex: progressSnapshot.activeIndex,
            activeProgressMap: progressSnapshot.activeProgressMap,
            origIndex: index,
          ),
          lines: <DesktopRenderLinePlan>[
            for (final String lang in enabledLangs)
              if (_resolvePanelLinePlan(
                    lang: lang,
                    origIndex: index,
                    origLine: origLines[index],
                    scene: scene,
                    style: style,
                    progressSnapshot: progressSnapshot,
                  )
                  case final DesktopRenderLinePlan linePlan)
                linePlan,
          ],
        ),
    ];
    return DesktopPanelRenderPlan(
      mode: scene.mode.name,
      activeIndex: progressSnapshot.activeIndex,
      enabledLangs: enabledLangs,
      blocks: blocks,
    );
  }

  void _syncClockFromEvent(
    DesktopLyricsPlaybackSyncEvent event, {
    required int nowMs,
    required int basisNowMs,
  }) {
    // delay 要按子窗口首次真正处理该 anchor 的时刻扣除，之后重放沿用同一基准。
    final int anchorNowMs = basisNowMs;
    int playbackTimeMs = event.pluginPlaybackTimeMs.clamp(0, 1 << 31);
    final int? sendTimeMs = event.pluginSendTimeMs;
    if (sendTimeMs != null) {
      final int delayMs = anchorNowMs - sendTimeMs;
      if (delayMs > 0) {
        playbackTimeMs = (playbackTimeMs - delayMs).clamp(0, 1 << 31);
      }
    }
    _startTimeMs = anchorNowMs - playbackTimeMs;
    _currentTimeMs = event.isPlaying
        ? (nowMs - _startTimeMs).clamp(0, 1 << 31)
        : playbackTimeMs;
    _isPlaying = event.isPlaying;
  }

  String _buildReplayKey(DesktopLyricsPlaybackSyncEvent event) {
    return <Object?>[
      event.syncRevision,
      event.task.name,
      event.pluginPlaybackTimeMs,
      event.pluginSendTimeMs,
      event.hostReceivedAtMs,
      event.isPlaying,
      event.sceneId,
      event.songToken,
    ].join('|');
  }

  int _resolveSyncBasisNowMs(String replayKey, int resolvedNowMs) {
    if (_lastSyncBasisKey == replayKey && _lastSyncBasisNowMs != null) {
      return _lastSyncBasisNowMs!;
    }
    _lastSyncBasisKey = replayKey;
    _lastSyncBasisNowMs = resolvedNowMs;
    return resolvedNowMs;
  }

  _DesktopProgressSnapshot _resolveProgressSnapshot({
    required int? currentTimeMs,
    required List<String> enabledLangs,
  }) {
    final DesktopLyricsSceneDocument? scene = _scene;
    if (scene == null || !_hasResolvableLyricsTiming(scene)) {
      return const _DesktopProgressSnapshot(
        activeIndex: -1,
        activeProgressMap: <int, Map<String, CharProgress>>{},
      );
    }
    final int resolvedCurrentTimeMs = _resolveCurrentTimeMs(currentTimeMs);
    if (_lastProgressSnapshot != null &&
        _lastProgressTimeMs == resolvedCurrentTimeMs &&
        _listEquals(_lastProgressLangs, enabledLangs)) {
      return _lastProgressSnapshot!;
    }
    final _DesktopProgressSnapshot snapshot = _computeProgressSnapshot(
      currentTimeMs: resolvedCurrentTimeMs,
      multiLyricsData: scene.multiLyricsData,
      lyricsMapping: scene.lyricsMapping,
      enabledLangs: enabledLangs,
    );
    _lastProgressTimeMs = resolvedCurrentTimeMs;
    _lastProgressLangs = List<String>.unmodifiable(enabledLangs);
    _lastProgressSnapshot = snapshot;
    return snapshot;
  }

  int _resolveCurrentTimeMs(int? currentTimeMs) {
    if (currentTimeMs != null) {
      return currentTimeMs;
    }
    return tick();
  }

  _DesktopProgressSnapshot _computeProgressSnapshot({
    required int currentTimeMs,
    required MultiLyricsData multiLyricsData,
    required DesktopLyricsMapping lyricsMapping,
    required List<String> enabledLangs,
  }) {
    final LyricsData? origLines = multiLyricsData['orig'];
    if (origLines == null || origLines.isEmpty) {
      return const _DesktopProgressSnapshot(
        activeIndex: -1,
        activeProgressMap: <int, Map<String, CharProgress>>{},
      );
    }

    int activeIndex = -1;
    final _DesktopActiveProgressMap activeProgressMap =
        <int, Map<String, CharProgress>>{};
    final Set<String> langsToProcess = <String>{'orig', ...enabledLangs};

    for (int index = 0; index < origLines.length; index += 1) {
      final LyricsLine line = origLines[index];
      final int? lineStartMs = _resolveLineStartMs(line);
      final int? lineEndMs = _resolveLineEndMs(line);
      if (lineStartMs == null || lineEndMs == null) {
        continue;
      }

      if (lineStartMs <= currentTimeMs && currentTimeMs <= lineEndMs) {
        activeIndex = index;
        final Map<String, CharProgress> lineProgress = <String, CharProgress>{};
        for (final String lang in langsToProcess) {
          final LyricsLine? targetLine = _resolveTargetLine(
            lang: lang,
            origLine: line,
            origIndex: index,
            lyricsMapping: lyricsMapping,
          );
          if (targetLine == null) {
            continue;
          }
          lineProgress[lang] = _computeLineProgress(
            currentTimeMs: currentTimeMs,
            origLine: line,
            targetLine: targetLine,
            forceSyncOrigTimeline:
                lang != 'orig' && targetLine.words.length == 1,
          );
        }
        activeProgressMap[index] = lineProgress;
        continue;
      }

      if (lineStartMs > currentTimeMs) {
        if (activeProgressMap.isEmpty) {
          if (index > 0) {
            final LyricsLine prevLine = origLines[index - 1];
            final int? prevEndMs = _resolveLineEndMs(prevLine);
            if (prevEndMs != null && currentTimeMs > prevEndMs) {
              activeIndex = index - 1;
              activeProgressMap[index - 1] = _buildFullProgress(
                origLine: prevLine,
                origIndex: index - 1,
                lyricsMapping: lyricsMapping,
                langsToProcess: langsToProcess,
              );
            }
          } else {
            activeIndex = 0;
          }
        }
        break;
      }
    }

    final LyricsLine lastLine = origLines.last;
    final int? lastEndMs = _resolveLineEndMs(lastLine);
    if (activeProgressMap.isEmpty &&
        lastEndMs != null &&
        currentTimeMs > lastEndMs) {
      activeIndex = origLines.length - 1;
      activeProgressMap[activeIndex] = _buildFullProgress(
        origLine: lastLine,
        origIndex: activeIndex,
        lyricsMapping: lyricsMapping,
        langsToProcess: langsToProcess,
      );
    }

    return _DesktopProgressSnapshot(
      activeIndex: activeIndex,
      activeProgressMap: activeProgressMap,
    );
  }

  LyricsLine? _resolveTargetLine({
    required String lang,
    required LyricsLine origLine,
    required int origIndex,
    required DesktopLyricsMapping lyricsMapping,
  }) {
    if (lang == 'orig') {
      return origLine;
    }
    return lyricsMapping[lang]?[origIndex];
  }

  CharProgress _computeLineProgress({
    required int currentTimeMs,
    required LyricsLine origLine,
    required LyricsLine targetLine,
    required bool forceSyncOrigTimeline,
  }) {
    int currentGlobalIndex = 0;
    bool calculated = false;
    CharProgress progress = const CharProgress(charIndex: 0, charRatio: 0.0);

    for (
      int wordIndex = 0;
      wordIndex < targetLine.words.length;
      wordIndex += 1
    ) {
      final LyricsWord word = targetLine.words[wordIndex];
      // 渲染层以 Unicode grapheme 为字符坐标；这里若使用 UTF-16 code unit
      // 长度，emoji、组合音标和部分少数文字会让扫色索引越过真实字形。
      final int wordLength = _graphemeLength(word.text);
      final int? wordStartMs = forceSyncOrigTimeline
          ? _resolveLineStartMs(origLine)
          : _resolveWordStartMs(targetLine, wordIndex);
      final int? wordEndMs = forceSyncOrigTimeline
          ? _resolveLineEndMs(origLine)
          : _resolveWordEndMs(targetLine, wordIndex);

      if (wordStartMs == null || wordEndMs == null) {
        currentGlobalIndex += wordLength;
        continue;
      }

      if (wordStartMs <= currentTimeMs && currentTimeMs <= wordEndMs) {
        final int durationMs = wordEndMs - wordStartMs;
        if (durationMs > 0 && wordLength > 0) {
          final double wordProgress =
              (currentTimeMs - wordStartMs) / durationMs;
          final double virtualIndex = wordProgress * wordLength;
          int charOffset = virtualIndex.floor();
          double charRatio = virtualIndex - charOffset;
          if (charOffset >= wordLength) {
            charOffset = wordLength - 1;
            charRatio = 1.0;
          }
          progress = CharProgress(
            charIndex: currentGlobalIndex + charOffset,
            charRatio: charRatio,
          );
          calculated = true;
          break;
        }
      } else if (currentTimeMs < wordStartMs) {
        progress = CharProgress(charIndex: currentGlobalIndex, charRatio: 0.0);
        calculated = true;
        break;
      }

      currentGlobalIndex += wordLength;
    }

    if (!calculated) {
      final CharProgress completed = CharProgress(
        charIndex: currentGlobalIndex,
        charRatio: 0.0,
      );
      return completed;
    }
    return progress;
  }

  Map<String, CharProgress> _buildFullProgress({
    required LyricsLine origLine,
    required int origIndex,
    required DesktopLyricsMapping lyricsMapping,
    required Set<String> langsToProcess,
  }) {
    final Map<String, CharProgress> fullProgress = <String, CharProgress>{};
    for (final String lang in langsToProcess) {
      final LyricsLine? line = _resolveTargetLine(
        lang: lang,
        origLine: origLine,
        origIndex: origIndex,
        lyricsMapping: lyricsMapping,
      );
      if (line == null) {
        continue;
      }
      final int totalChars = line.words.fold<int>(
        0,
        (sum, word) => sum + _graphemeLength(word.text),
      );
      fullProgress[lang] = CharProgress(charIndex: totalChars, charRatio: 0.0);
    }
    return fullProgress;
  }

  DesktopRenderLinePlan? _resolvePanelLinePlan({
    required String lang,
    required int origIndex,
    required LyricsLine origLine,
    required DesktopLyricsSceneDocument scene,
    required DesktopLyricsProjectionStyle style,
    required _DesktopProgressSnapshot progressSnapshot,
  }) {
    final LyricsLine? displayLine = switch (lang) {
      'orig' => origLine,
      _ => scene.lyricsMapping[lang]?[origIndex],
    };
    if (displayLine == null) {
      return null;
    }
    final String text = displayLine.words
        .map((LyricsWord word) => word.text)
        .join();
    if (!desktopLyricsHasRenderableContent(text)) {
      return null;
    }
    return DesktopRenderLinePlan(
      origIndex: origIndex,
      lang: lang,
      text: text,
      state: _resolveBlockState(
        activeIndex: progressSnapshot.activeIndex,
        activeProgressMap: progressSnapshot.activeProgressMap,
        origIndex: origIndex,
      ),
      activeProgress:
          progressSnapshot.activeProgressMap[origIndex]?[lang] ??
          const CharProgress(charIndex: 0, charRatio: 0),
      rubies: lang == 'orig' && style.showFurigana
          ? (scene.rubyMapping[origIndex] ?? const <RubySpan>[])
          : const <RubySpan>[],
      words: _buildRenderWords(
        displayLine,
        overrideStartMs: lang != 'orig' && displayLine.words.length == 1
            ? _resolveLineStartMs(origLine)
            : null,
        overrideEndMs: lang != 'orig' && displayLine.words.length == 1
            ? _resolveLineEndMs(origLine)
            : null,
      ),
    );
  }

  int _resolveDurationMs({
    required int? durationMs,
    required Map<(Direction, int), List<(int, LyricsLine)>> assignedLyricsSlots,
  }) {
    if (durationMs != null && durationMs > 0) {
      return durationMs;
    }

    int best = 0;
    for (final List<(int, LyricsLine)> slotLines
        in assignedLyricsSlots.values) {
      for (final (int _, LyricsLine line) in slotLines) {
        final int? endMs = _resolveLineEndMs(line);
        if (endMs != null && endMs > best) {
          best = endMs;
        }
      }
    }
    return best;
  }

  _ResolvedSlotWindow? _resolveSlotWindow({
    required List<(int, LyricsLine)> slotLines,
    required int currentTimeMs,
    required int durationMs,
  }) {
    return resolveDesktopLyricsSlotWindow<(int, LyricsLine)>(
      entries: slotLines,
      currentTimeMs: currentTimeMs,
      durationMs: durationMs,
      resolveLineStartMs: ((int, LyricsLine) entry) =>
          _resolveLineStartMs(entry.$2),
      resolveLineEndMs: ((int, LyricsLine) entry) =>
          _resolveLineEndMs(entry.$2),
    );
  }

  double _computeOpacity({
    required _ResolvedSlotWindow slotWindow,
    required int currentTimeMs,
    required int track,
  }) {
    return computeDesktopLyricsSlotOpacity(
      slotWindow: slotWindow,
      currentTimeMs: currentTimeMs,
      track: track,
    );
  }

  int? _resolveTransitionStartMs(_ResolvedSlotWindow slotWindow) {
    return resolveDesktopLyricsTransitionStartMs(slotWindow);
  }

  int? _resolveTransitionEndMs(_ResolvedSlotWindow slotWindow) {
    return resolveDesktopLyricsTransitionEndMs(slotWindow);
  }

  _ResolvedDisplayLine? _resolveFloatingDisplayLine({
    required String lang,
    required int origIndex,
    required LyricsLine origLine,
    required DesktopLyricsMapping lyricsMapping,
    required Map<int, List<RubySpan>> rubyMapping,
  }) {
    if (lang == 'orig') {
      final String text = origLine.words.map((word) => word.text).join();
      if (!desktopLyricsHasRenderableContent(text)) {
        return const _ResolvedDisplayLine(
          text: '',
          words: <DesktopRenderWordPlan>[],
        );
      }
      return _ResolvedDisplayLine(
        text: text,
        rubies: rubyMapping[origIndex],
        words: _buildRenderWords(origLine),
      );
    }

    final Map<int, LyricsLine>? mapping = lyricsMapping[lang];
    if (mapping == null) {
      return null;
    }

    final LyricsLine? mappedLine = mapping[origIndex];
    if (mappedLine == null) {
      return const _ResolvedDisplayLine(
        text: '',
        words: <DesktopRenderWordPlan>[],
      );
    }
    final String text = mappedLine.words.map((word) => word.text).join();
    if (!desktopLyricsHasRenderableContent(text)) {
      return const _ResolvedDisplayLine(
        text: '',
        words: <DesktopRenderWordPlan>[],
      );
    }
    return _ResolvedDisplayLine(
      text: text,
      words: _buildRenderWords(
        mappedLine,
        overrideStartMs: mappedLine.words.length == 1
            ? _resolveLineStartMs(origLine)
            : null,
        overrideEndMs: mappedLine.words.length == 1
            ? _resolveLineEndMs(origLine)
            : null,
      ),
    );
  }

  DesktopFloatingRenderPlan? _buildStaticFloatingPlan(
    DesktopLyricsSceneDocument scene,
  ) {
    final List<String> lines = desktopLyricsRetainStaticDisplayLines(
      scene.staticDisplayLines,
    );
    if (lines.isEmpty) {
      return null;
    }
    final List<DesktopRenderLinePlan> leftLines = <DesktopRenderLinePlan>[];
    final List<DesktopRenderLinePlan> rightLines = <DesktopRenderLinePlan>[];
    int visibleCount = 0;
    for (int index = 0; index < lines.length; index += 1) {
      final bool isLeft = visibleCount.isEven;
      final DesktopRenderLinePlan line = DesktopRenderLinePlan(
        origIndex: index,
        lang: 'orig',
        text: lines[index],
        state: DesktopRenderLineState.played,
        activeProgress: CharProgress(
          charIndex: lines[index].length,
          charRatio: 0,
        ),
        align: isLeft ? Direction.left : Direction.right,
      );
      if (isLeft) {
        leftLines.add(line);
      } else {
        rightLines.add(line);
      }
      visibleCount += 1;
    }
    return DesktopFloatingRenderPlan(
      leftTracks: leftLines.isEmpty
          ? const <DesktopRenderTrackPlan>[]
          : <DesktopRenderTrackPlan>[
              DesktopRenderTrackPlan(
                side: Direction.left,
                track: 0,
                focusedOrigIndex: leftLines.first.origIndex,
                lines: leftLines,
              ),
            ],
      rightTracks: rightLines.isEmpty
          ? const <DesktopRenderTrackPlan>[]
          : <DesktopRenderTrackPlan>[
              DesktopRenderTrackPlan(
                side: Direction.right,
                track: 0,
                focusedOrigIndex: rightLines.first.origIndex,
                lines: rightLines,
              ),
            ],
      hasRubiesGlobally: false,
    );
  }

  DesktopPanelRenderPlan _buildStaticPanelPlan(
    DesktopLyricsSceneDocument scene,
  ) {
    final List<String> lines = desktopLyricsVisibleStaticDisplayLines(
      scene.staticDisplayLines,
    );
    return DesktopPanelRenderPlan(
      mode: DesktopLyricsSceneMode.staticText.name,
      activeIndex: 0,
      enabledLangs: const <String>['orig'],
      blocks: <DesktopRenderBlockPlan>[
        for (int index = 0; index < lines.length; index += 1)
          DesktopRenderBlockPlan(
            origIndex: index,
            state: DesktopRenderLineState.active,
            lines: <DesktopRenderLinePlan>[
              DesktopRenderLinePlan(
                origIndex: index,
                lang: 'orig',
                text: lines[index],
                state: DesktopRenderLineState.active,
                activeProgress: CharProgress(
                  charIndex: lines[index].length,
                  charRatio: 0,
                ),
              ),
            ],
          ),
      ],
    );
  }

  DesktopRenderLineState _resolveBlockState({
    required int activeIndex,
    required _DesktopActiveProgressMap activeProgressMap,
    required int origIndex,
  }) {
    if (activeProgressMap.containsKey(origIndex)) {
      return DesktopRenderLineState.active;
    }
    if (activeIndex >= 0 && origIndex < activeIndex) {
      return DesktopRenderLineState.played;
    }
    return DesktopRenderLineState.unplayed;
  }

  bool _hasResolvableLyricsTiming(DesktopLyricsSceneDocument scene) {
    final LyricsData? origLines = scene.multiLyricsData['orig'];
    if (origLines == null || origLines.isEmpty) {
      return false;
    }
    for (final LyricsLine line in origLines) {
      if (_resolveLineStartMs(line) != null &&
          _resolveLineEndMs(line) != null) {
        return true;
      }
    }
    return false;
  }

  List<String> _resolveEnabledLangs({
    required List<String> preferred,
    required List<String> fallback,
  }) {
    final List<String> source = preferred.isNotEmpty ? preferred : fallback;
    final List<String> ordered = <String>[];
    for (final String lang in source) {
      if (!ordered.contains(lang)) {
        ordered.add(lang);
      }
    }
    return List<String>.unmodifiable(ordered);
  }

  List<DesktopRenderWordPlan> _buildRenderWords(
    LyricsLine line, {
    int? overrideStartMs,
    int? overrideEndMs,
  }) {
    final List<LyricsWord> words = line.words;
    if (words.isEmpty) {
      return const <DesktopRenderWordPlan>[];
    }
    final int? lineStartMs = overrideStartMs ?? _resolveLineStartMs(line);
    final int? lineEndMs = overrideEndMs ?? _resolveLineEndMs(line);
    if (_shouldUseLineLevelWordPlan(line) &&
        lineStartMs != null &&
        lineEndMs != null) {
      return <DesktopRenderWordPlan>[
        DesktopRenderWordPlan(
          text: line.text,
          startMs: lineStartMs,
          endMs: lineEndMs,
        ),
      ];
    }
    return words
        .asMap()
        .entries
        .map((MapEntry<int, LyricsWord> entry) {
          final LyricsWord word = entry.value;
          return DesktopRenderWordPlan(
            text: word.text,
            startMs: entry.key == 0
                ? (lineStartMs ??
                      resolveDesktopLyricsWordStartMs(line, entry.key))
                : resolveDesktopLyricsWordStartMs(line, entry.key),
            endMs: entry.key == words.length - 1
                ? (lineEndMs ?? resolveDesktopLyricsWordEndMs(line, entry.key))
                : resolveDesktopLyricsWordEndMs(line, entry.key),
          );
        })
        .toList(growable: false);
  }

  bool _shouldUseLineLevelWordPlan(LyricsLine line) {
    return shouldUseDesktopLineLevelWordPlan(line);
  }

  int? _resolveLineStartMs(LyricsLine line) {
    return resolveDesktopLyricsLineStartMs(line);
  }

  int? _resolveLineEndMs(LyricsLine line) {
    return resolveDesktopLyricsLineEndMs(line);
  }

  int? _resolveWordStartMs(LyricsLine line, int wordIndex) {
    return resolveDesktopLyricsWordStartMs(line, wordIndex);
  }

  int? _resolveWordEndMs(LyricsLine line, int wordIndex) {
    return resolveDesktopLyricsWordEndMs(line, wordIndex);
  }

  int _graphemeLength(String text) {
    return _graphemeLengthCache.putIfAbsent(text, () => text.characters.length);
  }

  bool _listEquals(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  void _resetComputedState() {
    _lastProgressTimeMs = -1;
    _lastProgressLangs = const <String>[];
    _lastProgressSnapshot = null;
  }
}

final class _DesktopProgressSnapshot {
  const _DesktopProgressSnapshot({
    required this.activeIndex,
    required this.activeProgressMap,
  });

  final int activeIndex;
  final _DesktopActiveProgressMap activeProgressMap;
}

typedef _ResolvedSlotWindow = DesktopLyricsSlotWindow<(int, LyricsLine)>;

extension on _ResolvedSlotWindow {
  int get origIndex => entry.$1;

  LyricsLine get origLine => entry.$2;
}

class _ResolvedDisplayLine {
  const _ResolvedDisplayLine({
    required this.text,
    required this.words,
    this.rubies,
  });

  final String text;
  final List<DesktopRenderWordPlan> words;
  final List<RubySpan>? rubies;
}
