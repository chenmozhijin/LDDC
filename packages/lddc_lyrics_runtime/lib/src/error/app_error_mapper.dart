import 'dart:async';
import 'dart:io';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 异常到结构化错误的映射器。
class AppErrorMapper {
  const AppErrorMapper._();

  /// 将任意异常映射为 [AppError]。
  static AppError fromException(Object error, [StackTrace? stackTrace]) {
    if (error is AppError) {
      return error;
    }

    if (error is LddcException) {
      return _fromLddcException(error, stackTrace);
    }

    if (error is TimeoutException) {
      return _build(
        code: AppErrorCode.operationTimeout,
        message: error.message ?? error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is SocketException) {
      return _build(
        code: AppErrorCode.networkUnavailable,
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FileSystemException) {
      return _build(
        code: _isPermissionDenied(error)
            ? AppErrorCode.permissionDenied
            : AppErrorCode.ioFailure,
        message: error.message,
        detail: error.path,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FormatException) {
      return _build(
        code: AppErrorCode.invalidPayload,
        message: error.message,
        cause: error,
        stackTrace: stackTrace,
        context: <String, Object?>{
          'offset': error.offset,
          if (error.source != null)
            'sourceType': error.source.runtimeType.toString(),
        },
      );
    }

    return _build(
      code: AppErrorCode.unknown,
      message: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  /// 将 IPC 协议错误码映射为 [AppError]。
  static AppError fromIpcProtocolCode({
    required String protocolCode,
    required String message,
    String? detail,
  }) {
    final AppErrorCode code =
        tryParseIpcAppErrorCode(protocolCode) ?? AppErrorCode.unknown;
    return _build(
      code: code,
      message: message,
      detail: detail,
      context: <String, Object?>{
        if (code == AppErrorCode.unknown) 'protocolCode': protocolCode,
      },
    );
  }

  static AppError _fromLddcException(
    LddcException error,
    StackTrace? fallbackStackTrace,
  ) {
    return _build(
      code: error.code,
      message: error.message,
      detail: _detailOf(error),
      cause: error.cause ?? error,
      stackTrace: error.stackTrace ?? fallbackStackTrace,
      context: error.context,
    );
  }

  static String? _detailOf(LddcException error) {
    if (error.detail != null) {
      return error.detail;
    }
    if (error is LddcAutoFetchUnknownException && error.causes.isNotEmpty) {
      return error.causes
          .map((AppFailureCause cause) => cause.toString())
          .join('\n');
    }
    return null;
  }

  static bool _isPermissionDenied(FileSystemException error) {
    final int? errorCode = error.osError?.errorCode;
    // POSIX 的 EPERM/EACCES 分别是 1/13，Windows 的
    // ERROR_ACCESS_DENIED 是 5。其余文件系统错误仍归入通用 IO 失败。
    return errorCode == 1 || errorCode == 5 || errorCode == 13;
  }

  /// 内部统一构造函数，保证默认字段一致。
  static AppError _build({
    required AppErrorCode code,
    required String message,
    String? detail,
    Object? cause,
    StackTrace? stackTrace,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    return AppError(
      code: code,
      message: message,
      detail: detail,
      cause: cause,
      stackTrace: stackTrace,
      context: context,
    );
  }
}
