import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int qmDataLocalSnapshotVersion = 2;

const List<String> _dataLocalStatPaths = <String>[
  '/storage/emulated',
  '/storage/emulated/0',
  '/data/data',
  '/data/user',
  '/mnt',
  '/storage/emulated/0/Android/data',
  '/storage/emulated/0/Android',
  '/storage/emulated/0/tencent',
  '/data/system/job',
  '/data/dalvik-cache',
  '/data/system/locksettings.db',
  '/data/system/inputmethod',
  '/cache',
  '/data/app-lib',
  '/data/system/recoverablekeystore.db',
  '/data/system/graphicsstats',
  '/data/system/sensor_service',
  '/data/system/last-header.txt',
  '/data/system/sync',
  '/data/system/netstats',
  '/data/media',
  '/data/system/procstats',
  '/data/system/notification_log.db',
  '/data/resource-cache',
  '/data/lost+found',
  '/data/ss',
  '/data/system/uiderrors.txt',
];

const List<String> _dataLocalLstatPaths = <String>['/mnt/sdcard'];
const List<String> _dataLocalStatvfsPaths = <String>[
  '/storage/emulated',
  '/system/etc',
  '/cache',
];

/// QM synthetic 设备档案。
///
/// 档案的任一稳定字段变化都会让已缓存
/// QIMEI 失效，但不会更换 Android ID，从而避免把“参数升级”和“设备刷新”混为一谈。
final class QmDeviceProfile {
  const QmDeviceProfile({
    this.androidVersion = '14',
    this.model = '22041211AC',
    this.rom = 'XiaoMi/MIUI/V816',
    this.abi = 'arm64-v8a',
    this.imei = '',
    this.simSerial = 'null',
    this.mcc = '',
    this.mnc = '',
    this.appCode = '14100508',
    this.appVersion = '14.10.5.8',
    this.qimeiAppKey = '0AND0HD6FE4HY80F',
    this.qimeiSdkVersion = '5.1.2.22',
    this.qimeiOsVersion = 'Android 14,level 34',
    this.qimeiChannel = '73387',
    this.qimeiNetworkType = 'wifi',
    this.qimeiProcessName = 'com.tencent.qqmusic',
    this.qimeiPackageName = 'com.tencent.qqmusic',
    this.qimeiPreauditEnabled = true,
    this.dataLocalSize = 1048576,
    this.sourceDirStatus = 4,
    this.signingBlockStatus = 776813932,
    this.riskBitmask = 1,
    this.virtioBitmask = 0,
    this.networkBitmask,
    this.instrumentationClass = '',
    this.callbackClass = '',
    this.mountinfoZygisk = false,
    this.suspiciousModules = const <Map<String, Object?>>[],
    this.artMethodEntries = const <Map<String, Object?>>[],
  });

  final String androidVersion;
  final String model;
  final String rom;
  final String abi;
  final String imei;
  final String simSerial;
  final String mcc;
  final String mnc;
  final String appCode;
  final String appVersion;
  final String qimeiAppKey;
  final String qimeiSdkVersion;
  final String qimeiOsVersion;
  final String qimeiChannel;
  final String qimeiNetworkType;
  final String qimeiProcessName;
  final String qimeiPackageName;
  final bool qimeiPreauditEnabled;
  final int dataLocalSize;
  final int sourceDirStatus;
  final int signingBlockStatus;
  final int riskBitmask;
  final int virtioBitmask;
  final int? networkBitmask;
  final String instrumentationClass;
  final String callbackClass;
  final bool mountinfoZygisk;
  final List<Map<String, Object?>> suspiciousModules;
  final List<Map<String, Object?>> artMethodEntries;

  String get userAgent => 'QQMusic $appCode(android $androidVersion)';
  String get platformDeviceId => qimeiAppKey;
  String get sdkVersion => qimeiSdkVersion;
  String get osVersion => qimeiOsVersion;
  String get channel => qimeiChannel;
  String get networkType => qimeiNetworkType;
  String get processName => qimeiProcessName;

