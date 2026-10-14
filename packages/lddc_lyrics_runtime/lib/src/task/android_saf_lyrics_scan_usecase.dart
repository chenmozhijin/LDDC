import 'dart:collection';

import 'package:path/path.dart' as p;

import '../lyrics_source/local_lyrics_input_normalizer.dart';
import 'android_saf_ports.dart';
import 'batch_convert_locations.dart';

/// Android SAF 歌词扫描进度快照。
///
/// 扫描阶段不返回"第几个文件/共几个文件"（SAF 枚举前不知道总数），只回传
/// 已扫描目录数、已发现歌词数与当前目录可读名；界面把它们映射成自己的进度文案。
class AndroidSafLyricsScanProgress {
  const AndroidSafLyricsScanProgress({
    required this.scannedDirectoryCount,
    required this.foundCount,
    required this.currentDirectoryLabel,
  });

  /// 已枚举的目录数（每处理完一个目录的一段分页算一个）。
  final int scannedDirectoryCount;

  /// 已发现的歌词文件数。
  final int foundCount;

  /// 正在枚举的目录可读名（根目录用树显示名）。
  final String currentDirectoryLabel;
}

/// 单个歌词文件的批次回调：每满一批（或扫描结束时）交付一次。
typedef AndroidSafLyricsScanChunkCallback =
    void Function(List<SafDocumentSource> sources);

/// 进度回调。
typedef AndroidSafLyricsScanProgressCallback =
    void Function(AndroidSafLyricsScanProgress progress);

/// Android SAF 歌词目录扫描结果。
class AndroidSafLyricsScanResult {
  AndroidSafLyricsScanResult({
    required this.foundCount,
    required this.cancelled,
    required List<String> errors,
  }) : errors = List<String>.unmodifiable(errors);

  /// 扫描到的歌词文件数（不含被去重跳过的重复文档）。
  final int foundCount;

  /// 是否因取消而提前结束。
  final bool cancelled;

  /// 非致命错误（单个目录枚举失败等），已按发生顺序收集。
  final List<String> errors;
}

/// Android SAF 歌词文件扫描用例（批量转换"导入文件夹"的安卓入口）。
///
/// 与 [AndroidSafLocalMatchGetInfosUseCase] 一样采用"分页目录 + BFS"：单次
/// MethodChannel 最多返回 [_directoryPageSize] 个直接子项，当前页处理完才请求下一页，
/// 避免大目录一次性把全部子项留在内存里。
///
/// 与本地目录扫描的差异：
/// - 条目以 [SafDocumentSource] 交付（带 documentUri / 源树 URI / 源树显示名 / 可读落点），
///   `dart:io` 拿不到 `content://`，因此不能复用 app 层的本地目录扫描器；
/// - 非递归时只枚举树根的直接子项（不下钻子目录）；
/// - 单个目录枚举失败只记录错误并继续，不中断整次导入。
class AndroidSafLyricsScanUseCase {
  AndroidSafLyricsScanUseCase({required this.treePort});

  final AndroidSafTreePort treePort;

  /// 单次 MethodChannel 拉取的直接子项数量，与本地匹配扫描保持一致。
  static const int _directoryPageSize = 128;

  /// 批量交付条目的阈值：大目录扫描时按分片刷新 UI，避免每个文件都触发状态更新。
  static const int _chunkSize = 64;

