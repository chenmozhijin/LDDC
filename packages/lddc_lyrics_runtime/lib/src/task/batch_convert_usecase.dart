import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../files/background_file_io.dart';
import '../lyrics_source/lyrics_source.dart';

/// 批量转换单条任务：输入文件与输出文件路径。
class BatchConvertItem {
  const BatchConvertItem({required this.sourcePath, required this.targetPath});

  final String sourcePath;
  final String targetPath;
}

/// 单条转换状态类型，对齐Python版 `ConverStatusType` 语义。
enum BatchConvertStatusType { success, failure }

enum BatchConvertProgressMessageCode {
  empty,
  convertingFile,
  itemSuccess,
  itemFailure,
  preparingConversion,
  cancellingConversion,
  conversionCancelled,
  conversionCompleted,
  conversionFailed,
  scanningFolders,
  scanningDirectory,
  scannedLyricsFiles,
  scanCancelled,
  scanNoSupportedFiles,
  scanCompleted,
}

class BatchConvertProgressMessage {
  const BatchConvertProgressMessage({
    required this.code,
    this.detail,
    this.count,
    this.successCount,
    this.failureCount,
  });

  const BatchConvertProgressMessage.empty()
    : code = BatchConvertProgressMessageCode.empty,
      detail = null,
      count = null,
      successCount = null,
      failureCount = null;

  final BatchConvertProgressMessageCode code;
  final String? detail;
  final int? count;
  final int? successCount;
  final int? failureCount;

  bool get isEmpty => code == BatchConvertProgressMessageCode.empty;
}

/// 单条状态回传（索引 + 状态）。
class BatchConvertStatus {
  const BatchConvertStatus({required this.type, required this.index});

  final BatchConvertStatusType type;
  final int index;
}

/// 进度事件：对齐Python版 `progress(text, value, max, status)`。
class BatchConvertProgress {
  const BatchConvertProgress({
    required this.message,
    required this.value,
    required this.maxValue,
    this.status,
  });

  final BatchConvertProgressMessage message;
  final int value;
  final int maxValue;
  final BatchConvertStatus? status;
}

/// 批量转换逐条日志。
class BatchConvertLogEntry {
  const BatchConvertLogEntry({
    required this.index,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    required this.message,
    this.error,
  });

  final int index;
  final String sourcePath;
  final String targetPath;
  final BatchConvertStatusType status;
  final String message;
  final Object? error;
}

/// 批量转换汇总结果。
class BatchConvertResult {
  BatchConvertResult({
    required this.successCount,
    required this.failureCount,
    required this.cancelled,
    required List<BatchConvertLogEntry> logs,
  }) : logs = List<BatchConvertLogEntry>.unmodifiable(logs);

  final int successCount;
  final int failureCount;
  final bool cancelled;
  final List<BatchConvertLogEntry> logs;
}

/// 批量转换取消令牌：UI 可通过 `cancel()` 请求中断后续条目。
class BatchConvertCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

typedef BatchConvertProgressCallback =
    void Function(BatchConvertProgress value);

/// 批量转换文件 IO 端口。
///
/// use case 通过端口读写文件，测试可以注入慢 IO 或失败 IO 来验证取消边界；
/// 默认实现仍使用 Dart 的异步文件 API 与后台写入 helper。
abstract interface class BatchConvertFileIo {
  Future<Uint8List> readBytes(String path);

  Future<String> writeText({
    required String sourcePath,
    required String targetPath,
    required String text,
    required bool allowOverwrite,
  });
}

final class DefaultBatchConvertFileIo implements BatchConvertFileIo {
  const DefaultBatchConvertFileIo();

  @override
  Future<Uint8List> readBytes(String path) {
    return File(path).readAsBytes();
  }

  @override
  Future<String> writeText({
    required String sourcePath,
    required String targetPath,
    required String text,
    required bool allowOverwrite,
  }) async {
    final bool sameFile = _sameFilePath(sourcePath, targetPath);
    if (sameFile && !allowOverwrite) {
      throw LddcApiParamsException('导出目标与源文件相同: $targetPath');
    }
    // 批量转换可能处理网络盘或大量文件；这里保持异步检查，避免同步 stat 阻塞 UI isolate。
    // ignore: avoid_slow_async_io
    if (!sameFile && !allowOverwrite && await File(targetPath).exists()) {
      throw LddcApiParamsException('导出目标已存在: $targetPath');
    }
    if (sameFile) {
      return _writeReplacingOriginal(path: targetPath, text: text);
    }
    return BackgroundFileIo.writeText(path: targetPath, text: text);
  }

