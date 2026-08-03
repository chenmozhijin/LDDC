import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  testWidgets('LyricsTranslationProgressOverlay 在内容顶部覆盖进度条', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: SizedBox(
          width: 240,
          height: 120,
          child: LyricsTranslationProgressOverlay(
            progress: const OpenAiTranslationProgress(
              completedLines: 2,
              totalLines: 4,
              isIndeterminate: false,
            ),
            strings: _englishStrings,
            child: const ColoredBox(
              color: Colors.white,
              child: Center(child: Text('歌词正文')),
            ),
          ),
        ),
      ),
    );

    final Finder progressBar = find.byKey(
      const ValueKey<String>('lyrics_translation_progress_bar'),
    );
    expect(progressBar, findsOneWidget);
    expect(find.text('歌词正文'), findsOneWidget);

    final LinearProgressIndicator indicator = tester.widget(progressBar);
    expect(indicator.value, 0.5);
    expect(indicator.minHeight, 3);
    final Tooltip tooltip = tester.widget(find.byType(Tooltip));
    expect(tooltip.message, 'OpenAI streaming translation: 2 / 4 lines');
  });

  testWidgets('LyricsTranslationProgressOverlay 无进度时只显示内容', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: LyricsTranslationProgressOverlay(
          progress: null,
          strings: LyricsUiStrings.zhHans(),
          child: const Text('歌词正文'),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('lyrics_translation_progress_bar')),
      findsNothing,
    );
    expect(find.text('歌词正文'), findsOneWidget);
  });
}

Widget _testApp({required Widget home}) => MaterialApp(home: home);

final LyricsUiStrings _englishStrings = LyricsUiStrings(
  textResolver: (LyricsUiTextKey key, LyricsUiTextArguments arguments) {
    if (key == LyricsUiTextKey.openAiTranslationProgress) {
      return 'OpenAI streaming translation: '
          '${arguments.completed} / ${arguments.total} lines';
    }
    return key.name;
  },
  formatLabelResolver: (format) => format.name,
  languageLabelResolver: (String language) => language,
  typeLabelResolver: (type) => type.name,
);
