/// 页面异步状态模型。
///
/// 这个类型描述 controller/application 层的状态，而不是具体 UI 控件，所以放在
/// shared/state。UI 组件只负责根据状态渲染，不反向成为业务状态的依赖来源。
sealed class AsyncViewState<T> {
  const AsyncViewState();
}

final class AsyncLoading<T> extends AsyncViewState<T> {
  const AsyncLoading({this.message});

  final String? message;
}

final class AsyncEmpty<T> extends AsyncViewState<T> {
  const AsyncEmpty({this.message});

  final String? message;
}

final class AsyncError<T> extends AsyncViewState<T> {
  const AsyncError({required this.message, this.detail});

  final String message;
  final String? detail;
}

final class AsyncPartial<T> extends AsyncViewState<T> {
  const AsyncPartial({required this.data, this.message, this.warningMessage});

  final T data;
  final String? message;
  final String? warningMessage;
}

final class AsyncSuccess<T> extends AsyncViewState<T> {
  const AsyncSuccess({required this.data});

  final T data;
}
