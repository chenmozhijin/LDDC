import 'app_error_code.dart';

/// 结构化应用错误对象。
class AppError implements Exception {
  AppError({
    required this.code,
    required this.message,
    this.detail,
    this.cause,
    this.stackTrace,
    Map<String, Object?> context = const <String, Object?>{},
  }) : severity = code.defaultSeverity,
       context = Map<String, Object?>.unmodifiable(context);

  final AppErrorCode code;
  final String message;
  final String? detail;
  final AppErrorSeverity severity;
  final Object? cause;
  final StackTrace? stackTrace;
  final Map<String, Object?> context;

  @override
  String toString() {
    return '${code.value}: $message';
  }
}
