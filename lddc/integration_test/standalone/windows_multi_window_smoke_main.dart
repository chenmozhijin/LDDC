import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:window_manager/window_manager.dart';
import 'package:win32/win32.dart';

import 'package:lddc/src/app/bootstrap/app_entrypoint.dart'
    if (dart.library.io) 'package:lddc/src/app/bootstrap/app_entrypoint_io.dart'
    as app_entrypoint;

typedef _GetCurrentProcessNative = IntPtr Function();
typedef _GetCurrentProcessDart = int Function();
typedef _GetProcessHandleCountNative =
    Int32 Function(IntPtr process, Pointer<Uint32> handleCount);
typedef _GetProcessHandleCountDart =
    int Function(int process, Pointer<Uint32> handleCount);
typedef _GetGuiResourcesNative = Uint32 Function(IntPtr process, Uint32 flag);
typedef _GetGuiResourcesDart = int Function(int process, int flag);

const int _kGdiObjects = 0;
const int _kUserObjects = 1;
const int _kPrivateBytesSlack = 24 * 1024 * 1024;
const int _kLastCycleGrowthLimit = 256 * 1024;
const int _kResidentWarmupOperations = 20;

Future<void> main(List<String> args) async {
  if (DesktopWindowLaunchArguments.isDesktopMultiWindowEntrypoint(args)) {
    await app_entrypoint.runAppEntrypoint(args);
    return;
  }

  final _SmokeArguments smokeArguments = _SmokeArguments.parse(args);
  final String? tracePath = smokeArguments.tracePath;
  final _SmokeTrace? trace;
  if (tracePath == null) {
    trace = null;
  } else {
    trace = _SmokeTrace(File(tracePath))..reset();
  }
  trace?.write('main_enter');
  WidgetsFlutterBinding.ensureInitialized();
  trace?.write('binding_ready');
  await windowManager.ensureInitialized();
  trace?.write('window_manager_ready');
  runApp(const ProviderScope(child: MaterialApp(home: SizedBox.shrink())));
  await WidgetsBinding.instance.endOfFrame;
  trace?.write('main_first_frame');
  await windowManager.hide();
  trace?.write('main_window_hidden');

  final Map<String, Object?> report = await _runSmoke(
    smokeArguments,
    trace: trace,
  );
  trace?.write('report_ready success=${report['success']}');
  final File reportFile = File(smokeArguments.reportPath);
  await reportFile.parent.create(recursive: true);
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  trace?.write('report_written');
  // 只写失败报告会让 CI 把阈值超标误判为通过。设置 exitCode 不会立即终止
  // 进程，因此仍能完成窗口和 Flutter engine 的正常销毁，再由 runner 返回失败。
  exitCode = report['success'] == true ? 0 : 1;
  // 不能使用 dart:io exit() 跳过 Win32 消息循环收尾。多窗口插件在
  // DLL 卸载阶段再析构子 engine 会破坏 FlutterWindowsView 的销毁顺序。
  await windowManager.setPreventClose(false);
  trace?.write('main_close_begin');
  await windowManager.close();
  trace?.write('main_close_requested');
}

Future<Map<String, Object?>> _runSmoke(
  _SmokeArguments arguments, {
  _SmokeTrace? trace,
}) async {
  return switch (arguments.scenario) {
    _SmokeScenario.resident => _runResidentSmoke(arguments, trace: trace),
    _SmokeScenario.rebuild => _runRebuildSmoke(arguments, trace: trace),
  };
}

