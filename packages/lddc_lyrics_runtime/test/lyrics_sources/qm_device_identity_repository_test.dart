import 'dart:async';

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

const String _q16 = '0123456789abcdef';
const String _q36 = 'b925092ce71e51774071587c100013f14a01';

void main() {
  group('QmDeviceIdentityRepository', () {
    late CacheFacade cache;
    late QmDeviceIdentityRepository repository;

    setUp(() {
      cache = CacheFacade(
        store: PersistentCacheStore(executor: NativeDatabase.memory()),
      );
      repository = QmDeviceIdentityRepository(cache: cache);
    });

    tearDown(() => cache.dispose());

    test('损坏缓存生成 generation=0 的新设备', () async {
      await cache.set('qm_device', 'identity', <String, Object?>{
        'broken': true,
      });

      final QmDeviceIdentity identity = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );

      expect(identity.generation, 0);
      expect(identity.androidId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(identity.openUdid2, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(
        (identity.dataLocalSnapshot['records']! as List<Object?>).length,
        122,
      );
    });

    test('profile 变化只清空 QIMEI，不更换 Android 身份', () async {
      const QmDeviceProfile original = QmDeviceProfile();
      final QmDeviceIdentity first = await repository.loadOrCreate(original);
      await repository.ensureQimei(
        original,
        first,
        (_) async => (qimei16: _q16, qimei36: _q36),
      );

      final QmDeviceIdentity changed = await repository.loadOrCreate(
        const QmDeviceProfile(model: 'ChangedModel'),
      );

      expect(changed.androidId, first.androidId);
      expect(changed.openUdid2, first.openUdid2);
      expect(changed.qimei16, isEmpty);
      expect(changed.qimei36, isEmpty);
    });

    test('清空缓存后自然生成新设备', () async {
      final QmDeviceIdentity first = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );
      await cache.clearAll();

      final QmDeviceIdentity second = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );

      expect(second.androidId, isNot(first.androidId));
      expect(second.generation, 0);
    });

    test('并发 generation CAS 只替换一次', () async {
      final QmDeviceIdentity first = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );

      final List<({QmDeviceIdentity identity, bool replaced})> results =
          await Future.wait(
            <Future<({QmDeviceIdentity identity, bool replaced})>>[
              repository.replaceIfGeneration(
                const QmDeviceProfile(),
                first.generation,
              ),
              repository.replaceIfGeneration(
                const QmDeviceProfile(),
                first.generation,
              ),
            ],
          );

      expect(results.where((result) => result.replaced).length, 1);
      expect(
        results.every((result) => result.identity.generation == 1),
        isTrue,
      );
    });

    test('同 generation 的并发 ensureQimei 只调用一次 REGISTER', () async {
      final QmDeviceIdentity identity = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );
      final Completer<void> gate = Completer<void>();
      int registerCalls = 0;

      Future<({String qimei16, String qimei36})> register(
        QmDeviceIdentity current,
      ) async {
        registerCalls += 1;
        await gate.future;
        return (qimei16: _q16, qimei36: _q36);
      }

      final Future<QmDeviceIdentity> first = repository.ensureQimei(
        const QmDeviceProfile(),
        identity,
        register,
      );
      final Future<QmDeviceIdentity> second = repository.ensureQimei(
        const QmDeviceProfile(),
        identity,
        register,
      );
      await Future<void>.delayed(Duration.zero);
      expect(registerCalls, 1);
      gate.complete();

      final List<QmDeviceIdentity> results = await Future.wait(
        <Future<QmDeviceIdentity>>[first, second],
      );
      expect(results.every((item) => item.qimei36 == _q36), isTrue);
      expect(repository.pendingRegisterCount, 0);
    });

    test('旧 generation REGISTER 完成后不能覆盖已替换身份', () async {
      final QmDeviceIdentity identity = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );
      final Completer<void> gate = Completer<void>();
      final Future<QmDeviceIdentity> registration = repository.ensureQimei(
        const QmDeviceProfile(),
        identity,
        (_) async {
          await gate.future;
          return (qimei16: _q16, qimei36: _q36);
        },
      );
      await Future<void>.delayed(Duration.zero);
      final ({QmDeviceIdentity identity, bool replaced}) replacement =
          await repository.replaceIfGeneration(
            const QmDeviceProfile(),
            identity.generation,
          );
      gate.complete();

      final QmDeviceIdentity result = await registration;
      final QmDeviceIdentity cached = await repository.loadOrCreate(
        const QmDeviceProfile(),
      );
      expect(replacement.replaced, isTrue);
      expect(result.generation, 1);
      expect(cached.generation, 1);
      expect(cached.qimei36, isEmpty);
    });
  });
}
