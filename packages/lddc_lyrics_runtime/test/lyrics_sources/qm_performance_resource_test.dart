import 'dart:io';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  test('QM REGISTER、身份读取和恢复循环资源证据', () async {
    const QmDeviceProfile profile = QmDeviceProfile();
    final PersistentCacheStore store = PersistentCacheStore(
      executor: NativeDatabase.memory(),
    );
    final CacheFacade cache = CacheFacade(store: store);
    final QmDeviceIdentityRepository repository = QmDeviceIdentityRepository(
      cache: cache,
    );
    final QmDeviceIdentity initial = await repository.loadOrCreate(profile);
    final int rssBefore = ProcessInfo.currentRss;

    // 生产路径通过 Isolate.run 执行完整 REGISTER 构造。这里不设置固定耗时上限，
    // 因为 CI 与开发机的 CPU 差异很大；测试关注次数、协议成功和主 isolate 边界。
    const IsolateQimeiProtocolWorker worker = IsolateQimeiProtocolWorker();
    final Stopwatch registerWatch = Stopwatch()..start();
    for (int index = 0; index < 20; index += 1) {
      final QimeiRequestArtifacts artifacts = await worker.buildRequest(
        profile: profile,
        state: QimeiPayloadState(
          headDeviceToken: '0011223344556677',
          registerCounter: index,
          dataLocalSnapshot: initial.dataLocalSnapshot,
          dataLocalTimestampSeconds: 1710000000,
          preauditTimestampSeconds: 1710000000,
        ),
      );
      expect(artifacts.requestKey, hasLength(16));
      expect(artifacts.requestIv, hasLength(16));
      expect(artifacts.ky, isNotEmpty);
    }
    registerWatch.stop();

    final Stopwatch readWatch = Stopwatch()..start();
    for (int index = 0; index < 1000; index += 1) {
      final QmDeviceIdentity loaded = await repository.loadOrCreate(profile);
      expect(loaded.androidId, isNotEmpty);
    }
    readWatch.stop();

    final Stopwatch recoveryWatch = Stopwatch()..start();
    QmDeviceIdentity current = await repository.loadOrCreate(profile);
    for (int index = 0; index < 100; index += 1) {
      final ({QmDeviceIdentity identity, bool replaced}) replacement =
          await repository.replaceIfGeneration(profile, current.generation);
      expect(replacement.replaced, isTrue);
      current = await repository.ensureQimei(
        profile,
        replacement.identity,
        (QmDeviceIdentity identity) async => (
          qimei16: '0123456789abcdef',
          qimei36: identity.generation.toString().padLeft(36, '0'),
        ),
      );
      expect(current.generation, index + 1);
      expect(repository.pendingRegisterCount, 0);
    }
    recoveryWatch.stop();

    final int rssBeforeClose = ProcessInfo.currentRss;
    await cache.dispose();
    // 给数据库 executor 和短生命周期 isolate 的完成消息一次事件循环收口机会。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final int rssAfterClose = ProcessInfo.currentRss;

    // 输出结构化证据，便于迁移进度文档记录；RSS 只作观测，不以不可控的 GC 时机
    // 作为成败条件。资源正确性由单飞容器归零和缓存成功关闭共同约束。
    // ignore: avoid_print
    print(<String, Object?>{
      'qmRegisterBuild20Ms': registerWatch.elapsedMilliseconds,
      'qmIdentityRead1000Ms': readWatch.elapsedMilliseconds,
      'qmRecoveryLoop100Ms': recoveryWatch.elapsedMilliseconds,
      'rssBefore': rssBefore,
      'rssBeforeClose': rssBeforeClose,
      'rssAfterClose': rssAfterClose,
      'pendingRegisterCount': repository.pendingRegisterCount,
    });

    expect(repository.pendingRegisterCount, 0);
    expect(current.generation, 100);
  });
}
