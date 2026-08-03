// ignore_for_file: avoid_slow_async_io
// 桌面服务互操作测试覆盖异步路径写入，临时文件检查保持与生产实现一致。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../support/desktop_service_test_support.dart';

void main() {
  group('Desktop service interop', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lddc_service_interop_');
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      if (await tempDir.exists()) {
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

    test(
      '--get-service-port -> TCP -> live routing -> control command 全链路可跑通',
      () async {
        final _SharedSingletonBootstrapPort sharedPort =
            _SharedSingletonBootstrapPort();
        DesktopServiceBootstrap? primaryBootstrap;
        DesktopServiceCoordinator? primaryCoordinator;
        DesktopServiceHost? primaryHost;
        final _CallbackProcessLauncher launcher = _CallbackProcessLauncher(
          onLaunch: (DesktopServiceLaunchCommand command) async {
            expect(command.toCommandLine(), r'"C:\LDDC\lddc.exe"');

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
            expect(primaryBootstrap!.isPrimaryInstance, isTrue);
            expect(primaryBootstrap!.shouldStartHidden, isTrue);

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

        final DesktopServiceEntrypointResult result = await bootstrap
            .prepareEntrypoint(
              windowLaunch: const DesktopWindowLaunchArguments.main(),
              launchArguments: const DesktopServiceLaunchArguments(
                getServicePort: true,
              ),
            );

        expect(result.shouldRunApp, isFalse);
        expect(result.exitCode, 0);
        expect(primaryHost, isNotNull);
        expect(result.stdoutLine, '${primaryHost!.port}');

        final File infoFile = await createPaths().resolveInfoFile();
        expect(await infoFile.exists(), isTrue);
        final Map<String, Object?> infoPayload =
            jsonDecode(await infoFile.readAsString()) as Map<String, Object?>;
        expect(infoPayload['Command Line'], r'"C:\LDDC\lddc.exe"');

        final Socket socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          int.parse(result.stdoutLine!),
        );
        addTearDown(socket.destroy);
        final TestSocketFrameReader reader = TestSocketFrameReader(socket);
        addTearDown(reader.dispose);
        final DesktopIpcFramer framer = const DesktopIpcFramer();

        socket.add(
          framer.encodeJson(
            const DesktopHelloMessage(
              pid: 4321,
              availableTaskNames: <String>['play', 'pause', 'stop'],
              clientInfo: DesktopClientInfo(name: 'foo_lddc', version: '1.0'),
            ).toJson(),
          ),
        );
        await socket.flush();

        final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
            .decodeInstanceAck(await reader.nextFrame());
        expect(
          primaryCoordinator?.sessionFor(ack.instanceId)?.client.name,
          'foo_lddc',
        );
        expect(
          primaryCoordinator
              ?.sessionFor(ack.instanceId)
              ?.lyricsRuntime
              .staticDisplayLines,
          kDesktopServiceWelcomeLines,
        );

        socket.add(
          framer.encodeJson(
            DesktopChangMusicMessage(
              instanceId: ack.instanceId,
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              durationMs: 180000,
              path: r'D:\music\song.flac',
              track: 1,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.start,
              instanceId: ack.instanceId,
              playbackTimeMs: 5000,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.pause,
              instanceId: ack.instanceId,
              playbackTimeMs: 5200,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.proceed,
              instanceId: ack.instanceId,
              playbackTimeMs: 5300,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.sync,
              instanceId: ack.instanceId,
              playbackTimeMs: 5400,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopPanelCreateMessage(
              instanceId: ack.instanceId,
              panelId: 7,
              hostWindowId: 99,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopPanelSurfaceUpdateMessage(
              instanceId: ack.instanceId,
              panelId: 7,
              width: 640,
              height: 240,
              sizeSpace: DesktopPanelSizeSpace.hostPhysicalPx,
              visible: true,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopPanelSurfaceUpdateMessage(
              instanceId: ack.instanceId,
              panelId: 7,
              width: 640,
              height: 240,
              sizeSpace: DesktopPanelSizeSpace.hostPhysicalPx,
              visible: false,
            ).toJson(),
          ),
        );
        socket.add(
          framer.encodeJson(
            DesktopPanelDestroyMessage(
              instanceId: ack.instanceId,
              panelId: 7,
            ).toJson(),
          ),
        );
        await socket.flush();

        await waitForCondition(() {
          final session = primaryCoordinator?.sessionFor(ack.instanceId);
          return session != null &&
              session.lyricsRuntime.song?.title == 'Song' &&
              session.playbackSync.pluginPlaybackTimeMs == 5400 &&
              session.isPlaying &&
              !session.panels.containsKey(7);
        });

        final bool sent = await primaryHost!.sendControlCommand(
          instanceId: ack.instanceId,
          task: DesktopControlCommandTask.play,
        );
        expect(sent, isTrue);
        final DesktopControlCommandMessage controlMessage =
            const DesktopIpcMessageCodec().decodeControlCommand(
              await reader.nextFrame(),
            );
        expect(controlMessage.task, DesktopControlCommandTask.play);

        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.stop,
              instanceId: ack.instanceId,
            ).toJson(),
          ),
        );
        await socket.flush();

        await waitForCondition(() {
          final session = primaryCoordinator?.sessionFor(ack.instanceId);
          return session != null &&
              !session.isPlaying &&
              session.playbackSync.pluginPlaybackTimeMs == 0 &&
              session.playbackSync.task == DesktopIpcTask.stop &&
              session.playbackSync.syncRevision > 0 &&
              session.lyricsRuntime.song == null &&
              session.lyricsRuntime.sceneRef == null &&
              session.lyricsRuntime.staticDisplayLines.isEmpty;
        });

        socket.add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.delInstance,
              instanceId: ack.instanceId,
            ).toJson(),
          ),
        );
        await socket.flush();

        await waitForCondition(
          () => primaryCoordinator?.sessionFor(ack.instanceId) == null,
        );
        expect(primaryCoordinator?.sessionFor(ack.instanceId), isNull);
        expect(sharedPort.requests, equals(const <String>['get_service_port']));
      },
    );
  });
}

class _CallbackProcessLauncher implements DesktopServiceProcessLauncher {
  _CallbackProcessLauncher({required this.onLaunch});

  final Future<void> Function(DesktopServiceLaunchCommand command) onLaunch;
  final List<DesktopServiceLaunchCommand> commands =
      <DesktopServiceLaunchCommand>[];

  @override
  Future<void> launchBackgroundService(
    DesktopServiceLaunchCommand command,
  ) async {
    commands.add(command);
    await onLaunch(command);
  }
}

class _SharedSingletonBootstrapPort implements DesktopSingletonBootstrapPort {
  bool _primaryHeld = false;
  DesktopServiceSingletonRequestHandler? _handler;
  int? servicePort;
  final List<String> requests = <String>[];

  @override
  Future<void> close() async {
    _handler = null;
    servicePort = null;
    _primaryHeld = false;
  }

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requests.add(message);
    final handler = _handler;
    if (handler == null) {
      return null;
    }
    return await handler(message);
  }

  @override
  Future<void> setServicePort(int port) async {
    servicePort = port;
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
