import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';
import '../storage/app_storage_paths_port.dart';
import 'app_log_record.dart';
import 'log_retention_policy.dart';
import 'log_sink.dart';

abstract final class AppLogRuntime {
  static const int _maxQueueSize = 512;
  static const int _maxPreInitQueueSize = 64;
  static final Queue<_PendingRecord> _preInitQueue = Queue<_PendingRecord>();
  static final Queue<AppLogRecord> _queue = Queue<AppLogRecord>();
  static final List<LogSink> _sinks = <LogSink>[];
  static AppLogLevel _minimumLevel = AppLogLevel.info;
  static String _role = 'unknown';
  static int? _instanceId;
  static int? _panelId;
  static int _sequence = 0;
  static bool _initialized = false;
  static int _droppedCount = 0;
  static int _preInitDroppedCount = 0;
  static int _degradedSinkCount = 0;
  static Future<void>? _drainFuture;
  static Future<void>? _lifecycleBarrier;

  static bool get isInitialized => _initialized;
  static int get debugDroppedCount => _droppedCount + _preInitDroppedCount;
  static int get debugDegradedSinkCount => _degradedSinkCount;

  static bool isEnabled(AppLogLevel level) {
    return _compareLevel(level, _minimumLevel) >= 0;
  }

  static Future<void> initialize({
    required String role,
    int? instanceId,
    int? panelId,
    AppLogLevel minimumLevel = AppLogLevel.info,
    Future<Directory> Function()? logDirectoryResolver,
    List<LogSink>? sinks,
    LogRetentionPolicy retentionPolicy = const LogRetentionPolicy(),
  }) {
    final List<LogSink>? sinkSnapshot = sinks == null
        ? null
        : _snapshotSinks(sinks);
    return _enqueueLifecycle(() async {
      await _disposeCurrent(clearPreInit: false, resetDiagnostics: false);
      await _initializeCurrent(
        role: role,
        instanceId: instanceId,
        panelId: panelId,
        minimumLevel: minimumLevel,
        logDirectoryResolver: logDirectoryResolver,
        sinks: sinkSnapshot,
        retentionPolicy: retentionPolicy,
      );
    });
  }

  static Future<void> _initializeCurrent({
    required String role,
    required int? instanceId,
    required int? panelId,
    required AppLogLevel minimumLevel,
    required Future<Directory> Function()? logDirectoryResolver,
    required List<LogSink>? sinks,
    required LogRetentionPolicy retentionPolicy,
  }) async {
    _minimumLevel = minimumLevel;
    _role = role;
    _instanceId = instanceId;
    _panelId = panelId;
    _sequence = 0;
    _droppedCount = 0;
    _degradedSinkCount = 0;
    final List<LogSink> resolvedSinks =
        sinks ??
        <LogSink>[
          await FileLogSink.create(
            role: role,
            instanceId: instanceId,
            panelId: panelId,
            logDirectoryResolver:
                logDirectoryResolver ??
                () => AppStoragePathsRegistry.current.resolveLogDirectory(),
            retentionPolicy: retentionPolicy,
          ),
        ];
    if (resolvedSinks.isEmpty) {
      throw ArgumentError.value(sinks, 'sinks', '日志运行时至少需要一个 sink');
    }
    _sinks.addAll(resolvedSinks);
    _initialized = true;
    while (_preInitQueue.isNotEmpty) {
      final _PendingRecord pending = _preInitQueue.removeFirst();
      _enqueueRecord(
        AppLogRecord(
          timestamp: pending.timestamp,
          level: pending.level,
          role: _role,
          pid: pid,
          scope: pending.scope,
          sequence: ++_sequence,
          message: pending.message,
          instanceId: _instanceId,
          panelId: _panelId,
          fields: pending.fields,
        ),
      );
    }
    _droppedCount += _preInitDroppedCount;
    _preInitDroppedCount = 0;
    unawaited(_drainQueue());
  }

  static void updateLevel(AppLogLevel level) {
    _minimumLevel = level;
  }

  static void updateContext({
    required String role,
    int? instanceId,
    int? panelId,
  }) {
    _role = role;
    _instanceId = instanceId;
    _panelId = panelId;
  }

