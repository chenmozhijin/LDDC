import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../audio_tag/audio_file_extensions.dart';
import '../parser/cue_parser.dart';

/// 桌面本地匹配扫描出的 CUE 文件。
final class LocalMatchScannedCue {
  const LocalMatchScannedCue({
    required this.rootPath,
    required this.cueData,
    required this.audioPaths,
  });

  final String? rootPath;
  final CueData cueData;
  final List<String> audioPaths;
}

/// 桌面本地匹配扫描出的普通音频文件。
final class LocalMatchScannedAudio {
  const LocalMatchScannedAudio({
    required this.filePath,
    required this.rootPath,
  });

  final String filePath;
  final String? rootPath;
}

/// 扫描事件基类。
///
/// 扫描器不会一次返回整个目录结果，而是把错误、CUE 批次和音频批次逐步交给
/// 调用方。调用方处理完当前事件后，worker 才会继续发送下一批，从而给消息通道
/// 建立明确的背压边界。
sealed class LocalMatchFileScanEvent {
  const LocalMatchFileScanEvent();
}

final class LocalMatchFileScanErrors extends LocalMatchFileScanEvent {
  const LocalMatchFileScanErrors(this.errors);

  final List<String> errors;
}

final class LocalMatchFileScanCueBatch extends LocalMatchFileScanEvent {
  const LocalMatchFileScanCueBatch(this.items);

  final List<LocalMatchScannedCue> items;
}

final class LocalMatchFileScanSummary extends LocalMatchFileScanEvent {
  const LocalMatchFileScanSummary({
    required this.cueFileCount,
    required this.audioFileCount,
  });

  final int cueFileCount;
  final int audioFileCount;
}

final class LocalMatchFileScanAudioBatch extends LocalMatchFileScanEvent {
  const LocalMatchFileScanAudioBatch(this.items);

  final List<LocalMatchScannedAudio> items;
}

typedef LocalMatchFileScanEventHandler =
    FutureOr<void> Function(LocalMatchFileScanEvent event);

const int _scanBatchSize = 64;

/// 在 worker isolate 中渐进扫描桌面文件。
///
/// 返回 `true` 表示两阶段扫描完整结束；返回 `false` 表示扫描被取消。worker 每次
/// 只发送固定大小的批次，并等待主 isolate 回执，避免端口队列在消费速度较慢时
/// 无限制积压。
Future<bool> streamLocalMatchFiles({
  required List<String> inputPaths,
  required Future<void> cancelled,
  required bool Function() isCancelled,
  required LocalMatchFileScanEventHandler onEvent,
}) async {
  if (isCancelled()) {
    return false;
  }
  try {
    return await _runScanWorker(
      inputPaths: inputPaths,
      cancelled: cancelled,
      isCancelled: isCancelled,
      onEvent: onEvent,
    );
  } on UnsupportedError {
    // 某些运行环境不支持创建 isolate。此时仍复用同一套渐进扫描算法，保证行为
    // 一致；桌面平台正常会走上面的 worker 分支。
    return _runScanInCurrentIsolate(
      inputPaths: inputPaths,
      isCancelled: isCancelled,
      onEvent: onEvent,
    );
  }
}

Future<bool> _runScanInCurrentIsolate({
  required List<String> inputPaths,
  required bool Function() isCancelled,
  required LocalMatchFileScanEventHandler onEvent,
}) async {
  try {
    await _scanInputs(
      inputPaths,
      emit: (Map<String, Object?> message) async {
        if (isCancelled()) {
          throw const _LocalMatchFileScanCancelled();
        }
        await onEvent(_decodeEvent(message));
      },
    );
    return !isCancelled();
  } on _LocalMatchFileScanCancelled {
    return false;
  }
}

