import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../../../core/i18n/lyrics_ui_host_mapper.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/l10n/app_localizations.dart';

/// 把 LDDC 的生成式本地化对象裁剪为共享 Flutter 包所需的文案契约。
///
/// 闭包只持有当前构建周期的本地化对象，不注册监听器也不进入控制器状态；语言切换
/// 时页面重新构建并生成新映射，因此共享包无需依赖 LDDC 的本地化实现。
extension SearchUiAppLocalizationsMapper on AppLocalizations {
  SearchUiStrings toSearchUiStrings() {
    return SearchUiStrings(
      lyrics: toLyricsUiStrings(),
      textResolver: _resolveSearchUiText,
      sourceLabelResolver: sourceLabel,
      searchTypeLabelResolver: searchTypeLabel,
    );
  }

  String _resolveSearchUiText(
    SearchUiTextKey key,
    SearchUiTextArguments arguments,
  ) {
    final String detail = arguments.detail;
    return switch (key) {
      SearchUiTextKey.commonSearch => commonSearch,
      SearchUiTextKey.commonSource => commonSource,
      SearchUiTextKey.keywordHint => searchKeywordHint,
      SearchUiTextKey.batchSaveProgressTitle => searchBatchSaveProgressTitle,
      SearchUiTextKey.batchSaveProgressPreparing =>
        searchBatchSaveProgressPreparing,
      SearchUiTextKey.batchSaveProgressFetchingLyrics =>
        searchBatchSaveProgressFetchingLyrics(arguments.songName),
      SearchUiTextKey.loading => uiLoading,
      SearchUiTextKey.loadingStepFetching => uiLoadingStepFetching,
      SearchUiTextKey.initialResultTitle => searchInitialResultTitle,
      SearchUiTextKey.initialResultDescription =>
        searchInitialResultDescription,
      SearchUiTextKey.commonError => commonError,
      SearchUiTextKey.retry => actionRetry,
      SearchUiTextKey.viewDetails => actionViewDetails,
      SearchUiTextKey.empty => uiEmpty,
      SearchUiTextKey.resultLoadingMore => searchResultLoadingMore,
      SearchUiTextKey.resultLoadMoreFailed => searchResultLoadMoreFailed,
      SearchUiTextKey.resultScrollForMore => searchResultScrollForMore,
      SearchUiTextKey.noMoreResult => uiNoMoreResult,
      SearchUiTextKey.resultTitle => searchResultTitle,
      SearchUiTextKey.resultReturn => searchResultReturn,
      SearchUiTextKey.saveListLyrics => searchSaveListLyrics,
      SearchUiTextKey.saveListLyricsCancel => searchSaveListLyricsCancel,
      SearchUiTextKey.previewTitle => searchPreviewTitle,
      SearchUiTextKey.tableStatusAutoFetching => searchTableStatusAutoFetching,
      SearchUiTextKey.tableStatusSearching => searchTableStatusSearching,
      SearchUiTextKey.tableStatusFetchingSongList =>
        searchTableStatusFetchingSongList,
      SearchUiTextKey.tableStatusNoResults => searchTableStatusNoResults,
      SearchUiTextKey.tableStatusEmptyList => searchTableStatusEmptyList,
      SearchUiTextKey.tableStatusUnsupportedSearchType =>
        searchTableStatusUnsupportedSearchType,
      SearchUiTextKey.tableStatusSearchFailed => searchTableStatusSearchFailed,
      SearchUiTextKey.tableStatusSearchFailedWithDetail =>
        searchTableStatusSearchFailedWithDetail(detail),
      SearchUiTextKey.tableStatusAutoFetchFailed =>
        searchTableStatusAutoFetchFailed(detail),
      SearchUiTextKey.tableStatusSongListFailed =>
        searchTableStatusSongListFailed(detail),
      SearchUiTextKey.tableStatusPartialSourceUnavailable =>
        searchTableStatusPartialSourceUnavailable,
      SearchUiTextKey.tableStatusLoadMoreFailed =>
        searchTableStatusLoadMoreFailed,
      SearchUiTextKey.sourceFailureDetailsTitle =>
        searchSourceFailureDetailsTitle,
      SearchUiTextKey.sourceFailureRequest => searchSourceFailureRequest,
      SearchUiTextKey.sourceFailureTimeout => searchSourceFailureTimeout,
      SearchUiTextKey.sourceFailureParameters => searchSourceFailureParameters,
      SearchUiTextKey.sourceFailureUnsupported =>
        searchSourceFailureUnsupported,
      SearchUiTextKey.sourceFailureUnknown => searchSourceFailureUnknown,
      SearchUiTextKey.tableSongCount => searchTableSongCountValue(
        arguments.count,
      ),
      SearchUiTextKey.previewLoading => searchPreviewLoading,
      SearchUiTextKey.previewLangsLabel => searchPreviewLangsLabel,
      SearchUiTextKey.previewSongIdLabel => searchPreviewSongIdLabel,
      SearchUiTextKey.savePathLabel => tableSavePath,
      SearchUiTextKey.selectSavePath => searchSelectSavePath,
      SearchUiTextKey.savePreviewToDirectory => searchSavePreviewToDirectory,
      SearchUiTextKey.savePreviewToFile => searchSavePreviewToFile,
      SearchUiTextKey.savePreviewToTag => searchSavePreviewToTag,
      SearchUiTextKey.saving => commonSaving,
      SearchUiTextKey.translateLyrics => searchTranslateLyrics,
      SearchUiTextKey.previewNoLanguage => searchPreviewNoLanguage,
      SearchUiTextKey.previewNoContent => searchPreviewNoContent,
      SearchUiTextKey.previewPlaceholder => searchPreviewPlaceholder,
      SearchUiTextKey.resizeWorkspacePanes => searchResizeWorkspacePanes,
      SearchUiTextKey.selectorTitle => searchLyricsSelectorTitle,
      SearchUiTextKey.selectorDescription => searchLyricsSelectorDescription,
      SearchUiTextKey.selectorOpenLocal => searchLyricsSelectorOpenLocal,
      SearchUiTextKey.selectorSelect => searchLyricsSelectorSelect,
      SearchUiTextKey.selectorOpenLocalFailed =>
        searchLyricsSelectorOpenLocalFailed(detail),
      SearchUiTextKey.selectorSelectLyricsFirst =>
        searchLyricsSelectorSelectLyricsFirst,
      SearchUiTextKey.selectorSelectFailed => searchLyricsSelectorSelectFailed,
      SearchUiTextKey.noticeSearchPartialSourcesFailed =>
        searchNoticePartialSourcesFailed,
      SearchUiTextKey.noticeSearchAllSourcesFailed =>
        searchNoticeAllSourcesFailed,
      SearchUiTextKey.noticeSearchLoadMoreFailed => searchNoticeLoadMoreFailed,
      SearchUiTextKey.noticeDirectoryPickerUnsupported =>
        searchNoticeDirectoryPickerUnsupported,
      SearchUiTextKey.noticeAutoFetchSucceeded =>
        searchNoticeAutoFetchSucceeded(detail),
      SearchUiTextKey.noticeAutoFetchFailed => searchNoticeAutoFetchFailed(
        detail,
      ),
      SearchUiTextKey.noticeSelectedSongUnavailable =>
        searchNoticeSelectedSongUnavailable,
      SearchUiTextKey.noticeFilePickerUnsupported =>
        searchNoticeFilePickerUnsupported,
      SearchUiTextKey.noticeOpenSongFailed => searchNoticeOpenSongFailed(
        detail,
      ),
      SearchUiTextKey.noticeDroppedSongUnavailable =>
        searchNoticeDroppedSongUnavailable,
      SearchUiTextKey.noticeDroppedSongResolveFailed =>
        searchNoticeDroppedSongResolveFailed(detail),
      SearchUiTextKey.noticeEmptyKeyword => searchNoticeEmptyKeyword,
      SearchUiTextKey.noticeGetLyricsFirst => searchNoticeGetLyricsFirst,
      SearchUiTextKey.noticeTranslationCancelled => commonTranslationCancelled,
      SearchUiTextKey.noticeTranslationCompleted => commonTranslationCompleted,
      SearchUiTextKey.noticeTranslationFailed => commonTranslationFailed(
        detail,
      ),
      SearchUiTextKey.noticeLyricsSaved => commonLyricsSaved,
      SearchUiTextKey.noticeLyricsSaveSucceededWithPath =>
        searchNoticeLyricsSaveSucceededWithPath(detail),
      SearchUiTextKey.noticeLyricsSaveFailed => commonLyricsSaveFailed(detail),
      SearchUiTextKey.noticeSaveFileUnsupported =>
        searchNoticeSaveFileUnsupported,
      SearchUiTextKey.noticeFilePickerForTagUnsupported =>
        searchNoticeFilePickerForTagUnsupported,
      SearchUiTextKey.noticeFilePickerFailed => searchNoticeFilePickerFailed(
        detail,
      ),
      SearchUiTextKey.noticeBatchCancelling => searchNoticeBatchCancelling,
      SearchUiTextKey.noticeSelectAlbumOrPlaylistFirst =>
        searchNoticeSelectAlbumOrPlaylistFirst,
      SearchUiTextKey.noticeSelectAtLeastOneLyricsLanguage =>
        searchNoticeSelectAtLeastOneLyricsLanguage,
      SearchUiTextKey.noticeNoSongsToSave => searchNoticeNoSongsToSave,
      SearchUiTextKey.noticeBatchSaveCancelled =>
        searchNoticeBatchSaveCancelled(
          arguments.saved,
          arguments.failed,
          arguments.skipped,
        ),
      SearchUiTextKey.noticeBatchSaveCompleted =>
        searchNoticeBatchSaveCompleted(
          arguments.saved,
          arguments.failed,
          arguments.skipped,
        ),
      SearchUiTextKey.noticeBatchSaveFailed => searchNoticeBatchSaveFailed(
        detail,
      ),
      SearchUiTextKey.noticeMultipleLyricsCandidates =>
        searchNoticeMultipleLyricsCandidates,
      SearchUiTextKey.noticeGetLyricsFailed => searchNoticeGetLyricsFailed(
        detail,
      ),
      SearchUiTextKey.noticeSelectSavePathFirst =>
        searchNoticeSelectSavePathFirst,
      SearchUiTextKey.noticeDirectoryPickFailed =>
        searchNoticeDirectoryPickFailed(detail),
      SearchUiTextKey.noticePreviewLoading => searchNoticePreviewLoading,
      SearchUiTextKey.noticePreviewNoLanguage => searchNoticePreviewNoLanguage,
      SearchUiTextKey.noticePreviewNoContent => searchNoticePreviewNoContent,
      SearchUiTextKey.noticePreviewNoSelection =>
        searchNoticePreviewNoSelection,
      SearchUiTextKey.noticeAudioTagRequiresLrc => commonAudioTagRequiresLrc,
    };
  }
}
