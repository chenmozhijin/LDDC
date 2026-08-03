import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';
import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_floating_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_panel_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_selector_effect_executor.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_coordinator.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_launch_arguments.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_runtime_host_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_session_reducer.dart';

import 'support/integration_reporter.dart';

void main() {
  test('desktop lyrics protocol: 进程内 TCP/IPC 实例创建与回收', () async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'desktop_lyrics_protocol',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'desktop_lyrics_protocol',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    final Directory tempDir = await Directory.systemTemp.createTemp(
      'lddc_desktop_integration_',
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    AppStoragePaths createPaths() {
      return AppStoragePaths(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        windowsKnownFolderResolver: (String folderId) async => tempDir.path,
        applicationSupportDirectoryResolver: () async => tempDir,
        applicationCacheDirectoryResolver: () async => tempDir,
        applicationDocumentsDirectoryResolver: () async => tempDir,
        libraryDirectoryResolver: () async => tempDir,
      );
    }

    DesktopServiceInfoWriter createInfoWriter() {
      return DesktopServiceInfoWriter(
        paths: createPaths(),
        commandProvider: () =>
            const DesktopServiceLaunchCommand(executable: r'C:\LDDC\lddc.exe'),
      );
    }

    final _SharedSingletonBootstrapPort sharedPort =
        _SharedSingletonBootstrapPort();
    DesktopServiceBootstrap? primaryBootstrap;
    DesktopServiceCoordinator? primaryCoordinator;
    DesktopServiceHost? primaryHost;

    final _CallbackProcessLauncher launcher = _CallbackProcessLauncher(
      onLaunch: (DesktopServiceLaunchCommand command) async {
        primaryBootstrap = DesktopServiceBootstrap(
          infoWriter: createInfoWriter(),
          singletonPort: sharedPort,
          exitHandler: (_) {},
        );
        final DesktopServiceEntrypointResult primaryResult =
            await primaryBootstrap!.prepareEntrypoint(
              windowLaunch: const DesktopWindowLaunchArguments.main(),
              launchArguments: const DesktopServiceLaunchArguments(
                notShow: true,
              ),
            );
        expect(primaryResult.shouldRunApp, isTrue);

        const DesktopWindowBackend backend = DesktopWindowBackendPorts(
          floatingHost: DesktopNoopFloatingWindowHost(),
          selectorHost: DesktopNoopSelectorWindowHost(),
          panelHost: DesktopNoopPanelWindowHost(),
        );
        primaryCoordinator = DesktopServiceCoordinator(
          reducer: DesktopSessionReducer(),
          sceneStore: DesktopInMemorySceneStore(),
          floatingEffectExecutor: DesktopFloatingEffectExecutor(
            windowBackend: backend,
          ),
          panelEffectExecutor: DesktopPanelEffectExecutor(
            windowBackend: backend,
          ),
          selectorEffectExecutor: DesktopSelectorEffectExecutor(
            windowBackend: backend,
          ),
        );
        primaryHost = DesktopServiceHost(
          coordinator: primaryCoordinator!,
          reducer: DesktopSessionReducer(),
          bootstrap: primaryBootstrap!,
        );
        await primaryHost!.ensureStarted();
      },
    );

    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: sharedPort,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(() async {
      await primaryHost?.dispose();
      await primaryCoordinator?.dispose();
      await primaryBootstrap?.dispose();
      await bootstrap.dispose();
    });

    final DesktopServiceEntrypointResult result = await reporter.runStep(
      'get_service_port',
      () => bootstrap.prepareEntrypoint(
        windowLaunch: const DesktopWindowLaunchArguments.main(),
        launchArguments: const DesktopServiceLaunchArguments(
          getServicePort: true,
        ),
      ),
    );
    expect(result.shouldRunApp, isFalse);
    expect(primaryHost, isNotNull);

    final Socket socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      int.parse(result.stdoutLine!),
    );
    addTearDown(socket.destroy);
    final _TestSocketFrameReader reader = _TestSocketFrameReader(socket);
    addTearDown(reader.dispose);
    const DesktopIpcFramer framer = DesktopIpcFramer();

    // IPC 协议中的实例编号是整数；保持强类型可避免删除步骤把编号误当成文本，
    // 也确保 coordinator 查询与线上消息编解码使用完全相同的类型。
    final int instanceId = await reporter.runStep(
      'hello_and_new_instance',
      () async {
        socket.add(
          framer.encodeJson(
            const DesktopHelloMessage(
              pid: 4321,
              availableTaskNames: <String>['play', 'pause', 'stop'],
              clientInfo: DesktopClientInfo(
                name: 'integration',
                version: '1.0',
              ),
            ).toJson(),
          ),
        );
        await socket.flush();
        final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
            .decodeInstanceAck(await reader.nextFrame());
        expect(
          primaryCoordinator
              ?.sessionFor(ack.instanceId)
              ?.lyricsRuntime
              .staticDisplayLines,
          kDesktopServiceWelcomeLines,
        );
        return ack.instanceId;
      },
    );

    await reporter.runStep('delete_instance', () async {
      socket.add(
        framer.encodeJson(
          DesktopSimpleTaskMessage(
            task: DesktopIpcTask.delInstance,
            instanceId: instanceId,
          ).toJson(),
        ),
      );
      await socket.flush();
      final DateTime deadline = DateTime.now().add(runtime.desktopStepTimeout);
      while (DateTime.now().isBefore(deadline)) {
        if (primaryCoordinator?.sessionFor(instanceId) == null) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        primaryCoordinator?.sessionFor(instanceId),
        isNull,
        reason: 'del_instance 后实例必须从 coordinator 中最终移除',
      );
    });

    await reporter.writeSummary(
      extra: <String, Object?>{'port': result.stdoutLine},
    );
  });
}