Future<bool> _runScanWorker({
  required List<String> inputPaths,
  required Future<void> cancelled,
  required bool Function() isCancelled,
  required LocalMatchFileScanEventHandler onEvent,
}) async {
  final ReceivePort resultPort = ReceivePort();
  final ReceivePort errorPort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();
  final Completer<bool> completion = Completer<bool>();
  Isolate? isolate;
  SendPort? workerControlPort;
  StreamSubscription<Object?>? resultSubscription;
  StreamSubscription<Object?>? errorSubscription;
  StreamSubscription<Object?>? exitSubscription;
  Future<void> messageChain = Future<void>.value();

  void completeValue(bool value) {
    if (!completion.isCompleted) {
      completion.complete(value);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!completion.isCompleted) {
      completion.completeError(error, stackTrace);
    }
  }

  String formatWorkerError(Object? error) {
    if (error is List && error.isNotEmpty) {
      return error.map((Object? item) => item.toString()).join('\n');
    }
    return error.toString();
  }

  try {
    resultSubscription = resultPort.listen((Object? rawMessage) {
      messageChain = messageChain
          .then((_) async {
            if (completion.isCompleted) {
              return;
            }
            if (rawMessage is! Map) {
              throw StateError('扫描 worker 返回了未知结果');
            }
            final Map<Object?, Object?> message = Map<Object?, Object?>.from(
              rawMessage,
            );
            final String type = message['type']?.toString() ?? '';
            if (type == 'ready') {
              final Object? controlPort = message['controlPort'];
              if (controlPort is! SendPort) {
                throw StateError('扫描 worker 未返回控制端口');
              }
              workerControlPort = controlPort;
            } else if (type == 'done') {
              completeValue(true);
            } else {
              await onEvent(_decodeEvent(message));
            }

            if (isCancelled()) {
              isolate?.kill(priority: Isolate.immediate);
              completeValue(false);
              return;
            }
            // worker 在发送每个事件后都会等待该回执，因此内存中最多只有一个尚未
            // 消费的消息批次，而不会随着目录规模增长。
            workerControlPort?.send(true);
          })
          .catchError((Object error, StackTrace stackTrace) {
            isolate?.kill(priority: Isolate.immediate);
            completeError(error, stackTrace);
          });
    });
    errorSubscription = errorPort.listen((Object? error) {
      isolate?.kill(priority: Isolate.immediate);
      completeError(
        StateError('扫描 worker 失败: ${formatWorkerError(error)}'),
        StackTrace.current,
      );
    });
    exitSubscription = exitPort.listen((Object? _) {
      messageChain.whenComplete(() {
        if (completion.isCompleted) {
          return;
        }
        if (isCancelled()) {
          completeValue(false);
        } else {
          completeError(StateError('扫描 worker 异常退出'), StackTrace.current);
        }
      });
    });

    isolate = await Isolate.spawn<Map<String, Object?>>(
      _localMatchFileScanWorkerMain,
      <String, Object?>{
        'replyPort': resultPort.sendPort,
        'inputPaths': inputPaths,
      },
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
    );
    if (isCancelled()) {
      isolate.kill(priority: Isolate.immediate);
      return false;
    }
    unawaited(
      cancelled.then((_) {
        isolate?.kill(priority: Isolate.immediate);
        completeValue(false);
      }),
    );
    return await completion.future;
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    await messageChain.catchError((Object _) {});
    await resultSubscription?.cancel();
    await errorSubscription?.cancel();
    await exitSubscription?.cancel();
    resultPort.close();
    errorPort.close();
    exitPort.close();
  }
}

Future<void> _localMatchFileScanWorkerMain(
  Map<String, Object?> arguments,
) async {
  final SendPort replyPort = arguments['replyPort']! as SendPort;
  final List<String> inputPaths = (arguments['inputPaths']! as List<Object?>)
      .map((Object? item) => item?.toString() ?? '')
      .toList(growable: false);
  final ReceivePort controlPort = ReceivePort();
  final StreamIterator<Object?> controlMessages = StreamIterator<Object?>(
    controlPort,
  );

  Future<void> emit(Map<String, Object?> message) async {
    replyPort.send(message);
    if (!await controlMessages.moveNext() || controlMessages.current != true) {
      throw const _LocalMatchFileScanCancelled();
    }
  }

  try {
    await emit(<String, Object?>{
      'type': 'ready',
      'controlPort': controlPort.sendPort,
    });
    await _scanInputs(inputPaths, emit: emit);
    await emit(const <String, Object?>{'type': 'done'});
  } finally {
    await controlMessages.cancel();
    controlPort.close();
  }
}

