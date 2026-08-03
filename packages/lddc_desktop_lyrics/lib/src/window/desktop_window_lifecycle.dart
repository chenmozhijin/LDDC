import 'dart:async';

import '../logging/desktop_lyrics_logger.dart';

import '../models/desktop_style_models.dart';
import 'desktop_window_launch.dart';

enum DesktopWindowObservedState {
  creating,
  ready,
  visible,
  hiding,
  closing,
  closed,
  unreachable,
}

enum DesktopWindowDesiredState { absent, hidden, visible }

class DesktopWindowRef {
  const DesktopWindowRef({
    required this.role,
    required this.generation,
    this.instanceId,
    this.panelId,
  });

  final DesktopWindowRole role;
  final int? instanceId;
  final int? panelId;
  final int generation;

  String get key => switch (role) {
    DesktopWindowRole.main => 'main',
    DesktopWindowRole.floating => 'floating/${instanceId ?? '-'}',
    DesktopWindowRole.selector => 'selector/${instanceId ?? '-'}',
    DesktopWindowRole.panel => 'panel/${instanceId ?? '-'}/${panelId ?? '-'}',
  };

  String get generationKey => '$key#$generation';

  DesktopWindowLaunchArguments toLaunchArguments({
    required String? hostWindowId,
    WindowRect? initialWindowRect,
  }) {
    return DesktopWindowLaunchArguments(
      role: role,
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: hostWindowId,
      generation: generation,
      initialWindowRect: initialWindowRect,
    );
  }
}

class DesktopWindowLifecycleSnapshot {
  const DesktopWindowLifecycleSnapshot({
    required this.ref,
    required this.observedState,
    required this.desiredState,
    this.windowId,
  });

  final DesktopWindowRef ref;
  final DesktopWindowObservedState observedState;
  final DesktopWindowDesiredState desiredState;
  final String? windowId;

  bool get isReachable => !<DesktopWindowObservedState>{
    DesktopWindowObservedState.closing,
    DesktopWindowObservedState.closed,
    DesktopWindowObservedState.unreachable,
  }.contains(observedState);

  bool get isVisible =>
      observedState == DesktopWindowObservedState.visible ||
      desiredState == DesktopWindowDesiredState.visible;

  DesktopWindowLifecycleSnapshot copyWith({
    DesktopWindowObservedState? observedState,
    DesktopWindowDesiredState? desiredState,
    Object? windowId = _windowIdSentinel,
  }) {
    return DesktopWindowLifecycleSnapshot(
      ref: ref,
      observedState: observedState ?? this.observedState,
      desiredState: desiredState ?? this.desiredState,
      windowId: identical(windowId, _windowIdSentinel)
          ? this.windowId
          : windowId as String?,
    );
  }
}

class DesktopWindowLifecycleEvent {
  const DesktopWindowLifecycleEvent({
    required this.snapshot,
    required this.previousSnapshot,
    this.reason,
  });

  final DesktopWindowLifecycleSnapshot snapshot;
  final DesktopWindowLifecycleSnapshot? previousSnapshot;
  final String? reason;
}

abstract interface class DesktopWindowLifecycleRegistry {
  Stream<DesktopWindowLifecycleEvent> get events;

  DesktopWindowRef ensureMainWindow();

  DesktopWindowRef registerWindow({
    required DesktopWindowRole role,
    int? instanceId,
    int? panelId,
    String? windowId,
    DesktopWindowObservedState observedState,
    DesktopWindowDesiredState desiredState,
  });

  DesktopWindowRef? currentRef({
    required DesktopWindowRole role,
    int? instanceId,
    int? panelId,
  });

  DesktopWindowLifecycleSnapshot? snapshotForRef(DesktopWindowRef ref);

  DesktopWindowLifecycleSnapshot? snapshotForWindowId(String windowId);

  void attachWindowId(DesktopWindowRef ref, String windowId, {String? reason});

  void setDesired(
    DesktopWindowRef ref,
    DesktopWindowDesiredState desiredState, {
    String? reason,
  });

