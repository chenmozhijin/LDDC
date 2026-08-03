import 'package:test/test.dart';
import '../support/internal_runtime_test_api.dart';

void main() {
  group('buildKgUriWithQuery', () {
    test('空值参数保留 key= 形式', () {
      final Uri uri = Uri.parse('http://example.com/path');

      final Uri built = buildKgUriWithQuery(uri, <String, String>{
        'token': '',
        'keyword': 'Kud Wafter',
      });

      expect(built.toString(), contains('token='));
      expect(built.toString(), contains('keyword=Kud+Wafter'));
    });

    test('空参数时保持原始 URI', () {
      final Uri uri = Uri.parse('http://example.com/path');
      final Uri built = buildKgUriWithQuery(uri, const <String, String>{});
      expect(built, uri);
    });
  });
}
