import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_state.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_tray_controller.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_tray_port.dart';

import '../../../support/desktop_service_test_support.dart';

void main() {
  group('DesktopTrayController', () {
    test('会按实例存在懒创建并销毁托盘，单实例时隐藏实例切换入口', () async {
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      final StreamController<Map<int, DesktopSessionState>> snapshots =
          StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
      final DesktopTrayController controller = DesktopTrayController(
        trayPortFactory: trayFactory.call,
        sessionSnapshots: snapshots.stream,
        runWindowAction:
            ({
              required int instanceId,
              required DesktopWindowActionType action,
              DesktopPlaybackControlTask? controlTask,
            }) async => true,
        exitApplication: () async {},
        iconAsset: 'assets/tray_icon.png',
        labels: _testTrayLabels,
      );
      addTearDown(() async {
        await controller.dispose();
        await snapshots.close();
      });

      await controller.initialize();
      expect(trayFactory.createdPorts, isEmpty);
      expect(controller.menuEntries, isEmpty);
      expect(controller.selectedInstanceId, isNull);

      final DesktopSessionState firstSession = _session(
        instanceId: 1,
        title: 'Song A',
      );
      snapshots.add(<int, DesktopSessionState>{1: firstSession});
      await Future<void>.delayed(Duration.zero);

      expect(trayFactory.createdPorts, hasLength(1));
      expect(trayFactory.lastPort.initializedIconAsset, 'assets/tray_icon.png');
      expect(controller.menuEntries.first.label, '显示主窗口');
      expect(controller.selectedInstanceId, 1);
      expect(_hasInstanceSwitcher(controller.menuEntries), isFalse);

      final DesktopSessionState secondSession = _session(
        instanceId: 2,
        title: 'Song B',
      );
      snapshots.add(<int, DesktopSessionState>{
        1: firstSession,
        2: secondSession,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.selectedInstanceId, 1);
      expect(_hasInstanceSwitcher(controller.menuEntries), isTrue);

      await controller.updateLabels(_englishTrayLabels);
      expect(controller.menuEntries.first.label, 'Show main window');
      expect(
        controller.menuEntries
            .singleWhere(
              (DesktopTrayMenuEntry entry) =>
                  entry.key == DesktopTrayController.menuKeyInstanceSwitcher,
            )
            .label,
        'Target instance',
      );

      final _FakeTrayPort firstPort = trayFactory.lastPort;
      snapshots.add(const <int, DesktopSessionState>{});
      await Future<void>.delayed(Duration.zero);

      expect(firstPort.disposeCalls, 1);
      expect(controller.menuEntries, isEmpty);
      expect(controller.selectedInstanceId, isNull);

      snapshots.add(<int, DesktopSessionState>{
        3: _session(instanceId: 3, title: 'Song C'),
      });
      await Future<void>.delayed(Duration.zero);

      expect(trayFactory.createdPorts, hasLength(2));
      expect(trayFactory.lastPort.initializedIconAsset, 'assets/tray_icon.png');
      expect(controller.selectedInstanceId, 3);
      expect(_hasInstanceSwitcher(controller.menuEntries), isFalse);
    });

    test('会维护手动选中实例、派发菜单动作并在实例移除后回退', () async {
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      final StreamController<Map<int, DesktopSessionState>> snapshots =
          StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
      final List<({int instanceId, DesktopWindowActionType action})> actions =
          <({int instanceId, DesktopWindowActionType action})>[];
      int exitCalls = 0;
      final DesktopTrayController controller = DesktopTrayController(
        trayPortFactory: trayFactory.call,
        sessionSnapshots: snapshots.stream,
        runWindowAction:
            ({
              required int instanceId,
              required DesktopWindowActionType action,
              DesktopPlaybackControlTask? controlTask,
            }) async {
              actions.add((instanceId: instanceId, action: action));
              return true;
            },
        exitApplication: () async {
          exitCalls += 1;
        },
        iconAsset: 'assets/tray_icon.png',
        labels: _testTrayLabels,
      );
      addTearDown(() async {
        await controller.dispose();
        await snapshots.close();
      });

      final DesktopSessionState firstSession = _session(
        instanceId: 1,
        title: 'Song A',
      );
      final DesktopSessionState secondSession = _session(
        instanceId: 2,
        title: 'Song B',
      );
      await controller.initialize(
        initialSessions: <int, DesktopSessionState>{
          1: firstSession,
          2: secondSession,
        },
      );

      final _FakeTrayPort trayPort = trayFactory.lastPort;
      expect(controller.selectedInstanceId, 1);
      expect(
        _findInstanceEntries(
          controller.menuEntries,
        ).where((DesktopTrayMenuEntry entry) => entry.checked).single.key,
        'instance:1',
      );

      await trayPort.click('instance:1');
      expect(controller.selectedInstanceId, 1);

      snapshots.add(<int, DesktopSessionState>{
        1: firstSession,
        2: _session(instanceId: 2, title: 'Song B2'),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.selectedInstanceId, 1);

      await trayPort.click(
        DesktopTrayController.menuKeyToggleFloatingVisibility,
      );
      expect(actions.last, (
        instanceId: 1,
        action: DesktopWindowActionType.toggleFloatingVisibility,
      ));

      snapshots.add(<int, DesktopSessionState>{
        2: _session(instanceId: 2, title: 'Song B3'),
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.selectedInstanceId, 2);
      expect(_hasInstanceSwitcher(controller.menuEntries), isFalse);

      await trayPort.click(DesktopTrayController.menuKeyExitApp);
      expect(exitCalls, 1);
    });

    test('单实例左键直接切换桌面歌词，多实例左键只弹菜单', () async {
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      final StreamController<Map<int, DesktopSessionState>> snapshots =
          StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
      final List<({int instanceId, DesktopWindowActionType action})> actions =
          <({int instanceId, DesktopWindowActionType action})>[];
      final DesktopTrayController controller = DesktopTrayController(
        trayPortFactory: trayFactory.call,
        sessionSnapshots: snapshots.stream,
        runWindowAction:
            ({
              required int instanceId,
              required DesktopWindowActionType action,
              DesktopPlaybackControlTask? controlTask,
            }) async {
              actions.add((instanceId: instanceId, action: action));
              return true;
            },
        exitApplication: () async {},
        iconAsset: 'assets/tray_icon.png',
        labels: _testTrayLabels,
      );
      addTearDown(() async {
        await controller.dispose();
        await snapshots.close();
      });

      await controller.initialize(
        initialSessions: <int, DesktopSessionState>{
          1: _session(instanceId: 1, title: 'Song A'),
        },
      );

      final _FakeTrayPort trayPort = trayFactory.lastPort;
      await trayPort.primaryClick();
      await Future<void>.delayed(Duration.zero);
      expect(actions.single, (
        instanceId: 1,
        action: DesktopWindowActionType.toggleFloatingVisibility,
      ));
      expect(trayPort.showContextMenuCalls, 0);

      snapshots.add(<int, DesktopSessionState>{
        1: _session(instanceId: 1, title: 'Song A'),
        2: _session(instanceId: 2, title: 'Song B'),
      });
      await Future<void>.delayed(Duration.zero);

      await trayPort.primaryClick();
      await Future<void>.delayed(Duration.zero);
      expect(actions, hasLength(1));
      expect(trayPort.showContextMenuCalls, 1);
    });

    test('右键与多实例左键共享单次菜单弹出链路，弹出中不会重复 show', () async {
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      final StreamController<Map<int, DesktopSessionState>> snapshots =
          StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
      final DesktopTrayController controller = DesktopTrayController(
        trayPortFactory: trayFactory.call,
        sessionSnapshots: snapshots.stream,
        runWindowAction:
            ({
              required int instanceId,
              required DesktopWindowActionType action,
              DesktopPlaybackControlTask? controlTask,
            }) async => true,
        exitApplication: () async {},
        iconAsset: 'assets/tray_icon.png',
        labels: _testTrayLabels,
      );
      addTearDown(() async {
        await controller.dispose();
        await snapshots.close();
      });

      await controller.initialize(
        initialSessions: <int, DesktopSessionState>{
          1: _session(instanceId: 1, title: 'Song A'),
          2: _session(instanceId: 2, title: 'Song B'),
        },
      );

      final _FakeTrayPort trayPort = trayFactory.lastPort;
      final Completer<void> popupCompleter = Completer<void>();
      trayPort.showContextMenuCompleter = popupCompleter;

      await trayPort.primaryClick();
      await Future<void>.delayed(Duration.zero);
      await trayPort.secondaryClick();
      await Future<void>.delayed(Duration.zero);

      expect(trayPort.showContextMenuCalls, 1);

      popupCompleter.complete();
      await Future<void>.delayed(Duration.zero);

      await trayPort.secondaryClick();
      await Future<void>.delayed(Duration.zero);
      expect(trayPort.showContextMenuCalls, 2);
    });

    test('初始化期间释放会等待并清理端口，不会补挂 session 订阅', () async {
      final _FakeTrayPortFactory trayFactory = _FakeTrayPortFactory();
      final StreamController<Map<int, DesktopSessionState>> snapshots =
          StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
      final DesktopTrayController controller = DesktopTrayController(
        trayPortFactory: trayFactory.call,
        sessionSnapshots: snapshots.stream,
        runWindowAction:
            ({
              required int instanceId,
              required DesktopWindowActionType action,
              DesktopPlaybackControlTask? controlTask,
            }) async => true,
        exitApplication: () async {},
        iconAsset: 'assets/tray_icon.png',
        labels: _testTrayLabels,
      );
      final Completer<void> initializeGate = Completer<void>();
      trayFactory.nextInitializeCompleter = initializeGate;

      final Future<void> initializeFuture = controller.initialize(
        initialSessions: <int, DesktopSessionState>{
          1: _session(instanceId: 1, title: 'Song A'),
        },
      );
      await waitForCondition(() => trayFactory.createdPorts.isNotEmpty);
      final _FakeTrayPort port = trayFactory.lastPort;
      final Future<void> firstDispose = controller.dispose();
      final Future<void> secondDispose = controller.dispose();

      initializeGate.complete();
      await Future.wait(<Future<void>>[
        initializeFuture,
        firstDispose,
        secondDispose,
      ]);

      expect(port.disposeCalls, 1);
      expect(port.onPrimaryAction, isNull);
      expect(port.onSecondaryAction, isNull);
      expect(port.onSelected, isNull);
      snapshots.add(<int, DesktopSessionState>{
        2: _session(instanceId: 2, title: 'Song B'),
      });
      await Future<void>.delayed(Duration.zero);
      expect(trayFactory.createdPorts, hasLength(1));
      await snapshots.close();
    });
  });
}

const DesktopTrayLabels _testTrayLabels = (
  showMainWindow: '显示主窗口',
  currentTarget: '当前目标：',
  noSelection: '未选择',
  targetInstance: '目标实例',
  instance: '实例',
  selectLyrics: '选择歌词',
  markInstrumental: '标记为纯音乐',
  disableAutoSearch: '禁用自动搜索(仅本曲)',
  unlinkLyrics: '取消歌词关联',
  clickThrough: '鼠标穿透',
  toggleFloating: '显示/隐藏桌面歌词',
  associationManager: '歌词关联管理器',
  exit: '退出',
);

const DesktopTrayLabels _englishTrayLabels = (
  showMainWindow: 'Show main window',
  currentTarget: 'Current target: ',
  noSelection: 'None',
  targetInstance: 'Target instance',
  instance: 'Instance',
  selectLyrics: 'Select lyrics',
  markInstrumental: 'Mark as instrumental',
  disableAutoSearch: 'Disable auto search for this song',
  unlinkLyrics: 'Unlink lyrics',
  clickThrough: 'Click-through',
  toggleFloating: 'Show or hide desktop lyrics',
  associationManager: 'Lyrics association manager',
  exit: 'Exit',
);

DesktopSessionState _session({required int instanceId, required String title}) {
  return DesktopSessionState.initial().copyWith(
    instanceId: instanceId,
    lyricsRuntime: DesktopLyricsRuntimeState(
      song: SongInfo(
        source: Source.local,
        title: title,
        artist: SongArtist(<String>['Artist']),
        album: 'Album',
        durationMs: 180000,
        id: '$instanceId',
      ),
    ),
  );
}

bool _hasInstanceSwitcher(List<DesktopTrayMenuEntry> entries) {
  return entries.any(
    (DesktopTrayMenuEntry entry) =>
        entry.key == DesktopTrayController.menuKeyInstanceSwitcher,
  );
}

List<DesktopTrayMenuEntry> _findInstanceEntries(
  List<DesktopTrayMenuEntry> entries,
) {
  return entries
      .singleWhere(
        (DesktopTrayMenuEntry entry) =>
            entry.key == DesktopTrayController.menuKeyInstanceSwitcher,
      )
      .children;
}

class _FakeTrayPortFactory {
  final List<_FakeTrayPort> createdPorts = <_FakeTrayPort>[];
  Completer<void>? nextInitializeCompleter;

  _FakeTrayPort get lastPort => createdPorts.last;

  DesktopTrayPort call() {
    final _FakeTrayPort port = _FakeTrayPort()
      ..initializeCompleter = nextInitializeCompleter;
    nextInitializeCompleter = null;
    createdPorts.add(port);
    return port;
  }
}

class _FakeTrayPort implements DesktopTrayPort {
  String? initializedIconAsset;
  List<DesktopTrayMenuEntry> menuEntries = const <DesktopTrayMenuEntry>[];
  VoidCallback? onPrimaryAction;
  VoidCallback? onSecondaryAction;
  ValueChanged<String>? onSelected;
  int disposeCalls = 0;
  int showContextMenuCalls = 0;
  Completer<void>? initializeCompleter;
  Completer<void>? showContextMenuCompleter;

  Future<void> click(String key) async {
    final ValueChanged<String>? handler = onSelected;
    if (handler != null) {
      handler(key);
    }
  }

  Future<void> primaryClick() async {
    onPrimaryAction?.call();
  }

  Future<void> secondaryClick() async {
    onSecondaryAction?.call();
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  Future<void> initialize({required String iconAsset, String? toolTip}) async {
    initializedIconAsset = iconAsset;
    await initializeCompleter?.future;
  }

  @override
  void setOnPrimaryAction(VoidCallback? onPrimaryAction) {
    this.onPrimaryAction = onPrimaryAction;
  }

  @override
  void setOnSecondaryAction(VoidCallback? onSecondaryAction) {
    this.onSecondaryAction = onSecondaryAction;
  }

  @override
  void setOnMenuItemSelected(ValueChanged<String>? onSelected) {
    this.onSelected = onSelected;
  }

  @override
  Future<void> showContextMenu() async {
    showContextMenuCalls += 1;
    final Completer<void>? completer = showContextMenuCompleter;
    if (completer != null) {
      await completer.future;
      showContextMenuCompleter = null;
    }
  }

  @override
  Future<Rect?> getBounds() async => null;

  @override
  Future<void> updateMenu(List<DesktopTrayMenuEntry> entries) async {
    menuEntries = entries;
  }
}