Future<void> _scanInputs(
  List<String> inputPaths, {
  required Future<void> Function(Map<String, Object?> message) emit,
}) async {
  final _LocalMatchInputSelection selection = _buildInputSelection(inputPaths);
  if (selection.errors.isNotEmpty) {
    await emit(<String, Object?>{'type': 'errors', 'errors': selection.errors});
  }

  int cueFileCount = 0;
  int audioFileCount = 0;
  final List<Map<String, Object?>> cueBatch = <Map<String, Object?>>[];
  final List<String> pendingErrors = <String>[];

  Future<void> flushCueBatch() async {
    if (cueBatch.isEmpty) {
      return;
    }
    await emit(<String, Object?>{
      'type': 'cueBatch',
      'items': List<Map<String, Object?>>.of(cueBatch),
    });
    cueBatch.clear();
  }

  Future<void> flushErrors() async {
    if (pendingErrors.isEmpty) {
      return;
    }
    await emit(<String, Object?>{
      'type': 'errors',
      'errors': List<String>.of(pendingErrors),
    });
    pendingErrors.clear();
  }

  // 第一遍只解析 CUE，同时统计普通音频数量。这样既能保证所有外部 CUE 先于
  // 音频处理，又不需要把全部音频路径保存在内存中。
  await _visitSelectedFiles(
    selection,
    onError: (String error) async {
      pendingErrors.add(error);
      if (pendingErrors.length >= _scanBatchSize) {
        await flushErrors();
      }
    },
    onFile: (_LocalMatchSelectedFile file) async {
      final String extension = p.extension(file.filePath).toLowerCase();
      if (extension == '.cue') {
        cueFileCount += 1;
        try {
          final CueData cueData = parseCue(cuePath: file.filePath);
          final List<String> audioPaths = cueData.getAudioPaths(
            audioExistsChecker: selection.containsSelectedAudio,
          );
          cueBatch.add(<String, Object?>{
            'rootPath': file.rootPath,
            'cueData': cueData.toMap(),
            'audioPaths': audioPaths,
          });
          if (cueBatch.length >= _scanBatchSize) {
            await flushCueBatch();
          }
        } on Exception catch (error) {
          pendingErrors.add('${error.runtimeType}: $error');
          if (pendingErrors.length >= _scanBatchSize) {
            await flushErrors();
          }
        }
        return;
      }
      if (_isSupportedAudioPath(file.filePath)) {
        audioFileCount += 1;
      }
    },
  );
  await flushCueBatch();
  await flushErrors();
  await emit(<String, Object?>{
    'type': 'summary',
    'cueFileCount': cueFileCount,
    'audioFileCount': audioFileCount,
  });

  final List<Map<String, Object?>> audioBatch = <Map<String, Object?>>[];
  Future<void> flushAudioBatch() async {
    if (audioBatch.isEmpty) {
      return;
    }
    await emit(<String, Object?>{
      'type': 'audioBatch',
      'items': List<Map<String, Object?>>.of(audioBatch),
    });
    audioBatch.clear();
  }

  // 第二遍只交付音频路径。每批处理完成后才继续遍历，因此主 isolate 的 metadata
  // 读取速度会自然限制扫描速度，不会在端口中堆积尚未处理的文件。
  await _visitSelectedFiles(
    selection,
    onError: (String error) async {
      pendingErrors.add(error);
      if (pendingErrors.length >= _scanBatchSize) {
        await flushErrors();
      }
    },
    onFile: (_LocalMatchSelectedFile file) async {
      if (!_isSupportedAudioPath(file.filePath)) {
        return;
      }
      audioBatch.add(file.toMap());
      if (audioBatch.length >= _scanBatchSize) {
        await flushAudioBatch();
      }
    },
  );
  await flushAudioBatch();
  await flushErrors();
}

