import 'app_log_record.dart';

abstract interface class LogSink {
  Future<void> write(AppLogRecord record);

  Future<void> flush();

  Future<void> close();
}