  Map<String, Object?> toJson() => <String, Object?>{
    'android_version': androidVersion,
    'model': model,
    'rom': rom,
    'abi': abi,
    'imei': imei,
    'sim_serial': simSerial,
    'mcc': mcc,
    'mnc': mnc,
    'app_code': appCode,
    'app_version': appVersion,
    'qimei_app_key': qimeiAppKey,
    'qimei_sdk_version': qimeiSdkVersion,
    'qimei_os_version': qimeiOsVersion,
    'qimei_channel': qimeiChannel,
    'qimei_network_type': qimeiNetworkType,
    'qimei_process_name': qimeiProcessName,
    'qimei_package_name': qimeiPackageName,
    'qimei_preaudit_enabled': qimeiPreauditEnabled,
    'data_local_size': dataLocalSize,
    'source_dir_status': sourceDirStatus,
    'signing_block_status': signingBlockStatus,
    'risk_bitmask': riskBitmask,
    'virtio_bitmask': virtioBitmask,
    'network_bitmask': networkBitmask,
    'instrumentation_class': instrumentationClass,
    'callback_class': callbackClass,
    'mountinfo_zygisk': mountinfoZygisk,
    'suspicious_modules': suspiciousModules,
    'art_method_entries': artMethodEntries,
  };

  String get qimeiFingerprint => sha256
      .convert(
        utf8.encode(
          encodePythonJson(toJson(), asciiOnly: true, sortKeys: true),
        ),
      )
      .toString();
}

/// 持久化的 QM 设备身份。
final class QmDeviceIdentity {
  QmDeviceIdentity({
    required int generation,
    required String androidId,
    required String openUdid2,
    required Map<String, Object?> dataLocalSnapshot,
    String qimei16 = '',
    String qimei36 = '',
    String qimeiProfileFingerprint = '',
  }) : this._(
         generation: generation,
         androidId: androidId,
         openUdid2: openUdid2,
         dataLocalSnapshot: _freezeSnapshot(dataLocalSnapshot),
         qimei16: qimei16,
         qimei36: qimei36,
         qimeiProfileFingerprint: qimeiProfileFingerprint,
       );

  const QmDeviceIdentity._({
    required this.generation,
    required this.androidId,
    required this.openUdid2,
    required this.dataLocalSnapshot,
    required this.qimei16,
    required this.qimei36,
    required this.qimeiProfileFingerprint,
  });

  final int generation;
  final String androidId;
  final String openUdid2;
  final Map<String, Object?> dataLocalSnapshot;
  final String qimei16;
  final String qimei36;
  final String qimeiProfileFingerprint;

  String qimeiFingerprint(QmDeviceProfile profile) {
    final Map<String, Object?> payload = <String, Object?>{
      'profile': profile.qimeiFingerprint,
      'data_local_snapshot': dataLocalSnapshot,
    };
    return sha256
        .convert(
          utf8.encode(
            encodePythonJson(payload, asciiOnly: true, sortKeys: true),
          ),
        )
        .toString();
  }

  QmDeviceIdentity withQimei(
    QmDeviceProfile profile,
    String qimei16,
    String qimei36,
  ) {
    return copyWith(
      qimei16: qimei16,
      qimei36: qimei36,
      qimeiProfileFingerprint: qimeiFingerprint(profile),
    );
  }

  QmDeviceIdentity clearQimei() =>
      copyWith(qimei16: '', qimei36: '', qimeiProfileFingerprint: '');

