import 'dart:math';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../lyrics_source/lyrics_source.dart';
import '../../network/request_cancellation.dart';
import '../json_api_reader.dart';
import 'lyrics_source_response_helpers.dart';
import 'lrclib_request_executor.dart';

/// Lrclib provider，实现 `search/get_lyrics` 主链路。
class LrclibLyricsProvider
    implements LyricsCloudSourceProvider, ClosableLyricsSourceProvider {
  LrclibLyricsProvider({
    LrclibRequestExecutor? requestExecutor,
    Future<void> Function()? close,
  }) : this._fromParts(parts: _resolveRequestExecutor(requestExecutor, close));

  LrclibLyricsProvider._fromParts({
    required ({LrclibRequestExecutor execute, Future<void> Function() close})
    parts,
  }) : this._(requestExecutor: parts.execute, close: parts.close);

  LrclibLyricsProvider._({
    required this._requestExecutor,
    required this._close,
  });

  static ({LrclibRequestExecutor execute, Future<void> Function() close})
  _resolveRequestExecutor(
    LrclibRequestExecutor? requestExecutor,
    Future<void> Function()? close,
  ) {
    if (requestExecutor != null) {
      return (execute: requestExecutor, close: close ?? _noopClose);
    }
    final LrclibRequestExecutorImpl executor = LrclibRequestExecutorImpl();
    return (execute: executor.execute, close: close ?? executor.close);
  }

  static Future<void> _noopClose() async {}

  static const int _pageSize = 20;

  final LrclibRequestExecutor _requestExecutor;
  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();

  @override
  Source get source => Source.lrclib;

  @override
  bool get supportsLyricsList => false;

  @override
  Set<SearchType> get supportedSearchTypes => const <SearchType>{
    SearchType.song,
  };

  @override
  Future<APIResultList<SourceAware>> search({
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (!supportedSearchTypes.contains(searchType)) {
      throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }
    if (page <= 0) {
      throw LddcApiParamsException('页码必须大于 0: $page');
    }

    final Object? response = await _request(
      endpoint: '/search',
      params: <String, String>{'q': keyword},
    );

    if (response is Map<String, Object?> || response is Map<Object?, Object?>) {
      final Map<String, Object?> errorPayload = asJsonMap(response);
      if (errorPayload.containsKey('error')) {
        throw LddcApiRequestException('lrclib API错误: ${errorPayload['error']}');
      }
    }

    final List<Object?> rows = asJsonList(response);
    final int start = (page - 1) * _pageSize;
    final int endExclusive = min(start + _pageSize, rows.length);
    final List<Object?> pageRows = start >= rows.length
        ? const <Object?>[]
        : rows.sublist(start, endExclusive);

    final List<SongInfo> songs = pageRows
        .map((Object? item) => _parseSongInfo(asJsonMap(item)))
        .toList(growable: false);

    return APIResultList<SourceAware>(
      songs,
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      ),
      ranges: buildCurrentPageRange(start: start, itemCount: songs.length),
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw const LddcApiNotSupportedException('lrclib API不支持获取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw const LddcApiNotSupportedException('来源 LRCLIB 不支持歌词候选列表');
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    if (info is! SongInfo) {
      throw const LddcApiParamsException('Lrclib getLyrics 仅支持 SongInfo');
    }
    if (!_isNonEmpty(info.title) ||
        info.artist == null ||
        info.artist!.isEmpty ||
        !_isNonEmpty(info.album) ||
        info.durationMs == null) {
      throw const LddcApiParamsException('缺少必要参数');
    }

    final Object? response = await _request(
      endpoint: '/get',
      params: <String, String>{
        'track_name': info.title!,
        'artist_name': info.artist!.join('/'),
        'album_name': info.album!,
        'duration': '${info.durationMs! / 1000}',
      },
    );

    final Map<String, Object?> data = asJsonMap(response);
    if (data.containsKey('error')) {
      throw LddcApiRequestException('lrclib API错误: ${data['error']}');
    }

    final Map<String, String> tags = <String, String>{
      'ti': data['trackName']?.toString() ?? info.title ?? '',
      'ar': data['artistName']?.toString() ?? info.artist?.join('/') ?? '',
      'al': data['albumName']?.toString() ?? info.album ?? '',
    };

    final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
    final Map<String, LyricsType> lyricsTypes = <String, LyricsType>{};

    final String syncedLyrics = data['syncedLyrics']?.toString() ?? '';
    final String plainLyrics = data['plainLyrics']?.toString() ?? '';

    if (syncedLyrics.isNotEmpty) {
      final ({Map<String, String> tags, LyricsData lyricsData}) parsed =
          parseLrcToData(syncedLyrics);
      tags.addAll(parsed.tags);
      lyricsData['orig'] = parsed.lyricsData;
      lyricsTypes['orig'] = judgeLyricsType(parsed.lyricsData);
    } else if (plainLyrics.isNotEmpty) {
      final LyricsData plain = plaintextToData(plainLyrics);
      lyricsData['orig'] = plain;
      lyricsTypes['orig'] = judgeLyricsType(plain);
    }

    return Lyrics(
      songInfo: info,
      source: source,
      data: lyricsData,
      types: lyricsTypes,
      tags: tags,
      id: data['id']?.toString(),
      durationMs: _parseDurationMs(data['duration']),
    );
  }

  Future<Object?> _request({
    required String endpoint,
    Map<String, String>? params,
  }) async {
    try {
      return await _requestExecutor(endpoint: endpoint, params: params);
    } on LddcApiRequestException {
      rethrow;
    } catch (error) {
      throw LddcApiRequestException('lrclib API请求失败: $error');
    }
  }

  SongInfo _parseSongInfo(Map<String, Object?> data) {
    final int? durationMs = _parseDurationMs(data['duration']);
    final bool instrumental = data['instrumental'] == true;
    final String artistName = data['artistName']?.toString() ?? '';

    return SongInfo(
      source: source,
      title: data['trackName']?.toString(),
      artist: SongArtist(<String>[if (artistName.isNotEmpty) artistName]),
      album: data['albumName']?.toString(),
      durationMs: durationMs,
      id: data['id']?.toString(),
      language: instrumental ? Language.instrumental : Language.other,
    );
  }

  int? _parseDurationMs(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value * 1000;
    }
    if (value is num) {
      return (value * 1000).round();
    }
    if (value is String) {
      final double? seconds = double.tryParse(value);
      if (seconds == null) {
        return null;
      }
      return (seconds * 1000).round();
    }
    return null;
  }

  static bool _isNonEmpty(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
