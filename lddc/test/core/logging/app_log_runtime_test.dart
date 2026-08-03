import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lddc/src/core/config/app_config.dart';
import 'package:lddc/src/core/logging/app_log_runtime_io.dart' show FileLogSink;
import 'package:lddc/src/core/logging/logging.dart';

void main() {
  tearDown(() async {
    await AppLogRuntime.resetForTest();
  });

  test('日志运行时会按级别过滤并输出稳定格式', () async {
    final _MemoryLogSink sink = _MemoryLogSink();

    await AppLogRuntime.initialize(
      role: 'main\nrole',
      minimumLevel: AppLogLevel.info,
      sinks: <LogSink>[sink],
    );

    final AppLogger logger = AppLogger.scope('runtime\ntest');
    logger.debug('debug skipped');
    logger.info(
      'info kept\ncontinued',
      fields: <String, Object?>{'step\nid': 1},
    );
    await AppLogRuntime.flush();

    expect(sink.records, hasLength(1));
    final String logText = sink.records.single.formatLine();
    expect(logText, contains('[level=INFO]'));
    expect(logText, contains(r'[role=main\nrole]'));
    expect(logText, contains(r'[scope=runtime\ntest]'));
    expect(logText, contains(r'info kept\ncontinued step\nid=1'));
    expect(logText, isNot(contains('debug skipped')));
    expect(logText, isNot(contains('\n')));
  });

  test('预初始化日志会在初始化后补写', () async {
    final _MemoryLogSink sink = _MemoryLogSink();
    final AppLogger logger = AppLogger.scope('pre-init');

    logger.info('before init', fields: <String, Object?>{'phase': 'queued'});
    await AppLogRuntime.initialize(
      role: 'panel',
      instanceId: 7,
      panelId: 3,
      sinks: <LogSink>[sink],
    );
    await AppLogRuntime.flush();

    expect(sink.records, hasLength(1));
    expect(sink.records.single.role, 'panel');
    expect(sink.records.single.instanceId, 7);
    expect(sink.records.single.panelId, 3);
    expect(sink.records.single.message, 'before init');
    expect(sink.records.single.fields['phase'], 'queued');
  });

  test('队列溢出时会补一条丢弃摘要', () async {
    final Completer<void> releaseCompleter = Completer<void>();
    final _BlockingMemorySink sink = _BlockingMemorySink(
      release: releaseCompleter.future,
    );
    await AppLogRuntime.initialize(
      role: 'main',
      minimumLevel: AppLogLevel.trace,
      sinks: <LogSink>[sink],
    );
    final AppLogger logger = AppLogger.scope('overflow');

    for (int index = 0; index < 700; index += 1) {
      logger.info('event', fields: <String, Object?>{'index': index});
    }
    releaseCompleter.complete();
    await AppLogRuntime.flush();

    final List<AppLogRecord> summaries = sink.records
        .where((AppLogRecord record) => record.message == 'log_drop_summary')
        .toList(growable: false);
    final int eventCount = sink.records
        .where((AppLogRecord record) => record.message == 'event')
        .length;
    expect(summaries, hasLength(1));
    expect(eventCount + (summaries.single.fields['dropped']! as int), 700);
    expect(eventCount, lessThanOrEqualTo(513));
  });

  test('单个 sink 写入和关闭都失败时只降级一次且不影响其他 sink', () async {
    final _ThrowingSink broken = _ThrowingSink(
      throwOnWrite: true,
      throwOnClose: true,
    );
    final _MemoryLogSink healthy = _MemoryLogSink();
    await AppLogRuntime.initialize(
      role: 'main',
      sinks: <LogSink>[broken, healthy],
    );

    AppLogger.scope('runtime-test').info('kept');
    await AppLogRuntime.flush();

    expect(healthy.records.single.message, 'kept');
    expect(AppLogRuntime.debugDegradedSinkCount, 1);
  });

  test('并发 initialize 按调用顺序转移 sink 所有权', () async {
    final _TrackingMemorySink first = _TrackingMemorySink();
    final _TrackingMemorySink second = _TrackingMemorySink();
    final _TrackingMemorySink third = _TrackingMemorySink();
    await AppLogRuntime.initialize(role: 'first', sinks: <LogSink>[first]);

    final Future<void> secondInitialization = AppLogRuntime.initialize(
      role: 'second',
      sinks: <LogSink>[second],
    );
    final Future<void> thirdInitialization = AppLogRuntime.initialize(
      role: 'third',
      sinks: <LogSink>[third],
    );
    await Future.wait(<Future<void>>[
      secondInitialization,
      thirdInitialization,
    ]);

    AppLogger.scope('lifecycle').info('final owner');
    await AppLogRuntime.flush();

    expect(first.closeCount, 1);
    expect(second.closeCount, 1);
    expect(third.closeCount, 0);
    expect(first.records, isEmpty);
    expect(second.records, isEmpty);
    expect(third.records.single.role, 'third');
    expect(third.records.single.message, 'final owner');
  });

  test('重新初始化关闭旧 sink 期间产生的日志会交给新 sink', () async {
    final _BlockingCloseSink oldSink = _BlockingCloseSink();
    final _MemoryLogSink newSink = _MemoryLogSink();
    await AppLogRuntime.initialize(role: 'old', sinks: <LogSink>[oldSink]);

    final Future<void> initialization = AppLogRuntime.initialize(
      role: 'new',
      sinks: <LogSink>[newSink],
    );
    await oldSink.closeStarted;
    expect(AppLogRuntime.isInitialized, isFalse);
    AppLogger.scope('lifecycle').info('during transition');
    oldSink.releaseClose();
    await initialization;
    await AppLogRuntime.flush();

    expect(newSink.records.single.role, 'new');
    expect(newSink.records.single.message, 'during transition');
  });

  test('空 sink 初始化失败后仍可重试', () async {
    await expectLater(
      AppLogRuntime.initialize(role: 'invalid', sinks: <LogSink>[]),
      throwsArgumentError,
    );
    expect(AppLogRuntime.isInitialized, isFalse);

    final _MemoryLogSink sink = _MemoryLogSink();
    await AppLogRuntime.initialize(role: 'retry', sinks: <LogSink>[sink]);
    AppLogger.scope('lifecycle').info('recovered');
    await AppLogRuntime.flush();

    expect(sink.records.single.message, 'recovered');
  });

  test('dispose 遇到 sink close 失败仍会复位状态', () async {
    await AppLogRuntime.initialize(
      role: 'main',
      sinks: <LogSink>[_ThrowingSink(throwOnClose: true)],
    );

    await AppLogRuntime.dispose();

    expect(AppLogRuntime.isInitialized, isFalse);
    expect(AppLogRuntime.debugDegradedSinkCount, 1);
  });

  test('resetForTest 会清理未初始化日志队列', () async {
    AppLogger.scope('pre-init').info('old');
    await AppLogRuntime.resetForTest();
    final _MemoryLogSink sink = _MemoryLogSink();

    await AppLogRuntime.initialize(role: 'main', sinks: <LogSink>[sink]);
    await AppLogRuntime.flush();

    expect(sink.records, isEmpty);
  });

  test('FileLogSink close 会刷新内容并释放文件句柄', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'lddc_log_sink_',
    );
    addTearDown(() {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });
    final FileLogSink sink = await FileLogSink.create(
      role: 'test',
      instanceId: null,
      panelId: null,
      logDirectoryResolver: () async => directory,
      retentionPolicy: const LogRetentionPolicy(maxCleanupScanCount: 0),
    );

    await sink.write(
      AppLogRecord(
        timestamp: DateTime.utc(2026),
        level: AppLogLevel.info,
        role: 'test',
        pid: 1,
        scope: 'file-sink',
        sequence: 1,
        message: 'written',
      ),
    );
    await sink.close();

    final List<File> files = directory.listSync().whereType<File>().toList(
      growable: false,
    );
    expect(files, hasLength(1));
    expect(files.single.readAsLinesSync(), hasLength(1));
    files.single.deleteSync();
    expect(files.single.existsSync(), isFalse);
  });
}

