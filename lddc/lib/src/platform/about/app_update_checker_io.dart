import 'dart:convert';

import '../../core/about/about_ports.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'app_update_checker_common.dart';

AppUpdatePort createAppUpdatePort() => GitHubReleaseUpdatePort(
  transport: createDefaultHttpTransport(),
  ownsTransport: true,
);

final class GitHubReleaseUpdatePort implements CloseableAppUpdatePort {
  GitHubReleaseUpdatePort({
    required HttpTransport transport,
    bool ownsTransport = false,
  }) : _transport = transport,
       _ownsTransport = ownsTransport;

  final HttpTransport _transport;
  final bool _ownsTransport;
  Future<void>? _closeFuture;

  @override
  bool get isSupported => true;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({
    required Uri releaseUri,
  }) async {
    try {
      final HttpTransportResponse response = await _transport.send(
        HttpTransportRequest(
          method: 'GET',
          uri: kLddcLatestReleaseApiUri,
          timeout: kAppUpdateRequestTimeout,
          headers: <String, String>{
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'LDDC Flutter',
          },
        ),
      );
      return parseLatestReleaseResponse(
        statusCode: response.statusCode,
        body: utf8.decode(response.body),
        fallbackReleaseUri: releaseUri,
      );
    } catch (error) {
      return AppUpdateCheckResult.failed(error);
    }
  }

  @override
  Future<void> close() {
    if (!_ownsTransport) {
      return Future<void>.value();
    }
    return _closeFuture ??= _transport.close();
  }
}
