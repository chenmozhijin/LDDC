import 'dart:async';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../core/logging/logging.dart';
import 'desktop_session_state.dart';
import 'desktop_tray_port.dart';
import 'desktop_window_action_builder.dart';

final AppLogger _trayControllerLogger = AppLogger.scope('tray-controller');

typedef DesktopTrayActionRunner =
    Future<bool> Function({
      required int instanceId,
      required DesktopWindowActionType action,
      DesktopPlaybackControlTask? controlTask,
    });

typedef DesktopTrayExitHandler = Future<void> Function();

/// 托盘菜单的本地化文案快照。
///
/// controller 只负责菜单状态和动作分发，不读取 Flutter `BuildContext`。主窗口在
/// 本地化边界构造这份记录，并在 locale 变化时调用 [updateLabels] 刷新现有菜单。
typedef DesktopTrayLabels = ({
  String showMainWindow,
  String currentTarget,
  String noSelection,
  String targetInstance,
  String instance,
  String selectLyrics,
  String markInstrumental,
  String disableAutoSearch,
  String unlinkLyrics,
  String clickThrough,
  String toggleFloating,
  String associationManager,
  String exit,
});

final class DesktopTrayController {
  DesktopTrayController({
    required DesktopTrayPortFactory trayPortFactory,
    required Stream<Map<int, DesktopSessionState>> sessionSnapshots,
    required DesktopTrayActionRunner runWindowAction,
    required DesktopTrayExitHandler exitApplication,
    required String iconAsset,
    required DesktopTrayLabels labels,
    this.toolTip = 'LDDC',
  }) : _trayPortFactory = trayPortFactory,
       _sessionSnapshots = sessionSnapshots,
       _runWindowAction = runWindowAction,
       _exitApplication = exitApplication,
       _iconAsset = iconAsset,
       _labels = labels;

  static const String menuKeyShowMainWindow = 'show_main_window';
  static const String menuKeySelectLyrics = 'open_selector';
  static const String menuKeyToggleInstrumental = 'toggle_instrumental';
  static const String menuKeyToggleAutoSearchDisabled =
      'toggle_auto_search_disabled';
  static const String menuKeyUnlinkLyrics = 'unlink_lyrics';
  static const String menuKeyToggleClickThrough = 'toggle_click_through';
  static const String menuKeyToggleFloatingVisibility =
      'toggle_floating_visibility';
  static const String menuKeyOpenAssociationManager =
      'open_association_manager';
  static const String menuKeyCurrentTarget = 'current_target';
  static const String menuKeyExitApp = 'exit_app';
  static const String menuKeyInstanceSwitcher = 'instance_switcher';
  static const String _instanceKeyPrefix = 'instance:';

  final DesktopTrayPortFactory _trayPortFactory;
  final Stream<Map<int, DesktopSessionState>> _sessionSnapshots;
  final DesktopTrayActionRunner _runWindowAction;
  final DesktopTrayExitHandler _exitApplication;
  final String _iconAsset;
  final String toolTip;
  DesktopTrayLabels _labels;

  StreamSubscription<Map<int, DesktopSessionState>>? _subscription;
  DesktopTrayPort? _trayPort;
  Map<int, DesktopSessionState> _sessions = const <int, DesktopSessionState>{};
  List<DesktopTrayMenuEntry> _menuEntries = const <DesktopTrayMenuEntry>[];
  int? _selectedInstanceId;
  bool _manualSelectionLocked = false;
  bool _initialized = false;
  bool _menuPopupInFlight = false;
  bool _contextMenuTaskQueued = false;
  bool _disposed = false;
  Future<void>? _initializeFuture;
  Future<void>? _disposeFuture;
  Future<void> _trayTaskQueue = Future<void>.value();

  int? get selectedInstanceId => _selectedInstanceId;

  List<DesktopTrayMenuEntry> get menuEntries => _menuEntries;

  Future<void> initialize({
    Map<int, DesktopSessionState> initialSessions =
        const <int, DesktopSessionState>{},
  }) {
    if (_disposed) {
      return Future<void>.error(StateError('tray controller 已释放'));
    }
    return _initializeFuture ??= _initialize(initialSessions);
  }

