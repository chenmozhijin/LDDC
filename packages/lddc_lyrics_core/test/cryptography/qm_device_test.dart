import 'dart:math';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  group('QM 设备档案', () {
    test('协议别名、序列化字段和指纹随稳定字段变化', () {
      const QmDeviceProfile profile = QmDeviceProfile(
        androidVersion: '13',
        model: 'Synthetic Device',
        rom: 'Synthetic/ROM/1',
        abi: 'x86_64',
        imei: '000000000000000',
        simSerial: 'sim',
        mcc: '460',
        mnc: '00',
        appCode: '100',
        appVersion: '1.0.0',
        qimeiAppKey: 'TEST_APP_KEY',
        qimeiSdkVersion: '5.0.0',
        qimeiOsVersion: 'Android 13,level 33',
        qimeiChannel: 'test',
        qimeiNetworkType: 'mobile',
        qimeiProcessName: 'example.process',
        qimeiPackageName: 'example.package',
        qimeiPreauditEnabled: false,
        dataLocalSize: 2048,
        sourceDirStatus: 3,
        signingBlockStatus: 4,
        riskBitmask: 5,
        virtioBitmask: 6,
        networkBitmask: 7,
        instrumentationClass: 'ExampleInstrumentation',
        callbackClass: 'ExampleCallback',
        mountinfoZygisk: true,
        suspiciousModules: <Map<String, Object?>>[
          <String, Object?>{'name': 'synthetic'},
        ],
        artMethodEntries: <Map<String, Object?>>[
          <String, Object?>{'entry': 1},
        ],
      );

      expect(profile.userAgent, 'QQMusic 100(android 13)');
      expect(profile.platformDeviceId, 'TEST_APP_KEY');
      expect(profile.sdkVersion, '5.0.0');
      expect(profile.osVersion, 'Android 13,level 33');
      expect(profile.channel, 'test');
      expect(profile.networkType, 'mobile');
      expect(profile.processName, 'example.process');
      expect(profile.toJson(), <String, Object?>{
        'android_version': '13',
        'model': 'Synthetic Device',
        'rom': 'Synthetic/ROM/1',
        'abi': 'x86_64',
        'imei': '000000000000000',
        'sim_serial': 'sim',
        'mcc': '460',
        'mnc': '00',
        'app_code': '100',
        'app_version': '1.0.0',
        'qimei_app_key': 'TEST_APP_KEY',
        'qimei_sdk_version': '5.0.0',
        'qimei_os_version': 'Android 13,level 33',
        'qimei_channel': 'test',
        'qimei_network_type': 'mobile',
        'qimei_process_name': 'example.process',
        'qimei_package_name': 'example.package',
        'qimei_preaudit_enabled': false,
        'data_local_size': 2048,
        'source_dir_status': 3,
        'signing_block_status': 4,
        'risk_bitmask': 5,
        'virtio_bitmask': 6,
        'network_bitmask': 7,
        'instrumentation_class': 'ExampleInstrumentation',
        'callback_class': 'ExampleCallback',
        'mountinfo_zygisk': true,
        'suspicious_modules': <Map<String, Object?>>[
          <String, Object?>{'name': 'synthetic'},
        ],
        'art_method_entries': <Map<String, Object?>>[
          <String, Object?>{'entry': 1},
        ],
      });
      expect(profile.qimeiFingerprint, hasLength(64));
      expect(
        profile.qimeiFingerprint,
        isNot(const QmDeviceProfile(model: 'Changed').qimeiFingerprint),
      );
    });
  });

  group('QM 设备身份', () {
    test('固定随机源和时钟生成可持久化身份', () {
      const QmDeviceProfile profile = QmDeviceProfile(imei: '1234567890');
      final QmDeviceIdentity identity = generateQmDeviceIdentity(
        profile,
        generation: 3,
        random: Random(7),
        currentTimeMs: 1783352230057,
      );
      final List<Object?> records =
          identity.dataLocalSnapshot['records']! as List<Object?>;

      expect(identity.generation, 3);
      expect(identity.androidId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(identity.openUdid2, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(identity.dataLocalSnapshot['version'], qmDataLocalSnapshotVersion);
      expect(records, hasLength(122));
      expect(records[8], '1969-12-31190000.000000000');
      expect(records.last, '');
      expect(() => records.add('x'), throwsUnsupportedError);

      final QmDeviceIdentity decoded = QmDeviceIdentity.tryDecode(
        identity.toJson(),
      )!;
      expect(decoded.toJson(), identity.toJson());
      expect(() => decoded.dataLocalSnapshot['x'] = 1, throwsUnsupportedError);
    });

    test('QIMEI 绑定、清除和 copyWith 保持身份字段及快照边界', () {
      const QmDeviceProfile profile = QmDeviceProfile();
      final QmDeviceIdentity identity = generateQmDeviceIdentity(
        profile,
        generation: 1,
        random: Random(3),
        currentTimeMs: 1783352230057,
      );
      final QmDeviceIdentity bound = identity.withQimei(
        profile,
        '0123456789abcdef',
        defaultQimei36,
      );

      expect(bound.androidId, identity.androidId);
      expect(bound.qimei16, '0123456789abcdef');
      expect(bound.qimei36, defaultQimei36);
      expect(bound.qimeiProfileFingerprint, identity.qimeiFingerprint(profile));
      expect(bound.clearQimei().qimei16, isEmpty);
      expect(bound.clearQimei().qimei36, isEmpty);
      expect(bound.clearQimei().qimeiProfileFingerprint, isEmpty);

      final Map<String, Object?> replacement = <String, Object?>{
        'version': qmDataLocalSnapshotVersion,
        'records': List<String>.filled(122, 'replacement'),
        'nested': <String, Object?>{
          'items': <Object?>[
            1,
            <String, Object?>{'ok': true},
          ],
        },
      };
      final QmDeviceIdentity copied = bound.copyWith(
        generation: 4,
        androidId: 'fedcba9876543210',
        openUdid2: 'fedcba9876543210fedcba9876543210',
        dataLocalSnapshot: replacement,
        qimei16: 'fedcba9876543210',
        qimei36: 'changed',
        qimeiProfileFingerprint: 'fingerprint',
      );
      (replacement['records']! as List<String>)[0] = 'mutated';

      expect(copied.generation, 4);
      expect(copied.androidId, 'fedcba9876543210');
      expect(copied.openUdid2, 'fedcba9876543210fedcba9876543210');
      expect(
        (copied.dataLocalSnapshot['records']! as List<Object?>).first,
        'replacement',
      );
      expect(
        () =>
            (copied.dataLocalSnapshot['nested']! as Map<String, Object?>)['x'] =
                1,
        throwsUnsupportedError,
      );
      expect(copied.qimei16, 'fedcba9876543210');
      expect(copied.qimei36, 'changed');
      expect(copied.qimeiProfileFingerprint, 'fingerprint');
    });

    test('损坏的持久化身份被拒绝而不是带病进入请求', () {
      final Map<String, Object?> valid = generateQmDeviceIdentity(
        const QmDeviceProfile(),
        generation: 0,
        random: Random(1),
        currentTimeMs: 1783352230057,
      ).toJson();
      Map<String, Object?> changed(String key, Object? value) =>
          <String, Object?>{...valid, key: value};

      expect(QmDeviceIdentity.tryDecode(null), isNull);
      expect(
        QmDeviceIdentity.tryDecode(<Object?, Object?>{1: 'ignored'}),
        isNull,
      );
      expect(QmDeviceIdentity.tryDecode(changed('generation', -1)), isNull);
      expect(QmDeviceIdentity.tryDecode(changed('generation', '0')), isNull);
      expect(
        QmDeviceIdentity.tryDecode(changed('android_id', 'ABCDEF0123456789')),
        isNull,
      );
      expect(
        QmDeviceIdentity.tryDecode(changed('android_id', 'short')),
        isNull,
      );
      expect(
        QmDeviceIdentity.tryDecode(
          changed('open_udid2', List<String>.filled(32, 'g').join()),
        ),
        isNull,
      );
      expect(
        QmDeviceIdentity.tryDecode(changed('data_local_snapshot', 'bad')),
        isNull,
      );
      expect(QmDeviceIdentity.tryDecode(changed('qimei16', 1)), isNull);
      expect(QmDeviceIdentity.tryDecode(changed('qimei36', 1)), isNull);
      expect(
        QmDeviceIdentity.tryDecode(changed('qimei_profile_fingerprint', 1)),
        isNull,
      );

      final Map<String, Object?> badVersion = <String, Object?>{
        ...valid,
        'data_local_snapshot': <String, Object?>{
          'version': -1,
          'records': List<String>.filled(122, ''),
        },
      };
      final Map<String, Object?> badLength = <String, Object?>{
        ...valid,
        'data_local_snapshot': <String, Object?>{
          'version': qmDataLocalSnapshotVersion,
          'records': List<String>.filled(121, ''),
        },
      };
      final Map<String, Object?> badRecord = <String, Object?>{
        ...valid,
        'data_local_snapshot': <String, Object?>{
          'version': qmDataLocalSnapshotVersion,
          'records': <Object?>[...List<String>.filled(121, ''), 1],
        },
      };
      expect(QmDeviceIdentity.tryDecode(badVersion), isNull);
      expect(QmDeviceIdentity.tryDecode(badLength), isNull);
      expect(QmDeviceIdentity.tryDecode(badRecord), isNull);
    });

    test('默认随机源和当前时钟仍生成完整协议形状', () {
      final QmDeviceIdentity identity = generateQmDeviceIdentity(
        const QmDeviceProfile(),
        generation: 0,
      );
      final Map<String, Object?> snapshot = generateQmDataLocalSnapshot(
        const QmDeviceProfile(dataLocalSize: 4096),
      );

      expect(identity.androidId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(identity.openUdid2, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(snapshot['records'], hasLength(122));
      expect((snapshot['records']! as List<Object?>)[113], '4096');
    });
  });

  group('QM 设备协议基础值', () {
    test('Java hash、OpenUDID2 和时间文本保持边界语义', () {
      expect(qmJavaHashCode(''), 0);
      expect(qmJavaHashCode('hello'), 99162322);
      expect(qmJavaHashCode('polygenelubricants'), -2147483648);

      final String withoutImei = generateQmOpenUdid2(
        '0123456789abcdef',
        '',
        1783352230057,
      );
      final String withImei = generateQmOpenUdid2(
        '0123456789abcdef',
        '1234567890',
        1783352230057,
      );
      expect(withoutImei, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(withImei, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(withImei, isNot(withoutImei));
      expect(
        qmDataLocalTimestampText(0),
        matches(RegExp(r'^\d{4}-\d{2}-\d{8}\.000000000$')),
      );
    });

    test('Python JSON 规则覆盖排序、Unicode、集合和非法类型', () {
      expect(encodePythonJson(null, asciiOnly: true, sortKeys: true), 'null');
      expect(encodePythonJson(true, asciiOnly: true, sortKeys: true), 'true');
      expect(encodePythonJson(1.5, asciiOnly: true, sortKeys: true), '1.5');
      expect(
        encodePythonJson('歌词', asciiOnly: true, sortKeys: true),
        r'"\u6b4c\u8bcd"',
      );
      expect(encodePythonJson('歌词', asciiOnly: false, sortKeys: true), '"歌词"');
      expect(
        encodePythonJson(
          <Object?>[1, 'x', null],
          asciiOnly: true,
          sortKeys: true,
        ),
        '[1,"x",null]',
      );
      expect(
        encodePythonJson(
          <String, Object?>{'b': 2, 'a': 1},
          asciiOnly: true,
          sortKeys: true,
        ),
        '{"a":1,"b":2}',
      );
      expect(
        encodePythonJson(
          <String, Object?>{'b': 2, 'a': 1},
          asciiOnly: true,
          sortKeys: false,
        ),
        '{"b":2,"a":1}',
      );
      expect(
        () => encodePythonJson(
          <Object?, Object?>{1: 'bad'},
          asciiOnly: true,
          sortKeys: true,
        ),
        throwsArgumentError,
      );
      expect(
        () => encodePythonJson(Object(), asciiOnly: true, sortKeys: true),
        throwsArgumentError,
      );
      expect(
        () => QmDeviceIdentity(
          generation: 0,
          androidId: '0123456789abcdef',
          openUdid2: '0123456789abcdef0123456789abcdef',
          dataLocalSnapshot: <String, Object?>{
            'nested': <Object?, Object?>{1: 'bad'},
          },
        ),
        throwsArgumentError,
      );
    });
  });
}
