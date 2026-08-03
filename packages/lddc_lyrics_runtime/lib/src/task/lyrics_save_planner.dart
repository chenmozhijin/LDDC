import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'lyrics_path_template_formatter.dart';
import 'lyrics_save_persistence.dart';

/// 保存位置策略，供搜索、本地匹配和批量转换共用同一套路径规划。
enum LyricsSaveDirectoryMode { folder, songDirectory, mirrorSourceRoot }

/// 保存文件名策略，避免三个功能各自拼接模板和扩展名。
enum LyricsSaveFileNameMode { templateBySong, templateByLyrics, sourceBasename }

/// 保存规划失败原因。
enum LyricsSavePlanErrorCode {
  missingSaveRoot,
  missingSongRoot,
  missingSongPath,
  missingLyricsInfo,
  songOutsideRoot,
}

/// 歌词保存规划。
///
/// 这是纯计算模型，不做文件系统 IO。页面预览、已存在检查和真正写入都消费
/// 同一份规划，避免预览路径与执行路径在批量场景下悄悄分叉。
class LyricsSavePlan {
  const LyricsSavePlan._({
    required this.lyricsFormat,
    required this.fileName,
    required this.displayPath,
    required this.request,
    required this.errorCode,
  });

  factory LyricsSavePlan.success({
    required LyricsFormat lyricsFormat,
    required String fileName,
    required String displayPath,
    required LyricsSaveRequest request,
  }) {
    return LyricsSavePlan._(
      lyricsFormat: lyricsFormat,
      fileName: fileName,
      displayPath: displayPath,
      request: request,
      errorCode: null,
    );
  }

  factory LyricsSavePlan.error(LyricsSavePlanErrorCode code) {
    return LyricsSavePlan._(
      lyricsFormat: LyricsFormat.lineByLineLrc,
      fileName: '',
      displayPath: '',
      request: null,
      errorCode: code,
    );
  }

  final LyricsFormat lyricsFormat;
  final String fileName;
  final String displayPath;
  final LyricsSaveRequest? request;
  final LyricsSavePlanErrorCode? errorCode;

  bool get isSuccess => errorCode == null;
}

/// 歌词保存规划器：只负责字符串与请求模型计算，不触碰磁盘或平台通道。
final class LyricsSavePlanner {
  const LyricsSavePlanner._();

  static LyricsSavePlan planSearch({
    required String folder,
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
    required LyricsFormat lyricsFormat,
  }) {
    return _planTemplatePath(
      folder: folder,
      fileNameFormat: fileNameFormat,
      songInfo: songInfo,
      lyricLangs: lyricLangs,
      lyricsFormat: lyricsFormat,
    );
  }

