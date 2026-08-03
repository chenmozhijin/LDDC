import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  test('页面动作与视图 copyWith 可分别保留、替换和清空字段', () {
    const PageActionState action = PageActionState(
      phase: PageActionPhase.running,
      message: 'running',
    );
    final DateTime updatedAt = DateTime.utc(2026, 7, 31);
    final PageViewState<int> state = PageViewState<int>(
      view: const AsyncSuccess<int>(data: 1),
      action: action,
      lastUpdatedAt: updatedAt,
    );

    expect(action.isRunning, isTrue);
    expect(action.copyWith().message, 'running');
    expect(action.copyWith(clearMessage: true).message, isNull);
    expect(
      action.copyWith(phase: PageActionPhase.idle, message: 'done').isRunning,
      isFalse,
    );
    expect(state.copyWith().lastUpdatedAt, updatedAt);
    expect(state.copyWith(clearLastUpdatedAt: true).lastUpdatedAt, isNull);
    expect(
      state.copyWith(view: const AsyncEmpty<int>()).view,
      isA<AsyncEmpty<int>>(),
    );
    expect(
      state.copyWith(action: const PageActionState()).action.isRunning,
      isFalse,
    );
  });

  test('翻译按钮文案覆盖已有译文、确定进度、不定进度和空闲状态', () {
    final LyricsUiStrings strings = LyricsUiStrings.zhHans();
    expect(
      translationProgressButtonLabel(
        strings: strings,
        hasTranslation: true,
        isTranslating: false,
        progress: null,
        idleLabel: '开始',
      ),
      '取消翻译',
    );
    expect(
      translationProgressButtonLabel(
        strings: strings,
        hasTranslation: false,
        isTranslating: true,
        progress: const OpenAiTranslationProgress(
          completedLines: 2,
          totalLines: 4,
          isIndeterminate: false,
        ),
        idleLabel: '开始',
      ),
      contains('2/4'),
    );
    expect(
      translationProgressButtonLabel(
        strings: strings,
        hasTranslation: false,
        isTranslating: false,
        progress: const OpenAiTranslationProgress(
          completedLines: 0,
          totalLines: 0,
          isIndeterminate: true,
        ),
        idleLabel: '开始',
      ),
      '翻译中...',
    );
    expect(
      translationProgressButtonLabel(
        strings: strings,
        hasTranslation: false,
        isTranslating: false,
        progress: null,
        idleLabel: '开始',
      ),
      '开始',
    );
  });

  testWidgets('ProgressPanel 钳制确定进度并隐藏空状态文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProgressPanel(
          title: '任务',
          currentValue: 12,
          maxValue: 10,
          statusText: '',
        ),
      ),
    );

    expect(find.text('任务'), findsOneWidget);
    expect(find.text('12 / 10'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      1,
    );
    expect(find.text(''), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: ProgressPanel(
          title: '任务',
          currentValue: 0,
          maxValue: 0,
          statusText: '准备中',
        ),
      ),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(find.text('准备中'), findsOneWidget);
  });

  testWidgets('LyricsLanguageSegments 在全部选择组合下保持固定尺寸', (
    WidgetTester tester,
  ) async {
    Set<String> selected = <String>{'orig', 'ts'};
    late StateSetter updateState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              updateState = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: LyricsLanguageSegments(
                  selected: selected,
                  strings: LyricsUiStrings.zhHans(),
                  onSelectionChanged: (Set<String> next) {
                    setState(() => selected = next);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    final Finder segmentsFinder = find.byType(SegmentedButton<String>);
    final Size baseline = tester.getSize(segmentsFinder);
    final List<Set<String>> combinations = <Set<String>>[
      <String>{},
      <String>{'orig'},
      <String>{'ts'},
      <String>{'roma'},
      <String>{'orig', 'ts'},
      <String>{'orig', 'roma'},
      <String>{'ts', 'roma'},
      <String>{'orig', 'ts', 'roma'},
    ];

    for (final Set<String> combination in combinations) {
      updateState(() => selected = combination);
      await tester.pump();

      expect(tester.getSize(segmentsFinder), baseline, reason: '$combination');
      expect(
        tester.widget<SegmentedButton<String>>(segmentsFinder).selected,
        combination,
      );
      expect(
        find.descendant(of: segmentsFinder, matching: find.byType(Opacity)),
        findsNWidgets(3 - combination.length),
        reason: '$combination',
      );
    }
  });

  testWidgets('LyricsPreviewViewport 保留换行并提供横纵滚动视口', (
    WidgetTester tester,
  ) async {
    const String preview = 'first line\nsecond line with a very long suffix';
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 160,
          height: 80,
          child: LyricsPreviewViewport(text: preview),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsNWidgets(2));
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      preview,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchToolbar 可切换来源、输入关键词并通过按钮和提交触发搜索', (
    WidgetTester tester,
  ) async {
    final TextEditingController keywordController = TextEditingController();
    addTearDown(keywordController.dispose);
    final List<String> sources = <String>[];
    final List<String> keywords = <String>[];
    int searchCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SearchToolbar(
          keywordController: keywordController,
          sourceItems: const <SearchToolbarSourceItem>[
            SearchToolbarSourceItem(value: 'QM', label: 'QQ 音乐'),
            SearchToolbarSourceItem(value: 'KG', label: '酷狗音乐'),
          ],
          selectedSource: 'UNKNOWN',
          searchButtonLabel: '搜索',
          keywordHint: '关键词',
          sourceLabel: '来源',
          onSourceChanged: sources.add,
          onSearchPressed: () {
            searchCount += 1;
          },
          onKeywordChanged: keywords.add,
          isCompact: true,
        ),
      ),
    );

    expect(find.text('UNKNOWN'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_source_menu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_source_item_KG')),
    );
    await tester.pump();
    expect(sources, <String>['KG']);

    await tester.enterText(
      find.byKey(const ValueKey<String>('search_toolbar_search_bar')),
      'demo',
    );
    expect(keywords.last, 'demo');
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_search_button')),
    );
    await tester.pump();
    expect(searchCount, 1);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(searchCount, 2);
    expect(tester.takeException(), isNull);
  });
}
