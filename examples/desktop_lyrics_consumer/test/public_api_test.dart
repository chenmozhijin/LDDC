import 'package:desktop_lyrics_consumer/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  testWidgets('消费者只通过公开入口绘制桌面歌词', (WidgetTester tester) async {
    await tester.pumpWidget(const DesktopLyricsConsumerApp());
    await tester.pump();

    expect(find.byType(DesktopFloatingLyricsRenderView), findsOneWidget);
    final DesktopFloatingLyricsRenderView view = tester.widget(
      find.byType(DesktopFloatingLyricsRenderView),
    );
    expect(view.renderPlan, isNotNull);
    expect(
      view.renderPlan!.toJson().toString(),
      contains('LDDC desktop lyrics package'),
    );
  });
}
