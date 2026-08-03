import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../logging/desktop_lyrics_logger.dart';

import '../models/desktop_style_models.dart';
import '../render/desktop_render_models.dart';

class DesktopFloatingGeometryState {
  const DesktopFloatingGeometryState({
    this.isUserResizing = false,
    this.committedFontSizeOverride,
    this.lastResolvedFontSize,
  });

  final bool isUserResizing;
  final double? committedFontSizeOverride;
  final double? lastResolvedFontSize;

  DesktopFloatingGeometryState copyWith({
    bool? isUserResizing,
    double? committedFontSizeOverride,
    bool clearCommittedFontSizeOverride = false,
    double? lastResolvedFontSize,
  }) {
    return DesktopFloatingGeometryState(
      isUserResizing: isUserResizing ?? this.isUserResizing,
      committedFontSizeOverride: clearCommittedFontSizeOverride
          ? null
          : (committedFontSizeOverride ?? this.committedFontSizeOverride),
      lastResolvedFontSize: lastResolvedFontSize ?? this.lastResolvedFontSize,
    );
  }
}

/// 浮窗 frame 与原生窗口几何的事务协调器。
///
/// 所有 `setBounds` 都进入同一个 latest-wins 串行队列。高度增长先扩窗再
/// 允许 renderer 提交 candidate；高度缩小先提交 candidate，再缩窗。
class DesktopFloatingWindowGeometryCoordinator extends ChangeNotifier {
  DesktopFloatingWindowGeometryCoordinator({
    required this.isMounted,
    required this.setBounds,
    required this.awaitViewportStableBounds,
    required this.awaitNextFrame,
    required this.reapplyFlags,
    required this.scheduleRefreshRateResolve,
    required this.commitMetrics,
    required this.resolveSessionFontSize,
    DesktopLyricsLogger logger = const DesktopLyricsLogger(),
  }) : _logger = logger.child('floating-geometry');

  final bool Function() isMounted;
  final Future<void> Function(Rect bounds) setBounds;
  final Future<Rect?> Function() awaitViewportStableBounds;
  final Future<void> Function() awaitNextFrame;
  final Future<void> Function({bool force}) reapplyFlags;
  final void Function({bool immediate}) scheduleRefreshRateResolve;
  final Future<bool> Function(double fontSize) commitMetrics;
  final double Function() resolveSessionFontSize;
  final DesktopLyricsLogger _logger;

  DesktopFloatingGeometryState _state = const DesktopFloatingGeometryState();
  DesktopFloatingFrameMetrics? _latestCandidateMetrics;
  DesktopFloatingFrameMetrics? _committedMetrics;
  double _controlChromeHeight = 0;
  int _contentRevision = 0;
  int _nextBoundsRequestId = 0;
  int _latestBoundsRequestId = 0;
  _DesktopBoundsRequest? _pendingBoundsRequest;
  bool _boundsDrainRunning = false;
  Completer<void>? _boundsDrainCompleter;
  bool _programmaticBoundsChange = false;
  int _ignoreResizeEventsUntilMs = 0;
  Timer? _resizeIdleTimer;
  Timer? _geometryCommitTimer;
  bool _geometryDirty = false;
  int _geometryRevision = 0;
  Future<bool>? _geometryCommitFuture;
  bool _commitLatestAfterInFlight = false;

  DesktopFloatingGeometryState get state => _state;

  bool get isProgrammaticBoundsChange => _programmaticBoundsChange;

  bool get hasCommittedFrame => _committedMetrics != null;

  double effectiveFontSize(double sessionFontSize) {
    return _state.committedFontSizeOverride ?? sessionFontSize;
  }

  void updateControlChromeHeight(double height) {
    final double nextHeight = math.max(height.isFinite ? height : 0, 0);
    if ((nextHeight - _controlChromeHeight).abs() < 0.5) {
      return;
    }
    _controlChromeHeight = nextHeight;
    final DesktopFloatingFrameMetrics? metrics = _latestCandidateMetrics;
    if (metrics != null &&
        !_state.isUserResizing &&
        _isLatestCandidate(metrics)) {
      unawaited(_reconcileWindowHeight(metrics));
    }
  }

