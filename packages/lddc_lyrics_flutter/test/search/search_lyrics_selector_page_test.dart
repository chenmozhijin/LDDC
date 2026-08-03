import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  testWidgets('选择器应用预设歌词并回传语言、偏移和纯音乐状态', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    SearchLyricsSelectorResult? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchLyricsSelectorPage(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          initialState: SearchLyricsSelectorInitialState(
            lyrics: _lyrics('预设歌词'),
            langs: const <String>['orig'],
            offsetMs: 120,
          ),
          dependencies: SearchLyricsSelectorDependencies(
            pickLocalLyricsPath: () async => null,
            loadLocalLyrics: (_) async => throw StateError('不应加载本地歌词'),
          ),
          onLyricsSelected: (SearchLyricsSelectorResult result) async {
            selected = result;
            return true;
          },
        ),
      ),
    );
    await _pumpUntilEnabled(
      tester,
      const ValueKey<String>('selector_select_lyrics_button'),
    );

    expect(find.text('选择歌词'), findsWidgets);
    expect(controller.state.previewText, contains('预设歌词'));
    await tester.tap(
      find.byKey(const ValueKey<String>('selector_select_lyrics_button')),
    );
    await tester.pump();

    expect(selected, isNotNull);
    expect(selected?.lyrics.data['orig']?.single.text, '预设歌词');
    expect(selected?.path, isNull);
    expect(selected?.langs, <String>['orig']);
    expect(selected?.offsetMs, 120);
    expect(selected?.isInstrumental, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选择器打开本地歌词后回传来源路径', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    SearchLyricsSelectorResult? selected;
    int loadCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchLyricsSelectorPage(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          initialState: null,
          dependencies: SearchLyricsSelectorDependencies(
            pickLocalLyricsPath: () async => 'fixture.lrc',
            loadLocalLyrics: (String path) async {
              expect(path, 'fixture.lrc');
              loadCount += 1;
              return _lyrics('本地歌词');
            },
          ),
          onLyricsSelected: (SearchLyricsSelectorResult result) async {
            selected = result;
            return true;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('selector_open_local_button')),
    );
    await _pumpUntilEnabled(
      tester,
      const ValueKey<String>('selector_sheet_select_lyrics_button'),
    );
    expect(loadCount, 1);

    await tester.pump(const Duration(milliseconds: 400));
    final Finder sheetSelectButton = find.byKey(
      const ValueKey<String>('selector_sheet_select_lyrics_button'),
    );
    await tester.tap(sheetSelectButton);
    await tester.pump();

    expect(selected?.path, 'fixture.lrc');
    expect(selected?.lyrics.data['orig']?.single.text, '本地歌词');
    expect(selected?.langs, <String>['orig', 'ts']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('本地歌词加载失败会恢复按钮并显示安全错误文案', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchLyricsSelectorPage(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          initialState: null,
          dependencies: SearchLyricsSelectorDependencies(
            pickLocalLyricsPath: () async => 'broken.lrc',
            loadLocalLyrics: (_) async =>
                throw const FormatException('bad fixture'),
          ),
          onLyricsSelected: (_) async => true,
        ),
      ),
    );
    await tester.pump();
    final Finder openButton = find.byKey(
      const ValueKey<String>('selector_open_local_button'),
    );

    await tester.tap(openButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('打开本地歌词失败'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(openButton).onPressed, isNotNull);
    expect(controller.state.currentLyrics, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宿主拒绝选择结果时保留页面并提示回传失败', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SearchLyricsSelectorPage(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          initialState: SearchLyricsSelectorInitialState(
            lyrics: _lyrics('待选择歌词'),
            langs: const <String>['orig'],
            offsetMs: 0,
          ),
          dependencies: SearchLyricsSelectorDependencies(
            pickLocalLyricsPath: () async => null,
            loadLocalLyrics: (_) async => throw StateError('不应加载'),
          ),
          onLyricsSelected: (_) async => false,
        ),
      ),
    );
    await _pumpUntilEnabled(
      tester,
      const ValueKey<String>('selector_select_lyrics_button'),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('selector_select_lyrics_button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('歌词选择结果回传失败'), findsOneWidget);
    expect(controller.state.currentLyrics, isNotNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUntilEnabled(WidgetTester tester, Key key) async {
  for (int attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 10));
    final Finder finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      final ButtonStyleButton button = tester.widget<ButtonStyleButton>(finder);
      if (button.onPressed != null) {
        return;
      }
    }
  }
  throw TestFailure('等待按钮启用超时: $key');
}

Lyrics _lyrics(String text) {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: 'Fixture'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}
