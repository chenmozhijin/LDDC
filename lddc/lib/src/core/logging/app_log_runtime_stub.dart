import '../config/app_config.dart';
import 'log_retention_policy.dart';
import 'log_sink.dart';

abstract final class AppLogRuntime {
  static bool get isInitialized => false;
  static int get debugDroppedCount => 0;
  static int get debugDegradedSinkCount => 0;
  static bool isEnabled(AppLogLevel level) => false;

  static Future<void> initialize({
    required String role,
    int? instanceId,
    int? panelId,
    AppLogLevel minimumLevel = AppLogLevel.info,
    Future<Object?> Function()? logDirectoryResolver,
    List<LogSink>? sinks,
    LogRetentionPolicy retentionPolicy = const LogRetentionPolicy(),
  }) async {}

  static void updateLevel(AppLogLevel level) {}

  static void updateContext({
    required String role,
    int? instanceId,
    int? panelId,
  }) {}

  static void log({
    required String scope,
    required AppLogLevel level,
    required String message,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {}

  static Future<void> flush() async {}

  static Future<void> dispose() async {}

  static Future<void> resetForTest() async {}
}