  static LyricsSavePlan planBatchConvert({
    required String sourcePath,
    required LyricsFormat targetFormat,
    String? saveRootPath,
  }) {
    final String normalizedSource = sourcePath.trim();
    if (normalizedSource.isEmpty) {
      return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingSongPath);
    }
    final String normalizedRoot = saveRootPath?.trim() ?? '';
    final String folder = normalizedRoot.isEmpty
        ? p.dirname(normalizedSource)
        : normalizedRoot;
    final String fileName =
        '${p.basenameWithoutExtension(normalizedSource)}${targetFormat.ext}';
    final SongInfo songInfo = SongInfo(
      source: Source.local,
      path: normalizedSource,
      title: p.basenameWithoutExtension(normalizedSource),
    );
    return LyricsSavePlan.success(
      lyricsFormat: targetFormat,
      fileName: fileName,
      displayPath: p.normalize(
        p.join(LyricsPathTemplateFormatter.sanitizePath(folder), fileName),
      ),
      request: LyricsSaveRequest(
        songInfo: songInfo,
        lyricLangs: const <String>['orig'],
        lyricsFormat: targetFormat,
        fileNameFormat: p.basenameWithoutExtension(normalizedSource),
      ),
    );
  }

  static LyricsSavePlan planLocalMatch({
    required LyricsSaveDirectoryMode directoryMode,
    required LyricsSaveFileNameMode fileNameMode,
    required SongInfo localInfo,
    required LyricsFormat lyricsFormat,
    required String fileNameFormat,
    required List<String> lyricLangs,
    required String? saveRootPath,
    required SongInfo? lyricsInfo,
    required bool allowLyricsPlaceholder,
    required String? songRootPath,
  }) {
    final String? localPath = localInfo.path;
    if (localPath == null || localPath.trim().isEmpty) {
      return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingSongPath);
    }

    late String folder;
    switch (directoryMode) {
      case LyricsSaveDirectoryMode.mirrorSourceRoot:
        if (saveRootPath == null || saveRootPath.trim().isEmpty) {
          return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingSaveRoot);
        }
        if (songRootPath == null || songRootPath.trim().isEmpty) {
          return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingSongRoot);
        }
        final String normalizedLocalPath = p.normalize(localPath);
        final String normalizedSongRoot = p.normalize(songRootPath);
        if (!_isPlatformUri(normalizedLocalPath) &&
            !_isPlatformUri(normalizedSongRoot) &&
            !p.isWithin(normalizedSongRoot, normalizedLocalPath)) {
          return LyricsSavePlan.error(LyricsSavePlanErrorCode.songOutsideRoot);
        }
        final String relativePath = p.relative(
          normalizedLocalPath,
          from: normalizedSongRoot,
        );
        folder = p.join(saveRootPath, p.dirname(relativePath));
      case LyricsSaveDirectoryMode.songDirectory:
        folder = p.dirname(localPath);
      case LyricsSaveDirectoryMode.folder:
        if (saveRootPath == null || saveRootPath.trim().isEmpty) {
          return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingSaveRoot);
        }
        folder = saveRootPath;
    }
    if (fileNameMode == LyricsSaveFileNameMode.sourceBasename &&
        localInfo.fromCue) {
      folder = p.join(folder, p.basenameWithoutExtension(localPath));
    }

    final String? fileName = _resolveLocalMatchFileName(
      fileNameMode: fileNameMode,
      localInfo: localInfo,
      lyricsInfo: lyricsInfo,
      fileNameFormat: fileNameFormat,
      lyricsFormat: lyricsFormat,
      lyricLangs: lyricLangs,
      allowLyricsPlaceholder: allowLyricsPlaceholder,
    );
    if (fileName == null) {
      return LyricsSavePlan.error(LyricsSavePlanErrorCode.missingLyricsInfo);
    }

    final SongInfo requestSongInfo =
        fileNameMode == LyricsSaveFileNameMode.templateByLyrics &&
            lyricsInfo != null
        ? lyricsInfo
        : localInfo;
    return LyricsSavePlan.success(
      lyricsFormat: lyricsFormat,
      fileName: fileName,
      displayPath: p.normalize(
        p.join(LyricsPathTemplateFormatter.sanitizePath(folder), fileName),
      ),
      request: LyricsSaveRequest(
        songInfo: requestSongInfo,
        lyricLangs: lyricLangs,
        lyricsFormat: lyricsFormat,
        fileNameFormat: fileNameFormat,
      ),
    );
  }

  static LyricsSavePlan _planTemplatePath({
    required String folder,
    required String fileNameFormat,
    required SongInfo songInfo,
    required List<String> lyricLangs,
    required LyricsFormat lyricsFormat,
  }) {
    final String fileName = LyricsPathTemplateFormatter.buildFileName(
      fileNameFormat: '$fileNameFormat${lyricsFormat.ext}',
      songInfo: songInfo,
      lyricLangs: lyricLangs,
    );
    final String displayPath = LyricsPathTemplateFormatter.buildPath(
      folder: folder,
      fileNameFormat: '$fileNameFormat${lyricsFormat.ext}',
      songInfo: songInfo,
      lyricLangs: lyricLangs,
    );
    return LyricsSavePlan.success(
      lyricsFormat: lyricsFormat,
      fileName: fileName,
      displayPath: displayPath,
      request: LyricsSaveRequest(
        songInfo: songInfo,
        lyricLangs: lyricLangs,
        lyricsFormat: lyricsFormat,
        fileNameFormat: fileNameFormat,
      ),
    );
  }

  static String? _resolveLocalMatchFileName({
    required LyricsSaveFileNameMode fileNameMode,
    required SongInfo localInfo,
    required SongInfo? lyricsInfo,
    required String fileNameFormat,
    required LyricsFormat lyricsFormat,
    required List<String> lyricLangs,
    required bool allowLyricsPlaceholder,
  }) {
    final String? localPath = localInfo.path;
    switch (fileNameMode) {
      case LyricsSaveFileNameMode.sourceBasename:
        if (localInfo.fromCue) {
          if (lyricsInfo == null) {
            return allowLyricsPlaceholder
                ? '$fileNameFormat${lyricsFormat.ext}'
                : null;
          }
          return LyricsPathTemplateFormatter.buildFileName(
            fileNameFormat: '$fileNameFormat${lyricsFormat.ext}',
            songInfo: localInfo,
            lyricLangs: lyricLangs,
          );
        }
        return '${p.basenameWithoutExtension(localPath ?? '')}${lyricsFormat.ext}';
      case LyricsSaveFileNameMode.templateByLyrics:
        if (lyricsInfo == null) {
          return allowLyricsPlaceholder
              ? '$fileNameFormat${lyricsFormat.ext}'
              : null;
        }
        return LyricsPathTemplateFormatter.buildFileName(
          fileNameFormat: '$fileNameFormat${lyricsFormat.ext}',
          songInfo: lyricsInfo,
          lyricLangs: lyricLangs,
        );
      case LyricsSaveFileNameMode.templateBySong:
        if (!localInfo.fromCue &&
            (localInfo.title == null || localInfo.title!.isEmpty)) {
          return '${p.basenameWithoutExtension(localPath ?? '')}${lyricsFormat.ext}';
        }
        return LyricsPathTemplateFormatter.buildFileName(
          fileNameFormat: '$fileNameFormat${lyricsFormat.ext}',
          songInfo: localInfo,
          lyricLangs: lyricLangs,
        );
    }
  }

  static bool _isPlatformUri(String value) => value.contains('://');
}