  static void log({
    required String scope,
    required AppLogLevel level,
    required String message,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    if (!isEnabled(level)) {
      return;
    }
    if (!_initialized) {
      if (_preInitQueue.length >= _maxPreInitQueueSize) {
        _preInitQueue.removeFirst();
        _preInitDroppedCount += 1;
      }
      _preInitQueue.addLast(
        _PendingRecord(
          timestamp: DateTime.now(),
          level: level,
          scope: scope,
          message: message,
          fields: Map<String, Object?>.from(fields),
        ),
      );
      return;
    }
    _enqueueRecord(
      AppLogRecord(
        timestamp: DateTime.now(),
        level: level,
        role: _role,
        pid: pid,
        scope: scope,
        sequence: ++_sequence,
        message: message,
        instanceId: _instanceId,
        panelId: _panelId,
        fields: Map<String, Object?>.from(fields),
      ),
    );
    unawaited(_drainQueue());
  }

  static Future<void> flush() async {
    final Future<void>? lifecycle = _lifecycleBarrier;
    if (lifecycle != null) {
      await lifecycle;
    }
    await _drainQueue();
    for (final LogSink sink in List<LogSink>.of(_sinks)) {
      await _flushSink(sink);
    }
  }

  static Future<void> dispose() {
    return _enqueueLifecycle(
      () => _disposeCurrent(clearPreInit: false, resetDiagnostics: false),
    );
  }

  static Future<void> resetForTest() {
    return _enqueueLifecycle(
      () => _disposeCurrent(clearPreInit: true, resetDiagnostics: true),
    );
  }

  static Future<void> _disposeCurrent({
    required bool clearPreInit,
    required bool resetDiagnostics,
  }) async {
    // 关闭开始后，新日志进入有上限的预初始化队列，不再与正在关闭的 sink
    // 竞争。已有队列先排空，再逐个关闭资源，确保返回时没有后台写入。
    _initialized = false;
    try {
      await _drainQueue();
      for (final LogSink sink in List<LogSink>.of(_sinks)) {
        if (!await _tryCloseSink(sink)) {
          _degradedSinkCount += 1;
        }
      }
    } finally {
      _sinks.clear();
      _queue.clear();
      if (clearPreInit) {
        _preInitQueue.clear();
        _preInitDroppedCount = 0;
      }
      _drainFuture = null;
      _droppedCount = 0;
      if (resetDiagnostics) {
        _degradedSinkCount = 0;
      }
      _sequence = 0;
      _minimumLevel = AppLogLevel.info;
      _role = 'unknown';
      _instanceId = null;
      _panelId = null;
    }
  }

  static void _enqueueRecord(AppLogRecord record) {
    if (_queue.length >= _maxQueueSize) {
      _droppedCount += 1;
      return;
    }
    _queue.addLast(record);
  }

  static Future<void> _drainQueue() async {
    if (_sinks.isEmpty) {
      if (_queue.isNotEmpty) {
        _droppedCount += _queue.length;
        _queue.clear();
      }
      return;
    }
    final Future<void>? currentDrain = _drainFuture;
    if (currentDrain != null) {
      await currentDrain;
      return;
    }
    _drainFuture = () async {
      do {
        while (_queue.isNotEmpty && _sinks.isNotEmpty) {
          final AppLogRecord record = _queue.removeFirst();
          await _writeRecordToSinks(record);
        }
        if (_sinks.isEmpty) {
          _initialized = false;
          _droppedCount += _queue.length;
          _queue.clear();
          return;
        }
        if (_droppedCount > 0) {
          final int dropped = _droppedCount;
          _droppedCount = 0;
          final bool delivered = await _writeRecordToSinks(
            AppLogRecord(
              timestamp: DateTime.now(),
              level: AppLogLevel.warning,
              role: _role,
              pid: pid,
              scope: 'logging',
              sequence: ++_sequence,
              message: 'log_drop_summary',
              instanceId: _instanceId,
              panelId: _panelId,
              fields: <String, Object?>{'dropped': dropped},
            ),
          );
          if (!delivered) {
            _droppedCount += dropped;
          }
        }
        for (final LogSink sink in List<LogSink>.of(_sinks)) {
          await _flushSink(sink);
        }
      } while (_sinks.isNotEmpty && (_queue.isNotEmpty || _droppedCount > 0));
    }();
    try {
      await _drainFuture;
    } finally {
      _drainFuture = null;
    }
  }

  static Future<bool> _writeRecordToSinks(AppLogRecord record) async {
    bool delivered = false;
    for (final LogSink sink in List<LogSink>.of(_sinks)) {
      try {
        await sink.write(record);
        delivered = true;
      } on Object {
        await _markSinkDegraded(sink);
      }
    }
    return delivered;
  }

  static Future<void> _flushSink(LogSink sink) async {
    if (!_ownsSink(sink)) {
      return;
    }
    try {
      await sink.flush();
    } on Object {
      await _markSinkDegraded(sink);
    }
  }

  static Future<bool> _tryCloseSink(LogSink sink) async {
    try {
      await sink.close();
      return true;
    } on Object {
      return false;
    }
  }

  static Future<void> _markSinkDegraded(LogSink sink) async {
    final int index = _sinks.indexWhere(
      (LogSink candidate) => identical(candidate, sink),
    );
    if (index < 0) {
      return;
    }
    _sinks.removeAt(index);
    _degradedSinkCount += 1;
    await _tryCloseSink(sink);
    if (_sinks.isEmpty) {
      _initialized = false;
    }
  }

  static bool _ownsSink(LogSink sink) {
    return _sinks.any((LogSink candidate) => identical(candidate, sink));
  }

  static List<LogSink> _snapshotSinks(List<LogSink> sinks) {
    final Set<LogSink> seen = HashSet<LogSink>.identity();
    return List<LogSink>.unmodifiable(<LogSink>[
      for (final LogSink sink in sinks)
        if (seen.add(sink)) sink,
    ]);
  }

  static Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final Future<void> previous = _lifecycleBarrier ?? Future<void>.value();
    final Future<void> result = previous.then((_) => operation());
    late final Future<void> barrier;
    barrier = result.then<void>(
      (_) {
        if (identical(_lifecycleBarrier, barrier)) {
          _lifecycleBarrier = null;
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_lifecycleBarrier, barrier)) {
          _lifecycleBarrier = null;
        }
      },
    );
    _lifecycleBarrier = barrier;
    return result;
  }

  static int _compareLevel(AppLogLevel left, AppLogLevel right) {
    return left.index.compareTo(right.index);
  }
}

