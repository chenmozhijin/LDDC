import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrics_consumer/main.dart';

void main() {
  testWidgets('消费者只通过公开入口完成本地读取、转换和 Flutter 预览', (WidgetTester tester) async {
    final lyrics = await loadBundledLyrics();

    await tester.pumpWidget(LyricsConsumerApp(lyrics: lyrics));
    await tester.pump();

    expect(find.text('Lyrics consumer'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining('LDDC lyrics package'), findsOneWidget);
  });
}
