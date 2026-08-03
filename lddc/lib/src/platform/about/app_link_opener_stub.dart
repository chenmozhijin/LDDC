import '../../core/about/about_ports.dart';

AppLinkOpener createAppLinkOpener() => const _UnsupportedAppLinkOpener();

final class _UnsupportedAppLinkOpener implements AppLinkOpener {
  const _UnsupportedAppLinkOpener();

  @override
  bool get isSupported => false;

  @override
  Future<void> openExternalUri(Uri uri) {
    throw UnsupportedError('当前平台不支持打开外部链接');
  }
}