  QmDeviceIdentity copyWith({
    int? generation,
    String? androidId,
    String? openUdid2,
    Map<String, Object?>? dataLocalSnapshot,
    String? qimei16,
    String? qimei36,
    String? qimeiProfileFingerprint,
  }) {
    return QmDeviceIdentity._(
      generation: generation ?? this.generation,
      androidId: androidId ?? this.androidId,
      openUdid2: openUdid2 ?? this.openUdid2,
      dataLocalSnapshot: dataLocalSnapshot == null
          ? this.dataLocalSnapshot
          : _freezeSnapshot(dataLocalSnapshot),
      qimei16: qimei16 ?? this.qimei16,
      qimei36: qimei36 ?? this.qimei36,
      qimeiProfileFingerprint:
          qimeiProfileFingerprint ?? this.qimeiProfileFingerprint,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'generation': generation,
    'android_id': androidId,
    'open_udid2': openUdid2,
    'data_local_snapshot': dataLocalSnapshot,
    'qimei16': qimei16,
    'qimei36': qimei36,
    'qimei_profile_fingerprint': qimeiProfileFingerprint,
  };

  static QmDeviceIdentity? tryDecode(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Map<String, Object?> map = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final Object? generation = map['generation'];
    final Object? androidId = map['android_id'];
    final Object? openUdid2 = map['open_udid2'];
    final Object? snapshot = map['data_local_snapshot'];
    final Object qimei16 = map['qimei16'] ?? '';
    final Object qimei36 = map['qimei36'] ?? '';
    final Object fingerprint = map['qimei_profile_fingerprint'] ?? '';
    if (generation is! int || generation < 0) {
      return null;
    }
    if (androidId is! String || !_isLowerHex(androidId, 16)) {
      return null;
    }
    if (openUdid2 is! String || !_isLowerHex(openUdid2, 32)) {
      return null;
    }
    if (snapshot is! Map ||
        qimei16 is! String ||
        qimei36 is! String ||
        fingerprint is! String) {
      return null;
    }
    final Map<String, Object?> normalizedSnapshot = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in snapshot.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    if (normalizedSnapshot['version'] != qmDataLocalSnapshotVersion) {
      return null;
    }
    final Object? records = normalizedSnapshot['records'];
    if (records is! List ||
        records.length != 122 ||
        records.any((Object? item) => item is! String)) {
      return null;
    }
    normalizedSnapshot['records'] = List<String>.unmodifiable(
      records.cast<String>(),
    );
    return QmDeviceIdentity(
      generation: generation,
      androidId: androidId,
      openUdid2: openUdid2,
      dataLocalSnapshot: normalizedSnapshot,
      qimei16: qimei16,
      qimei36: qimei36,
      qimeiProfileFingerprint: fingerprint,
    );
  }
}

QmDeviceIdentity generateQmDeviceIdentity(
  QmDeviceProfile profile, {
  required int generation,
  Random? random,
  int? currentTimeMs,
}) {
  final Random source = random ?? Random.secure();
  const String chars = '0123456789abcdef';
  final StringBuffer androidIdBuffer = StringBuffer();
  for (int index = 0; index < 16; index += 1) {
    androidIdBuffer.write(chars[source.nextInt(chars.length)]);
  }
  final String androidId = androidIdBuffer.toString();
  final int timestamp = currentTimeMs ?? DateTime.now().millisecondsSinceEpoch;
  return QmDeviceIdentity(
    generation: generation,
    androidId: androidId,
    openUdid2: generateQmOpenUdid2(androidId, profile.imei, timestamp),
    dataLocalSnapshot: generateQmDataLocalSnapshot(
      profile,
      currentTimeMs: timestamp,
    ),
  );
}

Map<String, Object?> generateQmDataLocalSnapshot(
  QmDeviceProfile profile, {
  int? currentTimeMs,
}) {
  final int timestamp = currentTimeMs ?? DateTime.now().millisecondsSinceEpoch;
  final String normalTime = qmDataLocalTimestampText(timestamp ~/ 1000);
  final List<String> records = <String>[];
  final int statCount =
      _dataLocalStatPaths.length + _dataLocalLstatPaths.length;
  for (int index = 0; index < statCount; index += 1) {
    final String time = index == 2 ? '1969-12-31190000.000000000' : normalTime;
    records.addAll(<String>[time, time, '0', '0']);
  }
  for (int index = 0; index < _dataLocalStatvfsPaths.length; index += 1) {
    records.addAll(<String>[
      '0000000000000000',
      profile.dataLocalSize.toString(),
      profile.dataLocalSize.toString(),
    ]);
  }
  records.add('');
  return <String, Object?>{
    'version': qmDataLocalSnapshotVersion,
    'records': List<String>.unmodifiable(records),
  };
}

String qmDataLocalTimestampText(int timestampSeconds) {
  final DateTime value = DateTime.fromMillisecondsSinceEpoch(
    timestampSeconds * 1000,
  );
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}.000000000';
}

