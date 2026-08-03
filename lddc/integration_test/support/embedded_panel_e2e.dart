import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/platform/desktop/window/desktop_panel_window_host.dart';

const int _wsChild = 0x40000000;
const int _wsExTransparent = 0x00000020;
const int _wsExLayered = 0x00080000;

/// 独立 Windows runner 使用的 embedded Panel 验收程序。
///
/// 测试只调用生产 Panel host，并通过一个最小原生测试通道观察最终合成结果。
/// 生产代码中不增加截图、背景采样、重试 Timer 或测试模式分支。
Future<int> runEmbeddedPanelE2E(List<String> args) {
  return _EmbeddedPanelE2EProgram.run(args);
}

class _EmbeddedPanelE2EProgram {
  _EmbeddedPanelE2EProgram._(this.config)
    : reporter = _E2EReporter(config.reportFile),
      panelHost = WindowsEmbeddedPanelWindowHost(
        sceneStore: _sceneStore,
        lifecycleRegistry: DesktopWindowLifecycleRegistryController.instance,
        channelOperationTimeout: const Duration(seconds: 15),
      );

  final _E2EConfig config;
  final _E2EReporter reporter;
  final _NativePanelTestPort native = const _NativePanelTestPort();
  final WindowsEmbeddedPanelWindowHost panelHost;
  final Set<int> hostWindows = <int>{};

  static Future<int> run(List<String> args) async {
    final _E2EConfig config = _E2EConfig.fromArgs(args);
    final _EmbeddedPanelE2EProgram program = _EmbeddedPanelE2EProgram._(config);
    return program._run();
  }