Future<Map<String, Object?>> _runRebuildSmoke(
  _SmokeArguments arguments, {
  _SmokeTrace? trace,
}) async {
  final DesktopWindowLifecycleRegistryController lifecycle =
      DesktopWindowLifecycleRegistryController.instance;
  lifecycle.debugResetForTests();
  final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
  final DesktopMultiWindowFloatingWindowHost floatingHost =
      DesktopMultiWindowFloatingWindowHost(
        sceneStore: sceneStore,
        lifecycleRegistry: lifecycle,
        channelOperationTimeout: const Duration(seconds: 20),
        windowReadyTimeout: const Duration(seconds: 60),
      );
  final DesktopMultiWindowSelectorWindowHost selectorHost =
      DesktopMultiWindowSelectorWindowHost(
        lifecycleRegistry: lifecycle,
        channelOperationTimeout: const Duration(seconds: 20),
      );
  final List<int> floatingReadyMs = <int>[];
  final List<int> selectorReadyMs = <int>[];
  final List<_ProcessResources> cycleResources = <_ProcessResources>[];
  Object? failure;
  StackTrace? failureStack;

  try {
    trace?.write('warmup_begin');
    await _runCycle(
      cycleIndex: -1,
      windowMode: arguments.windowMode,
      sceneStore: sceneStore,
      floatingHost: floatingHost,
      selectorHost: selectorHost,
      lifecycle: lifecycle,
      trace: trace,
    );
    trace?.write('warmup_complete');
    final _ProcessResources baseline = _readProcessResources();
    trace?.write('baseline_read');

    for (int cycleIndex = 0; cycleIndex < arguments.cycles; cycleIndex += 1) {
      trace?.write('cycle=$cycleIndex begin');
      final _CycleTiming timing = await _runCycle(
        cycleIndex: cycleIndex,
        windowMode: arguments.windowMode,
        sceneStore: sceneStore,
        floatingHost: floatingHost,
        selectorHost: selectorHost,
        lifecycle: lifecycle,
        trace: trace,
      );
      floatingReadyMs.add(timing.floatingReadyMs);
      selectorReadyMs.add(timing.selectorReadyMs);
      cycleResources.add(_readProcessResources());
      trace?.write('cycle=$cycleIndex complete');
    }

    trace?.write('settle_begin');
    await Future<void>.delayed(Duration(seconds: arguments.settleSeconds));
    trace?.write('settle_complete');
    final _ProcessResources finalResources = _readProcessResources();
    final int floatingP95 = _percentile95(floatingReadyMs);
    final int selectorP95 = _percentile95(selectorReadyMs);
    final int maxReadyMs = <int>[
      floatingReadyMs.fold<int>(0, math.max),
      selectorReadyMs.fold<int>(0, math.max),
    ].fold<int>(0, math.max);
    final int lastCycleGrowth = _lastCyclePrivateGrowth(cycleResources);
    final bool resourcesPass =
        finalResources.handleCount <= baseline.handleCount &&
        finalResources.gdiObjects <= baseline.gdiObjects &&
        finalResources.userObjects <= baseline.userObjects + 2 &&
        finalResources.privateBytes <=
            baseline.privateBytes + _kPrivateBytesSlack &&
        lastCycleGrowth <= _kLastCycleGrowthLimit;
    final bool timingPass =
        floatingP95 <= 3000 && selectorP95 <= 3000 && maxReadyMs <= 15000;

    return <String, Object?>{
      'success': resourcesPass && timingPass,
      'scenario': arguments.scenario.name,
      'cycles': arguments.cycles,
      'settleSeconds': arguments.settleSeconds,
      'windowMode': arguments.windowMode.name,
      'timing': <String, Object?>{
        'floatingP95Ms': floatingP95,
        'selectorP95Ms': selectorP95,
        'maxReadyMs': maxReadyMs,
      },
      'resources': <String, Object?>{
        'baseline': baseline.toJson(),
        'final': finalResources.toJson(),
        'privateBytesByCycle': cycleResources
            .map((_ProcessResources value) => value.privateBytes)
            .toList(growable: false),
        'last20AveragePrivateGrowthPerCycle': lastCycleGrowth,
        'limits': <String, Object?>{
          'handleDelta': 0,
          'gdiDelta': 0,
          'userDelta': 2,
          'privateBytesDelta': _kPrivateBytesSlack,
          'last20AveragePrivateGrowthPerCycle': _kLastCycleGrowthLimit,
        },
      },
    };
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    trace?.write('dart_failure error=$error');
  } finally {
    trace?.write('selector_host_dispose_begin');
    await selectorHost.dispose();
    trace?.write('selector_host_dispose_complete');
    trace?.write('floating_host_dispose_begin');
    await floatingHost.dispose();
    trace?.write('floating_host_dispose_complete');
    lifecycle.debugResetForTests();
    trace?.write('lifecycle_reset');
  }

  return <String, Object?>{
    'success': false,
    'scenario': arguments.scenario.name,
    'cycles': arguments.cycles,
    'error': failure.toString(),
    'stack': failureStack.toString(),
  };
}

