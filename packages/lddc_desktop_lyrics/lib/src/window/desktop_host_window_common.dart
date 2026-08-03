import 'dart:async';

import '../logging/desktop_lyrics_logger.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_scene.dart';
import 'desktop_multi_window_port.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_lifecycle.dart';

Future<String> resolveDesktopHostWindowId({
  required String? cachedHostWindowId,
  required DesktopWindowLifecycleRegistry lifecycleRegistry,
  required DesktopMultiWindowPort multiWindowPort,
  required String attachReason,
}) async {
  if (cachedHostWindowId != null &&
      lifecycleRegistry.isWindowIdReachable(cachedHostWindowId)) {
    return cachedHostWindowId;
  }
  final DesktopRemoteWindowPort currentWindow = await multiWindowPort
      .currentWindow();
  final String resolvedHostWindowId = currentWindow.windowId;
  final DesktopWindowRef ref = lifecycleRegistry.ensureMainWindow();
  lifecycleRegistry.attachWindowId(
    ref,
    resolvedHostWindowId,
    reason: attachReason,
  );
  return resolvedHostWindowId;
}

Future<T> retryDesktopWindowChannel<T>(
  Future<T> Function() action, {
  required int instanceId,
  required String operation,
  required Duration retryDelay,
  required int retryLimit,
  required Duration operationTimeout,
  bool Function()? shouldRetry,
  DesktopLyricsLogger logger = const DesktopLyricsLogger(),
}) async {
  final DesktopLyricsLogger channelLogger = logger.child('window-channel');
  Object? lastError;
  StackTrace? lastStackTrace;
  for (int attempt = 1; attempt <= retryLimit; attempt += 1) {
    try {
      return await action().timeout(operationTimeout);
    } on Object catch (error, stackTrace) {
      final bool channelUnavailable = isDesktopWindowChannelUnregistered(error);
      final bool canRetry =
          channelUnavailable &&
          attempt < retryLimit &&
          (shouldRetry?.call() ?? true);
      channelLogger.info(
        'operation failed instance=$instanceId operation=$operation'
        ' attempt=$attempt/$retryLimit error=$error'
        ' retry=$canRetry',
      );
      if (!canRetry) {
        rethrow;
      }
      lastError = error;
      lastStackTrace = stackTrace;
      await Future<void>.delayed(retryDelay);
    }
  }
  Error.throwWithStackTrace(
    StateError(
      '桌面子窗口 channel 在重试后仍未就绪: instance=$instanceId '
      'operation=$operation error=$lastError',
    ),
    lastStackTrace!,
  );
}

class DesktopSelectorWindowEntry {
  const DesktopSelectorWindowEntry({
    required this.window,
    required this.ref,
    this.visible = false,
  });

  final DesktopRemoteWindowPort window;
  final DesktopWindowRef ref;
  final bool visible;

  DesktopSelectorWindowEntry copyWith({
    DesktopRemoteWindowPort? window,
    DesktopWindowRef? ref,
    bool? visible,
  }) {
    return DesktopSelectorWindowEntry(
      window: window ?? this.window,
      ref: ref ?? this.ref,
      visible: visible ?? this.visible,
    );
  }
}

class DesktopFloatingWindowSyncState {
  DesktopFloatingSessionSnapshot? lastSession;
  DesktopSceneRef? lastSceneRef;
  DesktopFloatingAnchorSnapshot? lastAnchor;
  DesktopFloatingWindowFlags? lastFlags;
  int contentRevision = 0;
  int flagsRevision = 0;
}

class DesktopFloatingWindowEntry {
  const DesktopFloatingWindowEntry({required this.window, required this.ref});

  final DesktopRemoteWindowPort window;
  final DesktopWindowRef ref;
}

bool desktopFloatingSessionEquals(
  DesktopFloatingSessionSnapshot? left,
  DesktopFloatingSessionSnapshot right,
) {
  if (left == null) {
    return false;
  }
  return left.songId == right.songId &&
      left.songTitle == right.songTitle &&
      left.artistText == right.artistText &&
      desktopStringListEquals(left.enabledLangs, right.enabledLangs) &&
      desktopRgbColorListEquals(left.playedColors, right.playedColors) &&
      desktopRgbColorListEquals(left.unplayedColors, right.unplayedColors) &&
      left.fontFamily == right.fontFamily &&
      left.fontSize == right.fontSize &&
      left.showFurigana == right.showFurigana &&
      left.isInstrumental == right.isInstrumental &&
      left.hasStaticDisplay == right.hasStaticDisplay &&
      left.refreshRate == right.refreshRate &&
      desktopWindowActionEquals(left.actions, right.actions) &&
      desktopInfoBadgeEquals(left.infoBadge, right.infoBadge);
}

bool desktopFloatingAnchorEquals(
  DesktopFloatingAnchorSnapshot? left,
  DesktopFloatingAnchorSnapshot right,
) {
  if (left == null) {
    return false;
  }
  return left.pluginPlaybackTimeMs == right.pluginPlaybackTimeMs &&
      left.pluginSendTimeMs == right.pluginSendTimeMs &&
      left.hostReceivedAtMs == right.hostReceivedAtMs &&
      left.isPlaying == right.isPlaying &&
      left.syncRevision == right.syncRevision &&
      left.eventKind == right.eventKind &&
      left.sceneId == right.sceneId &&
      left.songToken == right.songToken;
}

bool desktopFloatingFlagsEquals(
  DesktopFloatingWindowFlags? left,
  DesktopFloatingWindowFlags right,
) {
  if (left == null) {
    return false;
  }
  return left.visible == right.visible &&
      left.alwaysOnTop == right.alwaysOnTop &&
      left.clickThrough == right.clickThrough &&
      left.frameless == right.frameless &&
      left.opacity == right.opacity;
}

bool desktopWindowActionEquals(
  DesktopWindowActionSnapshot left,
  DesktopWindowActionSnapshot right,
) {
  return left.isInstrumental == right.isInstrumental &&
      left.isAutoSearchDisabled == right.isAutoSearchDisabled &&
      left.canUnlinkLyrics == right.canUnlinkLyrics &&
      left.canOpenSelector == right.canOpenSelector &&
      left.canShowMainWindow == right.canShowMainWindow &&
      left.canOpenAssociationManager == right.canOpenAssociationManager &&
      left.clickThroughEnabled == right.clickThroughEnabled &&
      left.floatingVisibilityMode == right.floatingVisibilityMode &&
      left.availableControlTasks.length == right.availableControlTasks.length &&
      left.availableControlTasks.containsAll(right.availableControlTasks);
}

bool desktopInfoBadgeEquals(
  DesktopLyricsInfoBadgeSnapshot left,
  DesktopLyricsInfoBadgeSnapshot right,
) {
  return left.source == right.source &&
      left.lyricsType == right.lyricsType &&
      left.isInstrumental == right.isInstrumental;
}

bool desktopStringListEquals(List<String> left, List<String> right) {
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

bool desktopRgbColorListEquals(List<RgbColor> left, List<RgbColor> right) {
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index += 1) {
    if (left[index].r != right[index].r ||
        left[index].g != right[index].g ||
        left[index].b != right[index].b) {
      return false;
    }
  }
  return true;
}

bool desktopWindowRectEquals(WindowRect? left, WindowRect? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.left == right.left &&
      left.top == right.top &&
      left.width == right.width &&
      left.height == right.height;
}