  Future<int> _run() async {
    Object? failure;
    StackTrace? failureStack;
    _ResourceCounts? finalCounts;
    try {
      await reporter.step('surface_unready_fail_fast', _verifyZeroSurface);
      await reporter.step('embedded_opaque_rendering', _verifyOpaqueRendering);
      await reporter.step('resize_visibility_lifecycle', _verifyLifecycle);
      await reporter.step('multiple_panels', _verifyMultiplePanels);
      await reporter.step('create_destroy_stress', _verifyStress);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      await panelHost.dispose();
      for (final int hostWindowId in hostWindows.toList(growable: false)) {
        try {
          await native.destroyHostWindow(hostWindowId);
        } on Object {
          // 清理阶段继续释放其余宿主，最终资源计数会暴露残留。
        }
      }
      hostWindows.clear();
      DesktopWindowLifecycleRegistryController.instance.debugResetForTests();
      try {
        finalCounts = await native.collectResourceCounts();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
      await reporter.finish(
        success: failure == null,
        failure: failure,
        failureStack: failureStack,
        extra: <String, Object?>{
          'stressCount': config.stressCount,
          'finalResources': finalCounts?.toJson(),
        },
      );
    }
    return failure == null ? 0 : 1;
  }

  Future<Map<String, Object?>> _verifyZeroSurface() async {
    final _HostWindow host = await _createHost(
      width: 0,
      height: 0,
      visible: false,
    );
    _expect(host.width == 0 && host.height == 0, '测试宿主没有形成 0x0 客户区');
    bool failedAsExpected = false;
    try {
      await panelHost.createPanel(
        instanceId: 9001,
        panelId: 1,
        hostWindowId: host.windowId,
        initialSurface: const PanelSurfaceUpdate(
          width: 999,
          height: 999,
          sizeSpace: PanelSizeSpace.hostPhysicalPx,
          visible: false,
        ),
      );
    } on DesktopPanelSurfaceUnavailable {
      failedAsExpected = true;
    }
    _expect(failedAsExpected, '0x0 客户区错误创建了半成品 Panel engine');
    final _ResourceCounts pendingCounts = await native.collectResourceCounts();
    _expect(
      pendingCounts.panelRegistryCount == 0,
      'surface_unready 后 native registry 未清空',
    );

    final _HostWindow ready = await native.setHostClientSize(
      host.windowId,
      width: 360,
      height: 120,
    );
    _expect(ready.width == 360 && ready.height == 120, '宿主客户区恢复失败');
    await panelHost.createPanel(
      instanceId: 9001,
      panelId: 1,
      hostWindowId: host.windowId,
      initialSurface: const PanelSurfaceUpdate(
        width: 1,
        height: 1,
        sizeSpace: PanelSizeSpace.unknownRaw,
        visible: false,
      ),
    );
    final _PanelState state = await native.collectPanelState(9001, 1);
    _expect(
      state.hostWidth == 360 && state.hostHeight == 120,
      '原生层错误采用 IPC 尺寸',
    );
    await panelHost.destroyPanel(instanceId: 9001, panelId: 1);
    await _destroyHost(host.windowId);
    return <String, Object?>{
      'surfaceUnavailableObserved': failedAsExpected,
      'readySurface': state.toJson(),
    };
  }

  Future<Map<String, Object?>> _verifyOpaqueRendering() async {
    const int instanceId = 9100;
    const int panelId = 1;
    final _HostWindow host = await _createHost(
      width: 960,
      height: 320,
      visible: true,
    );
    final _PixelCapture baseline0 = await native.captureHostClient(
      host.windowId,
    );
    await _writeBmp('checker_phase0_hidden.bmp', baseline0);

    final DesktopPanelWindowSnapshot snapshot = _buildStaticSnapshot(
      instanceId,
    );
    await panelHost.createPanel(
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: host.windowId,
      initialSnapshot: snapshot,
      initialSurface: const PanelSurfaceUpdate(
        width: 12,
        height: 34,
        sizeSpace: PanelSizeSpace.unknownRaw,
        visible: false,
      ),
    );
    final _PanelState hiddenState = await native.collectPanelState(
      instanceId,
      panelId,
    );
    _expect(hiddenState.rootParentId == host.windowId, 'root 未挂到宿主 HWND');
    _expect(
      hiddenState.viewWindowId != hiddenState.rootWindowId &&
          hiddenState.viewParentId == hiddenState.rootWindowId,
      'Flutter view 父链被污染',
    );
    _expect((hiddenState.rootStyle & _wsChild) != 0, 'root 缺少 WS_CHILD');
    _expect(
      (hiddenState.rootExStyle & _wsExTransparent) == 0,
      'root 错误设置 WS_EX_TRANSPARENT，Panel 将无法交互',
    );
    _expect(
      (hiddenState.rootExStyle & _wsExLayered) == 0,
      'root 不应设置 WS_EX_LAYERED，标准 Flutter surface 会丢失前景',
    );

    await _updateSurface(instanceId, panelId, visible: true);
    await _settle();
    final _PixelCapture shown0 = await native.captureHostClient(host.windowId);
    await _writeBmp('checker_phase0_panel.bmp', shown0);
    final _PixelComparison hostCoverage = _comparePixels(baseline0, shown0);
    final _PanelState shownState = await native.collectPanelState(
      instanceId,
      panelId,
    );
    _expect(shownState.rootVisible && shownState.viewVisible, 'Panel 显示状态未生效');
    _expect(
      hostCoverage.changedPixels > hostCoverage.totalPixels * 0.6,
      '不透明 Panel 没有覆盖宿主客户区',
    );
    final int foregroundPixels = _countBrightPixels(shown0);
    _expect(foregroundPixels > 300, 'Panel 已显示但歌词前景没有进入最终画面');

    await native.setCheckerPhase(host.windowId, 1);
    await _settle();
    final _PixelCapture shown1 = await native.captureHostClient(host.windowId);
    await _writeBmp('checker_phase1_panel.bmp', shown1);
    final _PixelComparison opaqueIsolation = _comparePixels(shown0, shown1);
    _expect(opaqueIsolation.matchRatio > 0.98, '宿主背景变化穿透或污染了不透明 Panel 画面');

    // standalone runner 只验证 Win32 嵌入边界：坐标必须真实命中 Flutter view。
    // 菜单手势与动作意图由 Widget 测试驱动 Flutter 指针事件验证，避免测试结果
    // 依赖当前桌面是否允许后台进程抢占前台窗口。
    final Map<String, Object?> pointerTarget = await native
        .collectPointerTarget(instanceId, panelId, x: 48, y: 48);
    _expect(
      pointerTarget['targetWindowId'] == pointerTarget['viewWindowId'],
      'Panel 客户区坐标没有命中 Flutter view: $pointerTarget',
    );

    await panelHost.destroyPanel(instanceId: instanceId, panelId: panelId);
    _sceneStore.evictScenes(instanceId);
    await _destroyHost(host.windowId);
    return <String, Object?>{
      'hostCoverage': hostCoverage.toJson(),
      'opaqueIsolation': opaqueIsolation.toJson(),
      'foregroundPixels': foregroundPixels,
      'pointerTarget': pointerTarget,
      'initialPanelState': hiddenState.toJson(),
      'shownPanelState': shownState.toJson(),
    };
  }

  Future<Map<String, Object?>> _verifyLifecycle() async {
    const int instanceId = 9200;
    const int panelId = 1;
    final _HostWindow host = await _createHost(
      width: 640,
      height: 180,
      visible: true,
    );
    await panelHost.createPanel(
      instanceId: instanceId,
      panelId: panelId,
      hostWindowId: host.windowId,
      initialSnapshot: _buildStaticSnapshot(instanceId),
      initialSurface: const PanelSurfaceUpdate(
        width: 640,
        height: 180,
        sizeSpace: PanelSizeSpace.hostPhysicalPx,
        visible: false,
      ),
    );
    final List<Map<String, Object?>> geometry = <Map<String, Object?>>[];
    for (final (int, int) size in <(int, int)>[
      (700, 240),
      (420, 260),
      (900, 140),
    ]) {
      await native.setHostClientSize(
        host.windowId,
        width: size.$1,
        height: size.$2,
      );
      // 故意发送错误兼容尺寸，验证 GetClientRect 才是唯一几何真源。
      await panelHost.updatePanelSurface(
        instanceId: instanceId,
        panelId: panelId,
        update: const PanelSurfaceUpdate(
          width: 1,
          height: 1,
          sizeSpace: PanelSizeSpace.unknownRaw,
          visible: true,
        ),
      );
      final _PanelState state = await _waitForPanelSize(
        instanceId,
        panelId,
        width: size.$1,
        height: size.$2,
      );
      geometry.add(state.toJson());
    }

    await _updateSurface(instanceId, panelId, visible: false);
    await native.setHostClientSize(host.windowId, width: 520, height: 300);
    await _updateSurface(instanceId, panelId, visible: false);
    final _PanelState hidden = await _waitForPanelSize(
      instanceId,
      panelId,
      width: 520,
      height: 300,
    );
    _expect(!hidden.rootVisible, 'hidden resize 期间 root 被提前显示');
    await _updateSurface(instanceId, panelId, visible: true);
    final _PanelState reshown = await native.collectPanelState(
      instanceId,
      panelId,
    );
    _expect(reshown.rootVisible, 'hidden resize 后匹配帧未恢复显示');

    await _updateSurface(instanceId, panelId, visible: false);
    final _HostWindow minimized = await native.setHostWindowState(
      host.windowId,
      'minimize',
    );
    _expect(minimized.minimized, '宿主最小化状态未生效');
    final _HostWindow restored = await native.setHostWindowState(
      host.windowId,
      'restore',
    );
    _expect(restored.visible && !restored.minimized, '宿主恢复状态未生效');
    await _updateSurface(instanceId, panelId, visible: true);
    final _PanelState restoredPanel = await native.collectPanelState(
      instanceId,
      panelId,
    );
    _expect(restoredPanel.rootVisible, '宿主恢复后 Panel 未显示');

    await panelHost.destroyPanel(instanceId: instanceId, panelId: panelId);
    _sceneStore.evictScenes(instanceId);
    await _destroyHost(host.windowId);
    return <String, Object?>{
      'geometry': geometry,
      'hiddenResize': hidden.toJson(),
      'restored': restoredPanel.toJson(),
      'dpi': restoredPanel.dpi,
    };
  }

  Future<Map<String, Object?>> _verifyMultiplePanels() async {
    final _HostWindow first = await _createHost(
      width: 360,
      height: 120,
      visible: false,
    );
    final _HostWindow second = await _createHost(
      width: 420,
      height: 140,
      visible: false,
    );
    await panelHost.createPanel(
      instanceId: 9300,
      panelId: 1,
      hostWindowId: first.windowId,
    );
    await panelHost.createPanel(
      instanceId: 9300,
      panelId: 2,
      hostWindowId: second.windowId,
    );
    final _ResourceCounts both = await native.collectResourceCounts();
    _expect(both.panelRegistryCount == 2, '多 Panel registry 数量错误');
    await panelHost.destroyPanel(instanceId: 9300, panelId: 1);
    final _ResourceCounts one = await native.collectResourceCounts();
    _expect(one.panelRegistryCount == 1, '销毁一个 Panel 影响了另一 Panel');
    await panelHost.destroyPanel(instanceId: 9300, panelId: 2);
    final _ResourceCounts none = await native.collectResourceCounts();
    _expect(none.panelRegistryCount == 0, '多 Panel 销毁后 registry 未清空');
    await _destroyHost(first.windowId);
    await _destroyHost(second.windowId);
    return <String, Object?>{
      'twoPanels': both.toJson(),
      'onePanel': one.toJson(),
      'zeroPanels': none.toJson(),
    };
  }

  Future<Map<String, Object?>> _verifyStress() async {
    final _HostWindow host = await _createHost(
      width: 320,
      height: 96,
      visible: false,
    );
    for (int index = 0; index < 2; index += 1) {
      await _stressIteration(host.windowId);
    }
    final _ResourceCounts baseline = await native.collectResourceCounts();
    for (int index = 0; index < config.stressCount; index += 1) {
      await _stressIteration(host.windowId);
      if ((index + 1) % 10 == 0) {
        final _ResourceCounts checkpoint = await native.collectResourceCounts();
        _expect(
          checkpoint.panelRegistryCount == 0,
          '压力测试第 ${index + 1} 轮后 registry 未清空',
        );
      }
    }
    final _ResourceCounts settled = await _waitForResourceBaseline(baseline);
    await _destroyHost(host.windowId);
    return <String, Object?>{
      'iterations': config.stressCount,
      'baseline': baseline.toJson(),
      'settled': settled.toJson(),
    };
  }

  Future<void> _stressIteration(int hostWindowId) async {
    await panelHost.createPanel(
      instanceId: 9400,
      panelId: 1,
      hostWindowId: hostWindowId,
    );
    await panelHost.destroyPanel(instanceId: 9400, panelId: 1);
  }

  Future<_ResourceCounts> _waitForResourceBaseline(
    _ResourceCounts baseline,
  ) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 10));
    _ResourceCounts current = await native.collectResourceCounts();
    while (!current.isAtMost(baseline) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      current = await native.collectResourceCounts();
    }
    _expect(
      current.isAtMost(baseline),
      '100 次创建销毁后句柄/GDI/USER 资源未回到预热基线: '
      'baseline=${baseline.toJson()} current=${current.toJson()}',
    );
    return current;
  }

  DesktopPanelWindowSnapshot _buildStaticSnapshot(int instanceId) {
    final String sceneId = '$instanceId:embedded-e2e';
    final DesktopLyricsSceneDocument scene = DesktopLyricsSceneDocument(
      mode: DesktopLyricsSceneMode.staticText,
      selectedLangs: <String>['orig'],
      langOrder: <String>['orig'],
      durationMs: null,
      staticDisplayLines: <String>['LDDC embedded panel', '稳定不透明渲染'],
    );
    const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();
    final Uint8List bytes = codec.encode(scene);
    final String checksum = codec.checksumForBytes(bytes);
    _sceneStore.putScene(sceneId, bytes, revision: 1, checksum: checksum);
    return DesktopPanelWindowSnapshot(
      session: DesktopPanelSessionSnapshot(
        songId: 'embedded-e2e',
        fontSize: 34,
        actions: const DesktopWindowActionSnapshot.empty(),
      ),
      anchor: DesktopPanelAnchorSnapshot(sceneId: sceneId, songToken: sceneId),
      sceneRef: DesktopSceneRef(
        sceneId: sceneId,
        sceneRevision: 1,
        checksum: checksum,
      ),
    );
  }

  static final DesktopInMemorySceneStore _sceneStore =
      DesktopInMemorySceneStore();

  Future<void> _updateSurface(
    int instanceId,
    int panelId, {
    required bool visible,
  }) {
    return panelHost.updatePanelSurface(
      instanceId: instanceId,
      panelId: panelId,
      update: PanelSurfaceUpdate(
        width: 1,
        height: 1,
        sizeSpace: PanelSizeSpace.unknownRaw,
        visible: visible,
      ),
    );
  }

  Future<_PanelState> _waitForPanelSize(
    int instanceId,
    int panelId, {
    required int width,
    required int height,
  }) async {
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 3));
    _PanelState state = await native.collectPanelState(instanceId, panelId);
    while ((state.rootWidth != width ||
            state.rootHeight != height ||
            state.viewWidth != width ||
            state.viewHeight != height) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      state = await native.collectPanelState(instanceId, panelId);
    }
    _expect(
      state.rootWidth == width &&
          state.rootHeight == height &&
          state.viewWidth == width &&
          state.viewHeight == height,
      'root/view 尺寸未匹配宿主客户区 ${width}x$height: ${state.toJson()}',
    );
    return state;
  }

  Future<_HostWindow> _createHost({
    required int width,
    required int height,
    required bool visible,
  }) async {
    final _HostWindow host = await native.createHostWindow(
      width: width,
      height: height,
      visible: visible,
    );
    hostWindows.add(host.windowId);
    return host;
  }

  Future<void> _destroyHost(int hostWindowId) async {
    await native.destroyHostWindow(hostWindowId);
    hostWindows.remove(hostWindowId);
  }

  Future<void> _writeBmp(String name, _PixelCapture capture) async {
    await config.reportDirectory.create(recursive: true);
    final File file = File(
      '${config.reportDirectory.path}${Platform.pathSeparator}$name',
    );
    await file.writeAsBytes(capture.toBmp(), flush: true);
  }
}

