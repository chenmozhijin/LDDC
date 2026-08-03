import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/src/search/ui/search_cover_network_image.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  testWidgets('NE封面使用标准 UA、物理缩略图参数和有界解码尺寸', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SearchCoverNetworkImage(
            url: 'https://p1.music.126.net/cover.jpg?quality=90',
            source: Source.ne,
            errorFallback: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    final ResizeImage resized = image.image as ResizeImage;
    final NetworkImage network = resized.imageProvider as NetworkImage;
    expect(network.headers, NeCoverRequestPolicy.headers);
    expect(Uri.parse(network.url).queryParameters, <String, String>{
      'quality': '90',
      'param': '100y100',
    });
    expect(resized.width, 100);
    expect(resized.height, 100);
  });

  testWidgets('非NE来源不附加 UA，也不改写图片 URL 参数', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    const String url = 'https://example.test/cover.jpg?size=large';
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SearchCoverNetworkImage(
            url: url,
            source: Source.qm,
            errorFallback: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    final ResizeImage resized = image.image as ResizeImage;
    final NetworkImage network = resized.imageProvider as NetworkImage;
    expect(network.url, url);
    expect(network.headers, isNull);
    expect(resized.width, 50);
    expect(resized.height, 50);
  });

  testWidgets('高 DPI 下解码边长封顶为 200px', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 8;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SearchCoverNetworkImage(
            url: 'https://p4.music.126.net/cover.jpg',
            source: Source.ne,
            errorFallback: SizedBox.shrink(),
          ),
        ),
      ),
    );

    final Image image = tester.widget<Image>(find.byType(Image));
    final ResizeImage resized = image.image as ResizeImage;
    final NetworkImage network = resized.imageProvider as NetworkImage;
    expect(Uri.parse(network.url).queryParameters['param'], '200y200');
    expect(resized.width, 200);
    expect(resized.height, 200);
  });
}