  /// 扫描 [rootTree] 授权树内的歌词文件。
  ///
  /// [shouldCancel] 在每页、每条候选文件前后检查；返回 true 时立即停止并返回
  /// `cancelled: true`（已交付的批次保留，不做回滚）。
  Future<AndroidSafLyricsScanResult> run({
    required AndroidSafTreeToken rootTree,
    required bool recursive,
    required AndroidSafLyricsScanChunkCallback onChunk,
    AndroidSafLyricsScanProgressCallback? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final Set<String> acceptedExtensions = <String>{
      for (final String extension in localLyricsInputSupportedExtensions)
        extension.toLowerCase(),
    };
    final String treeUri = rootTree.uri;
    final String treeLabel = rootTree.displayName ?? '';

    // BFS 队列：同一条目的后续分页会 addFirst 回队首，保证"扫完一个目录再进下一个"。
    final Queue<_AndroidSafLyricsScanDirectory> pendingDirectories =
        Queue<_AndroidSafLyricsScanDirectory>()..add(
          _AndroidSafLyricsScanDirectory(
            uri: treeUri,
            relativeDirectoryPath: '',
          ),
        );

    final Set<String> visitedDirectoryUris = <String>{};
    final Set<String> queuedDirectoryUris = <String>{};
    final Set<String> seenFileUris = <String>{};
    final List<String> errors = <String>[];
    final List<SafDocumentSource> chunk = <SafDocumentSource>[];
    int foundCount = 0;
    int scannedDirectoryCount = 0;
    bool cancelled = false;

    void publishProgress(String directoryLabel) {
      onProgress?.call(
        AndroidSafLyricsScanProgress(
          scannedDirectoryCount: scannedDirectoryCount,
          foundCount: foundCount,
          currentDirectoryLabel: directoryLabel,
        ),
      );
    }

    void flushChunk() {
      if (chunk.isEmpty) {
        return;
      }
      final List<SafDocumentSource> batch =
          List<SafDocumentSource>.unmodifiable(chunk);
      chunk.clear();
      onChunk(batch);
    }

    while (pendingDirectories.isNotEmpty) {
      if (shouldCancel?.call() ?? false) {
        cancelled = true;
        break;
      }

      final _AndroidSafLyricsScanDirectory directory = pendingDirectories
          .removeFirst();
      if (directory.offset == 0) {
        queuedDirectoryUris.remove(directory.uri);
        if (!visitedDirectoryUris.add(directory.uri)) {
          // 目录环或 provider 重复返回同一个目录：跳过，避免无限遍历。
          continue;
        }
      }
      final String directoryLabel = directory.relativeDirectoryPath.isEmpty
          ? (treeLabel.trim().isEmpty ? directory.uri : treeLabel)
          : directory.relativeDirectoryPath;

      final AndroidSafTreePage page;
      try {
        page = await treePort.listChildrenPage(
          uri: directory.uri,
          offset: directory.offset,
          limit: _directoryPageSize,
        );
      } on Exception catch (error) {
        // 单个目录枚举失败（权限被回收、provider 异常）只记录：其余目录仍要导入。
        errors.add('${error.runtimeType}: $error');
        continue;
      }
      scannedDirectoryCount += 1;
      publishProgress(directoryLabel);

      // 每一页都必须续页（不只是首页）：等号右侧的 `>` 判断一次写清"偏移必须前进"，
      // 否则端口返回错误偏移时本循环会永远取到同一页，把 UI 线程拖死。
      final int? nextOffset = page.nextOffset;
      if (nextOffset != null) {
        if (nextOffset > directory.offset) {
          // 后续分页排在队首：当前目录的下一页先于本轮新发现的子目录。
          pendingDirectories.addFirst(directory.nextPage(nextOffset));
        } else {
          errors.add(
            '目录分页偏移未前进：${directory.uri} offset=${directory.offset} '
            'nextOffset=$nextOffset',
          );
        }
      }

      for (final AndroidSafTreeEntry child in page.entries) {
        if (shouldCancel?.call() ?? false) {
          cancelled = true;
          break;
        }
        if (child.isDirectory) {
          if (!recursive ||
              visitedDirectoryUris.contains(child.uri) ||
              !queuedDirectoryUris.add(child.uri)) {
            continue;
          }
          pendingDirectories.addLast(
            _AndroidSafLyricsScanDirectory(
              uri: child.uri,
              relativeDirectoryPath: joinAndroidSafRelativePath(
                directory.relativeDirectoryPath,
                child.displayName,
              ),
            ),
          );
          continue;
        }
        if (!child.isFile) {
          // 端口契约上"目录/文件"必有一真；两者皆假的实现（异常 provider）若被静默
          // 跳过，目录子树会无声消失，因此必须留下记录。
          errors.add('目录项既不是文件也不是目录：${child.displayName} (${child.uri})');
          continue;
        }
        if (!acceptedExtensions.contains(_extensionOf(child.displayName))) {
          continue;
        }
        if (!seenFileUris.add(child.uri)) {
          // 同一文档被多个目录返回：只导入一次。
          continue;
        }
        final String relativePath = joinAndroidSafRelativePath(
          directory.relativeDirectoryPath,
          child.displayName,
        );
        chunk.add(
          SafDocumentSource(
            documentUri: child.uri,
            treeUri: treeUri,
            treeLabel: treeLabel,
            // 可读落点按"源树显示名 + 树内相对路径"拼好：展示层不允许解析 URI。
            displayPath: buildAndroidSafDisplayPath(
              treeLabel: treeLabel,
              relativePath: relativePath,
            ),
          ),
        );
        foundCount += 1;
        if (chunk.length >= _chunkSize) {
          flushChunk();
          publishProgress(directoryLabel);
        }
      }
      if (cancelled) {
        break;
      }
    }

    // 取消也要把已发现条目交付完：上层据此把界面刷成最终状态，避免丢条目。
    flushChunk();
    return AndroidSafLyricsScanResult(
      foundCount: foundCount,
      cancelled: cancelled,
      errors: errors,
    );
  }
}

final class _AndroidSafLyricsScanDirectory {
  const _AndroidSafLyricsScanDirectory({
    required this.uri,
    required this.relativeDirectoryPath,
    this.offset = 0,
  });

  final String uri;
  final String relativeDirectoryPath;
  final int offset;

  _AndroidSafLyricsScanDirectory nextPage(int nextOffset) {
    return _AndroidSafLyricsScanDirectory(
      uri: uri,
      relativeDirectoryPath: relativeDirectoryPath,
      offset: nextOffset,
    );
  }
}

/// 取小写扩展名（不含点），与本项目"扩展名白名单"的写法保持一致。
String _extensionOf(String displayName) {
  final String extension = p.extension(displayName).toLowerCase();
  return extension.startsWith('.') ? extension.substring(1) : extension;
}