Future<Map<String, Object?>> _runResidentSmoke(
  _SmokeArguments arguments, {
  _SmokeTrace? trace,
}) async {
  const int primaryInstanceId = 1000;
  const int isolationInstanceId = 1001;
  final DesktopWindowLifecycleRegistryController lifecycle =
      DesktopWindowLifecycleRegistryController.instance;
  lifecycle.debugResetForTests();
  final DesktopInMemorySceneStore sceneStore = DesktopInMemorySceneStore();
  final DesktopMultiWindowFloatingWindowHost floatingHost =
      DesktopMultiWindowFloatingWindowHost(
        sceneStore: sceneStore,
        lifecycleRegistry: lifecycle,
        channelOperationTimeout: const Duration(seconds: 20),
        windowReadyTimeout: const Duration(seconds: 60),
      );
  final DesktopMultiWindowSelectorWindowHost selectorHost =
      DesktopMultiWindowSelectorWindowHost(
        lifecycleRegistry: lifecycle,
        channelOperationTimeout: const Duration(seconds: 20),
      );
  final List<int> floatingOperationMs = <int>[];
  final List<int> selectorOperationMs = <int>[];
  final List<_ProcessResources> operationResources = <_ProcessResources>[];
  DesktopWindowRef? initialFloatingRef;
  DesktopWindowRef? initialSelectorRef;
  DesktopSceneRef? activePrimaryScene;
  Object? failure;
  StackTrace? failureStack;

  try {
    trace?.write('resident_warmup_begin');
    if (arguments.windowMode.includesFloating) {
      activePrimaryScene = _publishResidentScene(
        sceneStore: sceneStore,
        instanceId: primaryInstanceId,
        revision: 1,
        label: 'warmup',
      );
      await floatingHost.applyFloatingSnapshot(
        instanceId: primaryInstanceId,
        snapshot: _residentFloatingSnapshot(
          sceneRef: activePrimaryScene,
          revision: 1,
          visible: true,
        ),
      );
      initialFloatingRef = lifecycle.currentRef(
        role: DesktopWindowRole.floating,
        instanceId: primaryInstanceId,
      );
    }
    if (arguments.windowMode.includesSelector) {
      await selectorHost.publishConfigRevision(revision: 1);
      await selectorHost.showSelectorWindow(
        instanceId: primaryInstanceId,
        context: _residentSelectorContext(revision: 1),
      );
      initialSelectorRef = lifecycle.currentRef(
        role: DesktopWindowRole.selector,
        instanceId: primaryInstanceId,
      );
    }
    _requireResidentRef(
      enabled: arguments.windowMode.includesFloating,
      ref: initialFloatingRef,
      role: DesktopWindowRole.floating,
    );
    _requireResidentRef(
      enabled: arguments.windowMode.includesSelector,
      ref: initialSelectorRef,
      role: DesktopWindowRole.selector,
    );

    // 第二实例只做一次隔离探针；销毁后再建立资源基线，避免把合法的第二组
    // engine/窗口资源误算成主实例显隐泄漏。
    trace?.write('resident_isolation_probe_begin');
    DesktopSceneRef? isolationScene;
    if (arguments.windowMode.includesFloating) {
      isolationScene = _publishResidentScene(
        sceneStore: sceneStore,
        instanceId: isolationInstanceId,
        revision: 1,
        label: 'isolation',
      );
      await floatingHost.applyFloatingSnapshot(
        instanceId: isolationInstanceId,
        snapshot: _residentFloatingSnapshot(
          sceneRef: isolationScene,
          revision: 1,
          visible: true,
        ),
      );
    }
    if (arguments.windowMode.includesSelector) {
      await selectorHost.showSelectorWindow(
        instanceId: isolationInstanceId,
        context: _residentSelectorContext(revision: 1),
      );
      await selectorHost.hideSelectorWindow(instanceId: isolationInstanceId);
    }
    _ensureResidentRefUnchanged(
      lifecycle: lifecycle,
      role: DesktopWindowRole.floating,
      instanceId: primaryInstanceId,
      expected: initialFloatingRef,
    );
    _ensureResidentRefUnchanged(
      lifecycle: lifecycle,
      role: DesktopWindowRole.selector,
      instanceId: primaryInstanceId,
      expected: initialSelectorRef,
    );
    if (arguments.windowMode.includesSelector) {
      await selectorHost.destroySelectorWindow(instanceId: isolationInstanceId);
    }
    if (arguments.windowMode.includesFloating) {
      await floatingHost.destroyFloatingWindow(instanceId: isolationInstanceId);
    }
    if (isolationScene != null) {
      sceneStore.releaseScene(isolationScene.sceneId);
    }
    _requireRegistryAbsent(
      lifecycle: lifecycle,
      instanceId: isolationInstanceId,
    );
    trace?.write('resident_isolation_probe_complete');

    // 两个常驻 engine 首次同时执行内容更新和显隐时，Flutter/Windows 会延迟创建
    // 线程、字体和消息通道资源。资源阈值要求使用预热后基线，因此先执行固定数量
    // 的真实联合操作，并恢复到与最终采样相同的可见状态。
    trace?.write('resident_operation_warmup_begin');
    for (
      int warmupIndex = 0;
      warmupIndex < _kResidentWarmupOperations;
      warmupIndex += 1
    ) {
      final int revision = warmupIndex + 2;
      final bool visible = warmupIndex.isEven;
      if (arguments.windowMode.includesFloating) {
        activePrimaryScene = _publishResidentScene(
          sceneStore: sceneStore,
          instanceId: primaryInstanceId,
          revision: revision,
          label: 'warmup-$warmupIndex',
        );
        await floatingHost.applyFloatingSnapshot(
          instanceId: primaryInstanceId,
          snapshot: _residentFloatingSnapshot(
            sceneRef: activePrimaryScene,
            revision: revision,
            visible: visible,
          ),
        );
      }
      if (arguments.windowMode.includesSelector) {
        await selectorHost.publishConfigRevision(revision: revision);
        if (visible) {
          await selectorHost.showSelectorWindow(
            instanceId: primaryInstanceId,
            context: _residentSelectorContext(revision: revision),
          );
        } else {
          await selectorHost.hideSelectorWindow(instanceId: primaryInstanceId);
        }
      }
      _ensureResidentRefUnchanged(
        lifecycle: lifecycle,
        role: DesktopWindowRole.floating,
        instanceId: primaryInstanceId,
        expected: initialFloatingRef,
      );
      _ensureResidentRefUnchanged(
        lifecycle: lifecycle,
        role: DesktopWindowRole.selector,
        instanceId: primaryInstanceId,
        expected: initialSelectorRef,
      );
    }
    final int baselineRevision = _kResidentWarmupOperations + 2;
    if (arguments.windowMode.includesFloating) {
      activePrimaryScene = _publishResidentScene(
        sceneStore: sceneStore,
        instanceId: primaryInstanceId,
        revision: baselineRevision,
        label: 'baseline',
      );
      await floatingHost.applyFloatingSnapshot(
        instanceId: primaryInstanceId,
        snapshot: _residentFloatingSnapshot(
          sceneRef: activePrimaryScene,
          revision: baselineRevision,
          visible: true,
        ),
      );
    }
    if (arguments.windowMode.includesSelector) {
      await selectorHost.publishConfigRevision(revision: baselineRevision);
      await selectorHost.showSelectorWindow(
        instanceId: primaryInstanceId,
        context: _residentSelectorContext(revision: baselineRevision),
      );
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    trace?.write('resident_operation_warmup_complete');
    final _ProcessResources baseline = _readProcessResources();
    trace?.write('resident_baseline_read');

    for (
      int operationIndex = 0;
      operationIndex < arguments.cycles;
      operationIndex += 1
    ) {
      final int revision = _kResidentWarmupOperations + operationIndex + 3;
      final bool visible = operationIndex.isEven;
      trace?.write('resident_operation=$operationIndex begin');
      if (arguments.windowMode.includesFloating) {
        activePrimaryScene = _publishResidentScene(
          sceneStore: sceneStore,
          instanceId: primaryInstanceId,
          revision: revision,
          label: 'refresh-$operationIndex',
        );
        final Stopwatch stopwatch = Stopwatch()..start();
        await floatingHost.applyFloatingSnapshot(
          instanceId: primaryInstanceId,
          snapshot: _residentFloatingSnapshot(
            sceneRef: activePrimaryScene,
            revision: revision,
            visible: visible,
          ),
        );
        stopwatch.stop();
        floatingOperationMs.add(stopwatch.elapsedMilliseconds);
      }
      if (arguments.windowMode.includesSelector) {
        final Stopwatch stopwatch = Stopwatch()..start();
        await selectorHost.publishConfigRevision(revision: revision);
        if (visible) {
          await selectorHost.showSelectorWindow(
            instanceId: primaryInstanceId,
            context: _residentSelectorContext(revision: revision),
          );
        } else {
          await selectorHost.hideSelectorWindow(instanceId: primaryInstanceId);
        }
        stopwatch.stop();
        selectorOperationMs.add(stopwatch.elapsedMilliseconds);
      }
      _ensureResidentRefUnchanged(
        lifecycle: lifecycle,
        role: DesktopWindowRole.floating,
        instanceId: primaryInstanceId,
        expected: initialFloatingRef,
      );
      _ensureResidentRefUnchanged(
        lifecycle: lifecycle,
        role: DesktopWindowRole.selector,
        instanceId: primaryInstanceId,
        expected: initialSelectorRef,
      );
      if (sceneStore.stats.sceneCount > 1) {
        throw StateError(
          '长驻刷新后 scene store 未保持有界: ${sceneStore.stats.sceneCount}',
        );
      }
      operationResources.add(_readProcessResources());
      trace?.write('resident_operation=$operationIndex complete');
    }

    // 最终采样恢复到与基线一致的可见状态，避免把显隐状态差异当作资源变化。
    if (arguments.windowMode.includesFloating) {
      await floatingHost.applyFloatingSnapshot(
        instanceId: primaryInstanceId,
        snapshot: _residentFloatingSnapshot(
          sceneRef: activePrimaryScene!,
          revision: _kResidentWarmupOperations + arguments.cycles + 3,
          visible: true,
        ),
      );
    }
    if (arguments.windowMode.includesSelector) {
      await selectorHost.publishConfigRevision(
        revision: _kResidentWarmupOperations + arguments.cycles + 3,
      );
      await selectorHost.showSelectorWindow(
        instanceId: primaryInstanceId,
        context: _residentSelectorContext(
          revision: _kResidentWarmupOperations + arguments.cycles + 3,
        ),
      );
    }
    trace?.write('resident_settle_begin');
    await Future<void>.delayed(Duration(seconds: arguments.settleSeconds));
    trace?.write('resident_settle_complete');
    final _ProcessResources finalResources = _readProcessResources();
    DesktopSelectorRuntimeDiagnostics? selectorDiagnostics;
    bool selectorDiagnosticsPass = true;
    if (arguments.windowMode.includesSelector) {
      // 资源最终采样前读取子 engine 的工作流快照，确认 30 秒 settle 后没有
      // active batch、底层请求、debounce timer、pending 请求或分页任务残留。
      selectorDiagnostics = await selectorHost.readSelectorRuntimeDiagnostics(
        instanceId: primaryInstanceId,
      );
      selectorDiagnosticsPass =
          selectorDiagnostics.isIdle &&
          selectorDiagnostics.searchBatchStartedCount > 0 &&
          selectorDiagnostics.searchBatchSettledCount ==
              selectorDiagnostics.searchBatchStartedCount &&
          selectorDiagnostics.sourceRequestStartedCount > 0 &&
          selectorDiagnostics.sourceRequestSettledCount ==
              selectorDiagnostics.sourceRequestStartedCount;
      trace?.write(
        'selector_diagnostics idle=${selectorDiagnostics.isIdle}'
        ' activeBatch=${selectorDiagnostics.hasActiveBatch}'
        ' activeRequest=${selectorDiagnostics.hasActiveRequest}'
        ' pending=${selectorDiagnostics.hasPendingRequest}'
        ' debounce=${selectorDiagnostics.hasDebounceTimer}'
        ' searching=${selectorDiagnostics.isSearching}'
        ' loadingMore=${selectorDiagnostics.isLoadingMore}'
        ' batches=${selectorDiagnostics.searchBatchSettledCount}/'
        '${selectorDiagnostics.searchBatchStartedCount}'
        ' sources=${selectorDiagnostics.sourceRequestSettledCount}/'
        '${selectorDiagnostics.sourceRequestStartedCount}',
      );
    }
    final int floatingP95 = _percentile95(floatingOperationMs);
    final int selectorP95 = _percentile95(selectorOperationMs);
    final int maxOperationMs = <int>[
      floatingOperationMs.fold<int>(0, math.max),
      selectorOperationMs.fold<int>(0, math.max),
    ].fold<int>(0, math.max);
    final int tailGrowth = _lastCyclePrivateGrowth(operationResources);
    final bool resourcesPass =
        finalResources.handleCount <= baseline.handleCount &&
        finalResources.gdiObjects <= baseline.gdiObjects &&
        finalResources.userObjects <= baseline.userObjects + 2 &&
        finalResources.privateBytes <=
            baseline.privateBytes + _kPrivateBytesSlack &&
        tailGrowth <= _kLastCycleGrowthLimit;
    final bool timingPass =
        floatingP95 <= 3000 && selectorP95 <= 3000 && maxOperationMs <= 15000;
    final bool lifecyclePass =
        _residentRefMatches(
          lifecycle: lifecycle,
          role: DesktopWindowRole.floating,
          instanceId: primaryInstanceId,
          expected: initialFloatingRef,
        ) &&
        _residentRefMatches(
          lifecycle: lifecycle,
          role: DesktopWindowRole.selector,
          instanceId: primaryInstanceId,
          expected: initialSelectorRef,
        );
    final bool sceneStorePass = sceneStore.stats.sceneCount <= 1;

    if (arguments.windowMode.includesSelector) {
      await selectorHost.destroySelectorWindow(instanceId: primaryInstanceId);
    }
    if (arguments.windowMode.includesFloating) {
      await floatingHost.destroyFloatingWindow(instanceId: primaryInstanceId);
    }
    if (activePrimaryScene != null) {
      sceneStore.releaseScene(activePrimaryScene.sceneId);
    }
    final bool registryCleared = _registryIsAbsent(
      lifecycle: lifecycle,
      instanceId: primaryInstanceId,
    );

    return <String, Object?>{
      'success':
          resourcesPass &&
          timingPass &&
          lifecyclePass &&
          sceneStorePass &&
          selectorDiagnosticsPass &&
          registryCleared,
      'scenario': arguments.scenario.name,
      'cycles': arguments.cycles,
      'warmupOperations': _kResidentWarmupOperations,
      'settleSeconds': arguments.settleSeconds,
      'windowMode': arguments.windowMode.name,
      'lifecycle': <String, Object?>{
        'floatingCreationCount': initialFloatingRef?.generation ?? 0,
        'selectorCreationCount': initialSelectorRef?.generation ?? 0,
        'sameGenerationAcrossOperations': lifecyclePass,
        'registryClearedAfterInstanceEnd': registryCleared,
      },
      'sceneStore': <String, Object?>{
        'bounded': sceneStorePass,
        'finalSceneCount': sceneStore.stats.sceneCount,
        'finalBytes': sceneStore.stats.totalBytes,
      },
      'selectorDiagnostics': selectorDiagnostics == null
          ? null
          : <String, Object?>{
              'available': selectorDiagnostics.available,
              'idle': selectorDiagnostics.isIdle,
              'hasActiveBatch': selectorDiagnostics.hasActiveBatch,
              'hasActiveRequest': selectorDiagnostics.hasActiveRequest,
              'hasPendingRequest': selectorDiagnostics.hasPendingRequest,
              'hasDebounceTimer': selectorDiagnostics.hasDebounceTimer,
              'isSearching': selectorDiagnostics.isSearching,
              'isLoadingMore': selectorDiagnostics.isLoadingMore,
              'searchBatchStartedCount':
                  selectorDiagnostics.searchBatchStartedCount,
              'searchBatchSettledCount':
                  selectorDiagnostics.searchBatchSettledCount,
              'sourceRequestStartedCount':
                  selectorDiagnostics.sourceRequestStartedCount,
              'sourceRequestSettledCount':
                  selectorDiagnostics.sourceRequestSettledCount,
            },
      'timing': <String, Object?>{
        'floatingP95Ms': floatingP95,
        'selectorP95Ms': selectorP95,
        'maxOperationMs': maxOperationMs,
      },
      'resources': <String, Object?>{
        'baseline': baseline.toJson(),
        'final': finalResources.toJson(),
        'privateBytesByOperation': operationResources
            .map((_ProcessResources value) => value.privateBytes)
            .toList(growable: false),
        'handleCountByOperation': operationResources
            .map((_ProcessResources value) => value.handleCount)
            .toList(growable: false),
        'gdiObjectsByOperation': operationResources
            .map((_ProcessResources value) => value.gdiObjects)
            .toList(growable: false),
        'userObjectsByOperation': operationResources
            .map((_ProcessResources value) => value.userObjects)
            .toList(growable: false),
        'last20AveragePrivateGrowthPerOperation': tailGrowth,
        'limits': <String, Object?>{
          'handleDelta': 0,
          'gdiDelta': 0,
          'userDelta': 2,
          'privateBytesDelta': _kPrivateBytesSlack,
          'last20AveragePrivateGrowthPerOperation': _kLastCycleGrowthLimit,
        },
      },
    };
  } on Object catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    trace?.write('resident_dart_failure error=$error');
  } finally {
    trace?.write('resident_selector_host_dispose_begin');
    await selectorHost.dispose();
    trace?.write('resident_selector_host_dispose_complete');
    trace?.write('resident_floating_host_dispose_begin');
    await floatingHost.dispose();
    trace?.write('resident_floating_host_dispose_complete');
    lifecycle.debugResetForTests();
    trace?.write('resident_lifecycle_reset');
  }

  return <String, Object?>{
    'success': false,
    'scenario': arguments.scenario.name,
    'cycles': arguments.cycles,
    'error': failure.toString(),
    'stack': failureStack.toString(),
  };
}

