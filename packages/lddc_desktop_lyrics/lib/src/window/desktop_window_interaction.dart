import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 播放器无关的桌面歌词控制动作。
enum DesktopPlaybackControlTask {
  play('play'),
  pause('pause'),
  stop('stop'),
  previous('prev'),
  next('next');

  const DesktopPlaybackControlTask(this.value);

  final String value;

  static DesktopPlaybackControlTask? tryParse(Object? value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final DesktopPlaybackControlTask task in values) {
      if (task.value == normalized || task.name == normalized) {
        return task;
      }
    }
    return null;
  }
}

/// 浮窗显隐模式。
///
/// 语义对齐Python版：
/// - `auto`：按歌词/静态文本自动显示；
/// - `forcedHidden`：用户手动隐藏后保持隐藏；
/// - `forcedVisible`：用户手动显示后保持显示。
enum DesktopFloatingVisibilityMode {
  auto('auto'),
  forcedHidden('forced_hidden'),
  forcedVisible('forced_visible');

  const DesktopFloatingVisibilityMode(this.value);

  final String value;

  static DesktopFloatingVisibilityMode fromValue(Object? value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final DesktopFloatingVisibilityMode mode
        in DesktopFloatingVisibilityMode.values) {
      if (mode.value == normalized || mode.name.toLowerCase() == normalized) {
        return mode;
      }
    }
    return DesktopFloatingVisibilityMode.auto;
  }
}

/// 桌面窗口动作类型。
enum DesktopWindowActionType {
  openSelector('open_selector'),
  toggleInstrumental('toggle_instrumental'),
  toggleAutoSearchDisabled('toggle_auto_search_disabled'),
  unlinkLyrics('unlink_lyrics'),
  toggleClickThrough('toggle_click_through'),
  toggleFloatingVisibility('toggle_floating_visibility'),
  showMainWindow('show_main_window'),
  openAssociationManager('open_association_manager'),
  controlCommand('control_command');

  const DesktopWindowActionType(this.value);

  final String value;

  static DesktopWindowActionType? tryParse(Object? value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final DesktopWindowActionType action
        in DesktopWindowActionType.values) {
      if (action.value == normalized ||
          action.name.toLowerCase() == normalized) {
        return action;
      }
    }
    return null;
  }
}

/// 浮窗/面板共用动作能力快照。
class DesktopWindowActionSnapshot {
  factory DesktopWindowActionSnapshot({
    bool isInstrumental = false,
    bool isAutoSearchDisabled = false,
    bool canUnlinkLyrics = false,
    bool canOpenSelector = true,
    bool canShowMainWindow = true,
    bool canOpenAssociationManager = true,
    Set<DesktopPlaybackControlTask> availableControlTasks =
        const <DesktopPlaybackControlTask>{},
    bool clickThroughEnabled = false,
    DesktopFloatingVisibilityMode floatingVisibilityMode =
        DesktopFloatingVisibilityMode.auto,
  }) {
    return DesktopWindowActionSnapshot._(
      isInstrumental: isInstrumental,
      isAutoSearchDisabled: isAutoSearchDisabled,
      canUnlinkLyrics: canUnlinkLyrics,
      canOpenSelector: canOpenSelector,
      canShowMainWindow: canShowMainWindow,
      canOpenAssociationManager: canOpenAssociationManager,
      availableControlTasks: Set<DesktopPlaybackControlTask>.unmodifiable(
        availableControlTasks,
      ),
      clickThroughEnabled: clickThroughEnabled,
      floatingVisibilityMode: floatingVisibilityMode,
    );
  }

  const DesktopWindowActionSnapshot.empty()
    : isInstrumental = false,
      isAutoSearchDisabled = false,
      canUnlinkLyrics = false,
      canOpenSelector = true,
      canShowMainWindow = true,
      canOpenAssociationManager = true,
      availableControlTasks = const <DesktopPlaybackControlTask>{},
      clickThroughEnabled = false,
      floatingVisibilityMode = DesktopFloatingVisibilityMode.auto;

  const DesktopWindowActionSnapshot._({
    required this.isInstrumental,
    required this.isAutoSearchDisabled,
    required this.canUnlinkLyrics,
    required this.canOpenSelector,
    required this.canShowMainWindow,
    required this.canOpenAssociationManager,
    required this.availableControlTasks,
    required this.clickThroughEnabled,
    required this.floatingVisibilityMode,
  });

  final bool isInstrumental;
  final bool isAutoSearchDisabled;
  final bool canUnlinkLyrics;
  final bool canOpenSelector;
  final bool canShowMainWindow;
  final bool canOpenAssociationManager;
  final Set<DesktopPlaybackControlTask> availableControlTasks;
  final bool clickThroughEnabled;
  final DesktopFloatingVisibilityMode floatingVisibilityMode;

  bool supportsControlTask(DesktopPlaybackControlTask task) {
    return availableControlTasks.contains(task);
  }
}

/// 浮窗控制栏信息标签。
class DesktopLyricsInfoBadgeSnapshot {
  const DesktopLyricsInfoBadgeSnapshot({
    this.source,
    this.lyricsType,
    this.isInstrumental = false,
  });

  final Source? source;
  final LyricsType? lyricsType;
  final bool isInstrumental;
}

/// 面板回传给主机的动作意图。
class DesktopPanelActionIntent extends DesktopPanelWindowIntent {
  const DesktopPanelActionIntent({
    required super.instanceId,
    required super.panelId,
    required this.action,
    this.controlTask,
  });

  final DesktopWindowActionType action;
  final DesktopPlaybackControlTask? controlTask;
}

/// 面板动作意图基类。
sealed class DesktopPanelWindowIntent {
  const DesktopPanelWindowIntent({
    required this.instanceId,
    required this.panelId,
  });

  final int instanceId;
  final int panelId;
}
