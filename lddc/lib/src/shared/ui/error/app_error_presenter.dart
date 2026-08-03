import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../core/i18n/l10n/app_localizations.dart';

/// 面向 UI 的错误展示模型。
class AppErrorPresentation {
  const AppErrorPresentation({
    required this.title,
    required this.message,
    required this.severity,
    this.detail,
    this.actionHint,
  });

  final String title;
  final String message;
  final String? detail;
  final String? actionHint;
  final AppErrorSeverity severity;
}

/// 错误展示层适配器：将结构化错误转换为当前语言的 UI 文案。
class AppErrorPresenter {
  const AppErrorPresenter._();

  /// 生成展示模型（标题/文案/建议动作）。
  static AppErrorPresentation toPresentation(
    AppError error,
    AppLocalizations l10n,
  ) {
    return AppErrorPresentation(
      title: _titleOf(error.severity, l10n),
      message: _messageOf(error, l10n),
      detail: error.detail,
      actionHint: _actionHint(error.code, l10n),
      severity: error.severity,
    );
  }

  static String _titleOf(AppErrorSeverity severity, AppLocalizations l10n) {
    return switch (severity) {
      AppErrorSeverity.warning => l10n.commonWarning,
      AppErrorSeverity.error => l10n.commonError,
    };
  }

  static String _messageOf(AppError error, AppLocalizations l10n) {
    return switch (error.code) {
      AppErrorCode.operationTimeout => l10n.appErrorOperationTimeout,
      AppErrorCode.networkUnavailable => l10n.appErrorNetworkUnavailable,
      AppErrorCode.invalidPayload => l10n.appErrorInvalidPayload,
      AppErrorCode.unsupportedOperation => l10n.appErrorUnsupportedOperation,
      AppErrorCode.permissionDenied => l10n.appErrorPermissionDenied,
      AppErrorCode.ioFailure => l10n.appErrorIoFailure,
      AppErrorCode.lyricsRequestFailed => l10n.appErrorLyricsRequestFailed,
      AppErrorCode.lyricsNotFound => l10n.appErrorLyricsNotFound,
      AppErrorCode.lyricsProcessingFailed => l10n.appErrorLyricsProcessing,
      AppErrorCode.lyricsDecryptFailed => l10n.appErrorLyricsDecrypt,
      AppErrorCode.lyricsFormatUnsupported =>
        l10n.appErrorLyricsFormatUnsupported,
      AppErrorCode.decodingFailed => l10n.appErrorDecoding,
      AppErrorCode.songInfoReadFailed => l10n.appErrorSongInfoRead,
      AppErrorCode.unsupportedFileType => l10n.appErrorUnsupportedFileType,
      AppErrorCode.dragDropInvalid => l10n.appErrorDragDropInvalid,
      AppErrorCode.translateFailed => l10n.appErrorTranslateFailed,
      AppErrorCode.apiParamsInvalid => l10n.appErrorApiParamsInvalid,
      AppErrorCode.apiRequestFailed => l10n.appErrorApiRequestFailed,
      AppErrorCode.autoFetchUnknown => l10n.appErrorAutoFetchUnknown,
      AppErrorCode.notEnoughInfo => l10n.appErrorNotEnoughInfo,
      AppErrorCode.ipcInvalidLength => l10n.appErrorIpcInvalidLength,
      AppErrorCode.ipcUnsupportedTask => l10n.appErrorIpcUnsupportedTask,
      AppErrorCode.ipcInstanceNotFound => l10n.appErrorIpcInstanceNotFound,
      AppErrorCode.ipcPanelNotFound => l10n.appErrorIpcPanelNotFound,
      AppErrorCode.ipcInvalidWindowId => l10n.appErrorIpcInvalidWindowId,
      AppErrorCode.ipcEmbedUnsupported => l10n.appErrorIpcEmbedUnsupported,
      AppErrorCode.unknown => l10n.appErrorUnknown,
    };
  }

  static String? _actionHint(AppErrorCode code, AppLocalizations l10n) {
    return switch (code) {
      AppErrorCode.networkUnavailable ||
      AppErrorCode.apiRequestFailed ||
      AppErrorCode.operationTimeout => l10n.appErrorActionRetryNetwork,
      AppErrorCode.invalidPayload => l10n.appErrorActionCheckPayload,
      AppErrorCode.unsupportedFileType ||
      AppErrorCode.lyricsFormatUnsupported => l10n.appErrorActionChangeFormat,
      AppErrorCode.ipcEmbedUnsupported => l10n.appErrorActionDetachedMode,
      _ => null,
    };
  }
}
