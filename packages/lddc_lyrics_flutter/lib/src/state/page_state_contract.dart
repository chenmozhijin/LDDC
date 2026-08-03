import 'async_view_state.dart';

/// 页面动作阶段：用于统一表达“空闲/执行中”。
enum PageActionPhase { idle, running }

/// 页面动作状态：承载全局提示与执行态。
final class PageActionState {
  const PageActionState({this.phase = PageActionPhase.idle, this.message});

  final PageActionPhase phase;
  final String? message;

  bool get isRunning => phase == PageActionPhase.running;

  PageActionState copyWith({
    PageActionPhase? phase,
    String? message,
    bool clearMessage = false,
  }) {
    return PageActionState(
      phase: phase ?? this.phase,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// 页面状态契约：统一“视图数据态 + 动作态 + 最后更新时间”。
final class PageViewState<T> {
  const PageViewState({
    required this.view,
    this.action = const PageActionState(),
    this.lastUpdatedAt,
  });

  final AsyncViewState<T> view;
  final PageActionState action;
  final DateTime? lastUpdatedAt;

  PageViewState<T> copyWith({
    AsyncViewState<T>? view,
    PageActionState? action,
    DateTime? lastUpdatedAt,
    bool clearLastUpdatedAt = false,
  }) {
    return PageViewState<T>(
      view: view ?? this.view,
      action: action ?? this.action,
      lastUpdatedAt: clearLastUpdatedAt
          ? null
          : (lastUpdatedAt ?? this.lastUpdatedAt),
    );
  }
}
