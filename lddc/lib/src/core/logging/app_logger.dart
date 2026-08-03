import '../config/app_config.dart';
import 'app_log_runtime_stub.dart'
    if (dart.library.io) 'app_log_runtime_io.dart';

class AppLogger {
  const AppLogger._(this.scopeName, this.baseFields);

  final String scopeName;
  final Map<String, Object?> baseFields;

  factory AppLogger.scope(
    String scope, {
    Map<String, Object?> baseFields = const <String, Object?>{},
  }) {
    return AppLogger._(scope, Map<String, Object?>.unmodifiable(baseFields));
  }

  AppLogger child(
    String childScope, {
    Map<String, Object?> baseFields = const <String, Object?>{},
  }) {
    return AppLogger.scope(
      '$scopeName/$childScope',
      baseFields: <String, Object?>{...this.baseFields, ...baseFields},
    );
  }

  void trace(String message, {Map<String, Object?> fields = const {}}) {
    _log(AppLogLevel.trace, message, fields);
  }

  void debug(String message, {Map<String, Object?> fields = const {}}) {
    _log(AppLogLevel.debug, message, fields);
  }

  void info(String message, {Map<String, Object?> fields = const {}}) {
    _log(AppLogLevel.info, message, fields);
  }

  void warning(String message, {Map<String, Object?> fields = const {}}) {
    _log(AppLogLevel.warning, message, fields);
  }

  void error(String message, {Map<String, Object?> fields = const {}}) {
    _log(AppLogLevel.error, message, fields);
  }

  void _log(AppLogLevel level, String message, Map<String, Object?> fields) {
    if (!AppLogRuntime.isEnabled(level)) {
      return;
    }
    AppLogRuntime.log(
      scope: scopeName,
      level: level,
      message: message,
      fields: switch ((baseFields.isEmpty, fields.isEmpty)) {
        (true, _) => fields,
        (_, true) => baseFields,
        _ => <String, Object?>{...baseFields, ...fields},
      },
    );
  }
}
