import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import '../logging/desktop_lyrics_logger.dart';

import 'desktop_window_refresh.dart';

class DesktopWindowViewBindingCoordinator extends ChangeNotifier {
  DesktopWindowViewBindingCoordinator({
    required this.target,
    DesktopLyricsLogger logger = const DesktopLyricsLogger(),
  }) : _logger = logger.child('window-refresh') {
    _refreshController = DesktopWindowRefreshController(
      _currentDisplaySnapshot,
    );
    _refreshController.addListener(_handleRefreshStateChanged);
  }

  final String target;
  final DesktopLyricsLogger _logger;
  late final DesktopWindowRefreshController _refreshController;
  DesktopWindowRefreshState? _lastLoggedRefreshState;
  ui.FlutterView? _boundView;

  DesktopWindowRefreshState get state => _refreshController.state;

  ui.FlutterView? get boundView => _boundView;

  void bindView(ui.FlutterView? nextView) {
    if (identical(_boundView, nextView)) {
      return;
    }
    _boundView = nextView;
    scheduleResolve(immediate: true);
  }

  void updateConfiguredRefreshRate(int refreshRate, {bool immediate = false}) {
    _refreshController.updateConfiguredRefreshRate(
      refreshRate,
      immediate: immediate,
    );
  }

  void scheduleResolve({bool immediate = false}) {
    _refreshController.scheduleResolve(immediate: immediate);
  }

  DesktopWindowDisplaySnapshot? _currentDisplaySnapshot() {
    return desktopWindowDisplaySnapshotForView(_boundView);
  }

  void _handleRefreshStateChanged() {
    final DesktopWindowRefreshState next = _refreshController.state;
    if (_lastLoggedRefreshState != next && kDebugMode) {
      _logger.debug(
        'refresh state changed',
        fields: <String, Object?>{
          'target': target,
          'source': next.source.name,
          'configured': next.configuredRefreshRate,
          'effective': next.effectiveRefreshRate,
          'display': next.displayId,
        },
      );
    }
    _lastLoggedRefreshState = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshController
      ..removeListener(_handleRefreshStateChanged)
      ..dispose();
    super.dispose();
  }
}
