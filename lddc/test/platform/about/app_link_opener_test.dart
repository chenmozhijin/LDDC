import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/about/app_link_opener_io.dart';

void main() {
  group('AppLinkOpenerImpl', () {
    test('允许 http/https 并委托 url launcher', () async {
      final List<Uri> launched = <Uri>[];
      final AppLinkOpenerImpl opener = AppLinkOpenerImpl(
        launcher: (Uri uri) async {
          launched.add(uri);
          return true;
        },
      );

      await opener.openExternalUri(Uri.parse('https://example.com/project'));
      await opener.openExternalUri(Uri.parse('http://example.com/issues'));

      expect(opener.isSupported, isTrue);
      expect(launched.map((Uri uri) => uri.scheme), <String>['https', 'http']);
    });

    test('拒绝非 http/https、无主机名或携带凭据的 URI', () async {
      final AppLinkOpenerImpl opener = AppLinkOpenerImpl(
        launcher: (_) async => true,
      );

      for (final Uri uri in <Uri>[
        Uri.parse('file:///tmp/secret.txt'),
        Uri.parse('https:path-without-host'),
        Uri.parse('https://user:password@example.com/project'),
      ]) {
        await expectLater(
          opener.openExternalUri(uri),
          throwsA(isA<ArgumentError>()),
        );
      }
    });

    test('launcher 返回 false 时抛出结构化失败', () async {
      final AppLinkOpenerImpl opener = AppLinkOpenerImpl(
        launcher: (_) async => false,
      );

      await expectLater(
        opener.openExternalUri(Uri.parse('https://example.com/project')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
