import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../lyrics/lyrics_preview_composer.dart';
import 'search_workflow_state.dart';

/// 预览文本和辅助标签的不可变投影。
final class SearchPreviewProjection {
  const SearchPreviewProjection({
    required this.lyrics,
    required this.previewText,
    required this.songIdText,
    required this.emptyReason,
  });

  final Lyrics lyrics;
  final String previewText;
  final String songIdText;
  final SearchPreviewEmptyReason? emptyReason;
}

/// 预览与翻译协调器，不持有 UI 状态、epoch 或进度订阅。
final class SearchPreviewCoordinator {
  const SearchPreviewCoordinator({required this._translationClient});

  final TranslationClient _translationClient;

  SearchPreviewProjection buildProjection({
    required Lyrics lyrics,
    required List<String> selectedLangs,
    required LyricsFormat lyricsFormat,
    required int offsetMs,
    required LyricsConvertOptions convertOptions,
  }) {
    final String previewText = LyricsPreviewComposer.buildPreviewText(
      lyrics: lyrics,
      selectedLangs: selectedLangs,
      lyricsFormat: lyricsFormat,
      offsetMs: offsetMs,
      options: convertOptions,
    );
    final SearchPreviewEmptyReason? emptyReason = selectedLangs.isEmpty
        ? SearchPreviewEmptyReason.noLanguage
        : previewText.trim().isEmpty
        ? SearchPreviewEmptyReason.noContent
        : null;
    return SearchPreviewProjection(
      lyrics: lyrics,
      previewText: previewText,
      songIdText: lyrics.id ?? lyrics.songInfo.id ?? '',
      emptyReason: emptyReason,
    );
  }

  Future<Lyrics> translate({
    required Lyrics lyrics,
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    final LyricsData translated = await _translationClient.translateLyrics(
      lyrics,
      onOpenAiProgress: onOpenAiProgress,
    );
    return lyrics.copyWith(
      data: <String, LyricsData>{...lyrics.data, 'LDDC_ts': translated},
    );
  }

  Lyrics removeTranslation(Lyrics lyrics) {
    return lyrics.copyWith(
      data: <String, LyricsData>{...lyrics.data}..remove('LDDC_ts'),
    );
  }
}
