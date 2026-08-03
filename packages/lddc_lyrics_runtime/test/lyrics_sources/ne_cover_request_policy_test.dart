import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('NE封面只规范化自身 CDN 并生成固定有界候选', () {
    expect(
      NeCoverRequestPolicy.normalizeUrl('http://p4.music.126.net/cover.jpg'),
      'https://p4.music.126.net/cover.jpg',
    );
    expect(
      NeCoverRequestPolicy.normalizeUrl('http://images.example/cover.jpg'),
      'http://images.example/cover.jpg',
    );

    final List<Uri> candidates = NeCoverRequestPolicy.requestCandidates(
      url: 'http://p4.music.126.net/cover.jpg?quality=90',
      decodeSize: 100,
    );
    expect(candidates.map((Uri value) => value.host), <String>[
      'p4.music.126.net',
      'p1.music.126.net',
      'p3.music.126.net',
    ]);
    expect(candidates.first.queryParameters['param'], '100y100');
    expect(candidates, hasLength(3));
    expect(NeCoverRequestPolicy.headers['Origin'], isNull);
    expect(NeCoverRequestPolicy.headers['Referer'], isNull);
    expect(NeCoverRequestPolicy.headers['Cookie'], isNull);
  });
}
