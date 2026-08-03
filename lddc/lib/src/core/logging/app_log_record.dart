import '../config/app_config.dart';

class AppLogRecord {
  const AppLogRecord({
    required this.timestamp,
    required this.level,
    required this.role,
    required this.pid,
    required this.scope,
    required this.sequence,
    required this.message,
    this.instanceId,
    this.panelId,
    this.fields = const <String, Object?>{},
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String role;
  final int pid;
  final String scope;
  final int sequence;
  final String message;
  final int? instanceId;
  final int? panelId;
  final Map<String, Object?> fields;

  String formatLine() {
    final StringBuffer buffer = StringBuffer()
      ..write('[')
      ..write(timestamp.toIso8601String())
      ..write('][level=')
      ..write(level.value)
      ..write('][role=')
      ..write(_singleLine(role))
      ..write('][pid=')
      ..write(pid)
      ..write('][scope=')
      ..write(_singleLine(scope))
      ..write('][instance=')
      ..write(instanceId?.toString() ?? '-')
      ..write('][panel=')
      ..write(panelId?.toString() ?? '-')
      ..write('][seq=')
      ..write(sequence)
      ..write('] ')
      ..write(_singleLine(message));
    for (final MapEntry<String, Object?> entry in fields.entries) {
      if (entry.value == null) {
        continue;
      }
      buffer
        ..write(' ')
        ..write(_singleLine(entry.key))
        ..write('=')
        ..write(_formatValue(entry.value));
    }
    return buffer.toString();
  }

  static String _singleLine(String value) {
    return value.replaceAll('\r', r'\r').replaceAll('\n', r'\n');
  }

  static String _formatValue(Object? value) {
    if (value == null) {
      return '-';
    }
    final String text = value.toString();
    if (text.isEmpty) {
      return '""';
    }
    final bool needsQuote = text.contains(RegExp(r'\s|[=\[\]"]'));
    if (!needsQuote) {
      return text;
    }
    final String escaped = text
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }
}