  void markCommandIssued(
    DesktopWindowRef ref, {
    DesktopWindowDesiredState? desiredState,
    DesktopWindowObservedState? observedState,
    String? reason,
  });

  void upsertObserved(
    DesktopWindowRef ref,
    DesktopWindowObservedState observedState, {
    String? windowId,
    String? reason,
  });

  void markClosed(DesktopWindowRef ref, {String? reason});

  void markUnreachable(DesktopWindowRef ref, {String? reason});

  bool isWindowIdReachable(String windowId);

  bool isMainWindowReachable();

  bool hasVisibleWindow({DesktopWindowRef? excludeRef});

  Future<bool> awaitObservedClose(
    DesktopWindowRef ref, {
    Duration timeout = const Duration(seconds: 2),
  });

  /// 释放事件流、等待者和所有窗口索引；可安全重复调用。
  Future<void> dispose();

  void debugResetForTests();
}

class DesktopWindowLifecycleRegistryController
    implements DesktopWindowLifecycleRegistry {
  DesktopWindowLifecycleRegistryController({
    DesktopLyricsLogger logger = const DesktopLyricsLogger(),
  }) : _logger = logger.child('window-lifecycle');

  static final DesktopWindowLifecycleRegistryController instance =
      DesktopWindowLifecycleRegistryController();

  final DesktopLyricsLogger _logger;

  final StreamController<DesktopWindowLifecycleEvent> _eventsController =
      StreamController<DesktopWindowLifecycleEvent>.broadcast(sync: true);
  final Map<String, DesktopWindowLifecycleSnapshot> _snapshots =
      <String, DesktopWindowLifecycleSnapshot>{};
  final Map<String, String> _windowIdToRefKey = <String, String>{};
  final Map<String, int> _nextGenerations = <String, int>{};
  final Map<String, List<Completer<void>>> _closeWaiters =
      <String, List<Completer<void>>>{};
  bool _disposed = false;

  @override
  Stream<DesktopWindowLifecycleEvent> get events => _eventsController.stream;

  @override
  DesktopWindowRef ensureMainWindow() {
    final DesktopWindowRef? current = currentRef(role: DesktopWindowRole.main);
    final DesktopWindowLifecycleSnapshot? snapshot = current == null
        ? null
        : snapshotForRef(current);
    if (snapshot != null &&
        snapshot.observedState != DesktopWindowObservedState.closed &&
        snapshot.observedState != DesktopWindowObservedState.unreachable) {
      return current!;
    }
    return registerWindow(
      role: DesktopWindowRole.main,
      observedState: DesktopWindowObservedState.ready,
      desiredState: DesktopWindowDesiredState.visible,
    );
  }

  @override
  DesktopWindowRef registerWindow({
    required DesktopWindowRole role,
    int? instanceId,
    int? panelId,
    String? windowId,
    DesktopWindowObservedState observedState =
        DesktopWindowObservedState.creating,
    DesktopWindowDesiredState desiredState = DesktopWindowDesiredState.hidden,
  }) {
    final DesktopWindowRef probe = DesktopWindowRef(
      role: role,
      instanceId: instanceId,
      panelId: panelId,
      generation: 0,
    );
    final int generation = (_nextGenerations[probe.key] ?? 0) + 1;
    _nextGenerations[probe.key] = generation;
    final DesktopWindowRef ref = DesktopWindowRef(
      role: role,
      instanceId: instanceId,
      panelId: panelId,
      generation: generation,
    );
    final DesktopWindowLifecycleSnapshot snapshot =
        DesktopWindowLifecycleSnapshot(
          ref: ref,
          observedState: observedState,
          desiredState: desiredState,
          windowId: windowId,
        );
    _replaceSnapshot(snapshot, reason: 'register');
    return ref;
  }

  @override
  DesktopWindowRef? currentRef({
    required DesktopWindowRole role,
    int? instanceId,
    int? panelId,
  }) {
    final DesktopWindowRef probe = DesktopWindowRef(
      role: role,
      instanceId: instanceId,
      panelId: panelId,
      generation: 0,
    );
    final DesktopWindowLifecycleSnapshot? snapshot = _snapshots.values
        .where((DesktopWindowLifecycleSnapshot candidate) {
          return candidate.ref.key == probe.key;
        })
        .fold<DesktopWindowLifecycleSnapshot?>(null, (
          DesktopWindowLifecycleSnapshot? current,
          DesktopWindowLifecycleSnapshot candidate,
        ) {
          if (current == null) {
            return candidate;
          }
          return current.ref.generation > candidate.ref.generation
              ? current
              : candidate;
        });
    return snapshot?.ref;
  }

  @override
  DesktopWindowLifecycleSnapshot? snapshotForRef(DesktopWindowRef ref) {
    return _snapshots[ref.generationKey];
  }

  @override
  DesktopWindowLifecycleSnapshot? snapshotForWindowId(String windowId) {
    final String? refKey = _windowIdToRefKey[windowId];
    if (refKey == null) {
      return null;
    }
    return _snapshots[refKey];
  }

  @override
  void attachWindowId(DesktopWindowRef ref, String windowId, {String? reason}) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(
      ref,
    ).copyWith(windowId: windowId);
    _replaceSnapshot(snapshot, reason: reason ?? 'attach-window-id');
  }

  @override
  void setDesired(
    DesktopWindowRef ref,
    DesktopWindowDesiredState desiredState, {
    String? reason,
  }) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(
      ref,
    ).copyWith(desiredState: desiredState);
    _replaceSnapshot(snapshot, reason: reason ?? 'set-desired');
  }

  @override
  void markCommandIssued(
    DesktopWindowRef ref, {
    DesktopWindowDesiredState? desiredState,
    DesktopWindowObservedState? observedState,
    String? reason,
  }) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(
      ref,
    ).copyWith(desiredState: desiredState, observedState: observedState);
    _replaceSnapshot(snapshot, reason: reason ?? 'command-issued');
  }

  @override
  void upsertObserved(
    DesktopWindowRef ref,
    DesktopWindowObservedState observedState, {
    String? windowId,
    String? reason,
  }) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(
      ref,
    ).copyWith(observedState: observedState, windowId: windowId);
    _replaceSnapshot(snapshot, reason: reason ?? 'upsert-observed');
  }

  @override
  void markClosed(DesktopWindowRef ref, {String? reason}) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(ref)
        .copyWith(
          observedState: DesktopWindowObservedState.closed,
          desiredState: DesktopWindowDesiredState.absent,
        );
    _replaceSnapshot(snapshot, reason: reason ?? 'closed');
    _discardTerminalSnapshot(ref);
  }

  @override
  void markUnreachable(DesktopWindowRef ref, {String? reason}) {
    final DesktopWindowLifecycleSnapshot snapshot = _ensureSnapshot(ref)
        .copyWith(
          observedState: DesktopWindowObservedState.unreachable,
          desiredState: DesktopWindowDesiredState.absent,
        );
    _replaceSnapshot(snapshot, reason: reason ?? 'unreachable');
    _discardTerminalSnapshot(ref);
  }

  @override
  bool isWindowIdReachable(String windowId) {
    final DesktopWindowLifecycleSnapshot? snapshot = snapshotForWindowId(
      windowId,
    );
    return snapshot?.isReachable ?? false;
  }

  @override
  bool isMainWindowReachable() {
    final DesktopWindowRef? ref = currentRef(role: DesktopWindowRole.main);
    final DesktopWindowLifecycleSnapshot? snapshot = ref == null
        ? null
        : snapshotForRef(ref);
    return snapshot?.isReachable ?? false;
  }

  @override
  bool hasVisibleWindow({DesktopWindowRef? excludeRef}) {
    for (final DesktopWindowLifecycleSnapshot snapshot in _snapshots.values) {
      if (excludeRef != null &&
          snapshot.ref.generationKey == excludeRef.generationKey) {
        continue;
      }
      if (snapshot.isVisible && snapshot.isReachable) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> awaitObservedClose(
    DesktopWindowRef ref, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final DesktopWindowLifecycleSnapshot? snapshot = snapshotForRef(ref);
    if (snapshot == null ||
        snapshot.observedState == DesktopWindowObservedState.closed ||
        snapshot.observedState == DesktopWindowObservedState.unreachable) {
      return true;
    }
    final Completer<void> completer = Completer<void>();
    final List<Completer<void>> waiters = _closeWaiters[ref.generationKey] ??=
        <Completer<void>>[];
    waiters.add(completer);
    try {
      await completer.future.timeout(timeout);
      return true;
    } on TimeoutException {
      waiters.remove(completer);
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    debugResetForTests();
    await _eventsController.close();
  }

  @override
  void debugResetForTests() {
    _snapshots.clear();
    _windowIdToRefKey.clear();
    _nextGenerations.clear();
    for (final List<Completer<void>> waiters in _closeWaiters.values) {
      for (final Completer<void> waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
    }
    _closeWaiters.clear();
  }

  DesktopWindowLifecycleSnapshot _ensureSnapshot(DesktopWindowRef ref) {
    return _snapshots[ref.generationKey] ??
        DesktopWindowLifecycleSnapshot(
          ref: ref,
          observedState: DesktopWindowObservedState.creating,
          desiredState: DesktopWindowDesiredState.hidden,
        );
  }

  void _replaceSnapshot(
    DesktopWindowLifecycleSnapshot snapshot, {
    String? reason,
  }) {
    if (_disposed) {
      throw StateError('桌面窗口生命周期注册表已经释放');
    }
    final DesktopWindowLifecycleSnapshot? previous =
        _snapshots[snapshot.ref.generationKey];
    _snapshots[snapshot.ref.generationKey] = snapshot;
    final String? previousWindowId = previous?.windowId;
    if (previousWindowId != null && previousWindowId != snapshot.windowId) {
      _windowIdToRefKey.remove(previousWindowId);
    }
    final String? windowId = snapshot.windowId;
    if (windowId != null && windowId.isNotEmpty) {
      _windowIdToRefKey[windowId] = snapshot.ref.generationKey;
    }
    if (previous?.observedState == snapshot.observedState &&
        previous?.desiredState == snapshot.desiredState &&
        previous?.windowId == snapshot.windowId) {
      return;
    }
    _logger.info(
      'lifecycle role=${snapshot.ref.role.name}'
      ' instance=${snapshot.ref.instanceId ?? '-'}'
      ' panel=${snapshot.ref.panelId ?? '-'}'
      ' generation=${snapshot.ref.generation}'
      ' observed=${snapshot.observedState.name}'
      ' desired=${snapshot.desiredState.name}'
      ' windowId=${snapshot.windowId ?? '-'}'
      ' reason=${reason ?? '-'}',
    );
    if (!_eventsController.isClosed) {
      _eventsController.add(
        DesktopWindowLifecycleEvent(
          snapshot: snapshot,
          previousSnapshot: previous,
          reason: reason,
        ),
      );
    }
    if (snapshot.observedState == DesktopWindowObservedState.closed ||
        snapshot.observedState == DesktopWindowObservedState.unreachable) {
      _completeCloseWaiters(snapshot.ref);
    }
  }

  void _completeCloseWaiters(DesktopWindowRef ref) {
    final List<Completer<void>> waiters =
        _closeWaiters.remove(ref.generationKey) ?? <Completer<void>>[];
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  void _discardTerminalSnapshot(DesktopWindowRef ref) {
    // 终态已经通过同步事件发出，后续 await 也把“找不到 snapshot”视为已关闭。
    // 立即删除历史 generation，避免频繁创建/销毁 Panel 时常驻 Map 线性增长；
    // `_nextGenerations` 仍保留单调计数，旧窗口回调不会碰撞到新 generation。
    final DesktopWindowLifecycleSnapshot? removed = _snapshots.remove(
      ref.generationKey,
    );
    final String? windowId = removed?.windowId;
    if (windowId != null && _windowIdToRefKey[windowId] == ref.generationKey) {
      _windowIdToRefKey.remove(windowId);
    }
  }
}

const Object _windowIdSentinel = Object();