DesktopSceneRef _publishResidentScene({
  required DesktopInMemorySceneStore sceneStore,
  required int instanceId,
  required int revision,
  required String label,
}) {
  final String sceneId = '$instanceId:$revision';
  final String checksum = 'resident-$instanceId-$revision';
  final Uint8List bytes = const DesktopLyricsSceneCodec().encode(
    DesktopLyricsSceneDocument(
      mode: DesktopLyricsSceneMode.staticText,
      selectedLangs: const <String>['orig'],
      langOrder: const <String>['orig'],
      durationMs: null,
      staticDisplayLines: <String>['Windows resident smoke $label'],
    ),
  );
  sceneStore.putScene(sceneId, bytes, revision: revision, checksum: checksum);
  return DesktopSceneRef(
    sceneId: sceneId,
    sceneRevision: revision,
    checksum: checksum,
  );
}

DesktopFloatingWindowSnapshot _residentFloatingSnapshot({
  required DesktopSceneRef sceneRef,
  required int revision,
  required bool visible,
}) {
  return DesktopFloatingWindowSnapshot(
    session: DesktopFloatingSessionSnapshot(
      songId: 'resident-song',
      songTitle: 'Resident $revision',
      enabledLangs: const <String>['orig'],
      hasStaticDisplay: true,
      refreshRate: 60,
    ),
    contentRevision: revision,
    sceneRef: sceneRef,
    anchor: DesktopFloatingAnchorSnapshot(
      pluginPlaybackTimeMs: revision * 100,
      pluginSendTimeMs: revision * 100,
      hostReceivedAtMs: DateTime.now().millisecondsSinceEpoch,
      isPlaying: true,
      syncRevision: revision,
      sceneId: sceneRef.sceneId,
      songToken: 'resident-song',
    ),
    flags: DesktopFloatingWindowFlags(visible: visible),
  );
}