  void beginContentRevision(int revision) {
    if (revision <= _contentRevision) {
      return;
    }
    _contentRevision = revision;
    _latestCandidateMetrics = null;
  }

  Future<void> applyInitialWindowRect(WindowRect? windowRect) async {
    if (windowRect == null) {
      return;
    }
    await _enqueueFullBounds(
      bounds: Rect.fromLTWH(
        windowRect.left,
        windowRect.top,
        windowRect.width,
        windowRect.height,
      ),
      kind: _DesktopBoundsRequestKind.initialBounds,
      contentRevision: _contentRevision,
      layoutRevision: null,
      requireCurrentLayout: false,
      waitForViewport: false,
      suppressWindowEvents: true,
    );
  }

  Future<void> applyUserBounds(Rect bounds) async {
    final bool applied = await _enqueueFullBounds(
      bounds: bounds,
      kind: _DesktopBoundsRequestKind.userBounds,
      contentRevision: _contentRevision,
      layoutRevision: null,
      requireCurrentLayout: false,
      waitForViewport: false,
      suppressWindowEvents: false,
    );
    if (applied) {
      _markGeometryDirty();
    }
  }

  void reconcileSessionFontSize(double sessionFontSize) {
    final double? committedOverride = _state.committedFontSizeOverride;
    if (committedOverride == null ||
        (sessionFontSize - committedOverride).abs() >= 0.1) {
      return;
    }
    _state = _state.copyWith(clearCommittedFontSizeOverride: true);
    notifyListeners();
  }

  Future<bool> handleFrameCandidate(DesktopFloatingFrameMetrics metrics) async {
    if (!_isCurrentMetrics(metrics)) {
      return false;
    }
    _latestCandidateMetrics = metrics;
    _state = _state.copyWith(lastResolvedFontSize: metrics.resolvedFontSize);
    notifyListeners();
    if (_state.isUserResizing) {
      // 用户拖拽时原生 viewport 已经是几何真源。此时立即提交新布局，才能
      // 让字体和排版逐帧跟随窗口；禁止在这里反向 setBounds，避免拖拽抖动。
      return true;
    }
    final Rect? bounds = await awaitViewportStableBounds();
    if (bounds == null || !_isLatestCandidate(metrics)) {
      return false;
    }
    if (_targetWindowHeight(metrics) <= bounds.height + 1) {
      return true;
    }
    return _resizeForMetrics(metrics);
  }

  Future<void> handleFrameCommitted(DesktopFloatingFrameMetrics metrics) async {
    if (!_isLatestCandidate(metrics)) {
      return;
    }
    _committedMetrics = metrics;
    if (_state.isUserResizing) {
      return;
    }
    final Rect? bounds = await awaitViewportStableBounds();
    if (bounds == null || !_isCurrentMetrics(metrics)) {
      return;
    }
    if (_targetWindowHeight(metrics) < bounds.height - 1) {
      final bool resized = await _resizeForMetrics(metrics);
      if (!resized || !_isCurrentMetrics(metrics)) {
        return;
      }
    }
  }

  void didChangeMetrics() {
    scheduleRefreshRateResolve();
  }

  void onWindowResize() {
    if (_shouldIgnoreResizeEvent()) {
      return;
    }
    _resizeIdleTimer?.cancel();
    if (_state.isUserResizing) {
      return;
    }
    _state = _state.copyWith(isUserResizing: true);
    notifyListeners();
    unawaited(reapplyFlags(force: true));
  }

