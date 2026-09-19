import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:test/test.dart';

void main() {
  final SearchUiStrings strings = SearchUiStrings.zhHans();

  test('简体中文搜索文案完整覆盖全部稳定语义键', () {
    const SearchUiTextArguments arguments = SearchUiTextArguments(
      detail: '测试详情',
      songName: '测试歌曲',
      count: 3,
      saved: 2,
      failed: 1,
      skipped: 4,
    );

    for (final SearchUiTextKey key in SearchUiTextKey.values) {
      expect(
        strings.text(key, arguments: arguments),
        isNotEmpty,
        reason: key.name,
      );
    }
    expect(
      strings.text(
        SearchUiTextKey.batchSaveProgressFetchingLyrics,
        arguments: arguments,
      ),
      contains('测试歌曲'),
    );
    expect(
      strings.text(SearchUiTextKey.tableSongCount, arguments: arguments),
      contains('3'),
    );
    expect(
      strings.text(
        SearchUiTextKey.noticeBatchSaveCompleted,
        arguments: arguments,
      ),
      allOf(contains('2'), contains('1'), contains('4')),
    );
  });

  test('来源、搜索类型和歌词组件文案覆盖全部公开枚举值', () {
    for (final Source source in Source.values) {
      expect(strings.sourceLabel(source), isNotEmpty, reason: source.name);
    }
    for (final SearchType type in SearchType.values) {
      expect(strings.searchTypeLabel(type), isNotEmpty, reason: type.name);
    }
    for (final LyricsUiTextKey key in LyricsUiTextKey.values) {
      expect(
        strings.lyrics.text(
          key,
          arguments: const LyricsUiTextArguments(
            completed: 2,
            total: 3,
            language: '原文',
            type: '逐行',
          ),
        ),
        isNotEmpty,
        reason: key.name,
      );
    }
    for (final LyricsFormat format in LyricsFormat.values) {
      expect(
        strings.lyrics.formatLabel(format),
        isNotEmpty,
        reason: format.name,
      );
    }
    for (final LyricsType type in LyricsType.values) {
      expect(strings.lyrics.typeLabel(type), isNotEmpty, reason: type.name);
    }
    for (final String language in <String>[
      'orig',
      'ts',
      'LDDC_ts',
      'roma',
      'custom',
    ]) {
      expect(
        strings.lyrics.languageLabel(language),
        isNotEmpty,
        reason: language,
      );
    }
  });

  test('所有搜索通知码都能在当前语言解析为用户文案', () {
    for (final SearchNoticeCode code in SearchNoticeCode.values) {
      final String text = searchNoticeText(
        strings,
        SearchNotice(
          code: code,
          detail: '测试详情',
          successCount: 2,
          failureCount: 1,
          skippedCount: 3,
        ),
      );
      expect(text, isNotEmpty, reason: code.name);
    }

    expect(
      searchNoticeText(
        strings,
        const SearchNotice(code: SearchNoticeCode.lyricsSaveSucceeded),
      ),
      strings.text(SearchUiTextKey.noticeLyricsSaved),
    );
  });

  test('表格状态编码保留裁剪后的详情并兼容无详情消息', () {
    expect(
      SearchTableStatusMessage.encode(SearchTableStatusMessageCode.searching),
      SearchTableStatusMessageCode.searching,
    );
    expect(
      SearchTableStatusMessage.encode(
        SearchTableStatusMessageCode.searchFailed,
        '   ',
      ),
      SearchTableStatusMessageCode.searchFailed,
    );
    final String encoded = SearchTableStatusMessage.encode(
      SearchTableStatusMessageCode.searchFailed,
      '  网络错误  ',
    );
    expect(SearchTableStatusMessage.decode(encoded), (
      SearchTableStatusMessageCode.searchFailed,
      '网络错误',
    ));
    expect(SearchTableStatusMessage.decode('plain'), ('plain', null));
  });

  test('工具栏来源描述和诊断标签覆盖本地及远端来源', () {
    expect(kSearchToolbarSourceDescriptors.map((item) => item.source), <Source>[
      Source.multi,
      Source.qm,
      Source.kg,
      Source.ne,
      Source.lrclib,
    ]);
    for (final Source source in Source.values) {
      final SearchSourceDescriptor descriptor = SearchSourceDescriptor(
        source: source,
      );
      expect(descriptor.label(strings), strings.sourceLabel(source));
      expect(descriptor.diagnosticLabel, isNotEmpty);
      expect(searchSourceDiagnosticLabel(source), descriptor.diagnosticLabel);
    }
  });
}
