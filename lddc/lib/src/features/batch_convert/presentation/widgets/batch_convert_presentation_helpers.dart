import 'package:flutter/widgets.dart';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../../core/i18n/i18n.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../application/batch_convert_page_state.dart';

typedef BatchConvertStatusView = ({
  BatchConvertTaskPhase taskPhase,
  int progressCurrent,
  int progressTotal,
  BatchConvertProgressMessage progressMessage,
  bool isBusy,
  bool hasQueue,
  BatchConvertRunSummary? runSummary,
});

typedef BatchConvertControlsView = ({
  LyricsFormat targetFormat,
  String? saveRootPath,
  bool recursive,
  bool isBusy,
  bool isScanning,
  bool isRunning,
  bool hasQueue,
  bool canStart,
});

// Riverpod 的 select 会用记录类型的结构相等判断是否需要重建。
// 队列行已经由 TaskQueueRuntime 和 ValueListenable 单独驱动，这里只订阅状态条、
// 控制区真正需要的字段，避免单条任务进度刷新时把整块页面都重新 build。
BatchConvertStatusView batchConvertStatusViewOf(BatchConvertPageState state) =>
    (
      taskPhase: state.taskPhase,
      progressCurrent: state.progressCurrent,
      progressTotal: state.progressTotal,
      progressMessage: state.progressMessage,
      isBusy: state.isBusy,
      hasQueue: state.queueItems.isNotEmpty,
      runSummary: state.runSummary,
    );

BatchConvertControlsView batchConvertControlsViewOf(
  BatchConvertPageState state,
) => (
  targetFormat: state.targetFormat,
  saveRootPath: state.saveRootPath,
  recursive: state.recursive,
  isBusy: state.isBusy,
  isScanning: state.isScanning,
  isRunning: state.isRunning,
  hasQueue: state.queueItems.isNotEmpty,
  canStart: state.canStart,
);

const List<LyricsFormat> batchConvertTargetFormats =
    LyricsFormatCapabilities.exportableFormats;

String batchConvertPhaseLabel(
  BuildContext context,
  BatchConvertTaskPhase phase,
) {
  final l10n = context.l10n;
  return switch (phase) {
    BatchConvertTaskPhase.idle => l10n.batchConvertPhaseIdle,
    BatchConvertTaskPhase.scanning => l10n.batchConvertPhaseScanning,
    BatchConvertTaskPhase.running => l10n.batchConvertPhaseRunning,
    BatchConvertTaskPhase.completed => l10n.batchConvertPhaseCompleted,
  };
}

String batchConvertPhasePipelineLabel(
  BuildContext context,
  BatchConvertTaskPhase phase,
) {
  final l10n = context.l10n;
  return switch (phase) {
    BatchConvertTaskPhase.idle => l10n.batchConvertPipelineIdle,
    BatchConvertTaskPhase.scanning => l10n.batchConvertPipelineScanning,
    BatchConvertTaskPhase.running => l10n.batchConvertPipelineRunning,
    BatchConvertTaskPhase.completed => l10n.batchConvertPipelineCompleted,
  };
}

String batchConvertPhaseHint(
  BuildContext context,
  BatchConvertStatusView view,
) {
  final l10n = context.l10n;
  if (view.runSummary != null) {
    final BatchConvertRunSummary summary = view.runSummary!;
    return summary.cancelled
        ? l10n.batchConvertHintCancelled(
            summary.successCount,
            summary.failureCount,
          )
        : l10n.batchConvertHintCompleted(
            summary.successCount,
            summary.failureCount,
          );
  }
  if (!view.hasQueue) {
    return l10n.batchConvertHintNoQueue;
  }
  return l10n.batchConvertHintReady;
}

String batchConvertProgressMessageText(
  BuildContext context,
  BatchConvertProgressMessage message,
) {
  final l10n = context.l10n;
  return switch (message.code) {
    BatchConvertProgressMessageCode.empty => '',
    BatchConvertProgressMessageCode.convertingFile =>
      l10n.batchConvertProgressConvertingFile(message.detail ?? ''),
    BatchConvertProgressMessageCode.itemSuccess =>
      l10n.batchConvertProgressItemSuccess,
    BatchConvertProgressMessageCode.itemFailure =>
      l10n.batchConvertProgressItemFailure,
    BatchConvertProgressMessageCode.preparingConversion =>
      l10n.batchConvertProgressPreparingConversion,
    BatchConvertProgressMessageCode.cancellingConversion =>
      l10n.batchConvertProgressCancellingConversion,
    BatchConvertProgressMessageCode.conversionCancelled =>
      l10n.batchConvertProgressConversionCancelled,
    BatchConvertProgressMessageCode.conversionCompleted =>
      l10n.batchConvertProgressConversionCompleted(
        message.successCount ?? 0,
        message.failureCount ?? 0,
      ),
    BatchConvertProgressMessageCode.conversionFailed =>
      l10n.batchConvertProgressConversionFailed(message.detail ?? ''),
    BatchConvertProgressMessageCode.scanningFolders =>
      l10n.batchConvertProgressScanningFolders,
    BatchConvertProgressMessageCode.scanningDirectory =>
      l10n.batchConvertProgressScanningDirectory(message.detail ?? ''),
    BatchConvertProgressMessageCode.scannedLyricsFiles =>
      l10n.batchConvertProgressScannedLyricsFiles(message.count ?? 0),
    BatchConvertProgressMessageCode.scanCancelled =>
      l10n.batchConvertProgressScanCancelled,
    BatchConvertProgressMessageCode.scanNoSupportedFiles =>
      l10n.batchConvertProgressScanNoSupportedFiles,
    BatchConvertProgressMessageCode.scanCompleted =>
      l10n.batchConvertProgressScanCompleted,
  };
}
