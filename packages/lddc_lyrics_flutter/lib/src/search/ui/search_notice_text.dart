import '../../ui/search_ui_strings.dart';
import '../search_workflow_state.dart';

/// 将控制器通知解析为当前宿主语言的可见文本。
String searchNoticeText(SearchUiStrings strings, SearchNotice notice) {
  final String detail = notice.detail ?? '';
  final int saved = notice.successCount ?? 0;
  final int failed = notice.failureCount ?? 0;
  final int skipped = notice.skippedCount ?? 0;
  final SearchUiTextArguments detailArguments = SearchUiTextArguments(
    detail: detail,
  );
  final SearchUiTextArguments batchArguments = SearchUiTextArguments(
    detail: detail,
    saved: saved,
    failed: failed,
    skipped: skipped,
  );
  return switch (notice.code) {
    SearchNoticeCode.searchPartialSourcesFailed => strings.text(
      SearchUiTextKey.noticeSearchPartialSourcesFailed,
    ),
    SearchNoticeCode.searchAllSourcesFailed => strings.text(
      SearchUiTextKey.noticeSearchAllSourcesFailed,
    ),
    SearchNoticeCode.searchLoadMoreFailed => strings.text(
      SearchUiTextKey.noticeSearchLoadMoreFailed,
    ),
    SearchNoticeCode.directoryPickerUnsupported => strings.text(
      SearchUiTextKey.noticeDirectoryPickerUnsupported,
    ),
    SearchNoticeCode.autoFetchSucceeded => strings.text(
      SearchUiTextKey.noticeAutoFetchSucceeded,
      arguments: detailArguments,
    ),
    SearchNoticeCode.autoFetchFailed => strings.text(
      SearchUiTextKey.noticeAutoFetchFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.selectedSongUnavailable => strings.text(
      SearchUiTextKey.noticeSelectedSongUnavailable,
    ),
    SearchNoticeCode.filePickerUnsupported => strings.text(
      SearchUiTextKey.noticeFilePickerUnsupported,
    ),
    SearchNoticeCode.openSongFailed => strings.text(
      SearchUiTextKey.noticeOpenSongFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.droppedSongUnavailable => strings.text(
      SearchUiTextKey.noticeDroppedSongUnavailable,
    ),
    SearchNoticeCode.droppedSongResolveFailed => strings.text(
      SearchUiTextKey.noticeDroppedSongResolveFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.emptyKeyword => strings.text(
      SearchUiTextKey.noticeEmptyKeyword,
    ),
    SearchNoticeCode.getLyricsFirst => strings.text(
      SearchUiTextKey.noticeGetLyricsFirst,
    ),
    SearchNoticeCode.translationCancelled => strings.text(
      SearchUiTextKey.noticeTranslationCancelled,
    ),
    SearchNoticeCode.translationCompleted => strings.text(
      SearchUiTextKey.noticeTranslationCompleted,
    ),
    SearchNoticeCode.translationFailed => strings.text(
      SearchUiTextKey.noticeTranslationFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.lyricsSaveSucceeded =>
      detail.isEmpty
          ? strings.text(SearchUiTextKey.noticeLyricsSaved)
          : strings.text(
              SearchUiTextKey.noticeLyricsSaveSucceededWithPath,
              arguments: detailArguments,
            ),
    SearchNoticeCode.lyricsSaveFailed => strings.text(
      SearchUiTextKey.noticeLyricsSaveFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.saveFileUnsupported => strings.text(
      SearchUiTextKey.noticeSaveFileUnsupported,
    ),
    SearchNoticeCode.filePickerForTagUnsupported => strings.text(
      SearchUiTextKey.noticeFilePickerForTagUnsupported,
    ),
    SearchNoticeCode.filePickerFailed => strings.text(
      SearchUiTextKey.noticeFilePickerFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.batchCancelling => strings.text(
      SearchUiTextKey.noticeBatchCancelling,
    ),
    SearchNoticeCode.selectAlbumOrPlaylistFirst => strings.text(
      SearchUiTextKey.noticeSelectAlbumOrPlaylistFirst,
    ),
    SearchNoticeCode.selectAtLeastOneLyricsLanguage => strings.text(
      SearchUiTextKey.noticeSelectAtLeastOneLyricsLanguage,
    ),
    SearchNoticeCode.noSongsToSave => strings.text(
      SearchUiTextKey.noticeNoSongsToSave,
    ),
    SearchNoticeCode.batchSaveCancelled => strings.text(
      SearchUiTextKey.noticeBatchSaveCancelled,
      arguments: batchArguments,
    ),
    SearchNoticeCode.batchSaveCompleted => strings.text(
      SearchUiTextKey.noticeBatchSaveCompleted,
      arguments: batchArguments,
    ),
    SearchNoticeCode.batchSaveFailed => strings.text(
      SearchUiTextKey.noticeBatchSaveFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.multipleLyricsCandidates => strings.text(
      SearchUiTextKey.noticeMultipleLyricsCandidates,
    ),
    SearchNoticeCode.getLyricsFailed => strings.text(
      SearchUiTextKey.noticeGetLyricsFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.selectSavePathFirst => strings.text(
      SearchUiTextKey.noticeSelectSavePathFirst,
    ),
    SearchNoticeCode.directoryPickFailed => strings.text(
      SearchUiTextKey.noticeDirectoryPickFailed,
      arguments: detailArguments,
    ),
    SearchNoticeCode.previewLoading => strings.text(
      SearchUiTextKey.noticePreviewLoading,
    ),
    SearchNoticeCode.previewNoLanguage => strings.text(
      SearchUiTextKey.noticePreviewNoLanguage,
    ),
    SearchNoticeCode.previewNoContent => strings.text(
      SearchUiTextKey.noticePreviewNoContent,
    ),
    SearchNoticeCode.previewNoSelection => strings.text(
      SearchUiTextKey.noticePreviewNoSelection,
    ),
    SearchNoticeCode.audioTagRequiresLrc => strings.text(
      SearchUiTextKey.noticeAudioTagRequiresLrc,
    ),
  };
}