Future<void> _visitSelectedFiles(
  _LocalMatchInputSelection selection, {
  required Future<void> Function(_LocalMatchSelectedFile file) onFile,
  required Future<void> Function(String error) onError,
}) async {
  for (final _LocalMatchSelectedFile file in selection.explicitFiles) {
    await onFile(file);
  }

  for (final _LocalMatchDirectoryRoot root in selection.directoryRoots) {
    final List<Directory> pendingDirectories = <Directory>[
      Directory(root.path),
    ];
    while (pendingDirectories.isNotEmpty) {
      final Directory directory = pendingDirectories.removeLast();
      try {
        final List<FileSystemEntity> children =
            directory.listSync(followLinks: false)..sort(
              (FileSystemEntity left, FileSystemEntity right) =>
                  left.path.compareTo(right.path),
            );

        // 栈按后进先出处理，逆序压入目录后即可保持稳定的路径升序遍历。
        final List<Directory> childDirectories = <Directory>[];
        for (final FileSystemEntity child in children) {
          if (child is Directory) {
            if (!root.excludesDirectory(child.path)) {
              childDirectories.add(child);
            }
            continue;
          }
          if (child is! File || selection.isExplicitFile(child.path)) {
            continue;
          }
          await onFile(
            _LocalMatchSelectedFile(
              filePath: p.normalize(p.absolute(child.path)),
              rootPath: root.path,
            ),
          );
        }
        for (final Directory child in childDirectories.reversed) {
          pendingDirectories.add(child);
        }
      } on Exception catch (error) {
        await onError('${error.runtimeType}: $error');
      }
    }
  }
}

_LocalMatchInputSelection _buildInputSelection(List<String> inputPaths) {
  final List<String> errors = <String>[];
  final List<_LocalMatchSelectedFile> explicitFiles =
      <_LocalMatchSelectedFile>[];
  final List<String> directoryPaths = <String>[];
  final Set<String> seenExplicitFiles = <String>{};
  final Set<String> seenDirectories = <String>{};

  // 显式文件沿用旧行为：先于目录扫描获得所有权，因此同一文件同时作为单文件和
  // 目录成员传入时，最终 rootPath 仍为 null。
  for (final String rawPath in inputPaths) {
    final String normalized = p.normalize(p.absolute(rawPath));
    final FileSystemEntityType type = FileSystemEntity.typeSync(normalized);
    if (type == FileSystemEntityType.file) {
      final String canonical = _canonicalPath(normalized);
      if (seenExplicitFiles.add(canonical)) {
        explicitFiles.add(
          _LocalMatchSelectedFile(filePath: normalized, rootPath: null),
        );
      }
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      final String canonical = _canonicalPath(normalized);
      if (seenDirectories.add(canonical)) {
        directoryPaths.add(normalized);
      }
      continue;
    }
    errors.add('输入路径不存在或不可访问: $normalized');
  }

  final List<_LocalMatchDirectoryRoot> directoryRoots =
      <_LocalMatchDirectoryRoot>[];
  for (final String directoryPath in directoryPaths) {
    if (directoryRoots.any(
      (_LocalMatchDirectoryRoot previous) =>
          _isWithinOrEqual(previous.path, directoryPath),
    )) {
      // 当前目录已经完全包含在更早输入的目录中。跳过它可以避免重复遍历，同时
      // 保持旧实现“先输入的目录决定 rootPath”的语义。
      continue;
    }
    directoryRoots.add(
      _LocalMatchDirectoryRoot(
        path: directoryPath,
        excludedSubtrees: <String>[
          for (final _LocalMatchDirectoryRoot previous in directoryRoots)
            if (_isWithinOrEqual(directoryPath, previous.path)) previous.path,
        ],
      ),
    );
  }

  return _LocalMatchInputSelection(
    explicitFiles: explicitFiles,
    directoryRoots: directoryRoots,
    errors: errors,
  );
}

