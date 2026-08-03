import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  test('IoHttpTransport 统一写入请求并读取响应元数据', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final List<HttpRequest> requests = <HttpRequest>[];
    server.listen((HttpRequest request) async {
      requests.add(request);
      final List<int> body = await request.fold<List<int>>(
        <int>[],
        (List<int> previous, List<int> chunk) => previous..addAll(chunk),
      );
      request.response
        ..statusCode = 201
        ..headers.set('X-Reply', 'ok')
        ..cookies.add(Cookie('sid', 'cookie-value'))
        ..add(body)
        ..close();
    });

    final HttpTransport transport = createDefaultHttpTransport();
    addTearDown(transport.close);

    final HttpTransportResponse response = await transport.send(
      HttpTransportRequest(
        method: 'POST',
        uri: Uri.parse(
          'http://127.0.0.1:${server.port}/api?token=keep&version=1',
        ),
        queryParameters: const <String, String>{'q': '歌词', 'token': 'new'},
        headers: const <String, String>{'X-Test': 'header-value'},
        body: Uint8List.fromList(<int>[1, 2, 3]),
        timeout: const Duration(seconds: 2),
      ),
    );

    expect(response.statusCode, 201);
    expect(response.body, <int>[1, 2, 3]);
    expect(response.headers['x-reply'] ?? response.headers['X-Reply'], 'ok');
    expect(response.cookies['sid'], 'cookie-value');
    expect(requests.single.uri.queryParameters['q'], '歌词');
    expect(requests.single.uri.queryParameters['token'], 'new');
    expect(requests.single.uri.queryParameters['version'], '1');
    expect(requests.single.headers.value('X-Test'), 'header-value');
  });

  test('IoHttpTransport 响应超时会及时抛出 TimeoutException', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response
        ..statusCode = 200
        ..write('late')
        ..close();
    });

    final HttpTransport transport = createDefaultHttpTransport();
    addTearDown(transport.close);

    await expectLater(
      transport.send(
        HttpTransportRequest(
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:${server.port}/slow'),
          timeout: const Duration(milliseconds: 20),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('IoHttpTransport 取消等待响应头时会立即 abort', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> accepted = Completer<void>();
    server.listen((HttpRequest request) {
      if (!accepted.isCompleted) {
        accepted.complete();
      }
      // 服务端故意不发送响应头，用来验证取消不会继续等待 transport timeout。
    });

    final HttpTransport transport = createDefaultHttpTransport();
    addTearDown(transport.close);
    final RequestCancellationToken token = RequestCancellationToken();
    addTearDown(token.dispose);
    final Stopwatch stopwatch = Stopwatch()..start();
    final Future<HttpTransportResponse> pending = transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/cancel'),
        timeout: const Duration(seconds: 5),
        cancellationToken: token,
      ),
    );
    await accepted.future;

    token.cancel();

    await expectLater(
      pending.timeout(const Duration(seconds: 1)),
      throwsA(isA<RequestCancelledException>()),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('IoHttpTransport 取消未监听的响应体也会释放原生请求', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> headersSent = Completer<void>();
    final Completer<void> releaseBody = Completer<void>();
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = 200
        ..headers.chunkedTransferEncoding = true
        ..write('header');
      await request.response.flush();
      if (!headersSent.isCompleted) {
        headersSent.complete();
      }
      await releaseBody.future;
      request.response.write('tail');
      await request.response.close();
    });

    final StreamingHttpTransport transport =
        createDefaultHttpTransport() as StreamingHttpTransport;
    addTearDown(transport.close);
    final RequestCancellationToken token = RequestCancellationToken();
    addTearDown(token.dispose);
    final HttpTransportStreamResponse response = await transport.sendStream(
      HttpTransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/stream-cancel'),
        timeout: const Duration(seconds: 5),
        cancellationToken: token,
      ),
    );
    await headersSent.future;
    token.cancel();
    releaseBody.complete();

    await expectLater(
      response.body.toList(),
      throwsA(isA<RequestCancelledException>()),
    );
  });

  test('IoHttpTransport 流式响应体超时会 abort 并结束读取', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      request.response
        ..statusCode = 200
        ..headers.chunkedTransferEncoding = true
        ..write('header');
      await request.response.flush();
      // 不关闭响应，模拟 SSE/分块响应停滞在 body 阶段。
    });

    final StreamingHttpTransport transport =
        createDefaultHttpTransport() as StreamingHttpTransport;
    addTearDown(transport.close);
    final HttpTransportStreamResponse response = await transport.sendStream(
      HttpTransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/stream-timeout'),
        timeout: const Duration(milliseconds: 40),
      ),
    );

    await expectLater(
      response.body.toList(),
      throwsA(isA<RequestTimeoutException>()),
    );
  });

  test('IoHttpTransport.close 对未完成请求幂等并取消底层请求', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() => server.close(force: true));
    final Completer<void> accepted = Completer<void>();
    server.listen((HttpRequest request) {
      if (!accepted.isCompleted) {
        accepted.complete();
      }
      // 由 transport.close 负责打断请求，不让服务端主动返回。
    });

    final HttpTransport transport = createDefaultHttpTransport();
    final Future<HttpTransportResponse> pending = transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: Uri.parse('http://127.0.0.1:${server.port}/close'),
        timeout: const Duration(seconds: 5),
      ),
    );
    await accepted.future;

    await Future.wait<void>(<Future<void>>[
      transport.close(),
      transport.close(),
    ]);
    await expectLater(pending, throwsA(isA<RequestCancelledException>()));
  });
}
