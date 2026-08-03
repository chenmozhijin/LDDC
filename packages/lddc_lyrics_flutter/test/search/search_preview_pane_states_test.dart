import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  testWidgets('预览区区分加载、未选择、无语言和无内容空态', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController savePathController = TextEditingController();
    addTearDown(() {
      savePathController.dispose();
      controller.dispose();
    });

    await _pumpPreview(
      tester,
      controller: controller,
      savePathController: savePathController,
      state: controller.state.copyWith(
        previewPhase: SearchPreviewPhase.loading,
        clearPreviewEmptyReason: true,
      ),
      width: 500,
    );
    expect(find.text('正在生成歌词预览...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    for (final (SearchPreviewEmptyReason reason, String message)
        in <(SearchPreviewEmptyReason, String)>[
          (SearchPreviewEmptyReason.noSelection, '请选择歌曲并获取歌词'),
          (SearchPreviewEmptyReason.noLanguage, '请至少选择一种歌词语言'),
          (SearchPreviewEmptyReason.noContent, '所选语言没有可预览内容'),
        ]) {
      await _pumpPreview(
        tester,
        controller: controller,
        savePathController: savePathController,
        state: controller.state.copyWith(
          previewPhase: SearchPreviewPhase.idle,
          previewEmptyReason: reason,
          previewText: '',
        ),
        width: 500,
      );
      expect(find.text(message), findsOneWidget, reason: reason.name);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面预览控制区在宽、中、窄尺寸均保留完整动作', (WidgetTester tester) async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController savePathController = TextEditingController(
      text: 'C:/Lyrics',
    );
    addTearDown(() {
      savePathController.dispose();
      controller.dispose();
    });
    await controller.applyExternalPreset(
      lyrics: _lyrics(),
      selectedLangs: const <String>['orig'],
    );

    for (final (double width, bool showDirectory, bool showFile) layout
        in <(double, bool, bool)>[
          (1000, true, true),
          (700, true, false),
          (500, false, true),
        ]) {
      await _pumpPreview(
        tester,
        controller: controller,
        savePathController: savePathController,
        state: controller.state,
        width: layout.$1,
        showTagSave: true,
        showDirectorySave: layout.$2,
        showFileSave: layout.$3,
      );

      expect(find.textContaining('preview line'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey<String>('search_preview_save_directory_button'),
        ),
        layout.$2 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('search_preview_save_file_button')),
        layout.$2 ? findsNothing : findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('search_preview_save_tag_button')),
        findsOneWidget,
      );
      expect(
        find.byType(DropdownButtonFormField<LyricsFormat>),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'width=${layout.$1}');
    }
  });
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  required SearchWorkflowController controller,
  required TextEditingController savePathController,
  required SearchWorkflowState state,
  required double width,
  bool showTagSave = false,
  bool? showDirectorySave,
  bool? showFileSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 600,
            child: SearchPreviewPane(
              state: state,
              controller: controller,
              strings: SearchUiStrings.zhHans(),
              savePathController: savePathController,
              isDesktopPlatform: true,
              showTagSave: showTagSave,
              showDirectorySave: showDirectorySave,
              showFileSave: showFileSave,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Lyrics _lyrics() {
  return Lyrics(
    songInfo: const SongInfo(source: Source.qm, id: '1', title: 'Fixture'),
    source: Source.qm,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: 'preview line'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}