class _CallbackProcessLauncher implements DesktopServiceProcessLauncher {
  _CallbackProcessLauncher({required this.onLaunch});

  final Future<void> Function(DesktopServiceLaunchCommand command) onLaunch;

  @override
  Future<void> launchBackgroundService(
    DesktopServiceLaunchCommand command,
  ) async {
    await onLaunch(command);
  }
}

class _SharedSingletonBootstrapPort implements DesktopSingletonBootstrapPort {
  bool _primaryHeld = false;
  DesktopServiceSingletonRequestHandler? _handler;

  @override
  Future<void> close() async {
    _handler = null;
    _primaryHeld = false;
  }

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async {
    if (_primaryHeld) {
      return DesktopPrimaryClaimResult.existingPrimary;
    }
    _primaryHeld = true;
    _handler = onRequest;
    return DesktopPrimaryClaimResult.primary;
  }

  @override
  Future<bool> hasPrimaryInstance() async => _primaryHeld;

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final DesktopServiceSingletonRequestHandler? handler = _handler;
    if (handler == null) {
      return null;
    }
    return handler(message);
  }

  @override
  Future<void> setServicePort(int port) async {}

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_handler != null) {
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
}

class _TestSocketFrameReader {
  _TestSocketFrameReader(Socket socket)
    : _socket = socket,
      _subscription = socket.listen(null) {
    _subscription
      ..onData(_handleChunk)
      ..onDone(_closePending)
      ..onError((Object error, StackTrace stackTrace) => _closePending());
  }

  final Socket _socket;
  final DesktopIpcFrameBuffer _buffer = DesktopIpcFrameBuffer();
  final List<Map<String, Object?>> _pendingFrames = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _waiters =
      <Completer<Map<String, Object?>>>[];
  final StreamSubscription<List<int>> _subscription;

  void _handleChunk(List<int> chunk) {
    final List<Uint8List> frames = _buffer.addChunk(chunk);
    for (final Uint8List frame in frames) {
      final Object? payload = jsonDecode(utf8.decode(frame));
      final Map<String, Object?> normalized = Map<String, Object?>.from(
        payload! as Map<Object?, Object?>,
      );
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete(normalized);
      } else {
        _pendingFrames.add(normalized);
      }
    }
  }

  void _closePending() {
    while (_waiters.isNotEmpty) {
      _waiters
          .removeAt(0)
          .completeError(StateError('socket closed before frame received'));
    }
  }

  Future<Map<String, Object?>> nextFrame() {
    if (_pendingFrames.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_pendingFrames.removeAt(0));
    }
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}
