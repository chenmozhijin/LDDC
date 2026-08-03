import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/about/application/about_page_dependencies.dart';
import 'package:lddc/src/features/about/presentation/about_page.dart';
import 'package:lddc/src/core/about/about_ports.dart';

void main() {
  testWidgets('关于页在不同断点下展示精简结构', (WidgetTester tester) async {
    final AppConfig defaults = ConfigDefaults.current;
    final AppConfig config = AppConfig(
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
        autoCheckUpdate: false,
      ),
      storage: defaults.storage,
    );

    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(844, 390),
      const Size(1366, 1024),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            configRepositoryProvider.overrideWithValue(
              _TestConfigRepository(config),
            ),
            aboutPageDependenciesProvider.overrideWithValue(
              AboutPageDependencies(
                configRepository: _TestConfigRepository(config),
                linkOpener: _FakeLinkOpener(),
                updatePort: const UnsupportedAppUpdatePort(),
              ),
            ),
            appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
            appUpdatePortProvider.overrideWithValue(
              const UnsupportedAppUpdatePort(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AboutPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('about_brand_hero')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('about_resources_section')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('about_legal_footer')),
        findsOneWidget,
      );
      expect(find.text('LDDC'), findsOneWidget);
      expect(find.text('为精准歌词而设计'), findsOneWidget);
      expect(find.text('常用链接'), findsOneWidget);
      expect(find.text('产品状态'), findsNothing);
      expect(find.text('版权声明'), findsNothing);
      expect(find.text('GitHub仓库'), findsOneWidget);
      expect(find.text('问题反馈'), findsOneWidget);
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.text('许可证'), findsOneWidget);
      expect(find.textContaining('Copyright (C)'), findsOneWidget);
      expect(find.byType(OverflowBar), findsNothing);
    }
  });

  testWidgets('关于页在中屏模式下保持单列常用链接', (WidgetTester tester) async {
    final AppConfig defaults = ConfigDefaults.current;
    final AppConfig config = AppConfig(
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
        autoCheckUpdate: false,
      ),
      storage: defaults.storage,
    );

    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWithValue(
            _TestConfigRepository(config),
          ),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: _TestConfigRepository(config),
              linkOpener: _FakeLinkOpener(),
              updatePort: const UnsupportedAppUpdatePort(),
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(_FakeLinkOpener()),
          appUpdatePortProvider.overrideWithValue(
            const UnsupportedAppUpdatePort(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AboutPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Offset issuesTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('about_resource_issues')),
    );
    final Offset licenseTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('about_resource_license')),
    );
    final Offset changelogTopLeft = tester.getTopLeft(
      find.byKey(const ValueKey<String>('about_resource_changelog')),
    );

    expect(licenseTopLeft.dx, issuesTopLeft.dx);
    expect(changelogTopLeft.dx, issuesTopLeft.dx);
    expect(licenseTopLeft.dy, greaterThan(issuesTopLeft.dy));
    expect(changelogTopLeft.dy, greaterThan(licenseTopLeft.dy));
  });

  testWidgets('GitHub 外链不会借用检查更新进度动画', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final AppConfig defaults = ConfigDefaults.current;
    final AppConfig config = AppConfig(
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
        autoCheckUpdate: false,
      ),
      storage: defaults.storage,
    );
    final _DelayedLinkOpener opener = _DelayedLinkOpener();
    final _DelayedUpdatePort updatePort = _DelayedUpdatePort();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configRepositoryProvider.overrideWithValue(
            _TestConfigRepository(config),
          ),
          aboutPageDependenciesProvider.overrideWithValue(
            AboutPageDependencies(
              configRepository: _TestConfigRepository(config),
              linkOpener: opener,
              updatePort: updatePort,
            ),
          ),
          appLinkOpenerProvider.overrideWithValue(opener),
          appUpdatePortProvider.overrideWithValue(updatePort),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AboutPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('GitHub仓库'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    opener.completer.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    updatePort.completer.complete(AppUpdateCheckResult.upToDate());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _FakeLinkOpener implements AppLinkOpener {
  @override
  bool get isSupported => true;

  @override
  Future<void> openExternalUri(Uri uri) async {}
}

class _DelayedLinkOpener implements AppLinkOpener {
  final Completer<void> completer = Completer<void>();

  @override
  bool get isSupported => true;

  @override
  Future<void> openExternalUri(Uri uri) => completer.future;
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

class _TestConfigRepository implements ConfigRepository {
  _TestConfigRepository(this._config);

  final AppConfig _config;

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<AppConfig> refreshFromStorage() async => _config;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async => _config;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
  }
}