DesktopSelectorWindowContext _residentSelectorContext({required int revision}) {
  return DesktopSelectorWindowContext(
    keyword: 'Resident $revision',
    langs: const <String>['orig'],
    offsetMs: revision,
    refreshToken: revision,
  );
}

void _requireResidentRef({
  required bool enabled,
  required DesktopWindowRef? ref,
  required DesktopWindowRole role,
}) {
  if (enabled && ref == null) {
    throw StateError('${role.name} 长驻窗口未注册');
  }
  if (ref != null && ref.generation != 1) {
    throw StateError(
      '${role.name} 长驻窗口首次创建 generation=${ref.generation}，预期为 1',
    );
  }
}

void _ensureResidentRefUnchanged({
  required DesktopWindowLifecycleRegistryController lifecycle,
  required DesktopWindowRole role,
  required int instanceId,
  required DesktopWindowRef? expected,
}) {
  if (!_residentRefMatches(
    lifecycle: lifecycle,
    role: role,
    instanceId: instanceId,
    expected: expected,
  )) {
    final DesktopWindowRef? actual = lifecycle.currentRef(
      role: role,
      instanceId: instanceId,
    );
    throw StateError(
      '${role.name} 显隐过程中发生重复创建: '
      'expected=${expected?.generationKey} actual=${actual?.generationKey}',
    );
  }
}