class _E2EConfig {
  const _E2EConfig({
    required this.reportDirectory,
    required this.reportFile,
    required this.stressCount,
  });

  final Directory reportDirectory;
  final File reportFile;
  final int stressCount;

  factory _E2EConfig.fromArgs(List<String> args) {
    String reportPath = 'build/panel_e2e_reports';
    int stressCount = 100;
    for (final String argument in args) {
      if (argument.startsWith('--report-dir=')) {
        reportPath = argument.substring('--report-dir='.length);
      } else if (argument.startsWith('--stress-count=')) {
        stressCount =
            int.tryParse(argument.substring('--stress-count='.length)) ?? 100;
      }
    }
    final Directory directory = Directory(reportPath);
    return _E2EConfig(
      reportDirectory: directory,
      reportFile: File(
        '${directory.path}${Platform.pathSeparator}embedded_panel_e2e.json',
      ),
      stressCount: stressCount.clamp(1, 1000).toInt(),
    );
  }
}

class _E2EReporter {
  _E2EReporter(this.file);

  final File file;
  final List<Map<String, Object?>> steps = <Map<String, Object?>>[];

  Future<T> step<T>(String name, Future<T> Function() action) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final T result = await action();
      steps.add(<String, Object?>{
        'name': name,
        'success': true,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        if (result is Map<String, Object?>) 'details': result,
      });
      return result;
    } on Object catch (error, stackTrace) {
      steps.add(<String, Object?>{
        'name': name,
        'success': false,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      rethrow;
    }
  }

  Future<void> finish({
    required bool success,
    required Object? failure,
    required StackTrace? failureStack,
    required Map<String, Object?> extra,
  }) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'success': success,
        'steps': steps,
        'failure': failure?.toString(),
        'failureStack': failureStack?.toString(),
        'extra': extra,
      }),
      flush: true,
    );
  }
}

