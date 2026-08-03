import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

/// 桌面窗口刷新率回退值。
const int kDesktopFallbackRefreshRate = 60;

/// 窗口有效刷新率来源。
enum DesktopWindowRefreshSource { configured, display, fallback }

/// 当前窗口所在显示器的最小快照。
class DesktopWindowDisplaySnapshot {
  const DesktopWindowDisplaySnapshot({
    required this.displayId,
    required this.refreshRate,
  });

  final int displayId;
  final double refreshRate;
}

/// 窗口刷新率解析结果。
class DesktopWindowRefreshState {
  const DesktopWindowRefreshState({
    required this.configuredRefreshRate,
    required this.effectiveRefreshRate,
    required this.source,
    this.displayId,
  });

  const DesktopWindowRefreshState.fallback({this.configuredRefreshRate = -1})
    : effectiveRefreshRate = kDesktopFallbackRefreshRate,
      source = DesktopWindowRefreshSource.fallback,
      displayId = null;

  final int configuredRefreshRate;
  final int effectiveRefreshRate;
  final DesktopWindowRefreshSource source;
  final int? displayId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is DesktopWindowRefreshState &&
        other.configuredRefreshRate == configuredRefreshRate &&
        other.effectiveRefreshRate == effectiveRefreshRate &&
        other.source == source &&
        other.displayId == displayId;
  }

  @override
  int get hashCode => Object.hash(
    configuredRefreshRate,
    effectiveRefreshRate,
    source,
    displayId,
  );
}

/// 从 Flutter 当前 View 提取显示器刷新率信息。
DesktopWindowDisplaySnapshot? desktopWindowDisplaySnapshotForView(
  FlutterView? view,
) {
  if (view == null) {
    return null;
  }
  final Display display = view.display;
  return DesktopWindowDisplaySnapshot(
    displayId: display.id,
    refreshRate: display.refreshRate,
  );
}

/// 解析窗口当前应使用的有效刷新率。
DesktopWindowRefreshState resolveDesktopWindowRefreshState({
  required int configuredRefreshRate,
  required DesktopWindowDisplaySnapshot? displaySnapshot,
}) {
  if (configuredRefreshRate > 0) {
    return DesktopWindowRefreshState(
      configuredRefreshRate: configuredRefreshRate,
      effectiveRefreshRate: configuredRefreshRate,
      source: DesktopWindowRefreshSource.configured,
      displayId: displaySnapshot?.displayId,
    );
  }

  if (configuredRefreshRate == -1 && displaySnapshot != null) {
    final int roundedRefreshRate = displaySnapshot.refreshRate.round();
    if (roundedRefreshRate > 0) {
      return DesktopWindowRefreshState(
        configuredRefreshRate: configuredRefreshRate,
        effectiveRefreshRate: roundedRefreshRate,
        source: DesktopWindowRefreshSource.display,
        displayId: displaySnapshot.displayId,
      );
    }
  }

  return DesktopWindowRefreshState(
    configuredRefreshRate: configuredRefreshRate,
    effectiveRefreshRate: kDesktopFallbackRefreshRate,
    source: DesktopWindowRefreshSource.fallback,
    displayId: displaySnapshot?.displayId,
  );
}

/// 窗口级刷新率解析控制器。
///
/// 说明：
/// - 显式配置值优先；
/// - 自动模式只在本地窗口壳解析所在显示器刷新率；
/// - 换屏/系统指标变化时通过去抖重算，避免拖动窗口时高频抖动。
class DesktopWindowRefreshController extends ChangeNotifier {
  DesktopWindowRefreshController(
    this._displaySnapshotProvider, {
    this.debounceDuration = const Duration(milliseconds: 120),
  });

  final DesktopWindowDisplaySnapshot? Function() _displaySnapshotProvider;
  final Duration debounceDuration;

  Timer? _debounceTimer;
  int _configuredRefreshRate = -1;
  DesktopWindowRefreshState _state = const DesktopWindowRefreshState.fallback();

  DesktopWindowRefreshState get state => _state;

  void updateConfiguredRefreshRate(
    int configuredRefreshRate, {
    bool immediate = false,
  }) {
    final bool changed = _configuredRefreshRate != configuredRefreshRate;
    _configuredRefreshRate = configuredRefreshRate;
    if (changed || immediate) {
      scheduleResolve(immediate: immediate);
    }
  }

  void scheduleResolve({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _resolveNow();
      return;
    }
    _debounceTimer = Timer(debounceDuration, _resolveNow);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _resolveNow() {
    final DesktopWindowRefreshState next = resolveDesktopWindowRefreshState(
      configuredRefreshRate: _configuredRefreshRate,
      displaySnapshot: _displaySnapshotProvider(),
    );
    if (next == _state) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}