bool _residentRefMatches({
  required DesktopWindowLifecycleRegistryController lifecycle,
  required DesktopWindowRole role,
  required int instanceId,
  required DesktopWindowRef? expected,
}) {
  if (expected == null) {
    return true;
  }
  return lifecycle
          .currentRef(role: role, instanceId: instanceId)
          ?.generationKey ==
      expected.generationKey;
}

void _requireRegistryAbsent({
  required DesktopWindowLifecycleRegistryController lifecycle,
  required int instanceId,
}) {
  if (!_registryIsAbsent(lifecycle: lifecycle, instanceId: instanceId)) {
    throw StateError('实例销毁后生命周期注册表未归零: instance=$instanceId');
  }
}

bool _registryIsAbsent({
  required DesktopWindowLifecycleRegistryController lifecycle,
  required int instanceId,
}) {
  return lifecycle.currentRef(
            role: DesktopWindowRole.floating,
            instanceId: instanceId,
          ) ==
          null &&
      lifecycle.currentRef(
            role: DesktopWindowRole.selector,
            instanceId: instanceId,
          ) ==
          null;
}

Future<_CycleTiming> _runCycle({
  required int cycleIndex,
  required _SmokeWindowMode windowMode,
  required DesktopInMemorySceneStore sceneStore,
  required DesktopMultiWindowFloatingWindowHost floatingHost,
  required DesktopMultiWindowSelectorWindowHost selectorHost,
  required DesktopWindowLifecycleRegistryController lifecycle,
  _SmokeTrace? trace,
}) async {
  final int instanceId = cycleIndex + 1000;
  final String sceneId = '$instanceId:1';
  const String checksum = 'windows-multi-window-smoke';
  final Uint8List sceneBytes = const DesktopLyricsSceneCodec().encode(
    DesktopLyricsSceneDocument(
      mode: DesktopLyricsSceneMode.staticText,
      selectedLangs: const <String>['orig'],
      langOrder: const <String>['orig'],
      durationMs: null,
      staticDisplayLines: <String>['Windows multi-window smoke $cycleIndex'],
    ),
  );
  trace?.write('cycle=$cycleIndex scene_put_begin');
  sceneStore.putScene(sceneId, sceneBytes, revision: 1, checksum: checksum);
  trace?.write('cycle=$cycleIndex scene_put_complete');

  int floatingReadyMs = 0;
  if (windowMode.includesFloating) {
    final Stopwatch floatingStopwatch = Stopwatch()..start();
    trace?.write('cycle=$cycleIndex floating_apply_begin');
    await floatingHost.applyFloatingSnapshot(
      instanceId: instanceId,
      snapshot: DesktopFloatingWindowSnapshot(
        session: DesktopFloatingSessionSnapshot(
          songId: 'smoke-$cycleIndex',
          songTitle: 'Smoke $cycleIndex',
          enabledLangs: const <String>['orig'],
          hasStaticDisplay: true,
          refreshRate: 60,
        ),
        contentRevision: 1,
        sceneRef: DesktopSceneRef(
          sceneId: sceneId,
          sceneRevision: 1,
          checksum: checksum,
        ),
        flags: const DesktopFloatingWindowFlags(visible: true),
      ),
    );
    floatingStopwatch.stop();
    floatingReadyMs = floatingStopwatch.elapsedMilliseconds;
    trace?.write('cycle=$cycleIndex floating_apply_complete');
  }

  int selectorReadyMs = 0;
  if (windowMode.includesSelector) {
    final Stopwatch selectorStopwatch = Stopwatch()..start();
    trace?.write('cycle=$cycleIndex selector_show_begin');
    await selectorHost.showSelectorWindow(
      instanceId: instanceId,
      context: DesktopSelectorWindowContext(
        keyword: 'Smoke $cycleIndex',
        langs: const <String>['orig'],
        offsetMs: 0,
        refreshToken: cycleIndex + 1,
      ),
    );
    selectorStopwatch.stop();
    selectorReadyMs = selectorStopwatch.elapsedMilliseconds;
    trace?.write('cycle=$cycleIndex selector_show_complete');

    trace?.write('cycle=$cycleIndex selector_destroy_begin');
    await selectorHost.destroySelectorWindow(instanceId: instanceId);
    trace?.write('cycle=$cycleIndex selector_destroy_complete');
  }
  if (windowMode.includesFloating) {
    trace?.write('cycle=$cycleIndex floating_destroy_begin');
    await floatingHost.destroyFloatingWindow(instanceId: instanceId);
    trace?.write('cycle=$cycleIndex floating_destroy_complete');
  }
  sceneStore.releaseScene(sceneId);
  trace?.write('cycle=$cycleIndex scene_released');
  if (lifecycle.currentRef(
        role: DesktopWindowRole.floating,
        instanceId: instanceId,
      ) !=
      null) {
    throw StateError('浮窗生命周期未回收: instance=$instanceId');
  }
  if (lifecycle.currentRef(
        role: DesktopWindowRole.selector,
        instanceId: instanceId,
      ) !=
      null) {
    throw StateError('选择器生命周期未回收: instance=$instanceId');
  }
  return _CycleTiming(
    floatingReadyMs: floatingReadyMs,
    selectorReadyMs: selectorReadyMs,
  );
}

