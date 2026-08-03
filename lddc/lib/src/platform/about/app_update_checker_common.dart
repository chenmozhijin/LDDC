import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

import '../../core/about/about_ports.dart';
import '../../core/app_metadata.dart';

const Duration kAppUpdateRequestTimeout = Duration(seconds: 10);
final Uri kLddcLatestReleaseApiUri = Uri(
  scheme: 'https',
  host: 'api.github.com',
  path: '/repos/chenmozhijin/LDDC/releases/latest',
);

AppUpdateCheckResult parseLatestReleaseResponse({
  required int statusCode,
  required String body,
  required Uri fallbackReleaseUri,
}) {
  if (statusCode < 200 || statusCode >= 300) {
    return AppUpdateCheckResult.failed(
      StateError('github-release-status-$statusCode'),
    );
  }
  if (!_isSafeExternalUri(fallbackReleaseUri)) {
    return AppUpdateCheckResult.failed(
      ArgumentError.value(
        fallbackReleaseUri,
        'fallbackReleaseUri',
        'Release URI must be a safe http/https URI',
      ),
    );
  }
  try {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      return AppUpdateCheckResult.failed(
        const FormatException('GitHub release response is not an object'),
      );
    }
    final Object? tagName = decoded['tag_name'];
    if (tagName is! String || tagName.trim().isEmpty) {
      return AppUpdateCheckResult.failed(
        const FormatException('GitHub release response missing tag_name'),
      );
    }
    final String latestVersion = tagName.trim();
    final Version latest = _parseVersion(latestVersion);
    final Version current = _parseVersion(kLddcVersion);
    final Uri releaseUri = _releaseUriOrFallback(
      decoded['html_url'],
      fallbackReleaseUri,
    );
    if (latest > current) {
      return AppUpdateCheckResult.updateAvailable(
        latestVersion: latestVersion,
        releaseUri: releaseUri,
      );
    }
    return AppUpdateCheckResult.upToDate(latestVersion: latestVersion);
  } on FormatException catch (error) {
    return AppUpdateCheckResult.failed(error);
  }
}

Version _parseVersion(String raw) {
  final String normalized = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final Version parsed = Version.parse(normalized);
  // pub_semver 的 compareTo 为稳定排序还会比较 build metadata；更新判断必须
  // 遵循 SemVer precedence，因此复用包解析出的核心版本和 prerelease，丢弃
  // 不参与优先级的 build 标识后再比较。
  return Version(
    parsed.major,
    parsed.minor,
    parsed.patch,
    pre: parsed.preRelease.isEmpty ? null : parsed.preRelease.join('.'),
  );
}

Uri _releaseUriOrFallback(Object? raw, Uri fallback) {
  if (raw is String) {
    final Uri? parsed = Uri.tryParse(raw.trim());
    if (parsed != null && _isSafeExternalUri(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

bool _isSafeExternalUri(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return (scheme == 'http' || scheme == 'https') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
