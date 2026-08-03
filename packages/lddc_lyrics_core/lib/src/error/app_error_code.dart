/// 统一错误码枚举。
enum AppErrorCode {
  unknown,
  operationTimeout,
  networkUnavailable,
  invalidPayload,
  unsupportedOperation,
  permissionDenied,
  ioFailure,
  lyricsRequestFailed,
  lyricsNotFound,
  lyricsProcessingFailed,
  lyricsDecryptFailed,
  lyricsFormatUnsupported,
  decodingFailed,
  songInfoReadFailed,
  unsupportedFileType,
  dragDropInvalid,
  translateFailed,
  apiParamsInvalid,
  apiRequestFailed,
  autoFetchUnknown,
  notEnoughInfo,
  ipcInvalidLength,
  ipcUnsupportedTask,
  ipcInstanceNotFound,
  ipcPanelNotFound,
  ipcInvalidWindowId,
  ipcEmbedUnsupported,
}

/// 错误码元数据。
class _AppErrorCodeMeta {
  const _AppErrorCodeMeta({
    required this.protocolCode,
    required this.defaultSeverity,
    this.acceptsIpcInput = false,
  });

  final String protocolCode;
  final AppErrorSeverity defaultSeverity;
  final bool acceptsIpcInput;
}

/// 错误严重级别。
enum AppErrorSeverity { warning, error }

/// 单一错误码元数据表。
///
/// 错误码字符串、默认严重级别和协议输入权限都从这里派生，避免多个 switch 漂移。
const Map<AppErrorCode, _AppErrorCodeMeta> _appErrorCodeMetas =
    <AppErrorCode, _AppErrorCodeMeta>{
      AppErrorCode.unknown: _AppErrorCodeMeta(
        protocolCode: 'E_UNKNOWN',
        defaultSeverity: AppErrorSeverity.error,
        acceptsIpcInput: true,
      ),
      AppErrorCode.operationTimeout: _AppErrorCodeMeta(
        protocolCode: 'E_TIMEOUT',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.networkUnavailable: _AppErrorCodeMeta(
        protocolCode: 'E_NETWORK',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.invalidPayload: _AppErrorCodeMeta(
        protocolCode: 'E_INVALID_PAYLOAD',
        defaultSeverity: AppErrorSeverity.error,
        acceptsIpcInput: true,
      ),
      AppErrorCode.unsupportedOperation: _AppErrorCodeMeta(
        protocolCode: 'E_UNSUPPORTED_OPERATION',
        defaultSeverity: AppErrorSeverity.warning,
      ),
      AppErrorCode.permissionDenied: _AppErrorCodeMeta(
        protocolCode: 'E_PERMISSION_DENIED',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.ioFailure: _AppErrorCodeMeta(
        protocolCode: 'E_IO_FAILURE',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.lyricsRequestFailed: _AppErrorCodeMeta(
        protocolCode: 'E_LYRICS_REQUEST',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.lyricsNotFound: _AppErrorCodeMeta(
        protocolCode: 'E_LYRICS_NOT_FOUND',
        defaultSeverity: AppErrorSeverity.warning,
      ),
      AppErrorCode.lyricsProcessingFailed: _AppErrorCodeMeta(
        protocolCode: 'E_LYRICS_PROCESSING',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.lyricsDecryptFailed: _AppErrorCodeMeta(
        protocolCode: 'E_LYRICS_DECRYPT',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.lyricsFormatUnsupported: _AppErrorCodeMeta(
        protocolCode: 'E_LYRICS_FORMAT_UNSUPPORTED',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.decodingFailed: _AppErrorCodeMeta(
        protocolCode: 'E_DECODING',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.songInfoReadFailed: _AppErrorCodeMeta(
        protocolCode: 'E_SONG_INFO_READ',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.unsupportedFileType: _AppErrorCodeMeta(
        protocolCode: 'E_UNSUPPORTED_FILE_TYPE',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.dragDropInvalid: _AppErrorCodeMeta(
        protocolCode: 'E_DROP_INVALID',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.translateFailed: _AppErrorCodeMeta(
        protocolCode: 'E_TRANSLATE',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.apiParamsInvalid: _AppErrorCodeMeta(
        protocolCode: 'E_API_PARAMS',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.apiRequestFailed: _AppErrorCodeMeta(
        protocolCode: 'E_API_REQUEST',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.autoFetchUnknown: _AppErrorCodeMeta(
        protocolCode: 'E_AUTO_FETCH_UNKNOWN',
        defaultSeverity: AppErrorSeverity.error,
      ),
      AppErrorCode.notEnoughInfo: _AppErrorCodeMeta(
        protocolCode: 'E_NOT_ENOUGH_INFO',
        defaultSeverity: AppErrorSeverity.warning,
      ),
      AppErrorCode.ipcInvalidLength: _AppErrorCodeMeta(
        protocolCode: 'E_INVALID_LENGTH',
        defaultSeverity: AppErrorSeverity.error,
        acceptsIpcInput: true,
      ),
      AppErrorCode.ipcUnsupportedTask: _AppErrorCodeMeta(
        protocolCode: 'E_UNSUPPORTED_TASK',
        defaultSeverity: AppErrorSeverity.error,
        acceptsIpcInput: true,
      ),
      AppErrorCode.ipcInstanceNotFound: _AppErrorCodeMeta(
        protocolCode: 'E_INSTANCE_NOT_FOUND',
        defaultSeverity: AppErrorSeverity.warning,
        acceptsIpcInput: true,
      ),
      AppErrorCode.ipcPanelNotFound: _AppErrorCodeMeta(
        protocolCode: 'E_PANEL_NOT_FOUND',
        defaultSeverity: AppErrorSeverity.warning,
        acceptsIpcInput: true,
      ),
      AppErrorCode.ipcInvalidWindowId: _AppErrorCodeMeta(
        protocolCode: 'E_INVALID_WIN_ID',
        defaultSeverity: AppErrorSeverity.error,
        acceptsIpcInput: true,
      ),
      AppErrorCode.ipcEmbedUnsupported: _AppErrorCodeMeta(
        protocolCode: 'E_EMBED_UNSUPPORTED',
        defaultSeverity: AppErrorSeverity.warning,
        acceptsIpcInput: true,
      ),
    };

final Map<String, AppErrorCode> _appErrorCodesByProtocol =
    Map<String, AppErrorCode>.unmodifiable(<String, AppErrorCode>{
      for (final MapEntry<AppErrorCode, _AppErrorCodeMeta> entry
          in _appErrorCodeMetas.entries)
        entry.value.protocolCode: entry.key,
    });

AppErrorCode? tryParseAppErrorCode(String protocolCode) {
  return _appErrorCodesByProtocol[protocolCode];
}

AppErrorCode? tryParseIpcAppErrorCode(String protocolCode) {
  final AppErrorCode? code = _appErrorCodesByProtocol[protocolCode];
  return code != null && _appErrorCodeMetas[code]!.acceptsIpcInput
      ? code
      : null;
}

/// 错误码字符串映射（用于协议与日志输出）。
extension AppErrorCodeValue on AppErrorCode {
  String get value => _appErrorCodeMetas[this]!.protocolCode;

  AppErrorSeverity get defaultSeverity =>
      _appErrorCodeMetas[this]!.defaultSeverity;
}
