import 'app_error_code.dart';

/// 聚合错误中的单个底层失败原因。
class AppFailureCause {
  const AppFailureCause({
    required this.error,
    this.stackTrace,
    this.source,
    this.stage,
  });

  final Object error;
  final StackTrace? stackTrace;
  final String? source;
  final String? stage;

  @override
  String toString() {
    final StringBuffer buffer = StringBuffer(error);
    if (source != null) {
      buffer.write(' source=$source');
    }
    if (stage != null) {
      buffer.write(' stage=$stage');
    }
    return buffer.toString();
  }
}

/// LDDC 语义异常基类。
///
/// Python 版兼容只保留在数据、协议和文件格式边界；异常文本不再参与错误码判断，
/// 因此每个业务异常都必须显式携带结构化错误码。
abstract class LddcException implements Exception {
  const LddcException(
    this.message, {
    required this.code,
    this.detail,
    this.cause,
    this.stackTrace,
    this.context = const <String, Object?>{},
  });

  final String message;
  final AppErrorCode code;
  final String? detail;
  final Object? cause;
  final StackTrace? stackTrace;
  final Map<String, Object?> context;

  @override
  String toString() => message;
}

/// 请求歌词失败。
class LddcLyricsRequestException extends LddcException {
  const LddcLyricsRequestException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.lyricsRequestFailed);
}

/// 歌词处理失败（基类）。
class LddcLyricsProcessingException extends LddcException {
  const LddcLyricsProcessingException(
    super.message, {
    super.code = AppErrorCode.lyricsProcessingFailed,
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super();
}

/// 歌词解密失败。
class LddcLyricsDecryptException extends LddcLyricsProcessingException {
  const LddcLyricsDecryptException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.lyricsDecryptFailed);
}

/// 歌词格式不支持或解析失败。
class LddcLyricsFormatException extends LddcLyricsProcessingException {
  const LddcLyricsFormatException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.lyricsFormatUnsupported);
}

/// 通用解码失败。
class LddcDecodingException extends LddcException {
  const LddcDecodingException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.decodingFailed);
}

/// 读取歌曲信息失败。
class LddcGetSongInfoException extends LddcException {
  const LddcGetSongInfoException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.songInfoReadFailed);
}

/// 文件类型不支持。
class LddcFileTypeException extends LddcException {
  const LddcFileTypeException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.unsupportedFileType);
}

/// 拖拽输入数据无效。
class LddcDropException extends LddcException {
  const LddcDropException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.dragDropInvalid);
}

/// 翻译调用失败。
class LddcTranslateException extends LddcException {
  const LddcTranslateException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.translateFailed);
}

/// API 参数不合法。
class LddcApiParamsException extends LddcException {
  const LddcApiParamsException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.apiParamsInvalid);
}

/// API 请求失败。
class LddcApiRequestException extends LddcException {
  const LddcApiRequestException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.apiRequestFailed);
}

/// API 能力不支持（例如来源不支持候选歌词列表）。
class LddcApiNotSupportedException extends LddcException {
  const LddcApiNotSupportedException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.unsupportedOperation);
}

/// 未找到歌词。
class LddcLyricsNotFoundException extends LddcException {
  const LddcLyricsNotFoundException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.lyricsNotFound);
}

/// 搜索信息不足。
class LddcNotEnoughInfoException extends LddcException {
  const LddcNotEnoughInfoException(
    super.message, {
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : super(code: AppErrorCode.notEnoughInfo);
}

/// 自动匹配出现未知错误，可附带底层失败原因列表。
class LddcAutoFetchUnknownException extends LddcException {
  LddcAutoFetchUnknownException(
    super.message, {
    List<AppFailureCause> causes = const <AppFailureCause>[],
    super.detail,
    super.cause,
    super.stackTrace,
    super.context,
  }) : causes = List<AppFailureCause>.unmodifiable(causes),
       super(code: AppErrorCode.autoFetchUnknown);

  final List<AppFailureCause> causes;
}
