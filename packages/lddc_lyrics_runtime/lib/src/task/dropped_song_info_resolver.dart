import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../parser/cue_parser.dart';
import 'local_match_usecase.dart';

/// 拖拽歌曲解析失败异常。
class DroppedSongInfoResolveException implements Exception {
  const DroppedSongInfoResolveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 将拖拽描述对象解析为可直接进入业务链的单条 `SongInfo`。
final class DroppedSongInfoResolver {
  const DroppedSongInfoResolver({required this._mediaGateway});

  final LocalMatchMediaGateway _mediaGateway;

  Future<SongInfo> resolve({
    required String path,
    String? track,
    String? index,
  }) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw const DroppedSongInfoResolveException('拖拽的歌曲文件不可访问');
    }
    final String? normalizedTrack = _normalizeSelector(track);
    final String? normalizedIndex = _normalizeSelector(index);
    if (_isCuePath(normalizedPath) &&
        (normalizedTrack != null || normalizedIndex != null)) {
      return _resolveCueTrack(
        path: normalizedPath,
        track: normalizedTrack,
        index: normalizedIndex,
      );
    }
    return _resolveAudioTrack(path: normalizedPath, track: normalizedTrack);
  }

  Future<SongInfo> _resolveCueTrack({
    required String path,
    required String? track,
    required String? index,
  }) async {
    final CueData cueData;
    try {
      cueData = await parseCueFile(cuePath: path);
    } on Exception catch (error) {
      throw DroppedSongInfoResolveException('解析文件 $path 失败: $error');
    }
    final List<SongInfo> infos;
    try {
      final List<String> audioRefs = cueData.getAudioPaths();
      final Map<String, int?> durations = <String, int?>{};
      for (final String audioPath in audioRefs) {
        durations[p.normalize(p.absolute(audioPath))] = await _mediaGateway
            .readAudioDurationMs(audioPath);
      }
      infos = cueData.toSongInfos(
        durationResolver: (String audioPath) =>
            durations[p.normalize(p.absolute(audioPath))],
      );
    } on Exception catch (error) {
      throw DroppedSongInfoResolveException('解析文件 $path 失败: $error');
    }
    if (infos.isEmpty) {
      throw DroppedSongInfoResolveException('文件 $path 中没有找到任何歌曲');
    }
    if (index != null) {
      final int? resolvedIndex = int.tryParse(index);
      if (resolvedIndex == null ||
          resolvedIndex < 0 ||
          resolvedIndex >= infos.length) {
        throw DroppedSongInfoResolveException('文件 $path 中没有找到第 $index 轨歌曲');
      }
      return infos[resolvedIndex];
    }
    if (track != null) {
      final SongInfo? matched = _matchTrack(infos, track);
      if (matched == null) {
        throw DroppedSongInfoResolveException('文件 $path 中没有找到第 $track 轨歌曲');
      }
      return matched;
    }
    throw DroppedSongInfoResolveException('文件 $path 中没有找到可用轨道');
  }

  Future<SongInfo> _resolveAudioTrack({
    required String path,
    required String? track,
  }) async {
    final List<SongInfo> infos;
    try {
      infos = await _mediaGateway.readAudioSongInfos(path);
    } on Exception catch (error) {
      throw DroppedSongInfoResolveException('解析文件 $path 失败: $error');
    }
    if (infos.isEmpty) {
      throw DroppedSongInfoResolveException('无法读取歌曲信息');
    }
    if (infos.length == 1) {
      return infos.first;
    }
    if (track != null) {
      final SongInfo? matched = _matchTrack(infos, track);
      if (matched == null) {
        throw DroppedSongInfoResolveException('文件 $path 中没有找到第 $track 轨歌曲');
      }
      return matched;
    }
    throw DroppedSongInfoResolveException('文件 $path 中包含多个歌曲');
  }

  SongInfo? _matchTrack(List<SongInfo> infos, String track) {
    final int? numericTrack = int.tryParse(track);
    for (final SongInfo song in infos) {
      final String? songId = _normalizeSelector(song.id);
      if (songId == null) {
        continue;
      }
      if (songId == track) {
        return song;
      }
      if (numericTrack != null && int.tryParse(songId) == numericTrack) {
        return song;
      }
    }
    return null;
  }

  String? _normalizeSelector(String? value) {
    final String? trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _isCuePath(String path) => p.extension(path).toLowerCase() == '.cue';
}