class _NativePanelTestPort {
  const _NativePanelTestPort();

  static const MethodChannel _channel = MethodChannel(
    'lddc/windows_desktop_panel_host_test',
  );

  Future<_HostWindow> createHostWindow({
    required int width,
    required int height,
    required bool visible,
  }) async {
    return _HostWindow.fromPayload(
      await _channel.invokeMethod<Object?>(
        'createTestHostWindow',
        <String, Object?>{'width': width, 'height': height, 'visible': visible},
      ),
    );
  }

  Future<_HostWindow> setHostClientSize(
    int hostWindowId, {
    required int width,
    required int height,
  }) async {
    return _HostWindow.fromPayload(
      await _channel.invokeMethod<Object?>(
        'setTestHostClientSize',
        <String, Object?>{
          'hostWindowId': hostWindowId,
          'width': width,
          'height': height,
        },
      ),
    );
  }

  Future<_HostWindow> setHostWindowState(int hostWindowId, String state) async {
    return _HostWindow.fromPayload(
      await _channel.invokeMethod<Object?>(
        'setTestHostWindowState',
        <String, Object?>{'hostWindowId': hostWindowId, 'state': state},
      ),
    );
  }

  Future<void> setCheckerPhase(int hostWindowId, int phase) async {
    await _channel.invokeMethod<Object?>(
      'setTestHostCheckerPhase',
      <String, Object?>{'hostWindowId': hostWindowId, 'phase': phase},
    );
  }

