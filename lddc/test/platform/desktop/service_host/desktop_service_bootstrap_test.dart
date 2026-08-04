// ignore_for_file: avoid_slow_async_io
// 服务启动测试会检查 info.json 的异步写入结果，文件状态断言保持非阻塞口径。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:path/path.dart' as p;

import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap_io.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_launch_arguments.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lddc_service_bootstrap_');
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  AppStoragePaths createPaths({bool? isWindows, bool? isLinux, bool? isMacOS}) {
    return AppStoragePaths(
      // 文件并发测试必须使用当前宿主的路径分隔规则；Windows 路径纯语义由
      // AppStoragePaths 的独立单测覆盖，不能在 Linux 上把反斜杠当真实目录。
      isWindows: isWindows ?? Platform.isWindows,
      isLinux: isLinux ?? Platform.isLinux,
      isMacOS: isMacOS ?? Platform.isMacOS,
      windowsKnownFolderResolver: (String folderId) async => tempDir.path,
      linuxConfigHomeResolver: () async => tempDir,
      linuxDataHomeResolver: () async => tempDir,
      linuxCacheHomeResolver: () async => tempDir,
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

  test('macOS 单实例 endpoint 与 lock 使用稳定应用数据目录', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );

    final File endpoint = await runtimePaths.resolveMacOsControlEndpointFile();
    final File lock = await runtimePaths.resolveMacOsControlLockFile();

    expect(
      endpoint.path.replaceAll('\\', '/'),
      '${tempDir.path.replaceAll('\\', '/')}/Application Support/LDDC/runtime/control.json',
    );
    expect(
      lock.path.replaceAll('\\', '/'),
      '${tempDir.path.replaceAll('\\', '/')}/Application Support/LDDC/runtime/control.lock',
    );
  });

  test('macOS 取得锁后延迟发布业务端口并校验私有控制令牌', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );
    final DesktopMacOsSingletonBootstrapPort port =
        DesktopMacOsSingletonBootstrapPort(
          runtimePaths: runtimePaths,
          tokenFactory: () => 'a' * 64,
        );
    addTearDown(port.close);
    int requestCount = 0;

    expect(
      await port.claimPrimary(
        onRequest: (String message) {
          requestCount += 1;
          return message == 'get_service_port' ? '23333' : 'unknown';
        },
      ),
      DesktopPrimaryClaimResult.primary,
    );
    final File endpointFile = await runtimePaths
        .resolveMacOsControlEndpointFile();
    expect(await endpointFile.exists(), isFalse);
    expect(await port.hasPrimaryInstance(), isTrue);

    await port.setServicePort(23333);
    final Map<String, Object?> endpoint =
        jsonDecode(await endpointFile.readAsString()) as Map<String, Object?>;
    expect(endpoint.keys, unorderedEquals(<String>['schema', 'port', 'token']));
    expect(endpoint['schema'], 'lddc.macos_singleton_control');
    expect(endpoint['port'], 23333);
    expect(endpoint['token'], 'a' * 64);
    final DesktopPrivateControlFrameResult authenticated = await port
        .handlePrivateControlFrame(<String, Object?>{
          '_lddcControl': 1,
          'token': 'a' * 64,
          'command': 'get_service_port',
        }, encodedLength: 128);
    expect(authenticated.action, DesktopPrivateControlFrameAction.respond);
    expect(authenticated.response, <String, Object?>{
      '_lddcControl': 1,
      'ok': true,
      'port': 23333,
    });
    expect(requestCount, 1);

    final DesktopPrivateControlFrameResult unauthenticated = await port
        .handlePrivateControlFrame(<String, Object?>{
          '_lddcControl': 1,
          'token': 'b' * 64,
          'command': 'get_service_port',
        }, encodedLength: 128);
    expect(
      unauthenticated.action,
      DesktopPrivateControlFrameAction.rejectAndClose,
    );
    expect(requestCount, 1);

    final DesktopPrivateControlFrameResult oversized = await port
        .handlePrivateControlFrame(<String, Object?>{
          '_lddcControl': 1,
          'token': 'a' * 64,
          'command': 'show',
        }, encodedLength: 4097);
    expect(oversized.action, DesktopPrivateControlFrameAction.rejectAndClose);
    expect(requestCount, 1);

    await port.close();
    expect(await endpointFile.exists(), isFalse);
    expect(
      await (await runtimePaths.resolveMacOsControlLockFile()).exists(),
      isTrue,
    );
  });

  test('macOS 重复 claim 更新处理器且第二实例发现现有 primary', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );
    final DesktopMacOsSingletonBootstrapPort primary =
        DesktopMacOsSingletonBootstrapPort(
          runtimePaths: runtimePaths,
          tokenFactory: () => 'c' * 64,
        );
    final DesktopMacOsSingletonBootstrapPort secondary =
        DesktopMacOsSingletonBootstrapPort(runtimePaths: runtimePaths);
    addTearDown(primary.close);
    addTearDown(secondary.close);

    expect(
      await primary.claimPrimary(onRequest: (_) => 'first'),
      DesktopPrimaryClaimResult.primary,
    );
    expect(
      await primary.claimPrimary(onRequest: (_) => 'updated'),
      DesktopPrimaryClaimResult.primary,
    );
    expect(await secondary.hasPrimaryInstance(), isTrue);
    expect(
      await secondary.claimPrimary(onRequest: (_) => 'unused'),
      DesktopPrimaryClaimResult.existingPrimary,
    );
    final DesktopPrivateControlFrameResult response = await primary
        .handlePrivateControlFrame(<String, Object?>{
          '_lddcControl': 1,
          'token': 'c' * 64,
          'command': 'show',
        }, encodedLength: 128);
    expect(response.action, DesktopPrivateControlFrameAction.respond);
    expect(response.response, <String, Object?>{'_lddcControl': 1, 'ok': true});
  });

  test('macOS 关闭后拒绝 claim 且等待不存在的 primary 会有界返回', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );
    final DesktopMacOsSingletonBootstrapPort port =
        DesktopMacOsSingletonBootstrapPort(runtimePaths: runtimePaths);

    expect(
      await port.waitUntilPrimaryAvailable(
        timeout: const Duration(milliseconds: 30),
        pollInterval: const Duration(milliseconds: 5),
      ),
      isFalse,
    );
    await port.close();
    expect(
      () => port.claimPrimary(onRequest: (_) => 'unused'),
      throwsStateError,
    );
  });

  test('macOS 非法控制令牌初始化失败后释放文件锁', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );
    final DesktopMacOsSingletonBootstrapPort invalid =
        DesktopMacOsSingletonBootstrapPort(
          runtimePaths: runtimePaths,
          tokenFactory: () => 'not-a-32-byte-token',
        );

    await expectLater(
      invalid.claimPrimary(onRequest: (_) => 'unused'),
      throwsStateError,
    );

    // 若失败路径遗留文件锁，后续合法实例会被误判为已有 primary。
    final DesktopMacOsSingletonBootstrapPort recovered =
        DesktopMacOsSingletonBootstrapPort(
          runtimePaths: runtimePaths,
          tokenFactory: () => 'd' * 64,
        );
    addTearDown(recovered.close);
    expect(
      await recovered.claimPrimary(onRequest: (_) => 'recovered'),
      DesktopPrimaryClaimResult.primary,
    );
  });

  test('macOS 损坏 endpoint 不代表存活 primary 且取得锁后会清理', () async {
    final DesktopServiceRuntimePaths runtimePaths = DesktopServiceRuntimePaths(
      paths: createPaths(isWindows: false, isLinux: false, isMacOS: true),
    );
    final File endpoint = await runtimePaths.resolveMacOsControlEndpointFile();
    await endpoint.parent.create(recursive: true);
    await endpoint.writeAsString('{"schema":"broken"}');
    final DesktopMacOsSingletonBootstrapPort port =
        DesktopMacOsSingletonBootstrapPort(runtimePaths: runtimePaths);
    addTearDown(port.close);

    expect(await port.hasPrimaryInstance(), isFalse);
    await expectLater(port.request('show'), throwsFormatException);
    expect(
      await port.claimPrimary(onRequest: (_) => 'ready'),
      DesktopPrimaryClaimResult.primary,
    );
    expect(await endpoint.exists(), isFalse);
  });

  test('主窗口首次成为 primary 时会写入 info.json 并继续启动', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(),
        );

    expect(result.shouldRunApp, isTrue);
    expect(bootstrap.isPrimaryInstance, isTrue);
    expect(bootstrap.shouldStartHidden, isFalse);
    expect(port.claimedPrimary, isTrue);
    final File infoFile = await createPaths().resolveInfoFile();
    expect(await infoFile.exists(), isTrue);
    final Map<String, Object?> payload =
        jsonDecode(await infoFile.readAsString()) as Map<String, Object?>;
    expect(payload['Command Line'], equals(r'"C:\LDDC\lddc.exe"'));
    expect(payload['version'], isNotNull);
  });

  test('多个启动入口并发刷新 info.json 不共享临时文件且结果保持可解析', () async {
    final DesktopServiceInfoWriter writer = createInfoWriter();

    final List<File> results = await Future.wait<File>(
      List<Future<File>>.generate(24, (_) => writer.writeInfo()),
    );

    expect(results.map((File file) => file.path).toSet(), hasLength(1));
    final File infoFile = results.first;
    final Map<String, Object?> payload =
        jsonDecode(await infoFile.readAsString()) as Map<String, Object?>;
    expect(payload['schema'], 'lddc.desktop_service.info');
    expect(payload['Command Line'], r'"C:\LDDC\lddc.exe"');
    final List<FileSystemEntity> stagingResidue = await infoFile.parent
        .list()
        .where(
          (FileSystemEntity entity) =>
              p.basename(entity.path).startsWith('.info.json.write-'),
        )
        .toList();
    expect(stagingResidue, isEmpty);
  });

  test('已有 primary 时普通启动会转发 show 并退出', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.existingPrimary,
      waitUntilPrimaryAvailableResult: true,
      responses: <String, String?>{'show': 'message_received'},
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(port.requests, equals(const <String>['show']));
  });

  test('--not-show 遇到已有 primary 时直接退出且不转发 show', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.existingPrimary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(notShow: true),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(port.requests, isEmpty);
  });

  test('--get-service-port 会优先从已存在服务读取端口', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      responses: <String, String?>{'get_service_port': '23338'},
      hasPrimaryInstanceResult: true,
    );
    final _FakeProcessLauncher launcher = _FakeProcessLauncher();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '23338');
    expect(launcher.commands, isEmpty);
    expect(port.requests, equals(const <String>['get_service_port']));
  });

  test('--get-service-port 会在无服务时拉起后台实例并等待端口', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      hasPrimaryInstanceResult: false,
      waitUntilPrimaryAvailableResult: true,
      responsesSequence: <String, List<String?>>{
        'get_service_port': <String?>['24444'],
      },
    );
    final _FakeProcessLauncher launcher = _FakeProcessLauncher();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '24444');
    expect(launcher.commands.single.toCommandLine(), r'"C:\LDDC\lddc.exe"');
    expect(port.requests, equals(const <String>['get_service_port']));
  });

  test('--get-service-port 在无主实例时会先拉起后台服务再请求端口', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      hasPrimaryInstanceResult: false,
      waitUntilPrimaryAvailableResult: true,
      responsesSequence: <String, List<String?>>{
        'get_service_port': <String?>['27777'],
      },
    );
    final _RecordingProcessLauncher launcher = _RecordingProcessLauncher(
      onLaunch: () {
        expect(
          port.requests,
          isEmpty,
          reason: '无主实例时不应先做一次空的 get_service_port 查询',
        );
      },
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '27777');
    expect(launcher.commands.single.toCommandLine(), r'"C:\LDDC\lddc.exe"');
    expect(port.requests, equals(const <String>['get_service_port']));
  });

  test('--get-service-port 发现已有 primary 但端口未就绪时不会再次拉起', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      hasPrimaryInstanceResult: true,
      waitUntilPrimaryAvailableResult: true,
      responsesSequence: <String, List<String?>>{
        'get_service_port': <String?>[null, '25555'],
      },
    );
    final _FakeProcessLauncher launcher = _FakeProcessLauncher();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '25555');
    expect(launcher.commands, isEmpty);
    expect(
      port.requests,
      equals(const <String>['get_service_port', 'get_service_port']),
    );
  });

  test('--get-service-port 在空响应阶段会继续等合法端口且不重复拉起', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      hasPrimaryInstanceResult: true,
      responsesSequence: <String, List<String?>>{
        'get_service_port': <String?>['', '', '26666'],
      },
    );
    final _FakeProcessLauncher launcher = _FakeProcessLauncher();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '26666');
    expect(launcher.commands, isEmpty);
    expect(
      port.requests,
      equals(const <String>[
        'get_service_port',
        'get_service_port',
        'get_service_port',
      ]),
    );
  });

  test('--get-service-port 会在旧 primary 退出后立刻拉起新后台服务', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      hasPrimaryInstanceSequence: <bool>[true, false],
      responsesSequence: <String, List<String?>>{
        'get_service_port': <String?>['', '28888'],
      },
    );
    final _FakeProcessLauncher launcher = _FakeProcessLauncher();
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      processLauncher: launcher,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isFalse);
    expect(result.exitCode, 0);
    expect(result.stdoutLine, '28888');
    expect(launcher.commands.single.toCommandLine(), r'"C:\LDDC\lddc.exe"');
    expect(
      port.requests,
      equals(const <String>['get_service_port', 'get_service_port']),
    );
  });

  test('show 在 handler 注册前会缓存并在注册后立刻 flush', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(),
        );

    expect(result.shouldRunApp, isTrue);
    await port.onRequest?.call('show');
    int showCount = 0;
    await bootstrap.attachShowHandler(() async {
      showCount += 1;
    });

    expect(showCount, 1);
  });

  test('子窗口不会接管 bootstrap', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments(
            role: DesktopWindowRole.selector,
            instanceId: 1024,
            hostWindowId: 'host-window',
          ),
          launchArguments: const DesktopServiceLaunchArguments(
            getServicePort: true,
          ),
        );

    expect(result.shouldRunApp, isTrue);
    final File infoFile = await createPaths().resolveInfoFile();
    expect(await infoFile.exists(), isFalse);
    expect(port.claimedPrimary, isFalse);
  });

  test('macOS/Linux 也会接入隐藏服务入口', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);

    final DesktopServiceEntrypointResult result = await bootstrap
        .prepareEntrypoint(
          windowLaunch: const DesktopWindowLaunchArguments.main(),
          launchArguments: const DesktopServiceLaunchArguments(notShow: true),
        );

    expect(result.shouldRunApp, isTrue);
    expect(bootstrap.isPrimaryInstance, isTrue);
    expect(bootstrap.shouldStartHidden, isTrue);
    expect(port.claimedPrimary, isTrue);
    final File infoFile = await createPaths().resolveInfoFile();
    expect(await infoFile.exists(), isTrue);
    final Map<String, Object?> payload =
        jsonDecode(await infoFile.readAsString()) as Map<String, Object?>;
    expect(payload['Command Line'], equals(r'"C:\LDDC\lddc.exe"'));
    expect(payload['executable'], equals(r'C:\LDDC\lddc.exe'));
    expect(payload['arguments'], isEmpty);
  });

  test('finalizeEntrypoint 会先输出再调用 exitHandler', () async {
    final List<String> events = <String>[];
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: _FakeSingletonBootstrapPort(),
      stdoutWriter: (String line) => events.add('stdout:$line'),
      stderrWriter: (String line) => events.add('stderr:$line'),
      exitHandler: (int code) => events.add('exit:$code'),
    );
    addTearDown(bootstrap.dispose);

    final bool shouldRunApp = await bootstrap.finalizeEntrypoint(
      const DesktopServiceEntrypointResult.exit(
        exitCode: 7,
        stdoutLine: '57584',
        stderrLine: 'warning',
      ),
    );

    expect(shouldRunApp, isFalse);
    expect(
      events,
      equals(const <String>['stdout:57584', 'stderr:warning', 'exit:7']),
    );
  });

  test('端口发布失败时不会向控制通道暴露未就绪端口', () async {
    final StateError publishError = StateError('publish failed');
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
      setServicePortError: publishError,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    addTearDown(bootstrap.dispose);
    await bootstrap.prepareEntrypoint(
      windowLaunch: const DesktopWindowLaunchArguments.main(),
      launchArguments: const DesktopServiceLaunchArguments(),
    );

    await expectLater(
      bootstrap.registerServicePort(34567),
      throwsA(same(publishError)),
    );

    expect(await port.onRequest?.call('get_service_port'), '');
  });

  test('dispose 复用同一 Future，清除端口并拒绝后续操作', () async {
    final _FakeSingletonBootstrapPort port = _FakeSingletonBootstrapPort(
      claimResult: DesktopPrimaryClaimResult.primary,
    );
    final DesktopServiceBootstrap bootstrap = DesktopServiceBootstrap(
      infoWriter: createInfoWriter(),
      singletonPort: port,
      exitHandler: (_) {},
    );
    await bootstrap.prepareEntrypoint(
      windowLaunch: const DesktopWindowLaunchArguments.main(),
      launchArguments: const DesktopServiceLaunchArguments(),
    );
    await bootstrap.registerServicePort(45678);
    expect(await port.onRequest?.call('get_service_port'), '45678');

    await Future.wait(<Future<void>>[bootstrap.dispose(), bootstrap.dispose()]);

    expect(port.closeCount, 1);
    expect(await port.onRequest?.call('get_service_port'), '');
    await expectLater(
      bootstrap.attachShowHandler(() async {}),
      throwsStateError,
    );
    await expectLater(bootstrap.registerServicePort(45679), throwsStateError);
  });

  test('Windows 单实例轮询间隔必须大于零', () {
    expect(
      () => DesktopWindowsSingletonBootstrapPort(
        serverPollInterval: Duration.zero,
      ),
      throwsArgumentError,
    );
  });
}

