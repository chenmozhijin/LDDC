import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  test('控制器公开状态转换保持输入归一、能力约束和预览一致性', () async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    addTearDown(controller.dispose);
    expect(await controller.states.first, same(controller.state));
    expect(controller.canSavePreview(controller.state), isFalse);
    expect(controller.diagnostics.isIdle, isTrue);

    controller.setKeyword('  demo  ');
    controller.updateSaveDirectoryPath('  C:/Lyrics  ');
    expect(controller.state.keyword, '  demo  ');
    expect(controller.state.saveDirectoryPath, 'C:/Lyrics');
    controller.updateSaveDirectoryPath('   ');
    expect(controller.state.saveDirectoryPath, isEmpty);

    controller.updateSource(Source.kg);
    expect(controller.state.selectedSource, Source.kg);
    expect(controller.state.availableSearchTypes, <SearchType>[
      SearchType.song,
      SearchType.album,
      SearchType.songlist,
    ]);
    controller.updateSearchType(SearchType.lyrics);
    expect(controller.state.selectedSearchType, SearchType.song);
    controller.updateSearchType(SearchType.album);
    expect(controller.state.selectedSearchType, SearchType.album);

    controller.updatePreviewOptions(
      originalEnabled: false,
      translationEnabled: true,
      romanizedEnabled: true,
      lyricsFormat: LyricsFormat.srt,
      offsetMs: 250,
    );
    expect(controller.state.selectedLangs, <String>['ts', 'roma']);
    expect(controller.state.lyricsFormat, LyricsFormat.srt);
    expect(controller.state.offsetMs, 250);

    await controller.applyExternalPreset(
      keyword: 'preset',
      lyrics: _lyrics(),
      selectedLangs: const <String>['orig'],
      offsetMs: 120,
      selectedSource: Source.qm,
      selectedSearchType: SearchType.song,
    );
    expect(controller.state.keyword, 'preset');
    expect(controller.state.currentLyrics, isNotNull);
    expect(controller.state.previewPhase, SearchPreviewPhase.ready);
    expect(controller.state.previewText, contains('line'));
    expect(controller.canSavePreview(controller.state), isTrue);

    controller.updateSelectedLangs(const <String>{'orig', 'ts'});
    expect(controller.state.selectedLangs, <String>['orig', 'ts']);

    await controller.applyExternalPreset(clearLyricsWhenNull: true);
    expect(controller.state.currentLyrics, isNull);
    expect(controller.state.previewPhase, SearchPreviewPhase.idle);
    expect(
      controller.state.previewEmptyReason,
      SearchPreviewEmptyReason.noSelection,
    );
    expect(controller.state.previewText, isEmpty);
  });

  test('空关键词通知按 ID 消费，释放后拒绝继续发布状态', () async {
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    controller.setKeyword('   ');
    await controller.search();

    final SearchNotice notice = controller.state.notice!;
    expect(notice.code, SearchNoticeCode.emptyKeyword);
    controller.dismissNotice(notice.id + 1);
    expect(controller.state.notice, same(notice));
    controller.dismissNotice(notice.id);
    expect(controller.state.notice, isNull);

    final SearchWorkflowState beforeDispose = controller.state;
    controller.dispose();
    controller.dispose();
    expect(controller.diagnostics.isDisposed, isTrue);
    expect(controller.diagnostics.isIdle, isTrue);
    controller.setKeyword('ignored');
    expect(controller.state, same(beforeDispose));
  });
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
            LyricsWord(startMs: 0, endMs: 1000, text: 'line'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}