  Future<void> destroyHostWindow(int hostWindowId) {
    return _channel.invokeMethod<void>(
      'destroyTestHostWindow',
      <String, Object?>{'hostWindowId': hostWindowId},
    );
  }

  Future<_PixelCapture> captureHostClient(int hostWindowId) async {
    return _PixelCapture.fromPayload(
      await _channel.invokeMethod<Object?>(
        'captureTestHostClient',
        <String, Object?>{'hostWindowId': hostWindowId},
      ),
    );
  }

  Future<_PanelState> collectPanelState(int instanceId, int panelId) async {
    return _PanelState.fromPayload(
      await _channel.invokeMethod<Object?>(
        'collectPanelState',
        <String, Object?>{'instanceId': instanceId, 'panelId': panelId},
      ),
    );
  }

  Future<Map<String, Object?>> collectPointerTarget(
    int instanceId,
    int panelId, {
    required int x,
    required int y,
  }) async {
    return _stringMap(
      await _channel.invokeMethod<Object?>(
        'collectPanelPointerTarget',
        <String, Object?>{
          'instanceId': instanceId,
          'panelId': panelId,
          'x': x,
          'y': y,
        },
      ),
    );
  }

  Future<_ResourceCounts> collectResourceCounts() async {
    return _ResourceCounts.fromPayload(
      await _channel.invokeMethod<Object?>('collectResourceCounts'),
    );
  }
}

