import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../core/about/about_ports.dart';
import 'app_update_checker_common.dart';

AppUpdatePort createAppUpdatePort() => const BrowserGitHubReleaseUpdatePort();

final class BrowserGitHubReleaseUpdatePort implements AppUpdatePort {
  const BrowserGitHubReleaseUpdatePort();

  @override
  bool get isSupported => true;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({
    required Uri releaseUri,
  }) async {
    try {
      final ({int statusCode, String body}) response =
          await _requestLatestRelease();
      return parseLatestReleaseResponse(
        statusCode: response.statusCode,
        body: response.body,
        fallbackReleaseUri: releaseUri,
      );
    } catch (error) {
      return AppUpdateCheckResult.failed(error);
    }
  }
}

Future<({int statusCode, String body})> _requestLatestRelease() {
  final Completer<({int statusCode, String body})> completer =
      Completer<({int statusCode, String body})>();
  final web.XMLHttpRequest request = web.XMLHttpRequest();

  void detachHandlers() {
    request.onload = null;
    request.onerror = null;
    request.ontimeout = null;
  }

  void completeError(String message) {
    if (completer.isCompleted) {
      return;
    }
    detachHandlers();
    completer.completeError(StateError(message));
  }

  request
    ..open('GET', kLddcLatestReleaseApiUri.toString())
    ..setRequestHeader('Accept', 'application/vnd.github+json')
    ..timeout = kAppUpdateRequestTimeout.inMilliseconds
    ..onload = ((web.Event _) {
      if (completer.isCompleted) {
        return;
      }
      final ({int statusCode, String body}) response = (
        statusCode: request.status,
        body: request.responseText,
      );
      detachHandlers();
      completer.complete(response);
    }).toJS
    ..onerror = ((web.Event _) {
      completeError('浏览器更新请求失败');
    }).toJS
    ..ontimeout = ((web.Event _) {
      completeError('浏览器更新请求超时');
    }).toJS
    ..send();
  return completer.future;
}
