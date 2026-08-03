import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'http_transport.dart';
import '../network/request_cancellation.dart';

/// 基于 `dart:io HttpClient` 的共享 HTTP 传输实现。
class IoHttpTransport implements StreamingHttpTransport {
  IoHttpTransport({
    HttpClient? client,
    bool autoUncompress = true,
    this.requestOpener,
  }) : _client = client ?? HttpClient() {
    _client.autoUncompress = autoUncompress;
  }

  final HttpClient _client;
  // opener 只用于验证连接阶段的迟到 request 回收；生产环境始终使用 HttpClient。
  // IoHttpTransport 不从公共 barrel 导出，因此该测试注入点不会扩大 Runtime API。
  final Future<HttpClientRequest> Function(String method, Uri uri)?
  requestOpener;
  final Set<HttpClientRequest> _activeRequests = <HttpClientRequest>{};
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final HttpClientRequest request in _activeRequests.toList()) {
      request.abort(const RequestCancelledException());
    }
    _activeRequests.clear();
    _client.close(force: true);
  }

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) async {
    _ensureOpen();
    final RequestCancellationToken? token = request.cancellationToken;
    token?.throwIfCancelled();
    final Uri targetUri = _withQueryParameters(
      request.uri,
      request.queryParameters,
    );
    HttpClientRequest? nativeRequest;
    bool abandonOpenRequest = false;
    final Future<HttpClientRequest> openFuture = _openRequest(
      request.method,
      targetUri,
    );
    unawaited(
      openFuture.then<void>((HttpClientRequest lateRequest) {
        if (abandonOpenRequest || _closed || (token?.isCancelled ?? false)) {
          lateRequest.abort(const RequestCancelledException());
        }
      }, onError: (Object _, StackTrace _) {}),
    );

    try {
      nativeRequest = await _awaitStage<HttpClientRequest>(
        openFuture,
        timeout: request.timeout,
        token: token,
        onAbort: () {},
      );
      _activeRequests.add(nativeRequest);
      token?.throwIfCancelled();
      request.headers.forEach(nativeRequest.headers.set);
      final Uint8List? body = request.body;
      if (body != null && body.isNotEmpty) {
        nativeRequest.add(body);
      }

      final HttpClientResponse nativeResponse =
          await _awaitStage<HttpClientResponse>(
            nativeRequest.close(),
            timeout: request.timeout,
            token: token,
            onAbort: () =>
                nativeRequest?.abort(const RequestCancelledException()),
          );
      final Uint8List responseBody = await _readBody(
        nativeResponse,
        timeout: request.timeout,
        token: token,
        onAbort: () => nativeRequest?.abort(const RequestCancelledException()),
      );
      return HttpTransportResponse(
        statusCode: nativeResponse.statusCode,
        body: responseBody,
        headers: _readHeaders(nativeResponse),
        cookies: _readCookies(nativeResponse),
      );
    } catch (_) {
      abandonOpenRequest = true;
      rethrow;
    } finally {
      if (nativeRequest != null) {
        _activeRequests.remove(nativeRequest);
      }
    }
  }

  @override
  Future<HttpTransportStreamResponse> sendStream(
    HttpTransportRequest request,
  ) async {
    _ensureOpen();
    final RequestCancellationToken? token = request.cancellationToken;
    token?.throwIfCancelled();
    final Uri targetUri = _withQueryParameters(
      request.uri,
      request.queryParameters,
    );
    HttpClientRequest? nativeRequest;
    bool abandonOpenRequest = false;
    final Future<HttpClientRequest> openFuture = _openRequest(
      request.method,
      targetUri,
    );
    // openUrl 在 DNS/连接阶段尚未返回 HttpClientRequest，无法立刻调用 abort。
    // 这里观察迟到结果：调用方取消、阶段超时或 transport 关闭后，只要 request
    // 最终创建成功就立即 abort，避免未登记到活动集合的 socket 继续存活。
    unawaited(
      openFuture.then<void>((HttpClientRequest lateRequest) {
        if (abandonOpenRequest || _closed || (token?.isCancelled ?? false)) {
          lateRequest.abort(const RequestCancelledException());
        }
      }, onError: (Object _, StackTrace _) {}),
    );

    try {
      final HttpClientRequest requestHandle =
          await _awaitStage<HttpClientRequest>(
            openFuture,
            timeout: request.timeout,
            token: token,
            onAbort: () {},
          );
      nativeRequest = requestHandle;
      _activeRequests.add(requestHandle);
      token?.throwIfCancelled();
      request.headers.forEach(requestHandle.headers.set);
      final Uint8List? body = request.body;
      if (body != null && body.isNotEmpty) {
        requestHandle.add(body);
      }

      final HttpClientResponse nativeResponse =
          await _awaitStage<HttpClientResponse>(
            requestHandle.close(),
            timeout: request.timeout,
            token: token,
            onAbort: () =>
                requestHandle.abort(const RequestCancelledException()),
          );
      return HttpTransportStreamResponse(
        statusCode: nativeResponse.statusCode,
        body: _cancellableBodyStream(
          nativeResponse,
          request: requestHandle,
          timeout: request.timeout,
          token: token,
        ),
        headers: _readHeaders(nativeResponse),
        cookies: _readCookies(nativeResponse),
      );
    } catch (_) {
      abandonOpenRequest = true;
      if (nativeRequest != null) {
        _activeRequests.remove(nativeRequest);
      }
      rethrow;
    }
  }

  Future<HttpClientRequest> _openRequest(String method, Uri uri) {
    final Future<HttpClientRequest> Function(String method, Uri uri)? opener =
        requestOpener;
    if (opener != null) {
      return opener(method.toUpperCase(), uri);
    }
    return switch (method.toUpperCase()) {
      'POST' => _client.postUrl(uri),
      'GET' => _client.getUrl(uri),
      _ => _client.openUrl(method.toUpperCase(), uri),
    };
  }

  Future<T> _awaitStage<T>(
    Future<T> future, {
    required Duration timeout,
    required RequestCancellationToken? token,
    required void Function() onAbort,
  }) {
    token?.throwIfCancelled();
    final Completer<T> completer = Completer<T>();
    Timer? timer;
    void Function()? removeCancellationListener;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      onAbort();
      if (stackTrace == null) {
        completer.completeError(error);
      } else {
        completer.completeError(error, stackTrace);
      }
    }

    future.then<void>(
      (T value) {
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        completeError(error, stackTrace);
      },
    );
    timer = Timer(
      timeout,
      () => completeError(RequestTimeoutException(timeout)),
    );
    removeCancellationListener = token?.addCancellationListener(
      () => completeError(const RequestCancelledException()),
    );
    return completer.future.whenComplete(() {
      timer?.cancel();
      removeCancellationListener?.call();
    });
  }

  Future<Uint8List> _readBody(
    HttpClientResponse response, {
    required Duration timeout,
    required RequestCancellationToken? token,
    required void Function() onAbort,
  }) {
    token?.throwIfCancelled();
    final Completer<Uint8List> completer = Completer<Uint8List>();
    final BytesBuilder builder = BytesBuilder(copy: false);
    late final StreamSubscription<List<int>> subscription;
    Timer? timer;
    void Function()? removeCancellationListener;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      onAbort();
      unawaited(subscription.cancel());
      if (stackTrace == null) {
        completer.completeError(error);
      } else {
        completer.completeError(error, stackTrace);
      }
    }

    subscription = response.listen(
      builder.add,
      onError: (Object error, StackTrace stackTrace) {
        completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(builder.takeBytes());
        }
      },
      cancelOnError: true,
    );
    timer = Timer(
      timeout,
      () => completeError(RequestTimeoutException(timeout)),
    );
    removeCancellationListener = token?.addCancellationListener(
      () => completeError(const RequestCancelledException()),
    );
    return completer.future.whenComplete(() {
      timer?.cancel();
      removeCancellationListener?.call();
    });
  }

  Stream<List<int>> _cancellableBodyStream(
    HttpClientResponse response, {
    required HttpClientRequest request,
    required Duration timeout,
    required RequestCancellationToken? token,
  }) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    void Function()? removeCancellationListener;
    bool finished = false;

    Future<void> finish([Object? error, StackTrace? stackTrace]) async {
      if (finished) {
        return;
      }
      finished = true;
      timer?.cancel();
      removeCancellationListener?.call();
      _activeRequests.remove(request);
      await subscription?.cancel();
      if (error != null) {
        controller.addError(error, stackTrace);
      }
      await controller.close();
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        if (finished) {
          return;
        }
        subscription = response.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            unawaited(finish(error, stackTrace));
          },
          onDone: () => unawaited(finish()),
        );
      },
      onCancel: () async {
        request.abort(const RequestCancelledException());
        await finish();
      },
    );
    // body stream 即使暂时无人监听也仍占用原生响应和 socket，因此 deadline 与
    // 取消监听必须从收到 headers 后立即生效，不能延迟到 Dart 订阅建立时才注册。
    timer = Timer(timeout, () {
      request.abort(RequestTimeoutException(timeout));
      unawaited(finish(RequestTimeoutException(timeout)));
    });
    removeCancellationListener = token?.addCancellationListener(() {
      request.abort(const RequestCancelledException());
      unawaited(finish(const RequestCancelledException()));
    });
    return controller.stream;
  }

  Map<String, String> _readHeaders(HttpClientResponse response) {
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach((String name, List<String> values) {
      if (values.isNotEmpty) {
        headers[name] = values.join(', ');
      }
    });
    return headers;
  }

  Map<String, String> _readCookies(HttpClientResponse response) {
    return <String, String>{
      for (final Cookie cookie in response.cookies) cookie.name: cookie.value,
    };
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('HTTP transport 已关闭');
    }
  }

  Uri _withQueryParameters(Uri uri, Map<String, String> queryParameters) {
    if (queryParameters.isEmpty) {
      return uri;
    }
    // 调用方可能传入已经带 query 的 endpoint，再补充本次请求参数。
    // 这里保留 URI 原有参数，只让显式 queryParameters 覆盖同名键，避免
    // token、版本号等预置参数被 replace() 整包丢掉。
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...queryParameters,
      },
    );
  }
}