LocalMatchFileScanEvent _decodeEvent(Map<Object?, Object?> message) {
  final String type = message['type']?.toString() ?? '';
  return switch (type) {
    'errors' => LocalMatchFileScanErrors(_decodeStrings(message['errors'])),
    'cueBatch' => LocalMatchFileScanCueBatch(
      _decodeMaps(message['items'])
          .map(
            (Map<Object?, Object?> item) => LocalMatchScannedCue(
              rootPath: item['rootPath'] as String?,
              cueData: CueData.fromMap(
                Map<Object?, Object?>.from(item['cueData']! as Map),
              ),
              audioPaths: _decodeStrings(item['audioPaths']),
            ),
          )
          .toList(growable: false),
    ),
    'summary' => LocalMatchFileScanSummary(
      cueFileCount: _decodeNonNegativeInt(message['cueFileCount']),
      audioFileCount: _decodeNonNegativeInt(message['audioFileCount']),
    ),
    'audioBatch' => LocalMatchFileScanAudioBatch(
      _decodeMaps(message['items'])
          .map(
            (Map<Object?, Object?> item) => LocalMatchScannedAudio(
              filePath: item['filePath']?.toString() ?? '',
              rootPath: item['rootPath'] as String?,
            ),
          )
          .toList(growable: false),
    ),
    _ => throw StateError('扫描 worker 返回了未知事件: $type'),
  };
}

List<Map<Object?, Object?>> _decodeMaps(Object? value) {
  if (value is! List) {
    return const <Map<Object?, Object?>>[];
  }
  return value
      .whereType<Map>()
      .map((Map item) => Map<Object?, Object?>.from(item))
      .toList(growable: false);
}

List<String> _decodeStrings(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((Object? item) => item?.toString() ?? '')
      .toList(growable: false);
}

int _decodeNonNegativeInt(Object? value) {
  return value is int && value >= 0 ? value : 0;
}

bool _isSupportedAudioPath(String filePath) {
  final String extension = p.extension(filePath).toLowerCase();
  final String withoutDot = extension.startsWith('.')
      ? extension.substring(1)
      : extension;
  return audioFileExtensionSet.contains(withoutDot);
}

bool _isWithinOrEqual(String rootPath, String candidatePath) {
  final String root = p.normalize(p.absolute(rootPath));
  final String candidate = p.normalize(p.absolute(candidatePath));
  final String relative = p.relative(candidate, from: root);
  return relative == '.' ||
      (!p.isAbsolute(relative) &&
          relative != '..' &&
          !relative.startsWith('..${p.separator}'));
}

String _canonicalPath(String input) {
  final String normalized = p.normalize(p.absolute(input));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

final class _LocalMatchInputSelection {
  _LocalMatchInputSelection({
    required this.explicitFiles,
    required this.directoryRoots,
    required this.errors,
  }) : _explicitCanonicalPaths = explicitFiles
           .map((_LocalMatchSelectedFile file) => _canonicalPath(file.filePath))
           .toSet();

  final List<_LocalMatchSelectedFile> explicitFiles;
  final List<_LocalMatchDirectoryRoot> directoryRoots;
  final List<String> errors;
  final Set<String> _explicitCanonicalPaths;

  bool isExplicitFile(String filePath) {
    return _explicitCanonicalPaths.contains(_canonicalPath(filePath));
  }

  bool containsSelectedAudio(String audioPath) {
    if (!_isSupportedAudioPath(audioPath)) {
      return false;
    }
    final String canonical = _canonicalPath(audioPath);
    final bool selected =
        _explicitCanonicalPaths.contains(canonical) ||
        directoryRoots.any(
          (_LocalMatchDirectoryRoot root) =>
              _isWithinOrEqual(root.path, audioPath),
        );
    if (!selected) {
      return false;
    }
    return FileSystemEntity.typeSync(audioPath) == FileSystemEntityType.file;
  }
}

final class _LocalMatchSelectedFile {
  const _LocalMatchSelectedFile({
    required this.filePath,
    required this.rootPath,
  });

  final String filePath;
  final String? rootPath;

  Map<String, Object?> toMap() {
    return <String, Object?>{'filePath': filePath, 'rootPath': rootPath};
  }
}

final class _LocalMatchDirectoryRoot {
  const _LocalMatchDirectoryRoot({
    required this.path,
    required this.excludedSubtrees,
  });

  final String path;
  final List<String> excludedSubtrees;

  bool excludesDirectory(String directoryPath) {
    return excludedSubtrees.any(
      (String excludedPath) => _isWithinOrEqual(excludedPath, directoryPath),
    );
  }
}

final class _LocalMatchFileScanCancelled implements Exception {
  const _LocalMatchFileScanCancelled();
}