  void onWindowResized() {
    if (_shouldIgnoreResizeEvent()) {
      return;
    }
    _resizeIdleTimer?.cancel();
    _resizeIdleTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(_finalizeUserResize());
    });
  }

  void onWindowMove() {
    if (_programmaticBoundsChange) {
      return;
    }
    _markGeometryDirty();
    scheduleRefreshRateResolve();
  }

  void onWindowMoved() {
    if (_programmaticBoundsChange) {
      return;
    }
    _markGeometryDirty(immediate: true);
    scheduleRefreshRateResolve(immediate: true);
  }

  Future<bool> flushGeometry() async {
    _geometryCommitTimer?.cancel();
    _geometryCommitTimer = null;
    await _awaitBoundsDrain();
    if (!isMounted()) {
      return false;
    }
    // 关闭前无条件读取并提交一次真实 bounds，覆盖平台未派发 moved 事件的路径。
    _markGeometryDirty(schedule: false);
    while (_geometryDirty && isMounted()) {
      final bool committed = await _commitGeometry();
      if (!committed) {
        return false;
      }
    }
    return !_geometryDirty;
  }

  @override
  void dispose() {
    _resizeIdleTimer?.cancel();
    _geometryCommitTimer?.cancel();
    _pendingBoundsRequest?.complete(false);
    _pendingBoundsRequest = null;
    _boundsDrainCompleter?.complete();
    _boundsDrainCompleter = null;
    super.dispose();
  }

  bool _isCurrentMetrics(DesktopFloatingFrameMetrics metrics) {
    return isMounted() && metrics.contentRevision == _contentRevision;
  }

  bool _isLatestCandidate(DesktopFloatingFrameMetrics metrics) {
    final DesktopFloatingFrameMetrics? latest = _latestCandidateMetrics;
    return _isCurrentMetrics(metrics) &&
        latest != null &&
        latest.contentRevision == metrics.contentRevision &&
        latest.layoutRevision == metrics.layoutRevision;
  }

  Future<bool> _resizeForMetrics(DesktopFloatingFrameMetrics metrics) async {
    final double targetHeight = _targetWindowHeight(metrics);
    for (int attempt = 0; attempt < 3; attempt += 1) {
      if (!_isLatestCandidate(metrics)) {
        return false;
      }
      final bool applied = await _enqueueLayoutHeight(
        targetHeight: targetHeight,
        contentRevision: metrics.contentRevision,
        layoutRevision: metrics.layoutRevision,
        requireCurrentLayout: true,
        waitForViewport: true,
        suppressWindowEvents: true,
      );
      if (applied) {
        return true;
      }
      if (!_isCurrentMetrics(metrics)) {
        return false;
      }
      await awaitNextFrame();
      final Rect? stable = await awaitViewportStableBounds();
      if (stable == null) {
        continue;
      }
    }
    return false;
  }

  Future<void> _reconcileWindowHeight(
    DesktopFloatingFrameMetrics metrics,
  ) async {
    final Rect? bounds = await awaitViewportStableBounds();
    if (bounds == null || !_isLatestCandidate(metrics)) {
      return;
    }
    if ((_targetWindowHeight(metrics) - bounds.height).abs() <= 1) {
      return;
    }
    await _resizeForMetrics(metrics);
  }

  double _targetWindowHeight(DesktopFloatingFrameMetrics metrics) {
    return metrics.preferredHeight + _controlChromeHeight;
  }

  Future<bool> _enqueueFullBounds({
    required Rect bounds,
    required _DesktopBoundsRequestKind kind,
    required int contentRevision,
    required int? layoutRevision,
    required bool requireCurrentLayout,
    required bool waitForViewport,
    required bool suppressWindowEvents,
  }) {
    final int requestId = ++_nextBoundsRequestId;
    _latestBoundsRequestId = requestId;
    final _DesktopBoundsRequest request = _DesktopBoundsRequest(
      requestId: requestId,
      kind: kind,
      bounds: bounds,
      targetHeight: null,
      contentRevision: contentRevision,
      layoutRevision: layoutRevision,
      requireCurrentLayout: requireCurrentLayout,
      waitForViewport: waitForViewport,
      suppressWindowEvents: suppressWindowEvents,
    );
    _pendingBoundsRequest?.complete(false);
    _pendingBoundsRequest = request;
    _startBoundsDrain();
    return request.future;
  }

  Future<bool> _enqueueLayoutHeight({
    required double targetHeight,
    required int contentRevision,
    required int layoutRevision,
    required bool requireCurrentLayout,
    required bool waitForViewport,
    required bool suppressWindowEvents,
  }) {
    final int requestId = ++_nextBoundsRequestId;
    _latestBoundsRequestId = requestId;
    final _DesktopBoundsRequest request = _DesktopBoundsRequest(
      requestId: requestId,
      kind: _DesktopBoundsRequestKind.layoutHeight,
      bounds: null,
      targetHeight: targetHeight,
      contentRevision: contentRevision,
      layoutRevision: layoutRevision,
      requireCurrentLayout: requireCurrentLayout,
      waitForViewport: waitForViewport,
      suppressWindowEvents: suppressWindowEvents,
    );
    _pendingBoundsRequest?.complete(false);
    _pendingBoundsRequest = request;
    _startBoundsDrain();
    return request.future;
  }

  void _startBoundsDrain() {
    if (_boundsDrainRunning) {
      return;
    }
    _boundsDrainRunning = true;
    _boundsDrainCompleter = Completer<void>();
    unawaited(_drainBoundsRequests());
  }

  Future<void> _drainBoundsRequests() async {
    try {
      while (isMounted() && _pendingBoundsRequest != null) {
        final _DesktopBoundsRequest request = _pendingBoundsRequest!;
        _pendingBoundsRequest = null;
        if (!_requestIsCurrent(request)) {
          request.complete(false);
          continue;
        }
        final Rect? targetBounds = await _resolveRequestBounds(request);
        if (targetBounds == null || !_requestIsCurrent(request)) {
          request.complete(false);
          continue;
        }
        final bool oldProgrammaticState = _programmaticBoundsChange;
        if (request.suppressWindowEvents) {
          _programmaticBoundsChange = true;
          _ignoreResizeEventsUntilMs =
              DateTime.now().millisecondsSinceEpoch + 250;
        }
        bool applied = false;
        try {
          await setBounds(targetBounds);
          if (request.waitForViewport) {
            final Rect? stable = await awaitViewportStableBounds();
            applied =
                stable != null &&
                (stable.width - targetBounds.width).abs() <= 1 &&
                (stable.height - targetBounds.height).abs() <= 1;
          } else {
            applied = true;
          }
          scheduleRefreshRateResolve();
        } on Object catch (error, stackTrace) {
          _logger.warning(
            'set floating bounds failed'
            ' request=${request.requestId}'
            ' kind=${request.kind.name}'
            ' left=${targetBounds.left} top=${targetBounds.top}'
            ' size=${targetBounds.width}x${targetBounds.height}'
            ' error=$error stack=$stackTrace',
          );
        } finally {
          _programmaticBoundsChange = oldProgrammaticState;
        }
        request.complete(applied && _requestIsCurrent(request));
      }
    } finally {
      _boundsDrainRunning = false;
      _boundsDrainCompleter?.complete();
      _boundsDrainCompleter = null;
      if (_pendingBoundsRequest != null && isMounted()) {
        _startBoundsDrain();
      }
    }
  }

  Future<Rect?> _resolveRequestBounds(_DesktopBoundsRequest request) async {
    if (request.kind != _DesktopBoundsRequestKind.layoutHeight) {
      return request.bounds;
    }
    final Rect? current = await awaitViewportStableBounds();
    if (current == null || !_requestIsCurrent(request)) {
      return null;
    }
    // 自动布局只拥有高度。位置和宽度必须在执行系统调用前从原生窗口读取，
    // 禁止旧歌词 revision 携带历史 Rect 覆盖用户刚完成的移动。
    return Rect.fromLTWH(
      current.left,
      current.top,
      current.width,
      request.targetHeight!,
    );
  }

  Future<void> _awaitBoundsDrain() async {
    while (_boundsDrainRunning || _pendingBoundsRequest != null) {
      final Completer<void>? completer = _boundsDrainCompleter;
      if (completer == null) {
        _startBoundsDrain();
        continue;
      }
      await completer.future;
    }
  }

  bool _requestIsCurrent(_DesktopBoundsRequest request) {
    if (!isMounted() || request.requestId != _latestBoundsRequestId) {
      return false;
    }
    if (!request.requireCurrentLayout) {
      return true;
    }
    final DesktopFloatingFrameMetrics? latest = _latestCandidateMetrics;
    return request.contentRevision == _contentRevision &&
        latest?.contentRevision == request.contentRevision &&
        latest?.layoutRevision == request.layoutRevision;
  }

  bool _shouldIgnoreResizeEvent() {
    return _programmaticBoundsChange ||
        DateTime.now().millisecondsSinceEpoch < _ignoreResizeEventsUntilMs;
  }

  Future<void> _finalizeUserResize() async {
    if (!isMounted() || !_state.isUserResizing) {
      return;
    }
    final double resolvedFontSize =
        _state.lastResolvedFontSize ??
        effectiveFontSize(resolveSessionFontSize());
    _state = _state.copyWith(
      isUserResizing: false,
      committedFontSizeOverride: resolvedFontSize,
    );
    notifyListeners();
    await reapplyFlags(force: true);
    await awaitNextFrame();
    _markGeometryDirty(immediate: true);
    scheduleRefreshRateResolve(immediate: true);
  }

  void _markGeometryDirty({bool immediate = false, bool schedule = true}) {
    if (!isMounted() || _programmaticBoundsChange) {
      return;
    }
    _geometryDirty = true;
    _geometryRevision += 1;
    if (schedule) {
      _scheduleGeometryCommit(immediate: immediate);
    }
  }

  void _scheduleGeometryCommit({bool immediate = false}) {
    if (!isMounted() || _programmaticBoundsChange || _state.isUserResizing) {
      return;
    }
    _geometryCommitTimer?.cancel();
    _geometryCommitTimer = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 150),
      () {
        _geometryCommitTimer = null;
        if (!isMounted() ||
            _programmaticBoundsChange ||
            _state.isUserResizing ||
            !_geometryDirty) {
          return;
        }
        unawaited(_commitGeometry());
      },
    );
  }

  Future<bool> _commitGeometry() async {
    final Future<bool>? currentCommit = _geometryCommitFuture;
    if (currentCommit != null) {
      _commitLatestAfterInFlight = true;
      return currentCommit;
    }
    if (!_geometryDirty) {
      return true;
    }
    final int revision = _geometryRevision;
    final Future<bool> future = _commitMetricsGuarded(_resolvedFontSize);
    _geometryCommitFuture = future;
    final bool committed = await future;
    if (committed && revision == _geometryRevision) {
      _geometryDirty = false;
    }
    _geometryCommitFuture = null;
    if (_commitLatestAfterInFlight) {
      _commitLatestAfterInFlight = false;
      if (!isMounted() || _programmaticBoundsChange || _state.isUserResizing) {
        return committed;
      }
      if (_geometryDirty) {
        _scheduleGeometryCommit(immediate: true);
      }
    }
    return committed;
  }

  double get _resolvedFontSize {
    return _state.lastResolvedFontSize ??
        effectiveFontSize(resolveSessionFontSize());
  }

  Future<bool> _commitMetricsGuarded(double fontSize) async {
    try {
      return await commitMetrics(fontSize);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'commit floating metrics failed'
        ' fontSize=$fontSize error=$error stack=$stackTrace',
      );
      return false;
    }
  }
}

enum _DesktopBoundsRequestKind { initialBounds, userBounds, layoutHeight }

class _DesktopBoundsRequest {
  _DesktopBoundsRequest({
    required this.requestId,
    required this.kind,
    required this.bounds,
    required this.targetHeight,
    required this.contentRevision,
    required this.layoutRevision,
    required this.requireCurrentLayout,
    required this.waitForViewport,
    required this.suppressWindowEvents,
  });

  final int requestId;
  final _DesktopBoundsRequestKind kind;
  final Rect? bounds;
  final double? targetHeight;
  final int contentRevision;
  final int? layoutRevision;
  final bool requireCurrentLayout;
  final bool waitForViewport;
  final bool suppressWindowEvents;
  final Completer<bool> _completer = Completer<bool>();

  Future<bool> get future => _completer.future;

  void complete(bool applied) {
    if (!_completer.isCompleted) {
      _completer.complete(applied);
    }
  }
}
