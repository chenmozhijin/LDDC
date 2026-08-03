import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/about/about_ports.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/platform/about/app_update_checker_common.dart';
import 'package:lddc/src/platform/about/app_update_checker_io.dart';

void main() {
  final Uri fallbackUri = Uri.parse(
    'https://github.com/chenmozhijin/LDDC/releases',
  );

  test('更新响应按 SemVer 比较 prerelease、正式版和 build metadata', () {
    const List<(String, AppUpdateStatus)> cases = <(String, AppUpdateStatus)>[
      ('v0.10.0-alpha.2', AppUpdateStatus.updateAvailable),
      ('v0.10.0-alpha.10', AppUpdateStatus.updateAvailable),
      ('v0.10.0-alpha.1+build.7', AppUpdateStatus.upToDate),
      ('v0.9.9', AppUpdateStatus.upToDate),
      ('v0.10.0', AppUpdateStatus.updateAvailable),
    ];

    for (final (String tag, AppUpdateStatus expectedStatus) in cases) {
      final AppUpdateCheckResult result = parseLatestReleaseResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'tag_name': tag,
          'html_url': 'https://github.com/chenmozhijin/LDDC/releases/tag/$tag',
        }),
        fallbackReleaseUri: fallbackUri,
      );

      expect(result.status, expectedStatus, reason: tag);
      expect(result.latestVersion, tag, reason: tag);
    }
  });

  test('更新响应拒绝损坏内容并对不安全发布页回落', () {
    final List<AppUpdateCheckResult> failures = <AppUpdateCheckResult>[
      parseLatestReleaseResponse(
        statusCode: 500,
        body: '{}',
        fallbackReleaseUri: fallbackUri,
      ),
      parseLatestReleaseResponse(
        statusCode: 200,
        body: '{broken',
        fallbackReleaseUri: fallbackUri,
      ),
      parseLatestReleaseResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'tag_name': 'not-a-version'}),
        fallbackReleaseUri: fallbackUri,
      ),
      parseLatestReleaseResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'tag_name': 'v0.10.0'}),
        fallbackReleaseUri: Uri.parse('file:///tmp/releases'),
      ),
    ];

    expect(
      failures.map((AppUpdateCheckResult result) => result.status),
      everyElement(AppUpdateStatus.failed),
    );

    final AppUpdateCheckResult safeFallback = parseLatestReleaseResponse(
      statusCode: 200,
      body: jsonEncode(<String, Object?>{
        'tag_name': 'v0.10.0',
        'html_url': 'https://user:password@example.com/release',
      }),
      fallbackReleaseUri: fallbackUri,
    );
    expect(safeFallback.status, AppUpdateStatus.updateAvailable);
    expect(safeFallback.releaseUri, fallbackUri);
  });

  test('IO 更新端口发送固定 GitHub 请求并只关闭自有 transport 一次', () async {
    final _FakeHttpTransport ownedTransport = _FakeHttpTransport(
      response: HttpTransportResponse(
        statusCode: 200,
        body: Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'tag_name': 'v0.10.0',
              'html_url':
                  'https://github.com/chenmozhijin/LDDC/releases/tag/v0.10.0',
            }),
          ),
        ),
      ),
    );
    final GitHubReleaseUpdatePort ownedPort = GitHubReleaseUpdatePort(
      transport: ownedTransport,
      ownsTransport: true,
    );

    final AppUpdateCheckResult result = await ownedPort.checkForUpdates(
      releaseUri: fallbackUri,
    );
    await ownedPort.close();
    await ownedPort.close();

    expect(result.status, AppUpdateStatus.updateAvailable);
    expect(ownedTransport.lastRequest?.method, 'GET');
    expect(ownedTransport.lastRequest?.uri, kLddcLatestReleaseApiUri);
    expect(ownedTransport.lastRequest?.timeout, kAppUpdateRequestTimeout);
    expect(
      ownedTransport.lastRequest?.headers['Accept'],
      'application/vnd.github+json',
    );
    expect(ownedTransport.lastRequest?.headers['User-Agent'], 'LDDC Flutter');
    expect(ownedTransport.closeCount, 1);

    final _FakeHttpTransport borrowedTransport = _FakeHttpTransport(
      response: ownedTransport.response,
    );
    final GitHubReleaseUpdatePort borrowedPort = GitHubReleaseUpdatePort(
      transport: borrowedTransport,
    );
    await borrowedPort.close();
    expect(borrowedTransport.closeCount, 0);
  });

  test('IO 更新端口把 transport 异常收口为 failed 结果', () async {
    final StateError error = StateError('network down');
    final GitHubReleaseUpdatePort port = GitHubReleaseUpdatePort(
      transport: _FakeHttpTransport(error: error),
    );

    final AppUpdateCheckResult result = await port.checkForUpdates(
      releaseUri: fallbackUri,
    );

    expect(result.status, AppUpdateStatus.failed);
    expect(result.error, same(error));
  });
}

final class _FakeHttpTransport implements HttpTransport {
  _FakeHttpTransport({this.response, this.error});

  final HttpTransportResponse? response;
  final Object? error;
  HttpTransportRequest? lastRequest;
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  Future<HttpTransportResponse> send(HttpTransportRequest request) async {
    lastRequest = request;
    if (error case final Object error) {
      throw error;
    }
    return response!;
  }
}
