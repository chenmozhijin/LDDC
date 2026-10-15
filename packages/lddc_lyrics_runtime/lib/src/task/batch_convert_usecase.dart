import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../files/background_file_io.dart';
import '../lyrics_source/lyrics_source.dart';
import 'batch_convert_locations.dart';

/// 批量转换单条任务：读源与写目标（本地路径或 SAF 文档），外加可直接展示的目标落点。
class BatchConvertItem {
  const BatchConvertItem({
    required this.source,
    required this.target,
    required this.targetDisplayPath,
  });

  final BatchConvertSource source;
  final BatchConvertTarget target;

  /// 目标落点的可读文本（SAF 为"树名/层级/文件名"，桌面端为本地路径）。
  ///
  /// 由规划阶段算好后随条目传递：展示层不得自行解析 URI，写入侧也不重复推导，
  /// 避免"界面显示的位置"与"真实写入的位置"出现两套算法。
  final String targetDisplayPath;
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
    required this.sourceDisplayPath,
    required this.targetDisplayPath,
    required this.status,
    required this.message,
    this.error,
  });

  final int index;

  /// 源的可读文本（本地为路径，SAF 为"树名/层级/文件名"）。
  final String sourceDisplayPath;

  /// 目标的可读落点，与队列行展示的文本同源。
  final String targetDisplayPath;
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
  /// 读取源内容：本地路径走 dart:io，SAF 文档由平台层经内容端口读取。
  Future<Uint8List> readBytes(BatchConvertSource source);

  /// 写出转换结果。
  ///
  /// [allowOverwrite] 为 false 时实现**必须**先确认目标不存在再写：Android 的
  /// `writeDocument` 本身总是覆盖同名文档，端口没有"仅新建"的原子语义，
  /// 因此拒绝覆盖只能由调用方预检完成。
  Future<void> writeText({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String text,
    required bool allowOverwrite,
  });

  /// 启动前预检目标是否已存在（本地文件，或 SAF 树内同名文件/目录）。
  ///
  /// 返回 `null` 表示**无法确认**（例如树枚举失败）：调用方必须按失败处理，
  /// 不能当成"不存在"，否则权限问题会被误判为"无冲突"，
  /// 随后每个条目都会因拒绝覆盖而失败。
  Future<bool?> targetExists(BatchConvertTarget target);
}

final class DefaultBatchConvertFileIo implements BatchConvertFileIo {
  const DefaultBatchConvertFileIo();

  @override
  Future<Uint8List> readBytes(BatchConvertSource source) {
    if (source is! LocalFileSource) {
      throw UnsupportedError('本地文件 IO 不能读取 SAF 文档源，请改用 SafBatchConvertFileIo');
    }
    return File(source.path).readAsBytes();
  }

  @override
  Future<void> writeText({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String text,
    required bool allowOverwrite,
  }) async {
    if (source is! LocalFileSource || target is! LocalFileTarget) {
      throw UnsupportedError('本地文件 IO 不能写入 SAF 目标，请改用 SafBatchConvertFileIo');
    }
    final String sourcePath = source.path;
    final String targetPath = target.path;
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
      await _writeReplacingOriginal(path: targetPath, text: text);
      return;
    }
    await BackgroundFileIo.writeText(path: targetPath, text: text);
  }

  @override
  Future<bool?> targetExists(BatchConvertTarget target) {
    if (target is! LocalFileTarget) {
      throw UnsupportedError('本地文件 IO 不能预检 SAF 目标，请改用 SafBatchConvertFileIo');
    }
    // 批量转换可能处理网络盘；异步检查避免阻塞 UI isolate。
    // ignore: avoid_slow_async_io
    return File(target.path).exists();
  }

  Future<void> _writeReplacingOriginal({
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
            detail: item.source.displayName,
          ),
          value: index,
          maxValue: itemSnapshot.length,
          status: latestStatus,
        ),
      );

      try {
        _throwIfCancelled(token);
        final Lyrics lyrics = await _loadLyrics(item.source);
        _throwIfCancelled(token);
        final String converted = convert2(
          lyrics: lyrics,
          langs: effectiveOptions.languageOrder,
          lyricsFormat: targetFormat,
          options: effectiveOptions,
        );
        _throwIfCancelled(token);
        await _writeConvertedFile(
          source: item.source,
          target: item.target,
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
            sourceDisplayPath: item.source.displayName,
            targetDisplayPath: item.targetDisplayPath,
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
            sourceDisplayPath: item.source.displayName,
            targetDisplayPath: item.targetDisplayPath,
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

  Future<Lyrics> _loadLyrics(BatchConvertSource source) async {
    final Uint8List data = await _fileIo.readBytes(source);
    // 所有格式统一交给本地 provider。解密、未知编码读取、扩展名路由和无扩展名
    // 回退顺序都由同一个入口维护，避免批量转换与“打开歌词”出现解析差异。
    // SAF 文档没有文件系统路径，用含扩展名的可读名作为解析提示。
    return _localProvider.getLyrics(
      LocalLyricsRequest(path: source.parserPath, data: data),
    );
  }

  Future<void> _writeConvertedFile({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String content,
    required bool allowOverwrite,
  }) async {
    await _fileIo.writeText(
      source: source,
      target: target,
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