class _FakeProcessLauncher implements DesktopServiceProcessLauncher {
  final List<DesktopServiceLaunchCommand> commands =
      <DesktopServiceLaunchCommand>[];

  @override
  Future<void> launchBackgroundService(
    DesktopServiceLaunchCommand command,
  ) async {
    commands.add(command);
  }
}

class _RecordingProcessLauncher implements DesktopServiceProcessLauncher {
  _RecordingProcessLauncher({required this.onLaunch});

  final VoidCallback onLaunch;
  final List<DesktopServiceLaunchCommand> commands =
      <DesktopServiceLaunchCommand>[];

  @override
  Future<void> launchBackgroundService(
    DesktopServiceLaunchCommand command,
  ) async {
    onLaunch();
    commands.add(command);
  }
}

class _FakeSingletonBootstrapPort implements DesktopSingletonBootstrapPort {
  _FakeSingletonBootstrapPort({
    this.claimResult = DesktopPrimaryClaimResult.existingPrimary,
    this.hasPrimaryInstanceResult = false,
    List<bool>? hasPrimaryInstanceSequence,
    this.waitUntilPrimaryAvailableResult,
    Map<String, String?>? responses,
    Map<String, List<String?>>? responsesSequence,
    this.setServicePortError,
  }) : responses = responses ?? <String, String?>{},
       responsesSequence = responsesSequence ?? <String, List<String?>>{},
       hasPrimaryInstanceSequence = hasPrimaryInstanceSequence ?? <bool>[];