class FileLogSink implements LogSink {
  FileLogSink._(this._sink);

  final IOSink _sink;

  static Future<FileLogSink> create({
    required String role,
    required int? instanceId,
    required int? panelId,
    required Future<Directory> Function() logDirectoryResolver,
    required LogRetentionPolicy retentionPolicy,
  }) async {
    final Directory logDirectory = await logDirectoryResolver();
    await logDirectory.create(recursive: true);
    final DateTime now = DateTime.now();
    final String fileName =
        'lddc_${_timestampForName(now)}_${role}_pid$pid'
        '${instanceId == null ? '' : '_instance$instanceId'}'
        '${panelId == null ? '' : '_panel$panelId'}.log';
    final File file = File(
      '${logDirectory.path}${Platform.pathSeparator}$fileName',
    );
    // 浮窗、选择器和面板都是短生命周期子 engine。若每个子 engine 启动时
    // 都扫描整个日志目录，频繁开关窗口会叠加大量异步 stat/delete 请求；
    // 日志保留策略由没有实例标识的主运行时统一执行即可。
    if (instanceId == null && panelId == null) {
      unawaited(_cleanup(logDirectory, retentionPolicy));
    }
    final IOSink sink = file.openWrite(
      mode: FileMode.writeOnlyAppend,
      encoding: utf8,
    );
    return FileLogSink._(sink);
  }

  @override
  Future<void> write(AppLogRecord record) async {
    _sink.writeln(record.formatLine());
  }

  @override
  Future<void> flush() {
    return _sink.flush();
  }

  @override
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }

  static Future<void> _cleanup(
    Directory logDirectory,
    LogRetentionPolicy retentionPolicy,
  ) async {
    try {
      final DateTime now = DateTime.now();
      final List<_LogFileStat> fileStats = <_LogFileStat>[];
      int scanned = 0;
      int deleted = 0;
      await for (final FileSystemEntity entity in logDirectory.list(
        followLinks: false,
      )) {
        scanned += 1;
        if (scanned > retentionPolicy.maxCleanupScanCount) {
          break;
        }
        if (entity is! File || !entity.path.toLowerCase().endsWith('.log')) {
          continue;
        }
        // 历史日志维护在后台执行，必须使用 async IO，避免启动期同步扫目录卡住 UI isolate。
        // ignore: avoid_slow_async_io
        final FileStat stat = await entity.stat();
        if (now.difference(stat.modified) > retentionPolicy.maxAge) {
          if (deleted < retentionPolicy.maxDeletesPerRun) {
            final bool didDelete = await _tryDeleteLogFile(entity);
            if (didDelete) {
              deleted += 1;
              continue;
            }
          }
        }
        fileStats.add(_LogFileStat(file: entity, stat: stat));
      }
      fileStats.sort(
        (_LogFileStat left, _LogFileStat right) =>
            right.stat.modified.compareTo(left.stat.modified),
      );
      int totalBytes = 0;
      for (final _LogFileStat fileStat in fileStats) {
        totalBytes += fileStat.stat.size;
        if (totalBytes <= retentionPolicy.maxTotalBytes) {
          continue;
        }
        if (deleted >= retentionPolicy.maxDeletesPerRun) {
          break;
        }
        final bool didDelete = await _tryDeleteLogFile(fileStat.file);
        if (didDelete) {
          deleted += 1;
        }
      }
    } on Object {
      // 日志清理失败不能阻塞主流程。
    }
  }

  static Future<bool> _tryDeleteLogFile(File file) async {
    try {
      await file.delete();
      return true;
    } on Object {
      return false;
    }
  }

  static String _timestampForName(DateTime timestamp) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${timestamp.year}'
        '${twoDigits(timestamp.month)}'
        '${twoDigits(timestamp.day)}_'
        '${twoDigits(timestamp.hour)}'
        '${twoDigits(timestamp.minute)}'
        '${twoDigits(timestamp.second)}';
  }
}

class _PendingRecord {
  const _PendingRecord({
    required this.timestamp,
    required this.level,
    required this.scope,
    required this.message,
    required this.fields,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String scope;
  final String message;
  final Map<String, Object?> fields;
}

class _LogFileStat {
  const _LogFileStat({required this.file, required this.stat});

  final File file;
  final FileStat stat;
}
