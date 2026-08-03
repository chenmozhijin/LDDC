import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n.dart';
import '../application/local_match_page_state.dart';

String localMatchNoticeText(BuildContext context, LocalMatchNotice notice) {
  final l10n = context.l10n;
  final String detail = notice.detail ?? '';
  final int total = notice.totalCount ?? 0;
  final int success = notice.successCount ?? 0;
  final int failed = notice.failureCount ?? 0;
  final int skipped = notice.skippedCount ?? 0;
  return switch (notice.code) {
    LocalMatchNoticeCode.busyImportFiles =>
      l10n.localMatchNoticeBusyImportFiles,
    LocalMatchNoticeCode.selectedFilesUnavailable =>
      l10n.localMatchNoticeSelectedFilesUnavailable,
    LocalMatchNoticeCode.unsupportedOperation =>
      detail.isEmpty ? l10n.commonUnsupportedOperation : detail,
    LocalMatchNoticeCode.importFilesFailed =>
      l10n.localMatchNoticeImportFilesFailed(detail),
    LocalMatchNoticeCode.busyImportDirectories =>
      l10n.localMatchNoticeBusyImportDirectories,
    LocalMatchNoticeCode.importDirectoriesFailed =>
      l10n.localMatchNoticeImportDirectoriesFailed(detail),
    LocalMatchNoticeCode.droppedNoAccessibleFiles =>
      l10n.localMatchNoticeDroppedNoAccessibleFiles,
    LocalMatchNoticeCode.droppedSongResolveFailed =>
      l10n.localMatchNoticeDroppedSongResolveFailed(detail),
    LocalMatchNoticeCode.importCompletedWithErrors =>
      l10n.localMatchNoticeImportCompletedWithErrors,
    LocalMatchNoticeCode.safTreeUnsupported =>
      l10n.localMatchNoticeSafTreeUnsupported,
    LocalMatchNoticeCode.busySwitchTree => l10n.localMatchNoticeBusySwitchTree,
    LocalMatchNoticeCode.selectTreeFailed =>
      l10n.localMatchNoticeSelectTreeFailed(detail),
    LocalMatchNoticeCode.selectSaveRootFailed =>
      l10n.commonSelectSaveDirectoryFailed(detail),
    LocalMatchNoticeCode.busyClearQueue => l10n.localMatchNoticeBusyClearQueue,
    LocalMatchNoticeCode.selectItemsToDelete =>
      l10n.localMatchNoticeSelectItemsToDelete,
    LocalMatchNoticeCode.selectItemsToSetRoot =>
      l10n.localMatchNoticeSelectItemsToSetRoot,
    LocalMatchNoticeCode.selectedRootSkippedSongs =>
      l10n.localMatchNoticeSelectedRootSkippedSongs(detail),
    LocalMatchNoticeCode.setRootFailed => l10n.localMatchNoticeSetRootFailed(
      detail,
    ),
    LocalMatchNoticeCode.selectItemsToRestore =>
      l10n.localMatchNoticeSelectItemsToRestore,
    LocalMatchNoticeCode.cancelling => l10n.localMatchNoticeCancelling,
    LocalMatchNoticeCode.validationFailed => _validationIssuesText(
      context,
      notice.validationIssues ?? const <LocalMatchRunValidationIssue>[],
    ),
    LocalMatchNoticeCode.songDirectoryUnavailable =>
      l10n.localMatchNoticeSongDirectoryUnavailable,
    LocalMatchNoticeCode.openSongDirectoryFailed =>
      l10n.localMatchNoticeOpenSongDirectoryFailed(detail),
    LocalMatchNoticeCode.saveDirectoryUnavailable =>
      l10n.localMatchNoticeSaveDirectoryUnavailable,
    LocalMatchNoticeCode.openSaveDirectoryFailed =>
      l10n.commonOpenSaveDirectoryFailed(detail),
    LocalMatchNoticeCode.lyricsFileUnavailable =>
      l10n.commonLyricsFileUnavailable,
    LocalMatchNoticeCode.openLyricsFailed =>
      l10n.localMatchNoticeOpenLyricsFailed(detail),
    LocalMatchNoticeCode.scanCancelled => l10n.localMatchNoticeScanCancelled,
    LocalMatchNoticeCode.scanCompletedWithErrors =>
      l10n.localMatchNoticeScanCompletedWithErrors,
    LocalMatchNoticeCode.scanFailed => l10n.localMatchNoticeScanFailed(detail),
    LocalMatchNoticeCode.treeScanFailed => l10n.localMatchNoticeTreeScanFailed(
      detail,
    ),
    LocalMatchNoticeCode.matchCancelled => l10n.localMatchNoticeMatchCancelled,
    LocalMatchNoticeCode.matchCompleted => l10n.localMatchNoticeMatchCompleted(
      total,
      success,
      failed,
      skipped,
    ),
    LocalMatchNoticeCode.matchFailed => l10n.localMatchNoticeMatchFailed(
      detail,
    ),
    LocalMatchNoticeCode.missingAndroidTree =>
      l10n.localMatchValidationMissingAndroidTree,
    LocalMatchNoticeCode.androidMatchCancelledResume =>
      l10n.localMatchNoticeAndroidMatchCancelledResume,
    LocalMatchNoticeCode.androidMatchFailed =>
      l10n.localMatchNoticeAndroidMatchFailed(detail),
  };
}

String localMatchValidationIssueText(
  BuildContext context,
  LocalMatchRunValidationIssue issue,
) {
  final l10n = context.l10n;
  return switch (issue.code) {
    LocalMatchRunValidationCode.emptyLangs =>
      l10n.localMatchValidationEmptyLangs,
    LocalMatchRunValidationCode.emptySources =>
      l10n.localMatchValidationEmptySources,
    LocalMatchRunValidationCode.emptyQueue =>
      l10n.localMatchValidationEmptyQueue,
    LocalMatchRunValidationCode.tagRequiresLrc =>
      l10n.commonAudioTagRequiresLrc,
    LocalMatchRunValidationCode.skipExistingFileNameConflict =>
      l10n.localMatchValidationSkipExistingFileNameConflict,
    LocalMatchRunValidationCode.savePlanBlocked => _savePlanBlockerText(
      context,
      issue.savePlanBlocker,
    ),
    LocalMatchRunValidationCode.missingAndroidTree =>
      l10n.localMatchValidationMissingAndroidTree,
  };
}

String _validationIssuesText(
  BuildContext context,
  List<LocalMatchRunValidationIssue> issues,
) {
  if (issues.isEmpty) {
    return context.l10n.localMatchNoticeValidationFailed;
  }
  return issues
      .map((LocalMatchRunValidationIssue issue) {
        return localMatchValidationIssueText(context, issue);
      })
      .join('\n');
}

String _savePlanBlockerText(
  BuildContext context,
  LocalMatchSavePlanBlocker? blocker,
) {
  final l10n = context.l10n;
  return switch (blocker) {
    LocalMatchSavePlanBlocker.needsSaveRoot =>
      l10n.localMatchValidationNeedsSaveRoot,
    LocalMatchSavePlanBlocker.needsSongRoot =>
      l10n.localMatchValidationNeedsSongRoot,
    LocalMatchSavePlanBlocker.unknown ||
    null => l10n.localMatchValidationUnknownSavePath,
    LocalMatchSavePlanBlocker.none => l10n.localMatchNoticeValidationFailed,
  };
}