  Future<String> _writeReplacingOriginal({
    required String path,
    required String text,
  }) async {
    final File target = File(path);
    await target.parent.create(recursive: true);
    final String temporaryPath =
        '$path.lddc-tmp-${DateTime.now().microsecondsSinceEpoch}';
    final File temporary = File(temporaryPath);
    try {
      // 覆盖源文件时先写临时文件，转换成功后再替换目标，避免解析失败或取消时
      // 直接把用户原歌词截断为空文件；写入临时文件也走后台 helper，避免大文本
      // 在当前 isolate 上执行完整落盘流程。
      await BackgroundFileIo.writeText(path: temporaryPath, text: text);
      await temporary.copy(path);
      return target.path;
    } finally {
      // 清理临时文件不参与用户交互路径，仍用异步 IO 避免阻塞当前 isolate。
      // ignore: avoid_slow_async_io
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static bool _sameFilePath(String left, String right) {
    final String normalizedLeft = path.normalize(path.absolute(left));
    final String normalizedRight = path.normalize(path.absolute(right));
    if (Platform.isWindows) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
  }
}

final class _BatchConvertCancelled implements Exception {
  const _BatchConvertCancelled();
}

/// 批量转换工作流：对齐Python版 `gui/workers/batch_convert.py`。
class BatchConvertUseCase {
  BatchConvertUseCase({
    required this._localProvider,
    this._fileIo = const DefaultBatchConvertFileIo(),
  });

  final LyricsLocalSourceProvider _localProvider;
  final BatchConvertFileIo _fileIo;

  Future<BatchConvertResult> run({
    required List<BatchConvertItem> items,
    required LyricsFormat targetFormat,
    LyricsConvertOptions? convertOptions,
    bool allowOverwrite = false,
    BatchConvertCancellationToken? cancellationToken,
    BatchConvertProgressCallback? onProgress,
  }) async {
    final List<BatchConvertItem> itemSnapshot =
        List<BatchConvertItem>.unmodifiable(items);
    final LyricsConvertOptions effectiveOptions =
        convertOptions ?? LyricsConvertOptions();
    final BatchConvertCancellationToken token =
        cancellationToken ?? BatchConvertCancellationToken();
    final List<BatchConvertLogEntry> logs = <BatchConvertLogEntry>[];

    int success = 0;
    int failure = 0;
    BatchConvertStatus? latestStatus;

    for (int index = 0; index < itemSnapshot.length; index += 1) {
      if (token.isCancelled) {
        break;
      }

      final BatchConvertItem item = itemSnapshot[index];
      onProgress?.call(
        BatchConvertProgress(
          message: BatchConvertProgressMessage(
            code: BatchConvertProgressMessageCode.convertingFile,
            detail: path.basename(item.sourcePath),
          ),
          value: index,
          maxValue: itemSnapshot.length,
          status: latestStatus,
        ),
      );

      try {
        _throwIfCancelled(token);
        final Lyrics lyrics = await _loadLyrics(item.sourcePath);
        _throwIfCancelled(token);
        final String converted = convert2(
          lyrics: lyrics,
          langs: effectiveOptions.languageOrder,
          lyricsFormat: targetFormat,
          options: effectiveOptions,
        );
        _throwIfCancelled(token);
        await _writeConvertedFile(
          sourcePath: item.sourcePath,
          targetPath: item.targetPath,
          content: converted,
          allowOverwrite: allowOverwrite,
        );

        // 写入是不可回滚的副作用。若取消恰好发生在写盘期间，当前条目仍应记为成功，
        // 下一轮循环再停止；否则磁盘已有文件但结果中没有任何状态，会误导重试逻辑。
        success += 1;
        latestStatus = BatchConvertStatus(
          type: BatchConvertStatusType.success,
          index: index,
        );
        logs.add(
          BatchConvertLogEntry(
            index: index,
            sourcePath: item.sourcePath,
            targetPath: item.targetPath,
            status: BatchConvertStatusType.success,
            message: '转换成功',
          ),
        );
      } on _BatchConvertCancelled {
        break;
      } catch (error) {
        failure += 1;
        latestStatus = BatchConvertStatus(
          type: BatchConvertStatusType.failure,
          index: index,
        );
        logs.add(
          BatchConvertLogEntry(
            index: index,
            sourcePath: item.sourcePath,
            targetPath: item.targetPath,
            status: BatchConvertStatusType.failure,
            message: '转换失败',
            error: error,
          ),
        );
      }
    }

    onProgress?.call(
      BatchConvertProgress(
        message: const BatchConvertProgressMessage.empty(),
        value: 0,
        maxValue: 0,
        status: latestStatus,
      ),
    );

    final bool cancelled =
        token.isCancelled && (success + failure) < itemSnapshot.length;
    return BatchConvertResult(
      successCount: success,
      failureCount: failure,
      cancelled: cancelled,
      logs: logs,
    );
  }

  Future<Lyrics> _loadLyrics(String sourcePath) async {
    final Uint8List data = await _fileIo.readBytes(sourcePath);
    // 所有格式统一交给本地 provider。解密、未知编码读取、扩展名路由和无扩展名
    // 回退顺序都由同一个入口维护，避免批量转换与“打开歌词”出现解析差异。
    return _localProvider.getLyrics(
      LocalLyricsRequest(path: sourcePath, data: data),
    );
  }

  Future<void> _writeConvertedFile({
    required String sourcePath,
    required String targetPath,
    required String content,
    required bool allowOverwrite,
  }) async {
    await _fileIo.writeText(
      sourcePath: sourcePath,
      targetPath: targetPath,
      text: content,
      allowOverwrite: allowOverwrite,
    );
  }

  void _throwIfCancelled(BatchConvertCancellationToken token) {
    if (token.isCancelled) {
      throw const _BatchConvertCancelled();
    }
  }
}