int _percentile95(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  final List<int> sorted = List<int>.from(values)..sort();
  final int index = ((sorted.length - 1) * 0.95).ceil();
  return sorted[index];
}

int _lastCyclePrivateGrowth(List<_ProcessResources> resources) {
  if (resources.length < 2) {
    return 0;
  }
  final int start = math.max(0, resources.length - 20);
  final List<_ProcessResources> tail = resources.sublist(start);
  if (tail.length < 2) {
    return 0;
  }
  return ((tail.last.privateBytes - tail.first.privateBytes) /
          (tail.length - 1))
      .round();
}

_ProcessResources _readProcessResources() {
  final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
  final DynamicLibrary user32 = DynamicLibrary.open('user32.dll');
  final _GetCurrentProcessDart getCurrentProcess = kernel32
      .lookupFunction<_GetCurrentProcessNative, _GetCurrentProcessDart>(
        'GetCurrentProcess',
      );
  final _GetProcessHandleCountDart getProcessHandleCount = kernel32
      .lookupFunction<_GetProcessHandleCountNative, _GetProcessHandleCountDart>(
        'GetProcessHandleCount',
      );
  final _GetGuiResourcesDart getGuiResources = user32
      .lookupFunction<_GetGuiResourcesNative, _GetGuiResourcesDart>(
        'GetGuiResources',
      );
  final int process = getCurrentProcess();
  final Pointer<Uint32> handleCount = calloc<Uint32>();
  final Pointer<PROCESS_MEMORY_COUNTERS> memory =
      calloc<PROCESS_MEMORY_COUNTERS>();
  try {
    if (getProcessHandleCount(process, handleCount) == 0) {
      throw StateError('GetProcessHandleCount 失败');
    }
    memory.ref.cb = sizeOf<PROCESS_MEMORY_COUNTERS>();
    final Win32Result<bool> memoryResult = GetProcessMemoryInfo(
      GetCurrentProcess(),
      memory,
      memory.ref.cb,
    );
    if (!memoryResult.value) {
      throw StateError('GetProcessMemoryInfo 失败: ${memoryResult.error}');
    }
    return _ProcessResources(
      handleCount: handleCount.value,
      gdiObjects: getGuiResources(process, _kGdiObjects),
      userObjects: getGuiResources(process, _kUserObjects),
      workingSetBytes: memory.ref.WorkingSetSize,
      privateBytes: memory.ref.PagefileUsage,
    );
  } finally {
    calloc.free(handleCount);
    calloc.free(memory);
  }
}

