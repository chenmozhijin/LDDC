import 'package:flutter/widgets.dart';

import '../../../core/i18n/i18n.dart';
import '../application/batch_convert_page_state.dart';

String batchConvertNoticeText(BuildContext context, BatchConvertNotice notice) {
  final l10n = context.l10n;
  final String detail = notice.detail ?? '';
  final int count = notice.count ?? 0;
  final int success = notice.successCount ?? 0;
  final int failure = notice.failureCount ?? 0;
  return switch (notice.code) {
    BatchConvertNoticeCode.selectedFilesUnavailable =>
      l10n.batchConvertNoticeSelectedFilesUnavailable,
    BatchConvertNoticeCode.importFilesCompleted =>
      l10n.batchConvertNoticeImportFilesCompleted(count),
    BatchConvertNoticeCode.pageError => detail,
    BatchConvertNoticeCode.droppedNoAccessibleFiles =>
      l10n.batchConvertNoticeDroppedNoAccessibleFiles,
    BatchConvertNoticeCode.selectSaveRootFailed =>
      l10n.commonSelectSaveDirectoryFailed(detail),
    BatchConvertNoticeCode.emptyQueue => l10n.batchConvertNoticeEmptyQueue,
    BatchConvertNoticeCode.overwriteCancelled =>
      l10n.batchConvertNoticeOverwriteCancelled,
    BatchConvertNoticeCode.conversionCancelledCompleted =>
      l10n.batchConvertNoticeConversionCancelledCompleted(count),
    BatchConvertNoticeCode.conversionCompletedWithFailures =>
      l10n.batchConvertNoticeConversionCompletedWithFailures(success, failure),
    BatchConvertNoticeCode.conversionCompleted =>
      l10n.batchConvertNoticeConversionCompleted(count),
    BatchConvertNoticeCode.conversionFailed =>
      l10n.batchConvertNoticeConversionFailed(detail),
    BatchConvertNoticeCode.unsupportedOperation =>
      detail.isEmpty ? l10n.commonUnsupportedOperation : detail,
    BatchConvertNoticeCode.openSourceDirectoryFailed =>
      l10n.batchConvertNoticeOpenSourceDirectoryFailed(detail),
    BatchConvertNoticeCode.openSaveDirectoryFailed =>
      l10n.commonOpenSaveDirectoryFailed(detail),
    BatchConvertNoticeCode.outputFileUnavailable =>
      l10n.commonLyricsFileUnavailable,
    BatchConvertNoticeCode.openOutputFileFailed =>
      l10n.batchConvertNoticeOpenOutputFileFailed(detail),
    BatchConvertNoticeCode.scanNoSupportedFiles =>
      l10n.batchConvertNoticeScanNoSupportedFiles,
    BatchConvertNoticeCode.scanImportedFromDirectory =>
      l10n.batchConvertNoticeScanImportedFromDirectory(count),
    BatchConvertNoticeCode.duplicateItems =>
      l10n.batchConvertNoticeDuplicateItems,
  };
}
