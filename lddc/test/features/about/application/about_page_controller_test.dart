import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/features/about/application/about_page_controller.dart';
import 'package:lddc/src/features/about/application/about_page_dependencies.dart';
import 'package:lddc/src/features/about/application/about_page_models.dart';
import 'package:lddc/src/core/about/about_ports.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  group('AboutPageController', () {
    test('异步加载成功并输出结构化关于页载荷', () async {
      final _FakeConfigRepository repository = _FakeConfigRepository(
        _buildConfig(autoCheckUpdate: false),
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          configRepositoryProvider.overrideWithValue(repository),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: repository,
              linkOpener: _FakeLinkOpener(),
              updatePort: const UnsupportedAppUpdatePort(),
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
          appUpdatePortProvider.overrideWithValue(
            const UnsupportedAppUpdatePort(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      final PageViewState<AboutPagePayload> pageState = await container.read(
        aboutPageControllerProvider.future,
      );
      final AboutPagePayload payload =
          (pageState.view as AsyncSuccess<AboutPagePayload>).data;

      expect(payload.appName, 'LDDC');
      expect(payload.versionLabel, 'v0.10.0-alpha.1');
      expect(payload.projectLinks, hasLength(3));
      expect(payload.headline, isNotEmpty);
      expect(payload.description, isNotEmpty);
      expect(payload.canOpenExternalLinks, isTrue);
      expect(payload.canCheckUpdate, isFalse);
      expect(
        payload.projectLinks.map((AboutActionLink link) => link.kind),
        orderedEquals(<AboutActionLinkKind>[
          AboutActionLinkKind.issues,
          AboutActionLinkKind.license,
          AboutActionLinkKind.changelog,
        ]),
      );
      expect(payload.copyrightYearRange, startsWith('2024'));
    });

    test('仓库动作会调用统一外链端口', () async {
      final _FakeConfigRepository repository = _FakeConfigRepository(
        _buildConfig(autoCheckUpdate: true),
      );
      final _FakeLinkOpener opener = _FakeLinkOpener();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          configRepositoryProvider.overrideWithValue(repository),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: repository,
              linkOpener: opener,
              updatePort: const UnsupportedAppUpdatePort(),
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(opener),
          appUpdatePortProvider.overrideWithValue(
            const UnsupportedAppUpdatePort(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      await container.read(aboutPageControllerProvider.future);
      final AboutPageController controller = container.read(
        aboutPageControllerProvider.notifier,
      );
      final AboutActionResult result = await controller.openRepository();

      expect(result.type, AboutActionResultType.opened);
      expect(result.actionType, AboutActionType.repository);
      expect(
        opener.opened.single.toString(),
        'https://github.com/chenmozhijin/LDDC',
      );
    });

    test('检查更新在支持时走独立更新端口', () async {
      final _FakeConfigRepository repository = _FakeConfigRepository(
        _buildConfig(autoCheckUpdate: true),
      );
      final _FakeUpdatePort updatePort = _FakeUpdatePort(isSupported: true);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          configRepositoryProvider.overrideWithValue(repository),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: repository,
              linkOpener: _FakeLinkOpener(),
              updatePort: updatePort,
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
          appUpdatePortProvider.overrideWithValue(updatePort),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      await container.read(aboutPageControllerProvider.future);
      final AboutPageController controller = container.read(
        aboutPageControllerProvider.notifier,
      );
      final AboutActionResult result = await controller.checkForUpdates();

      expect(result.type, AboutActionResultType.updateAvailable);
      expect(result.actionType, AboutActionType.checkForUpdates);
      expect(result.latestVersion, 'v9.9.9');
      expect(
        updatePort.lastReleaseUri.toString(),
        'https://github.com/chenmozhijin/LDDC/releases',
      );
    });

    test('检查更新记录具体动作并在端口异常后可靠清理', () async {
      final _FakeConfigRepository repository = _FakeConfigRepository(
        _buildConfig(autoCheckUpdate: true),
      );
      final _DelayedUpdatePort updatePort = _DelayedUpdatePort();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          configRepositoryProvider.overrideWithValue(repository),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: repository,
              linkOpener: _FakeLinkOpener(),
              updatePort: updatePort,
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
          appUpdatePortProvider.overrideWithValue(updatePort),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      await container.read(aboutPageControllerProvider.future);
      final Future<AboutActionResult> pending = container
          .read(aboutPageControllerProvider.notifier)
          .checkForUpdates();
      await Future<void>.delayed(Duration.zero);

      PageViewState<AboutPagePayload> pageState = container
          .read(aboutPageControllerProvider)
          .requireValue;
      AboutPagePayload payload =
          (pageState.view as AsyncSuccess<AboutPagePayload>).data;
      expect(payload.activeAction, AboutActionType.checkForUpdates);
      expect(pageState.action.isRunning, isTrue);

      updatePort.completer.completeError(StateError('network-failed'));
      final AboutActionResult result = await pending;
      expect(result.type, AboutActionResultType.failed);

      pageState = container.read(aboutPageControllerProvider).requireValue;
      payload = (pageState.view as AsyncSuccess<AboutPagePayload>).data;
      expect(payload.activeAction, isNull);
      expect(pageState.action.isRunning, isFalse);
    });

    test('加载异常会进入 AsyncError', () async {
      final _FakeConfigRepository repository = _FakeConfigRepository(
        _buildConfig(autoCheckUpdate: true),
        throwOnLoad: true,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: [
          configRepositoryProvider.overrideWithValue(repository),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: repository,
              linkOpener: _FakeLinkOpener(),
              updatePort: const UnsupportedAppUpdatePort(),
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
          appUpdatePortProvider.overrideWithValue(
            const UnsupportedAppUpdatePort(),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await repository.dispose();
      });

      await expectLater(
        container.read(aboutPageControllerProvider.future),
        throwsA(isA<StateError>()),
      );
      final AsyncValue<PageViewState<AboutPagePayload>> state = container.read(
        aboutPageControllerProvider,
      );
      expect(state.hasError, isTrue);
    });
  });
}

class _FakeLinkOpener implements AppLinkOpener {
  @override
  bool get isSupported => true;

  final List<Uri> opened = <Uri>[];

  @override
  Future<void> openExternalUri(Uri uri) async {
    opened.add(uri);
  }
}

class _FakeUpdatePort implements AppUpdatePort {
  _FakeUpdatePort({required this.isSupported});

  @override
  final bool isSupported;

  Uri? lastReleaseUri;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({
    required Uri releaseUri,
  }) async {
    lastReleaseUri = releaseUri;
    if (!isSupported) {
      return AppUpdateCheckResult.unsupported();
    }
    return AppUpdateCheckResult.updateAvailable(
      latestVersion: 'v9.9.9',
      releaseUri: releaseUri,
    );
  }
}

class _DelayedUpdatePort implements AppUpdatePort {
  final Completer<AppUpdateCheckResult> completer =
      Completer<AppUpdateCheckResult>();

  @override
  bool get isSupported => true;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required Uri releaseUri}) {
    return completer.future;
  }
}

class _FakeConfigRepository implements ConfigRepository {
  _FakeConfigRepository(this._config, {this.throwOnLoad = false});

  final bool throwOnLoad;
  final AppConfig _config;
  final StreamController<AppConfig> _changes =
      StreamController<AppConfig>.broadcast();

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async {
    if (throwOnLoad) {
      throw StateError('mock-load-failed');
    }
    return _config;
  }

  @override
  Future<AppConfig> refreshFromStorage() => load();

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async {
    return _config;
  }

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
    yield* _changes.stream;
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}

AppConfig _buildConfig({required bool autoCheckUpdate}) {
  final AppConfig defaults = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: defaults.schemaVersion,
    search: defaults.search,
    lyrics: defaults.lyrics,
    match: defaults.match,
    translate: defaults.translate,
    desktop: defaults.desktop,
    app: AppUiConfig(
      language: AppLanguage.zhHans,
      colorScheme: defaults.app.colorScheme,
      logLevel: defaults.app.logLevel,
      autoCheckUpdate: autoCheckUpdate,
    ),
    storage: defaults.storage,
  );
}