class _HostWindow {
  const _HostWindow({
    required this.windowId,
    required this.width,
    required this.height,
    required this.visible,
    required this.minimized,
    required this.dpi,
  });

  final int windowId;
  final int width;
  final int height;
  final bool visible;
  final bool minimized;
  final int dpi;

  factory _HostWindow.fromPayload(Object? payload) {
    final Map<String, Object?> map = _stringMap(payload);
    final Map<String, Object?> rect = _stringMap(map['clientRect']);
    return _HostWindow(
      windowId: _asInt(map['windowId']),
      width: _asInt(rect['width']),
      height: _asInt(rect['height']),
      visible: map['visible'] == true,
      minimized: map['minimized'] == true,
      dpi: _asInt(map['dpi'], fallback: 96),
    );
  }
}

class _PanelState {
  const _PanelState({
    required this.hostWindowId,
    required this.rootWindowId,
    required this.viewWindowId,
    required this.rootParentId,
    required this.viewParentId,
    required this.rootStyle,
    required this.rootExStyle,
    required this.viewStyle,
    required this.viewExStyle,
    required this.rootVisible,
    required this.viewVisible,
    required this.rootWidth,
    required this.rootHeight,
    required this.viewWidth,
    required this.viewHeight,
    required this.hostWidth,
    required this.hostHeight,
    required this.surfaceRevision,
    required this.dpi,
  });

