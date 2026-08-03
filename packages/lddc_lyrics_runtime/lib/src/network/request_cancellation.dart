import 'dart:async';

/// 网络请求取消令牌。
///
/// 令牌既可以由调用方直接取消，也可以通过 [child] 创建来源级子令牌。
/// 子令牌会跟随父令牌取消，释放时移除父监听，避免长驻 runtime 累积回调。
final class RequestCancellationToken {
  RequestCancellationToken({RequestCancellationToken? parent}) {
    if (parent != null) {
      _removeParentListener = parent.addCancellationListener(cancel);
      if (parent.isCancelled) {
        cancel();
      }
    }
  }

  final Completer<void> _cancelledCompleter = Completer<void>();
  final Set<void Function()> _listeners = <void Function()>{};
  void Function()? _removeParentListener;
  bool _disposed = false;

  /// 当前令牌是否已经取消。
  bool get isCancelled => _cancelledCompleter.isCompleted;

  /// 取消完成通知；重复取消不会重复完成 Future。
  Future<void> get whenCancelled => _cancelledCompleter.future;

  /// 当前令牌尚未取消时创建一个跟随父令牌的子令牌。
  RequestCancellationToken child() {
    final RequestCancellationToken value = RequestCancellationToken(
      parent: this,
    );
    if (isCancelled) {
      value.cancel();
    }
    return value;
  }

  /// 幂等取消，并通知当前令牌的所有监听者。
  void cancel() {
    if (isCancelled) {
      return;
    }
    _cancelledCompleter.complete();
    final List<void Function()> listeners = List<void Function()>.of(
      _listeners,
    );
    for (final void Function() listener in listeners) {
      listener();
    }
  }

  /// 取消时抛出统一异常，供 request executor 在 retry 前检查。
  void throwIfCancelled() {
    if (isCancelled) {
      throw const RequestCancelledException();
    }
  }

  /// 注册取消监听并返回移除函数。
  void Function() addCancellationListener(void Function() listener) {
    if (isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () {
      _listeners.remove(listener);
    };
  }

  /// 释放父子监听；不影响令牌本身已经发出的取消状态。
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _removeParentListener?.call();
    _removeParentListener = null;
    _listeners.clear();
  }

  /// 读取当前 Zone 绑定的令牌，供内部 transport adapter 透传。
  static RequestCancellationToken? get current =>
      Zone.current[_zoneKey] as RequestCancellationToken?;

  /// 在当前异步调用链绑定令牌，避免每个协议 adapter 重复复制透传代码。
  static Future<T> runWith<T>(
    RequestCancellationToken token,
    Future<T> Function() action,
  ) {
    return runZoned<Future<T>>(
      action,
      zoneValues: <Object?, Object?>{_zoneKey: token},
    );
  }

  static const Object _zoneKey = #lddcRequestCancellationToken;
}

/// 请求在调用方主动取消后的控制流异常。
final class RequestCancelledException implements Exception {
  const RequestCancelledException();

  @override
  String toString() => 'RequestCancelledException';
}

/// 请求达到单次或来源 deadline 后的超时异常。
final class RequestTimeoutException extends TimeoutException {
  RequestTimeoutException(Duration duration)
    : super('请求达到 deadline: $duration', duration);

  @override
  String toString() => 'RequestTimeoutException: $duration';
}
