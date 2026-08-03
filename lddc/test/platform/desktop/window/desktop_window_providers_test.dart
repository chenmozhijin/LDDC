import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/core/config/config.dart';
import '../../../support/in_memory_library_link_repository.dart';
import '../../../support/desktop_service_host_exports.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('desktopWindowBackendProvider', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('主窗口角色会装配真实浮窗与选择器 host', () {
      final _FakeMultiWindowPort port = _FakeMultiWindowPort();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
          desktopMultiWindowPortProvider.overrideWithValue(port),
        ],
      );
      addTearDown(container.dispose);

      final DesktopWindowBackend backend = container.read(
        desktopWindowBackendProvider,
      );

      expect(backend.floatingHost, isA<DesktopMultiWindowFloatingWindowHost>());
      expect(backend.selectorHost, isA<DesktopMultiWindowSelectorWindowHost>());
    });

    test('子窗口角色会回退到 noop 应用自有窗口 host', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments(
              role: DesktopWindowRole.selector,
              instanceId: 7,
              hostWindowId: 'main-1',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopWindowBackend backend = container.read(
        desktopWindowBackendProvider,
      );

      expect(backend.floatingHost, isA<DesktopNoopFloatingWindowHost>());
      expect(backend.selectorHost, isA<DesktopNoopSelectorWindowHost>());
    });

    test('desktopPanelEffectExecutorProvider 会复用同一窗口后端', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopPanelEffectExecutor executor = container.read(
        desktopPanelEffectExecutorProvider,
      );

      expect(executor, isA<DesktopPanelEffectExecutor>());
    });

    test('desktopSelectorEffectExecutorProvider 会复用同一窗口后端', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopSelectorEffectExecutor executor = container.read(
        desktopSelectorEffectExecutorProvider,
      );

      expect(executor, isA<DesktopSelectorEffectExecutor>());
    });

    test('desktopFloatingEffectExecutorProvider 会装配浮窗同步执行器', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopFloatingEffectExecutor executor = container.read(
        desktopFloatingEffectExecutorProvider,
      );

      expect(executor, isA<DesktopFloatingEffectExecutor>());
    });

    test('desktopPendingEffectExecutorProvider 会装配持久化执行器', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopPendingEffectExecutor executor = container.read(
        desktopPendingEffectExecutorProvider,
      );

      expect(executor, isA<DesktopPendingEffectExecutor>());
    });

    test('desktopServiceCoordinatorProvider 会装配 reducer 与窗口 executors', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final DesktopServiceCoordinator coordinator = container.read(
        desktopServiceCoordinatorProvider,
      );

      expect(coordinator, isA<DesktopServiceCoordinator>());
    });

    test('desktopServiceCoordinatorProvider 不会因配置热更新重建实例', () async {
      final DefaultConfigRepository repository = DefaultConfigRepository();
      await repository.load();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          _desktopWindowAppDependenciesOverride(repository),
          desktopWindowLaunchProvider.overrideWithValue(
            const DesktopWindowLaunchArguments.main(),
          ),
          configRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final DesktopServiceCoordinator first = container.read(
        desktopServiceCoordinatorProvider,
      );
      await repository.update(<String, Object?>{
        ConfigKey.desktopDefaultLangs: <String>['orig'],
      });
      await Future<void>.delayed(Duration.zero);
      final DesktopServiceCoordinator second = container.read(
        desktopServiceCoordinatorProvider,
      );

      expect(identical(first, second), isTrue);
    });
  });
}

Override _desktopWindowAppDependenciesOverride([ConfigRepository? repository]) {
  return desktopWindowAppDependenciesProvider.overrideWithValue(
    DesktopWindowAppDependencies(
      configRepository: repository ?? _StaticConfigRepository(),
      libraryLinkRepository: InMemoryLibraryLinkRepository(),
      loadLinkedLyrics: (String lyricsPath) {
        throw UnimplementedError('测试未配置关联歌词加载');
      },
      runAutoFetch: (AutoFetchRequest request) {
        throw UnimplementedError('测试未配置自动获取');
      },
      resolveAutoSaveDirectory: () async => Directory.systemTemp,
      fileSavePersistenceFactory: (String folder) =>
          _FakeLyricsSavePersistence(),
      openAssociationManager: () async {},
    ),
  );
}

class _FakeLyricsSavePersistence extends LyricsSavePersistencePort {
  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    return 'memory://${request.songInfo.title ?? 'lyrics'}';
  }
}

class _StaticConfigRepository implements ConfigRepository {
  @override
  AppConfig get current => ConfigDefaults.current;

  Future<void> dispose() async {}

  @override
  Future<AppConfig> load() async => current;

  @override
  Future<AppConfig> refreshFromStorage() async => current;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async => current;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield current;
    }
  }
}

class _FakeMultiWindowPort implements DesktopMultiWindowPort {
  @override
  Future<DesktopRemoteWindowPort> createWindow({
    required DesktopWindowLaunchArguments arguments,
  }) async {
    return _FakeRemoteWindowPort(
      windowId: '${arguments.role.name}-${arguments.instanceId ?? 0}',
      arguments: arguments.encode(),
    );
  }

  @override
  Future<DesktopRemoteWindowPort> currentWindow() async {
    return _FakeRemoteWindowPort(windowId: 'main-1');
  }

  @override
  Future<DesktopRemoteWindowPort> fromWindowId(String windowId) async {
    return _FakeRemoteWindowPort(windowId: windowId);
  }
}

class _FakeRemoteWindowPort implements DesktopRemoteWindowPort {
  _FakeRemoteWindowPort({required this.windowId, this.arguments});

  @override
  final Object? arguments;

  @override
  final String windowId;

  @override
  Future<void> requestClose() async {}

  @override
  Future<void> hide() async {}

  @override
  Future<Object?> invokeMethod(String method, [Object? arguments]) async {
    return null;
  }

  @override
  Future<void> setMethodHandler(
    DesktopRemoteWindowMethodHandler? handler,
  ) async {}

  @override
  Future<void> setTitle(String title) async {}

  @override
  Future<void> show() async {}
}