  final int hostWindowId;
  final int rootWindowId;
  final int viewWindowId;
  final int rootParentId;
  final int viewParentId;
  final int rootStyle;
  final int rootExStyle;
  final int viewStyle;
  final int viewExStyle;
  final bool rootVisible;
  final bool viewVisible;
  final int rootWidth;
  final int rootHeight;
  final int viewWidth;
  final int viewHeight;
  final int hostWidth;
  final int hostHeight;
  final int surfaceRevision;
  final int dpi;

  factory _PanelState.fromPayload(Object? payload) {
    final Map<String, Object?> map = _stringMap(payload);
    final Map<String, Object?> root = _stringMap(map['rootClientRect']);
    final Map<String, Object?> view = _stringMap(map['viewClientRect']);
    final Map<String, Object?> host = _stringMap(map['hostClientRect']);
    return _PanelState(
      hostWindowId: _asInt(map['hostWindowId']),
      rootWindowId: _asInt(map['rootWindowId']),
      viewWindowId: _asInt(map['viewWindowId']),
      rootParentId: _asInt(map['rootParentId']),
      viewParentId: _asInt(map['viewParentId']),
      rootStyle: _asInt(map['rootStyle']),
      rootExStyle: _asInt(map['rootExStyle']),
      viewStyle: _asInt(map['viewStyle']),
      viewExStyle: _asInt(map['viewExStyle']),
      rootVisible: map['rootVisible'] == true,
      viewVisible: map['viewVisible'] == true,
      rootWidth: _asInt(root['width']),
      rootHeight: _asInt(root['height']),
      viewWidth: _asInt(view['width']),
      viewHeight: _asInt(view['height']),
      hostWidth: _asInt(host['width']),
      hostHeight: _asInt(host['height']),
      surfaceRevision: _asInt(map['surfaceRevision']),
      dpi: _asInt(map['dpi'], fallback: 96),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hostWindowId': hostWindowId,
      'rootWindowId': rootWindowId,
      'viewWindowId': viewWindowId,
      'rootParentId': rootParentId,
      'viewParentId': viewParentId,
      'rootStyle': rootStyle,
      'rootExStyle': rootExStyle,
      'viewStyle': viewStyle,
      'viewExStyle': viewExStyle,
      'rootVisible': rootVisible,
      'viewVisible': viewVisible,
      'rootSize': <int>[rootWidth, rootHeight],
      'viewSize': <int>[viewWidth, viewHeight],
      'hostSize': <int>[hostWidth, hostHeight],
      'surfaceRevision': surfaceRevision,
      'dpi': dpi,
    };
  }
}

class _PixelCapture {
  const _PixelCapture({
    required this.width,
    required this.height,
    required this.bgra,
  });

  final int width;
  final int height;
  final Uint8List bgra;

  factory _PixelCapture.fromPayload(Object? payload) {
    final Map<String, Object?> map = _stringMap(payload);
    final Uint8List pixels = switch (map['bgra']) {
      final Uint8List value => value,
      final List<int> value => Uint8List.fromList(value),
      _ => Uint8List(0),
    };
    final _PixelCapture capture = _PixelCapture(
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      bgra: pixels,
    );
    _expect(
      capture.bgra.lengthInBytes == capture.width * capture.height * 4,
      '原生截图字节数不匹配',
    );
    return capture;
  }

  Uint8List toBmp() {
    const int fileHeaderSize = 14;
    const int infoHeaderSize = 40;
    final int pixelOffset = fileHeaderSize + infoHeaderSize;
    final ByteData data = ByteData(pixelOffset + bgra.lengthInBytes);
    data
      ..setUint8(0, 0x42)
      ..setUint8(1, 0x4D)
      ..setUint32(2, data.lengthInBytes, Endian.little)
      ..setUint32(10, pixelOffset, Endian.little)
      ..setUint32(14, infoHeaderSize, Endian.little)
      ..setInt32(18, width, Endian.little)
      ..setInt32(22, -height, Endian.little)
      ..setUint16(26, 1, Endian.little)
      ..setUint16(28, 32, Endian.little)
      ..setUint32(34, bgra.lengthInBytes, Endian.little);
    data.buffer.asUint8List(pixelOffset).setAll(0, bgra);
    return data.buffer.asUint8List();
  }
}