  Future<void> _initialize(
    Map<int, DesktopSessionState> initialSessions,
  ) async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _runTrayTask(() => _applySessionSnapshot(initialSessions));
    if (_disposed) {
      return;
    }
    _subscription = _sessionSnapshots.listen((
      Map<int, DesktopSessionState> snapshot,
    ) {
      unawaited(_runTrayTask(() => _applySessionSnapshot(snapshot)));
    });
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> updateLabels(DesktopTrayLabels labels) {
    if (_disposed || _labels == labels) {
      return Future<void>.value();
    }
    _labels = labels;
    return _runTrayTask(() => _applySessionSnapshot(_sessions));
  }

  Future<void> _dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _initializeFuture;
    await _trayTaskQueue;
    await _disposeTrayPort();
  }

  Future<void> _runTrayTask(Future<void> Function() task) {
    final Future<void> previous = _trayTaskQueue;
    final Future<void> next = previous.then(
      (_) async {
        if (_disposed) {
          return;
        }
        try {
          await task();
        } on Object catch (error, stackTrace) {
          _trayControllerLogger.error(
            'tray task failed error=$error stack=$stackTrace',
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) async {
        _trayControllerLogger.error(
          'previous tray task failed error=$error stack=$stackTrace',
        );
        if (_disposed) {
          return;
        }
        try {
          await task();
        } on Object catch (nextError, nextStackTrace) {
          _trayControllerLogger.error(
            'tray task failed error=$nextError stack=$nextStackTrace',
          );
        }
      },
    );
    _trayTaskQueue = next;
    return next;
  }

  Future<void> _applySessionSnapshot(
    Map<int, DesktopSessionState> snapshot,
  ) async {
    if (_disposed) {
      return;
    }
    _sessions = Map<int, DesktopSessionState>.unmodifiable(
      Map<int, DesktopSessionState>.from(snapshot),
    );
    _syncSelectedInstance(nextSessions: _sessions);
    if (_sessions.isEmpty) {
      _menuEntries = const <DesktopTrayMenuEntry>[];
      await _disposeTrayPort();
      return;
    }
    _menuEntries = _buildMenuEntries();
    final DesktopTrayPort trayPort = await _ensureTrayPortInitialized();
    if (_disposed || !identical(trayPort, _trayPort)) {
      return;
    }
    await trayPort.updateMenu(_menuEntries);
  }

  void _syncSelectedInstance({
    required Map<int, DesktopSessionState> nextSessions,
  }) {
    if (nextSessions.isEmpty) {
      _selectedInstanceId = null;
      _manualSelectionLocked = false;
      return;
    }
    if (nextSessions.length == 1) {
      _selectedInstanceId = nextSessions.keys.single;
      _manualSelectionLocked = false;
      return;
    }
    if (_selectedInstanceId != null &&
        nextSessions.containsKey(_selectedInstanceId)) {
      if (_manualSelectionLocked) {
        return;
      }
    } else {
      _manualSelectionLocked = false;
    }
    _selectedInstanceId ??= nextSessions.keys.first;
    if (!nextSessions.containsKey(_selectedInstanceId)) {
      _selectedInstanceId = nextSessions.keys.first;
    }
  }

  List<DesktopTrayMenuEntry> _buildMenuEntries() {
    final DesktopSessionState? selectedState = _selectedState;
    final DesktopWindowActionSnapshot actions = selectedState == null
        ? DesktopWindowActionSnapshot(
            canOpenSelector: false,
            canUnlinkLyrics: false,
          )
        : buildDesktopWindowActionSnapshot(selectedState);
    return <DesktopTrayMenuEntry>[
      DesktopTrayMenuEntry.action(
        key: menuKeyShowMainWindow,
        label: _labels.showMainWindow,
      ),
      if (_sessions.length > 1) ...<DesktopTrayMenuEntry>[
        DesktopTrayMenuEntry.action(
          key: menuKeyCurrentTarget,
          label:
              '${_labels.currentTarget}${_selectedState == null ? _labels.noSelection : _buildInstanceLabel(_selectedInstanceId!, _selectedState!)}',
          enabled: false,
        ),
        DesktopTrayMenuEntry.submenu(
          key: menuKeyInstanceSwitcher,
          label: _labels.targetInstance,
          children: _buildInstanceEntries(),
        ),
      ],
      const DesktopTrayMenuEntry.separator(),
      DesktopTrayMenuEntry.action(
        key: menuKeySelectLyrics,
        label: _labels.selectLyrics,
        enabled: selectedState != null && actions.canOpenSelector,
      ),
      DesktopTrayMenuEntry.checkbox(
        key: menuKeyToggleInstrumental,
        label: _labels.markInstrumental,
        checked: actions.isInstrumental,
        enabled: selectedState != null,
      ),
      DesktopTrayMenuEntry.checkbox(
        key: menuKeyToggleAutoSearchDisabled,
        label: _labels.disableAutoSearch,
        checked: actions.isAutoSearchDisabled,
        enabled: selectedState != null,
      ),
      DesktopTrayMenuEntry.action(
        key: menuKeyUnlinkLyrics,
        label: _labels.unlinkLyrics,
        enabled: selectedState != null && actions.canUnlinkLyrics,
      ),
      DesktopTrayMenuEntry.checkbox(
        key: menuKeyToggleClickThrough,
        label: _labels.clickThrough,
        checked: actions.clickThroughEnabled,
        enabled: selectedState != null,
      ),
      DesktopTrayMenuEntry.action(
        key: menuKeyToggleFloatingVisibility,
        label: _labels.toggleFloating,
        enabled: selectedState != null,
      ),
      DesktopTrayMenuEntry.action(
        key: menuKeyOpenAssociationManager,
        label: _labels.associationManager,
      ),
      const DesktopTrayMenuEntry.separator(),
      DesktopTrayMenuEntry.action(key: menuKeyExitApp, label: _labels.exit),
    ];
  }

  List<DesktopTrayMenuEntry> _buildInstanceEntries() {
    final List<MapEntry<int, DesktopSessionState>> entries =
        _sessions.entries.toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));
    return entries
        .map(
          (MapEntry<int, DesktopSessionState> entry) =>
              DesktopTrayMenuEntry.checkbox(
                key: '$_instanceKeyPrefix${entry.key}',
                label: _buildInstanceLabel(entry.key, entry.value),
                checked: entry.key == _selectedInstanceId,
                enabled: true,
              ),
        )
        .toList(growable: false);
  }

  String _buildInstanceLabel(int instanceId, DesktopSessionState state) {
    final String artist = state.lyricsRuntime.song?.artistText.trim() ?? '';
    final String title = (state.lyricsRuntime.song?.title ?? '').trim();
    final String summary;
    if (artist.isEmpty && title.isEmpty) {
      summary = '${_labels.instance} $instanceId';
    } else if (artist.isEmpty) {
      summary = '$instanceId: $title';
    } else if (title.isEmpty) {
      summary = '$instanceId: $artist';
    } else {
      summary = '$instanceId: $artist - $title';
    }
    return summary;
  }

  DesktopSessionState? get _selectedState {
    final int? selectedInstanceId = _selectedInstanceId;
    if (selectedInstanceId == null) {
      return null;
    }
    return _sessions[selectedInstanceId];
  }

  Future<void> _handleMenuItemSelected(String key) async {
    if (key.startsWith(_instanceKeyPrefix)) {
      final int? instanceId = int.tryParse(
        key.substring(_instanceKeyPrefix.length),
      );
      if (instanceId != null && _sessions.containsKey(instanceId)) {
        _selectedInstanceId = instanceId;
        _manualSelectionLocked = true;
        _menuEntries = _buildMenuEntries();
        final DesktopTrayPort? trayPort = _trayPort;
        if (!_disposed && trayPort != null) {
          await trayPort.updateMenu(_menuEntries);
        }
      }
      return;
    }
    if (key == menuKeyExitApp) {
      await _exitApplication();
      return;
    }
    final DesktopWindowActionType? action = _mapMenuKeyToAction(key);
    if (action == null) {
      return;
    }
    final int instanceId = _selectedInstanceId ?? -1;
    await _runWindowAction(instanceId: instanceId, action: action);
  }

  Future<void> _handlePrimaryAction() async {
    if (_sessions.isEmpty) {
      return;
    }
    if (_sessions.length == 1) {
      final int instanceId = _selectedInstanceId ?? _sessions.keys.single;
      await _runWindowAction(
        instanceId: instanceId,
        action: DesktopWindowActionType.toggleFloatingVisibility,
      );
      return;
    }
    await _showContextMenuIfNeeded();
  }

  Future<void> _handleSecondaryAction() async {
    if (_sessions.isEmpty) {
      return;
    }
    await _showContextMenuIfNeeded();
  }

  Future<void> _showContextMenuIfNeeded() async {
    final DesktopTrayPort? trayPort = _trayPort;
    if (_disposed || trayPort == null || _menuPopupInFlight) {
      return;
    }
    _menuPopupInFlight = true;
    try {
      if (_disposed || !identical(trayPort, _trayPort)) {
        return;
      }
      await trayPort.updateMenu(_menuEntries);
      if (_disposed || !identical(trayPort, _trayPort)) {
        return;
      }
      await trayPort.showContextMenu();
    } finally {
      _menuPopupInFlight = false;
    }
  }

  DesktopWindowActionType? _mapMenuKeyToAction(String key) {
    return switch (key) {
      menuKeyShowMainWindow => DesktopWindowActionType.showMainWindow,
      menuKeySelectLyrics => DesktopWindowActionType.openSelector,
      menuKeyToggleInstrumental => DesktopWindowActionType.toggleInstrumental,
      menuKeyToggleAutoSearchDisabled =>
        DesktopWindowActionType.toggleAutoSearchDisabled,
      menuKeyUnlinkLyrics => DesktopWindowActionType.unlinkLyrics,
      menuKeyToggleClickThrough => DesktopWindowActionType.toggleClickThrough,
      menuKeyToggleFloatingVisibility =>
        DesktopWindowActionType.toggleFloatingVisibility,
      menuKeyOpenAssociationManager =>
        DesktopWindowActionType.openAssociationManager,
      _ => null,
    };
  }

  Future<DesktopTrayPort> _ensureTrayPortInitialized() async {
    final DesktopTrayPort? existing = _trayPort;
    if (existing != null) {
      return existing;
    }
    if (_disposed) {
      throw StateError('tray controller 已释放，不能初始化托盘');
    }
    final DesktopTrayPort trayPort = _trayPortFactory();
    trayPort.setOnPrimaryAction(() {
      if (_sessions.length == 1) {
        unawaited(_runTrayTask(_handlePrimaryAction));
        return;
      }
      _queueContextMenuTask(_handlePrimaryAction);
    });
    trayPort.setOnSecondaryAction(() {
      _queueContextMenuTask(_handleSecondaryAction);
    });
    trayPort.setOnMenuItemSelected((String key) {
      unawaited(_runTrayTask(() => _handleMenuItemSelected(key)));
    });
    try {
      await trayPort.initialize(iconAsset: _iconAsset, toolTip: toolTip);
    } on Object {
      _detachTrayCallbacks(trayPort);
      await trayPort.dispose();
      rethrow;
    }
    if (_disposed) {
      _detachTrayCallbacks(trayPort);
      await trayPort.dispose();
      throw StateError('tray controller 已释放，托盘初始化结果已销毁');
    }
    _trayPort = trayPort;
    return trayPort;
  }

  void _queueContextMenuTask(Future<void> Function() task) {
    if (_contextMenuTaskQueued || _menuPopupInFlight) {
      return;
    }
    _contextMenuTaskQueued = true;
    unawaited(
      _runTrayTask(() async {
        try {
          await task();
        } finally {
          _contextMenuTaskQueued = false;
        }
      }),
    );
  }

  Future<void> _disposeTrayPort() async {
    final DesktopTrayPort? trayPort = _trayPort;
    _trayPort = null;
    if (trayPort == null) {
      return;
    }
    _detachTrayCallbacks(trayPort);
    await trayPort.dispose();
  }

  void _detachTrayCallbacks(DesktopTrayPort trayPort) {
    trayPort.setOnPrimaryAction(null);
    trayPort.setOnSecondaryAction(null);
    trayPort.setOnMenuItemSelected(null);
  }
}
