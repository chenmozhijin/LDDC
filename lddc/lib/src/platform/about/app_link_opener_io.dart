import 'package:url_launcher/url_launcher.dart';

import '../../core/about/about_ports.dart';

AppLinkOpener createAppLinkOpener() => AppLinkOpenerImpl();

final class AppLinkOpenerImpl implements AppLinkOpener {
  AppLinkOpenerImpl({Future<bool> Function(Uri uri)? launcher})
    : _launcher =
          launcher ??
          ((Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final Future<bool> Function(Uri uri) _launcher;

  @override
  bool get isSupported => true;

  @override
  Future<void> openExternalUri(Uri uri) async {
    final String scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'uri', '外部链接必须是无凭据且包含主机名的 http/https URI');
    }
    // url_launcher 负责各平台真实外链调度；这里保留布尔失败检查，
    // 让 UI 能把“系统拒绝打开”与业务不支持区分开。
    final bool launched = await _launcher(uri);
    if (!launched) {
      throw StateError('系统拒绝打开外部链接：$uri');
    }
  }
}