class _PixelComparison {
  const _PixelComparison({
    required this.totalPixels,
    required this.matchingPixels,
    required this.changedPixels,
  });

  final int totalPixels;
  final int matchingPixels;
  final int changedPixels;
  double get matchRatio => totalPixels == 0 ? 0 : matchingPixels / totalPixels;

  Map<String, Object?> toJson() => <String, Object?>{
    'totalPixels': totalPixels,
    'matchingPixels': matchingPixels,
    'changedPixels': changedPixels,
    'matchRatio': matchRatio,
  };
}

class _ResourceCounts {
  const _ResourceCounts({
    required this.panelRegistryCount,
    required this.testHostWindowCount,
    required this.processHandleCount,
    required this.userObjectCount,
    required this.gdiObjectCount,
  });

  final int panelRegistryCount;
  final int testHostWindowCount;
  final int processHandleCount;
  final int userObjectCount;
  final int gdiObjectCount;

  factory _ResourceCounts.fromPayload(Object? payload) {
    final Map<String, Object?> map = _stringMap(payload);
    return _ResourceCounts(
      panelRegistryCount: _asInt(map['panelRegistryCount']),
      testHostWindowCount: _asInt(map['testHostWindowCount']),
      processHandleCount: _asInt(map['processHandleCount']),
      userObjectCount: _asInt(map['userObjectCount']),
      gdiObjectCount: _asInt(map['gdiObjectCount']),
    );
  }

  bool isAtMost(_ResourceCounts baseline) {
    return panelRegistryCount == 0 &&
        testHostWindowCount == baseline.testHostWindowCount &&
        processHandleCount <= baseline.processHandleCount &&
        userObjectCount <= baseline.userObjectCount &&
        gdiObjectCount <= baseline.gdiObjectCount;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'panelRegistryCount': panelRegistryCount,
    'testHostWindowCount': testHostWindowCount,
    'processHandleCount': processHandleCount,
    'userObjectCount': userObjectCount,
    'gdiObjectCount': gdiObjectCount,
  };
}

_PixelComparison _comparePixels(_PixelCapture expected, _PixelCapture actual) {
  _expect(
    expected.width == actual.width && expected.height == actual.height,
    '截图尺寸不一致',
  );
  int matching = 0;
  final int total = expected.width * expected.height;
  for (int offset = 0; offset < expected.bgra.lengthInBytes; offset += 4) {
    if (_sameBgr(expected.bgra, actual.bgra, offset)) {
      matching += 1;
    }
  }
  return _PixelComparison(
    totalPixels: total,
    matchingPixels: matching,
    changedPixels: total - matching,
  );
}

int _countBrightPixels(_PixelCapture capture) {
  int count = 0;
  for (int offset = 0; offset < capture.bgra.lengthInBytes; offset += 4) {
    final int brightest = math.max(
      capture.bgra[offset],
      math.max(capture.bgra[offset + 1], capture.bgra[offset + 2]),
    );
    if (brightest >= 72) {
      count += 1;
    }
  }
  return count;
}

bool _sameBgr(Uint8List left, Uint8List right, int offset) {
  return left[offset] == right[offset] &&
      left[offset + 1] == right[offset + 1] &&
      left[offset + 2] == right[offset + 2];
}

Map<String, Object?> _stringMap(Object? payload) {
  if (payload is! Map) {
    return <String, Object?>{};
  }
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in payload.entries)
      entry.key.toString(): entry.value,
  };
}

int _asInt(Object? value, {int fallback = 0}) {
  return switch (value) {
    final int number => number,
    final num number => number.toInt(),
    _ => int.tryParse(value?.toString() ?? '') ?? fallback,
  };
}

Future<void> _settle() {
  return Future<void>.delayed(const Duration(milliseconds: 250));
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
