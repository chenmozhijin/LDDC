import 'dart:async';
import 'dart:io';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_runtime/src/api/http_transport_io.dart';
import 'package:test/test.dart';

void main() {
  test('openUrl 尚未返回时取消会 abort 迟到创建的 request', () async {
    final Completer<void> openStarted = Completer<void>();
    final Completer<HttpClientRequest> lateRequest =
        Completer<HttpClientRequest>();
    final _AbortRecordingRequest nativeRequest = _AbortRecordingRequest();
    final IoHttpTransport transport = IoHttpTransport(
      requestOpener: (String method, Uri uri) {
        openStarted.complete();
        return lateRequest.future;
      },
    );
    addTearDown(transport.close);
    final RequestCancellationToken token = RequestCancellationToken();
    addTearDown(token.dispose);

    final Future<HttpTransportResponse> pending = transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1/delayed-open'),
        timeout: const Duration(seconds: 5),
        cancellationToken: token,
      ),
    );
    await openStarted.future;
    token.cancel();
    await expectLater(pending, throwsA(isA<RequestCancelledException>()));

    // 模拟 DNS/连接 Future 在调用方已经离开后才交付 request。transport 必须继续
    // 观察该 Future 并回收迟到对象，不能因为外层 Future 已失败就丢失所有权。
    lateRequest.complete(nativeRequest);
    await Future<void>.delayed(Duration.zero);
    expect(nativeRequest.abortCalls, 1);
    expect(nativeRequest.abortReason, isA<RequestCancelledException>());
  });
}

final class _AbortRecordingRequest implements HttpClientRequest {
  int abortCalls = 0;
  Object? abortReason;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    abortCalls += 1;
    abortReason = exception;
  }

  // 此测试只会触发 abort；其余 HttpClientRequest 能力不应被连接阶段回收路径访问。
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
