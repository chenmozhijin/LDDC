import 'dart:async';

/// 外部请求预算：统一收口超时与重试次数。
///
/// 这是跨歌词源和翻译源都能复用的纯策略对象，不依赖 Flutter、平台插件或 app
/// 装配层。放在 core 中可以让 infra 初始化器直接复用，避免 infra 反向依赖 app。
class NetworkRequestBudget {
  const NetworkRequestBudget({required this.timeout, required this.retryCount});

  final Duration timeout;
  final int retryCount;
}

/// 执行一个已经具备超时能力的异步请求，并只对 [TimeoutException] 重试。
///
/// 这个函数不会额外调用 `Future.timeout`。HTTP 传输层负责在超时后中止底层请求，
/// 此处只决定“收到明确超时结果后是否再发起一次请求”，避免歌词与翻译模块分别维护
/// 两套容易产生差异的重试循环。小于 1 的次数会按 1 次处理，确保请求至少执行一次。
Future<T> retryTimedOutRequest<T>(
  Future<T> Function() action, {
  required int maxAttempts,
}) async {
  final int attempts = maxAttempts < 1 ? 1 : maxAttempts;
  for (int index = 0; index < attempts; index += 1) {
    try {
      return await action();
    } on TimeoutException {
      if (index == attempts - 1) {
        rethrow;
      }
    }
  }
  throw StateError('超时重试循环未返回结果');
}

/// 歌词源默认预算：保持现有生产语义。
const NetworkRequestBudget kDefaultLyricsRequestBudget = NetworkRequestBudget(
  timeout: Duration(seconds: 10),
  retryCount: 3,
);

/// 翻译默认预算：保持现有生产语义。
const NetworkRequestBudget kDefaultTranslateRequestBudget =
    NetworkRequestBudget(timeout: Duration(seconds: 30), retryCount: 1);
