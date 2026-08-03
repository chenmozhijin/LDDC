import '../models/models.dart';
import 'lyrics_parser_port.dart';
import 'parser_utils.dart';

/// 组装上下文：用于把解析载荷补齐为完整 `Lyrics`。
class LyricsAssembleContext {
  const LyricsAssembleContext({
    this.songInfo,
    this.source,
    this.id,
    this.accessKey,
    this.durationMs,
    this.creator,
    this.score,
    this.path,
    this.cached = false,
  });

  final SongInfo? songInfo;
  final Source? source;
  final String? id;
  final String? accessKey;
  final int? durationMs;
  final String? creator;
  final int? score;
  final String? path;
  final bool cached;
}

/// 将 `ParsedLyricsPayload` 组装为领域实体 `Lyrics`。
final class LyricsAssembler {
  const LyricsAssembler();

  Lyrics assemble(
    ParsedLyricsPayload payload, {
    LyricsAssembleContext context = const LyricsAssembleContext(),
  }) {
    final ParsedLyricsMetadata? embedded = payload.embeddedInfo;
    final Source resolvedSource = _resolveSource(payload, context);
    final String? resolvedPath = embedded?.path ?? context.path;
    final SongInfo resolvedSongInfo = _resolveSongInfo(
      payload: payload,
      context: context,
      resolvedSource: resolvedSource,
      resolvedPath: resolvedPath,
    );

    final Map<String, LyricsType> types = <String, LyricsType>{
      for (final MapEntry<String, LyricsData> entry
          in payload.lyricsData.entries)
        entry.key: judgeLyricsType(entry.value),
    };

    return Lyrics(
      songInfo: resolvedSongInfo,
      source: resolvedSource,
      data: payload.lyricsData,
      types: types,
      tags: payload.tags,
      id: embedded?.id ?? context.id,
      accessKey: embedded?.accessKey ?? context.accessKey,
      durationMs: embedded?.durationMs ?? context.durationMs,
      creator: embedded?.creator ?? context.creator,
      score: embedded?.score ?? context.score,
      path: resolvedPath ?? resolvedSongInfo.path,
      cached: embedded?.cached ?? context.cached,
    );
  }

  Source _resolveSource(
    ParsedLyricsPayload payload,
    LyricsAssembleContext context,
  ) {
    return payload.embeddedInfo?.songInfo?.source ??
        payload.embeddedInfo?.source ??
        context.source ??
        context.songInfo?.source ??
        payload.sourceHint ??
        Source.local;
  }

  SongInfo _resolveSongInfo({
    required ParsedLyricsPayload payload,
    required LyricsAssembleContext context,
    required Source resolvedSource,
    required String? resolvedPath,
  }) {
    final SongInfo? embeddedSongInfo = payload.embeddedInfo?.songInfo;
    SongInfo songInfo =
        embeddedSongInfo ??
        context.songInfo ??
        SongInfo(source: resolvedSource, path: resolvedPath);

    if (songInfo.source != resolvedSource) {
      songInfo = songInfo.copyWith(source: resolvedSource);
    }
    if (songInfo.path == null && resolvedPath != null) {
      songInfo = songInfo.copyWith(path: resolvedPath);
    }
    return songInfo;
  }
}