int qmJavaHashCode(String value) {
  int result = 0;
  for (final int codeUnit in value.codeUnits) {
    result = ((31 * result) + codeUnit) & 0xFFFFFFFF;
  }
  return result >= 0x80000000 ? result - 0x100000000 : result;
}

String generateQmOpenUdid2(String androidId, String imei, int currentTimeMs) {
  final int mostSignificant = qmJavaHashCode(androidId);
  final int leastSignificant =
      qmJavaHashCode(imei.isEmpty ? 'null' : imei) | currentTimeMs;
  return _bytesToHex(
    Uint8List.fromList(<int>[
      ..._packSignedInt64(mostSignificant),
      ..._packSignedInt64(leastSignificant),
    ]),
  );
}

/// 生成与 Python `json.dumps` 对齐的紧凑 JSON。
///
/// 指纹路径需要 ASCII 转义和递归 key 排序；preaudit 路径则关闭这两项并依赖
/// Map 插入顺序。显式实现该规则是为了避免 Dart/Python JSON 编码器细节漂移。
String encodePythonJson(
  Object? value, {
  required bool asciiOnly,
  required bool sortKeys,
}) {
  if (value == null) {
    return 'null';
  }
  if (value is bool || value is num) {
    return jsonEncode(value);
  }
  if (value is String) {
    final String encoded = jsonEncode(value);
    if (!asciiOnly) {
      return encoded;
    }
    final StringBuffer escaped = StringBuffer();
    for (final int unit in encoded.codeUnits) {
      if (unit <= 0x7F) {
        escaped.writeCharCode(unit);
      } else {
        escaped.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return escaped.toString();
  }
  if (value is Iterable) {
    return '[${value.map((Object? item) => encodePythonJson(item, asciiOnly: asciiOnly, sortKeys: sortKeys)).join(',')}]';
  }
  if (value is Map) {
    final List<MapEntry<String, Object?>> entries =
        <MapEntry<String, Object?>>[];
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(entry.key, 'key', 'JSON 对象 key 必须是字符串');
      }
      entries.add(MapEntry<String, Object?>(entry.key! as String, entry.value));
    }
    if (sortKeys) {
      entries.sort(
        (MapEntry<String, Object?> left, MapEntry<String, Object?> right) =>
            left.key.compareTo(right.key),
      );
    }
    return '{${entries.map((MapEntry<String, Object?> entry) {
      final String key = encodePythonJson(entry.key, asciiOnly: asciiOnly, sortKeys: sortKeys);
      final String item = encodePythonJson(entry.value, asciiOnly: asciiOnly, sortKeys: sortKeys);
      return '$key:$item';
    }).join(',')}}';
  }
  throw ArgumentError.value(value, 'value', '不支持的 JSON 值类型');
}

Map<String, Object?> _freezeSnapshot(Map<String, Object?> snapshot) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final MapEntry<String, Object?> entry in snapshot.entries)
      entry.key: _freezeJsonValue(entry.value),
  });
}

Object? _freezeJsonValue(Object? value) {
  if (value is List) {
    return List<Object?>.unmodifiable(value.map<Object?>(_freezeJsonValue));
  }
  if (value is Map) {
    final Map<String, Object?> result = <String, Object?>{};
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      if (entry.key is! String) {
        throw ArgumentError.value(
          entry.key,
          'snapshot key',
          'JSON 对象 key 必须是字符串',
        );
      }
      result[entry.key! as String] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  return value;
}

bool _isLowerHex(String value, int length) {
  if (value.length != length) {
    return false;
  }
  for (final int codeUnit in value.codeUnits) {
    final bool digit = codeUnit >= 0x30 && codeUnit <= 0x39;
    final bool lowerHex = codeUnit >= 0x61 && codeUnit <= 0x66;
    if (!digit && !lowerHex) {
      return false;
    }
  }
  return true;
}

Uint8List _packSignedInt64(int value) {
  BigInt encoded = BigInt.from(value);
  if (encoded.isNegative) {
    encoded += BigInt.one << 64;
  }
  final Uint8List out = Uint8List(8);
  for (int index = 7; index >= 0; index -= 1) {
    out[index] = (encoded & BigInt.from(0xFF)).toInt();
    encoded >>= 8;
  }
  return out;
}

String _bytesToHex(Uint8List bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
