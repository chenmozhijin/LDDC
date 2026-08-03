import '../../cache/cache.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

const String _qmDeviceCacheNamespace = 'qm_device';
const String _qmDeviceCacheKey = 'identity';
const int _qmDeviceCacheVersion = 1;

typedef QimeiRegisterCallback =
    Future<({String qimei16, String qimei36})> Function(
      QmDeviceIdentity identity,
    );

/// QM 设备身份的单一事实来源。
///
/// 数据库事务只执行同步比较和写回。REGISTER 通过进程内单飞 Future 在事务外
/// 完成，既避免长时间占用 SQLite 锁，也防止同一 generation 重复注册。
final class QmDeviceIdentityRepository {
  QmDeviceIdentityRepository({required this._cache});

  final CacheFacade _cache;
  final Map<String, Future<QmDeviceIdentity>> _registerFutures =
      <String, Future<QmDeviceIdentity>>{};

  int get pendingRegisterCount => _registerFutures.length;

  Future<QmDeviceIdentity> loadOrCreate(QmDeviceProfile profile) async {
    late QmDeviceIdentity selected;
    await _cache.updateAtomically(_qmDeviceCacheNamespace, _qmDeviceCacheKey, (
      Object? raw,
    ) {
      QmDeviceIdentity? identity = QmDeviceIdentity.tryDecode(raw);
      identity ??= generateQmDeviceIdentity(profile, generation: 0);
      if (identity.qimei36.isNotEmpty &&
          identity.qimeiProfileFingerprint !=
              identity.qimeiFingerprint(profile)) {
        identity = identity.clearQimei();
      }
      selected = identity;
      return identity.toJson();
    }, cacheVersion: _qmDeviceCacheVersion);
    return selected;
  }

  Future<({QmDeviceIdentity identity, bool replaced})> replaceIfGeneration(
    QmDeviceProfile profile,
    int expectedGeneration,
  ) async {
    late QmDeviceIdentity selected;
    bool replaced = false;
    await _cache.updateAtomically(_qmDeviceCacheNamespace, _qmDeviceCacheKey, (
      Object? raw,
    ) {
      final QmDeviceIdentity current =
          QmDeviceIdentity.tryDecode(raw) ??
          generateQmDeviceIdentity(profile, generation: 0);
      if (current.generation != expectedGeneration) {
        selected = current;
        return current.toJson();
      }
      selected = generateQmDeviceIdentity(
        profile,
        generation: current.generation + 1,
      );
      replaced = true;
      return selected.toJson();
    }, cacheVersion: _qmDeviceCacheVersion);
    return (identity: selected, replaced: replaced);
  }

  Future<QmDeviceIdentity> ensureQimei(
    QmDeviceProfile profile,
    QmDeviceIdentity identity,
    QimeiRegisterCallback register,
  ) {
    if (hasValidCachedQimei(identity, profile)) {
      return Future<QmDeviceIdentity>.value(identity);
    }
    final String key = '${identity.generation}:${identity.androidId}';
    final Future<QmDeviceIdentity>? active = _registerFutures[key];
    if (active != null) {
      return active;
    }
    final Future<QmDeviceIdentity> future = _ensureQimei(
      profile,
      identity,
      register,
    );
    _registerFutures[key] = future;
    return future.whenComplete(() {
      if (identical(_registerFutures[key], future)) {
        _registerFutures.remove(key);
      }
    });
  }

  Future<QmDeviceIdentity> _ensureQimei(
    QmDeviceProfile profile,
    QmDeviceIdentity requested,
    QimeiRegisterCallback register,
  ) async {
    final QmDeviceIdentity current = await loadOrCreate(profile);
    if (hasValidCachedQimei(current, profile)) {
      return current;
    }
    final ({String qimei16, String qimei36}) registered = await register(
      current,
    );
    validateQimeiIdentity(registered.qimei16, registered.qimei36);
    late QmDeviceIdentity selected;
    await _cache.updateAtomically(_qmDeviceCacheNamespace, _qmDeviceCacheKey, (
      Object? raw,
    ) {
      final QmDeviceIdentity latest =
          QmDeviceIdentity.tryDecode(raw) ?? current;
      if (hasValidCachedQimei(latest, profile)) {
        selected = latest;
        return latest.toJson();
      }
      // REGISTER 完成期间若身份已经被 2001 恢复替换，旧 q36 绝不能覆盖新身份。
      if (latest.generation != current.generation ||
          latest.androidId != current.androidId) {
        selected = latest;
        return latest.toJson();
      }
      selected = latest.withQimei(
        profile,
        registered.qimei16,
        registered.qimei36,
      );
      return selected.toJson();
    }, cacheVersion: _qmDeviceCacheVersion);
    return selected;
  }
}

bool hasValidCachedQimei(QmDeviceIdentity identity, QmDeviceProfile profile) {
  if (identity.qimeiProfileFingerprint != identity.qimeiFingerprint(profile)) {
    return false;
  }
  try {
    validateQimeiIdentity(identity.qimei16, identity.qimei36);
    return true;
  } on QimeiProtocolException {
    return false;
  }
}
