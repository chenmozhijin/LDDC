import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_bootstrap.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';

void main() {
  test('并发初始化按调用顺序提交，较慢的旧结果不会覆盖新快照', () async {
    AppBootstrap.resetForTest();
    addTearDown(AppBootstrap.disposeForTest);

    final AppConfig firstConfig = _configWithLanguage(AppLanguage.zhHans);
    final AppConfig secondConfig = _configWithLanguage(AppLanguage.en);
    final _DelayedConfigRepository firstRepository = _DelayedConfigRepository(
      firstConfig,
    );
    final _DelayedConfigRepository secondRepository = _DelayedConfigRepository(
      secondConfig,
    );
    final AppCapability firstCapability = _capability(multiWindow: false);
    final AppCapability secondCapability = _capability(multiWindow: true);

    final Future<void> first = AppBootstrap.ensureInitialized(
      configRepository: firstRepository,
      capabilityOverride: firstCapability,
    );
    await firstRepository.started;

    final Future<void> second = AppBootstrap.ensureInitialized(
      configRepository: secondRepository,
      capabilityOverride: secondCapability,
    );
    await Future<void>.delayed(Duration.zero);

    // 第二个仓储必须等前一次初始化完整提交后才能开始，避免两个异步结果交错回写。
    expect(secondRepository.loadCount, 0);

    firstRepository.release();
    await secondRepository.started;
    expect(AppBootstrap.config, same(firstConfig));
    expect(AppBootstrap.capability, same(firstCapability));

    secondRepository.release();
    await Future.wait(<Future<void>>[first, second]);

    expect(AppBootstrap.configRepository, same(secondRepository));
    expect(AppBootstrap.config, same(secondConfig));
    expect(AppBootstrap.capability, same(secondCapability));
  });

  test('测试重置不会把下一次初始化调度回已结束的 Zone', () async {
    AppBootstrap.resetForTest();
    addTearDown(AppBootstrap.disposeForTest);

    bool oldZoneClosed = false;
    final Zone oldZone = Zone.current.fork(
      specification: ZoneSpecification(
        scheduleMicrotask:
            (Zone self, ZoneDelegate parent, Zone zone, void Function() task) {
              // 模拟 testWidgets 用例结束后的 FakeAsync Zone：旧 Zone 不再驱动
              // 微任务。重置若保留该 Zone 创建的 Future，下一次初始化就会超时。
              if (!oldZoneClosed) {
                parent.scheduleMicrotask(zone, task);
              }
            },
      ),
    );
    await oldZone.run(() async {
      await AppBootstrap.ensureInitialized(
        configRepository: _ImmediateConfigRepository(
          _configWithLanguage(AppLanguage.zhHans),
        ),
        capabilityOverride: _capability(multiWindow: false),
      );
      AppBootstrap.resetForTest();
    });
    oldZoneClosed = true;

    final AppConfig nextConfig = _configWithLanguage(AppLanguage.en);
    await AppBootstrap.ensureInitialized(
      configRepository: _ImmediateConfigRepository(nextConfig),
      capabilityOverride: _capability(multiWindow: true),
    ).timeout(const Duration(seconds: 1));

    expect(AppBootstrap.config, same(nextConfig));
  });
}

AppConfig _configWithLanguage(AppLanguage language) {
  final AppConfig base = ConfigDefaults.current;
  return base.copyWith(
    app: AppUiConfig(
      language: language,
      colorScheme: base.app.colorScheme,
      logLevel: base.app.logLevel,
      autoCheckUpdate: base.app.autoCheckUpdate,
    ),
  );
}

AppCapability _capability({required bool multiWindow}) {
  return AppCapability(
    multiWindow: multiWindow,
    desktopPanelDetached: false,
    desktopPanelEmbedded: false,
    systemTray: false,
    globalHotkey: false,
    audioTagWrite: false,
    directoryRecursiveScan: false,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

class _DelayedConfigRepository implements ConfigRepository {
  _DelayedConfigRepository(this._config);

  final AppConfig _config;
  final Completer<void> _started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int loadCount = 0;

  Future<void> get started => _started.future;

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async {
    loadCount += 1;
    if (!_started.isCompleted) {
      _started.complete();
    }
    await _release.future;
    return _config;
  }

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

class _ImmediateConfigRepository implements ConfigRepository {
  _ImmediateConfigRepository(this._config);

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
