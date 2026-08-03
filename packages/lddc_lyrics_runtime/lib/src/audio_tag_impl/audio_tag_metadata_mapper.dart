import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../audio_tag/audio_tag_port.dart';

/// 音频标签元数据到领域歌曲模型的唯一映射器。
///
/// 本地匹配和后台 metadata worker 都走这里，避免同一份 artist 拆分规则在多个
/// adapter 中漂移。B20 决策只保留 `/` 拆分，类似 `AC/DC` 的艺名保持当前行为，
/// 后续若要扩展分隔符必须先评估匹配评分影响。
final class AudioTagMetadataMapper {
  const AudioTagMetadataMapper();

  SongInfo toSongInfo({required String songPath, required AudioTagMeta meta}) {
    return SongInfo(
      source: Source.local,
      path: songPath,
      title: meta.title,
      artist: parseArtist(meta.artist),
      album: meta.album,
      durationMs: meta.durationMs,
      id: meta.trackNumber?.toString(),
    );
  }

  SongArtist? parseArtist(String? artistText) {
    if (artistText == null || artistText.trim().isEmpty) {
      return null;
    }
    final Set<String> seen = <String>{};
    final List<String> values = <String>[];
    for (final String rawItem in artistText.split('/')) {
      final String item = rawItem.trim();
      if (item.isEmpty || !seen.add(item)) {
        continue;
      }
      values.add(item);
    }
    if (values.isEmpty) {
      return null;
    }
    return SongArtist(values);
  }
}