  final DesktopPrimaryClaimResult claimResult;
  final bool hasPrimaryInstanceResult;
  final List<bool> hasPrimaryInstanceSequence;
  final bool? waitUntilPrimaryAvailableResult;
  final Map<String, String?> responses;
  final Map<String, List<String?>> responsesSequence;
  final Object? setServicePortError;
  final List<String> requests = <String>[];
  bool claimedPrimary = false;
  int? servicePort;
  int closeCount = 0;
  DesktopServiceSingletonRequestHandler? onRequest;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requests.add(message);
    final List<String?>? sequence = responsesSequence[message];
    if (sequence != null && sequence.isNotEmpty) {
      return sequence.removeAt(0);
    }
    final String? response = responses[message];
    if (response != null) {
      return response;
    }
    final DesktopServiceSingletonRequestHandler? handler = onRequest;
    if (handler != null) {
      return await handler(message);
    }
    return null;
  }

  @override
  Future<void> setServicePort(int port) async {
    final Object? error = setServicePortError;
    if (error != null) {
      throw error;
    }
    servicePort = port;
  }

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async {
    claimedPrimary = claimResult == DesktopPrimaryClaimResult.primary;
    if (claimedPrimary) {
      this.onRequest = onRequest;
    }
    return claimResult;
  }

  @override
  Future<bool> hasPrimaryInstance() async {
    if (hasPrimaryInstanceSequence.isNotEmpty) {
      return hasPrimaryInstanceSequence.removeAt(0);
    }
    return hasPrimaryInstanceResult;
  }

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final bool? ready = waitUntilPrimaryAvailableResult;
    if (ready != null) {
      return ready;
    }
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final String? response = await request(
        'get_service_port',
        timeout: pollInterval,
      );
      if (response != null) {
        return true;
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
}
