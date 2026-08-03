import 'package:flutter/foundation.dart';

/// 桌面歌词内部性能计数器。
///
/// 计数只在 debug/profile 模式启用，release 环境不会持续写入 Map。渲染缓存和
/// 窗口运行时都通过同一个单例记录命中、淘汰和内存估算，便于定位热路径抖动。
class DesktopLyricsPerfStats {
  DesktopLyricsPerfStats._();

  static final DesktopLyricsPerfStats instance = DesktopLyricsPerfStats._();

  final Map<String, int> _counters = <String, int>{};
  final Map<String, int> _peaks = <String, int>{};
  final Map<String, int> _latestValues = <String, int>{};

  bool get _enabled => kDebugMode || kProfileMode;

  void bump(String key, [int delta = 1]) {
    if (!_enabled || delta == 0) {
      return;
    }
    _counters.update(key, (int value) => value + delta, ifAbsent: () => delta);
  }

  void recordPeak(String key, int value) {
    if (!_enabled) {
      return;
    }
    final int? current = _peaks[key];
    if (current == null || value > current) {
      _peaks[key] = value;
    }
  }

  void recordLatest(String key, int value) {
    if (!_enabled) {
      return;
    }
    _latestValues[key] = value;
  }

  int counterOf(String key) => _counters[key] ?? 0;

  int peakOf(String key) => _peaks[key] ?? 0;

  int latestOf(String key) => _latestValues[key] ?? 0;

  Map<String, int> snapshotCounters() =>
      Map<String, int>.unmodifiable(_counters);

  Map<String, int> snapshotPeaks() => Map<String, int>.unmodifiable(_peaks);

  Map<String, int> snapshotLatestValues() =>
      Map<String, int>.unmodifiable(_latestValues);

  void reset() {
    if (!_enabled) {
      return;
    }
    _counters.clear();
    _peaks.clear();
    _latestValues.clear();
  }
}