class _SmokeArguments {
  const _SmokeArguments({
    required this.cycles,
    required this.settleSeconds,
    required this.reportPath,
    required this.tracePath,
    required this.windowMode,
    required this.scenario,
  });

  final int cycles;
  final int settleSeconds;
  final String reportPath;
  final String? tracePath;
  final _SmokeWindowMode windowMode;
  final _SmokeScenario scenario;

  factory _SmokeArguments.parse(List<String> args) {
    int cycles = 100;
    int settleSeconds = 10;
    String reportPath = 'build/windows_multi_window_smoke/report.json';
    String? tracePath;
    _SmokeWindowMode windowMode = _SmokeWindowMode.both;
    _SmokeScenario scenario = _SmokeScenario.resident;
    for (final String arg in args) {
      if (arg.startsWith('--cycles=')) {
        cycles = int.parse(arg.substring('--cycles='.length));
      } else if (arg.startsWith('--settle-seconds=')) {
        settleSeconds = int.parse(arg.substring('--settle-seconds='.length));
      } else if (arg.startsWith('--report=')) {
        reportPath = arg.substring('--report='.length);
      } else if (arg.startsWith('--trace=')) {
        tracePath = arg.substring('--trace='.length);
      } else if (arg.startsWith('--window-mode=')) {
        windowMode = _SmokeWindowMode.parse(
          arg.substring('--window-mode='.length),
        );
      } else if (arg.startsWith('--scenario=')) {
        scenario = _SmokeScenario.parse(arg.substring('--scenario='.length));
      }
    }
    if (cycles <= 0) {
      throw ArgumentError.value(cycles, 'cycles', '必须大于 0');
    }
    if (settleSeconds < 0) {
      throw ArgumentError.value(settleSeconds, 'settleSeconds', '不能小于 0');
    }
    return _SmokeArguments(
      cycles: cycles,
      settleSeconds: settleSeconds,
      reportPath: reportPath,
      tracePath: tracePath,
      windowMode: windowMode,
      scenario: scenario,
    );
  }
}

enum _SmokeScenario {
  resident,
  rebuild;

  static _SmokeScenario parse(String value) {
    for (final _SmokeScenario scenario in values) {
      if (scenario.name == value) {
        return scenario;
      }
    }
    throw ArgumentError.value(value, 'scenario', '必须为 resident 或 rebuild');
  }
}

enum _SmokeWindowMode {
  both,
  floating,
  selector;

  bool get includesFloating => this == both || this == floating;

  bool get includesSelector => this == both || this == selector;

  static _SmokeWindowMode parse(String value) {
    for (final _SmokeWindowMode mode in values) {
      if (mode.name == value) {
        return mode;
      }
    }
    throw ArgumentError.value(
      value,
      'windowMode',
      '必须为 both、floating 或 selector',
    );
  }
}

class _SmokeTrace {
  const _SmokeTrace(this.file);

  final File file;

  void reset() {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('', flush: true);
  }

  void write(String message) {
    // 原生崩溃不会执行 Dart finally，因此诊断检查点必须同步刷新到磁盘。
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

class _CycleTiming {
  const _CycleTiming({
    required this.floatingReadyMs,
    required this.selectorReadyMs,
  });

  final int floatingReadyMs;
  final int selectorReadyMs;
}

class _ProcessResources {
  const _ProcessResources({
    required this.handleCount,
    required this.gdiObjects,
    required this.userObjects,
    required this.workingSetBytes,
    required this.privateBytes,
  });

  final int handleCount;
  final int gdiObjects;
  final int userObjects;
  final int workingSetBytes;
  final int privateBytes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'handleCount': handleCount,
      'gdiObjects': gdiObjects,
      'userObjects': userObjects,
      'workingSetBytes': workingSetBytes,
      'privateBytes': privateBytes,
    };
  }
}
