import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

class BatchConvertDirectoryScanResult {
  const BatchConvertDirectoryScanResult({
    required this.foundCount,
    required this.cancelled,
    required this.errors,
  });

  final int foundCount;
  final bool cancelled;
  final List<String> errors;
}

abstract interface class BatchConvertDirectoryScanner {
  Future<BatchConvertDirectoryScanResult> scan({
    required List<String> rootDirectories,
    required bool recursive,
    required void Function(List<String> sourcePaths) onChunk,
    required void Function(
      BatchConvertProgressMessage message,
      int value,
      int maxValue,
    )
    onProgress,
    bool Function()? shouldCancel,
  });
}

class BatchConvertDirectoryScannerImpl implements BatchConvertDirectoryScanner {
  const BatchConvertDirectoryScannerImpl({this.chunkSize = 64})
    : assert(chunkSize > 0);

  final int chunkSize;

  @override
  Future<BatchConvertDirectoryScanResult> scan({
    required List<String> rootDirectories,
    required bool recursive,
    required void Function(List<String> sourcePaths) onChunk,
    required void Function(
      BatchConvertProgressMessage message,
      int value,
      int maxValue,
    )
    onProgress,
    bool Function()? shouldCancel,
  }) async {
    final Set<String> acceptedExtensions = localLyricsInputSupportedExtensions
        .map((String ext) => '.${ext.toLowerCase()}')
        .toSet();
    final List<String> errors = <String>[];
    int foundCount = 0;
    bool cancelled = false;

    final ReceivePort receivePort = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn<Map<String, Object?>>(
        _batchConvertDirectoryScanWorker,
        <String, Object?>{
          'sendPort': receivePort.sendPort,
          'rootDirectories': rootDirectories,
          'recursive': recursive,
          'acceptedExtensions': acceptedExtensions.toList(growable: false),
          'chunkSize': chunkSize,
        },
      );
      await for (final Object? rawMessage in receivePort) {
        if (shouldCancel?.call() ?? false) {
          cancelled = true;
          worker.kill(priority: Isolate.immediate);
          break;
        }

        final Map<Object?, Object?>? message = rawMessage is Map
            ? rawMessage
            : null;
        if (message == null) {
          continue;
        }
        switch (message['type']) {
          case 'scanningDirectory':
            onProgress(
              BatchConvertProgressMessage(
                code: BatchConvertProgressMessageCode.scanningDirectory,
                detail: message['detail']?.toString(),
              ),
              foundCount,
              0,
            );
          case 'chunk':
            final List<String> paths = (message['paths'] as List<Object?>)
                .map((Object? item) => item.toString())
                .toList(growable: false);
            foundCount = message['foundCount'] as int? ?? foundCount;
            onChunk(List<String>.unmodifiable(paths));
            // 大目录扫描时按分片刷新 UI，避免每个文件都触发 state 更新。
            onProgress(
              BatchConvertProgressMessage(
                code: BatchConvertProgressMessageCode.scannedLyricsFiles,
                count: foundCount,
              ),
              foundCount,
              0,
            );
          case 'error':
            errors.add(message['message']?.toString() ?? '未知扫描错误');
          case 'done':
            foundCount = message['foundCount'] as int? ?? foundCount;
            return BatchConvertDirectoryScanResult(
              foundCount: foundCount,
              cancelled: false,
              errors: List<String>.unmodifiable(errors),
            );
        }
      }
    } finally {
      receivePort.close();
      worker?.kill(priority: Isolate.immediate);
    }

    return BatchConvertDirectoryScanResult(
      foundCount: foundCount,
      cancelled: cancelled,
      errors: List<String>.unmodifiable(errors),
    );
  }
}

void _batchConvertDirectoryScanWorker(Map<String, Object?> args) {
  final SendPort sendPort = args['sendPort']! as SendPort;
  final List<String> rootDirectories =
      (args['rootDirectories']! as List<Object?>)
          .map((Object? item) => item.toString())
          .toList(growable: false);
  final bool recursive = args['recursive']! as bool;
  final Set<String> acceptedExtensions =
      (args['acceptedExtensions']! as List<Object?>)
          .map((Object? item) => item.toString())
          .toSet();
  final int chunkSize = args['chunkSize']! as int;

  final List<String> chunk = <String>[];
  int foundCount = 0;

  void flushChunk() {
    if (chunk.isEmpty) {
      return;
    }
    sendPort.send(<String, Object?>{
      'type': 'chunk',
      'paths': List<String>.unmodifiable(chunk),
      'foundCount': foundCount,
    });
    chunk.clear();
  }

  for (final String root in rootDirectories) {
    sendPort.send(<String, Object?>{
      'type': 'scanningDirectory',
      'detail': p.basename(root),
    });
    try {
      for (final FileSystemEntity entity in Directory(
        root,
      ).listSync(recursive: recursive, followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final String sourcePath = entity.path;
        if (!acceptedExtensions.contains(
          p.extension(sourcePath).toLowerCase(),
        )) {
          continue;
        }
        chunk.add(sourcePath);
        foundCount += 1;
        if (chunk.length >= chunkSize) {
          flushChunk();
        }
      }
    } on FileSystemException catch (error) {
      sendPort.send(<String, Object?>{
        'type': 'error',
        'message': error.message,
      });
    }
  }

  flushChunk();
  sendPort.send(<String, Object?>{'type': 'done', 'foundCount': foundCount});
}

final Provider<BatchConvertDirectoryScanner>
batchConvertDirectoryScannerProvider = Provider<BatchConvertDirectoryScanner>((
  Ref ref,
) {
  return const BatchConvertDirectoryScannerImpl();
});
