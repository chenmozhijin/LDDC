import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

const int _kFallbackRefreshRate = 60;
const int _kMinRefreshRate = 1;
const int _kMaxRefreshRate = 240;

class DesktopPlaybackTickerCoordinator {
  DesktopPlaybackTickerCoordinator({
    required TickerProvider vsync,
    required this.shouldTick,
    required this.tickPlaybackTime,
    required this.resolveRefreshRate,
    int? initialPlaybackTimeMs,
  }) : estimatedPlaybackTimeMsNotifier = ValueNotifier<int?>(
         initialPlaybackTimeMs,
       ) {
    _ticker = vsync.createTicker(_handleTick);
  }

  final bool Function() shouldTick;
  final int Function() tickPlaybackTime;
  final int Function() resolveRefreshRate;
  final ValueNotifier<int?> estimatedPlaybackTimeMsNotifier;
  late final Ticker _ticker;
  Duration? _lastTickerFrame;

  void syncCurrentTime(int? playbackTimeMs) {
    if (estimatedPlaybackTimeMsNotifier.value == playbackTimeMs) {
      return;
    }
    estimatedPlaybackTimeMsNotifier.value = playbackTimeMs;
  }

  void resetCadence() {
    _lastTickerFrame = null;
  }

  void syncTicker() {
    if (shouldTick()) {
      if (!_ticker.isActive) {
        _lastTickerFrame = null;
        _ticker.start();
      }
      return;
    }
    _ticker.stop();
    _lastTickerFrame = null;
  }

  void _handleTick(Duration elapsed) {
    if (!shouldTick()) {
      return;
    }
    final int refreshRate = _sanitizeRefreshRate(resolveRefreshRate());
    final Duration frameInterval = Duration(
      microseconds: (1000000 / refreshRate).round(),
    );
    final Duration? lastFrame = _lastTickerFrame;
    if (lastFrame != null && elapsed - lastFrame < frameInterval) {
      return;
    }
    _lastTickerFrame = elapsed;
    final int nextPlaybackTime = tickPlaybackTime();
    if (estimatedPlaybackTimeMsNotifier.value == nextPlaybackTime) {
      return;
    }
    estimatedPlaybackTimeMsNotifier.value = nextPlaybackTime;
  }

  void dispose() {
    _ticker.dispose();
    estimatedPlaybackTimeMsNotifier.dispose();
  }

  int _sanitizeRefreshRate(int value) {
    // 配置或插件侧传入 0/负数/异常高值时，直接用于除法会触发异常或让
    // ticker 接近忙等；这里在窗口热路径入口统一限幅。
    if (value <= 0) {
      return _kFallbackRefreshRate;
    }
    return value.clamp(_kMinRefreshRate, _kMaxRefreshRate);
  }
}
