import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 保存目标无法推导时抛出的异常（缺少保存根树 / 歌曲不在授权树内）。
///
/// 必须是 `Exception`：上层执行链只对 `Exception` 做结构化分类，
/// 抛 `Error` 会逃过分类并让整批任务失去可解释的错误信息。
class AndroidSafSaveTargetException implements Exception {
  const AndroidSafSaveTargetException(this.failure, this.songPath);

  final AndroidSafSaveTargetFailure failure;
  final String? songPath;

  @override
  String toString() {
    final String reason = switch (failure) {
      AndroidSafSaveTargetFailure.missingSaveTree => '尚未选择保存根目录树',
      AndroidSafSaveTargetFailure.songOutsideTree => '歌曲不在已授权的目录树内，无法推导保存位置',
      AndroidSafSaveTargetFailure.unknownSongPath => '无法从歌曲路径推导保存位置',
    };
    final String path = songPath?.trim() ?? '';
    return path.isEmpty ? '无法保存歌词：$reason' : '无法保存歌词：$reason（$path）';
  }
}

/// 基于 Android SAF 树目录的歌词保存实现。
///
/// 保存目标统一表达为"目标授权树 + 树内相对目录"，由 [saveMode] 决定：
/// - [LocalMatchSaveMode.song]：写到歌曲所在目录；
/// - [LocalMatchSaveMode.mirror]：写到 [saveTreeUri] 并保留歌曲相对歌曲树的目录层级；
/// - [LocalMatchSaveMode.specify]：扁平写到 [saveTreeUri] 根目录
///   （默认值，保持搜索页"写所选树根"的既有行为）。
///
/// 目录的定位与创建由原生侧在授权树内逐级完成，这里只传相对目录名。
final class AndroidSafLyricsSavePersistence extends LyricsSavePersistencePort
    implements LyricsSaveExistencePort {
  AndroidSafLyricsSavePersistence({
    required AndroidSafTreePort treePort,
    required this.treeUri,
    required this.saveMode,
    String? saveTreeUri,
    String? treeLabel,
    String? saveTreeLabel,
  }) : _treePort = treePort,
       _saveTreeUri = saveTreeUri,
       _treeLabel = treeLabel ?? '',
       _saveTreeLabel = saveTreeLabel ?? '';

  final AndroidSafTreePort _treePort;

  /// 歌曲所在授权树。
  final String treeUri;
  final LocalMatchSaveMode saveMode;
  final String? _saveTreeUri;
  final String? _treeLabel;
  final String? _saveTreeLabel;

  /// 目标目录 → 该目录下已存在的文件名。
  ///
  /// 按目录缓存：`skipExistingLyrics` 命中时每个目录只枚举一次，
  /// 缓存容量与涉及目录数同阶，不随歌曲数线性增长。
  final Map<String, Set<String>> _existingNamesByTarget =
      <String, Set<String>>{};

  @override
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  }) async {
    final AndroidSafSaveTarget target = _requireTarget(request);
    final String fileName = _buildFileName(request);
    final AndroidSafWriteDocumentResult result = await _treePort.writeDocument(
      treeUri: target.treeUri,
      directorySegments: target.directorySegments,
      displayName: fileName,
      mimeType: _resolveMimeType(request.lyricsFormat),
      bytes: bytes,
    );
    (_existingNamesByTarget[_targetKey(target)] ??= <String>{}).add(
      result.displayName,
    );
    return result.uri;
  }

  @override
  String displayPathFor(LyricsSaveRequest request, String path) {
    // 落点是 SAF 编码 URI，用户看不懂；这里用**已知的**授权树显示名与相对目录
    // 拼出可读文本（同一套 resolveAndroidSafSaveTarget 推导，和真实写入一致），
    // 展示层因此不需要再解析 URI。推导失败时退回真实路径，保证有内容可显示。
    final AndroidSafSaveTarget? target = _resolveTargetOrNull(request);
    if (target == null) {
      return path;
    }
    final String directoryLabel = target.directoryLabel.trim();
    final String fileName = _buildFileName(request);
    return directoryLabel.isEmpty ? fileName : '$directoryLabel / $fileName';
  }

  @override
  Future<bool> exists({required LyricsSaveRequest request}) async {
    final AndroidSafSaveTarget? target = _resolveTargetOrNull(request);
    if (target == null) {
      // 目标不可推导时不能默认"已存在"，否则本应写入的歌词会被静默跳过；
      // 目标缺失本身由启动前校验负责提示。
      return false;
    }
    final String key = _targetKey(target);
    final Set<String> names = _existingNamesByTarget[key] ??=
        await _listDirectoryNames(target);
    return names.contains(_buildFileName(request));
  }

  AndroidSafSaveTarget _requireTarget(LyricsSaveRequest request) {
    final AndroidSafSaveTargetResult resolved = _resolve(request);
    final AndroidSafSaveTarget? target = resolved.target;
    if (target == null) {
      throw AndroidSafSaveTargetException(
        resolved.failure ?? AndroidSafSaveTargetFailure.unknownSongPath,
        request.songInfo.path,
      );
    }
    return target;
  }

  AndroidSafSaveTarget? _resolveTargetOrNull(LyricsSaveRequest request) {
    return _resolve(request).target;
  }

  AndroidSafSaveTargetResult _resolve(LyricsSaveRequest request) {
    return resolveAndroidSafSaveTarget(
      saveMode: saveMode,
      songPath: request.songInfo.path,
      songTreeUri: treeUri,
      saveTreeUri: _saveTreeUri,
      songTreeLabel: _treeLabel,
      saveTreeLabel: _saveTreeLabel,
    );
  }

  Future<Set<String>> _listDirectoryNames(AndroidSafSaveTarget target) async {
    final String? directoryUri = safDirectoryUri(
      treeUri: target.treeUri,
      directorySegments: target.directorySegments,
    );
    if (directoryUri == null) {
      return <String>{};
    }
    final Set<String> names = <String>{};
    try {
      int offset = 0;
      while (true) {
        final AndroidSafTreePage page = await _treePort.listChildrenPage(
          uri: directoryUri,
          offset: offset,
          limit: 128,
        );
        for (final AndroidSafTreeEntry entry in page.entries) {
          if (entry.isFile) {
            names.add(entry.displayName);
          }
        }
        final int? nextOffset = page.nextOffset;
        if (nextOffset == null) {
          return names;
        }
        offset = nextOffset;
      }
    } on Exception {
      // mirror/specify 首次保存时目标目录还不存在，枚举会失败；此时按"没有任何
      // 同名歌词"处理。真正写入失败仍由 saveBytes 报错，不会被这里吞掉。
      return <String>{};
    }
  }

  String _targetKey(AndroidSafSaveTarget target) {
    return '${target.treeUri}#${target.directorySegments.join('/')}';
  }

  String _buildFileName(LyricsSaveRequest request) {
    return LyricsPathTemplateFormatter.buildFileName(
      fileNameFormat: request.resolvedFileNameFormat,
      songInfo: request.songInfo,
      lyricLangs: request.lyricLangs,
    );
  }

  String _resolveMimeType(LyricsFormat format) {
    return switch (format) {
      LyricsFormat.json => 'application/json',
      LyricsFormat.ass => 'text/x-ssa',
      LyricsFormat.srt => 'application/x-subrip',
      _ => 'text/plain',
    };
  }
}