class _MemoryLogSink implements LogSink {
  final List<AppLogRecord> records = <AppLogRecord>[];

  @override
  Future<void> write(AppLogRecord record) async {
    records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

class _BlockingMemorySink extends _MemoryLogSink {
  _BlockingMemorySink({required this.release});

  final Future<void> release;

  @override
  Future<void> write(AppLogRecord record) async {
    await release;
    await super.write(record);
  }
}

class _TrackingMemorySink extends _MemoryLogSink {
  int closeCount = 0;
  bool _closed = false;

  @override
  Future<void> write(AppLogRecord record) async {
    if (_closed) {
      throw StateError('write after close');
    }
    await super.write(record);
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    _closed = true;
  }
}

class _BlockingCloseSink extends _MemoryLogSink {
  final Completer<void> _closeStarted = Completer<void>();
  final Completer<void> _releaseClose = Completer<void>();

  Future<void> get closeStarted => _closeStarted.future;

  void releaseClose() {
    if (!_releaseClose.isCompleted) {
      _releaseClose.complete();
    }
  }

  @override
  Future<void> close() async {
    if (!_closeStarted.isCompleted) {
      _closeStarted.complete();
    }
    await _releaseClose.future;
  }
}

class _ThrowingSink implements LogSink {
  _ThrowingSink({this.throwOnWrite = false, this.throwOnClose = false});

  final bool throwOnWrite;
  final bool throwOnClose;

  @override
  Future<void> write(AppLogRecord record) async {
    if (throwOnWrite) {
      throw StateError('write failed');
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (throwOnClose) {
      throw StateError('close failed');
    }
  }
}
