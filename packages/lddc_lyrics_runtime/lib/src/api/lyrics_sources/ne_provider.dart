import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../lyrics_source/lyrics_source.dart';
import '../../network/request_cancellation.dart';
import '../json_api_reader.dart';
import 'lyrics_source_response_helpers.dart';
import 'ne_cover_request_policy.dart';
import 'ne_request_executor.dart';

/// NE provider，实现 `search/get_songlist/get_lyrics` 主链路。
class NeLyricsProvider
    implements LyricsCloudSourceProvider, ClosableLyricsSourceProvider {
  NeLyricsProvider({
    required this._requestExecutor,
    Future<void> Function()? close,
  }) : _close = close ?? _noopClose;

  static Future<void> _noopClose() async {}

  static const int _pageSize = 20;

  final NeRequestExecutor _requestExecutor;
  final Future<void> Function() _close;

  @override
  Future<void> close() => _close();

  @override
  Source get source => Source.ne;

  @override
  bool get supportsLyricsList => false;

  @override
  Set<SearchType> get supportedSearchTypes => const <SearchType>{
    SearchType.song,
    SearchType.songId,
    SearchType.album,
    SearchType.songlist,
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

    if (searchType == SearchType.songId) {
      final String songId = keyword.trim();
      if (!RegExp(r'^\d+$').hasMatch(songId)) {
        throw LddcApiParamsException('歌曲id格式不正确: $keyword');
      }
      final Map<String, Object?> data = await _request(
        path: '/eapi/v3/song/detail',
        params: <String, Object?>{
          'c': jsonEncode(<Map<String, Object?>>[
            <String, Object?>{'id': songId, 'v': 0},
          ]),
          'trialMode': '-1',
        },
      );
      final List<SongInfo> songs = _formatSongInfos(data['songs']);
      return APIResultList<SourceAware>(
        songs,
        info: SearchInfo(
          source: source,
          keyword: keyword,
          searchType: searchType,
          page: page,
        ),
        ranges: SourceRange(
          start: 0,
          end: songs.isEmpty ? -1 : songs.length - 1,
          total: songs.length,
        ),
      );
    }

    final int start = (page - 1) * _pageSize;
    final Map<String, Object?> params = <String, Object?>{
      'limit': '$_pageSize',
      'offset': '$start',
    };

    String path;
    switch (searchType) {
      case SearchType.song:
        params
          ..['keyword'] = keyword
          ..['scene'] = 'NORMAL'
          ..['needCorrect'] = 'true';
        path = '/eapi/search/song/list/page';
      case SearchType.album:
        params
          ..['s'] = keyword
          ..['queryCorrect'] = 'true';
        path = '/eapi/v1/search/album/get';
      case SearchType.songlist:
        params
          ..['s'] = keyword
          ..['queryCorrect'] = 'true';
        path = '/eapi/v1/search/playlist/get';
      default:
        throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }

    final Map<String, Object?> data = await _request(
      path: path,
      params: params,
    );
    final SearchInfo info = SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );

    if ((!data.containsKey('result') && !data.containsKey('data')) ||
        (asJsonMap(data['data'])['resources'] == null &&
            searchType == SearchType.song)) {
      return APIResultList<SourceAware>(
        const <SourceAware>[],
        info: info,
        ranges: const SourceRange(start: 0, end: -1, total: 0),
      );
    }

    switch (searchType) {
      case SearchType.song:
        final List<Object?> resources = asJsonList(
          asJsonMap(data['data'])['resources'],
        );
        final List<Object?> songs = resources
            .map((Object? item) {
              return asJsonMap(asJsonMap(item)['baseInfo'])['simpleSongData'];
            })
            .toList(growable: false);
        final List<SongInfo> results = _formatSongInfos(songs);
        return APIResultList<SourceAware>(
          results,
          info: info,
          ranges: buildCurrentPageRange(
            start: start,
            itemCount: results.length,
          ),
        );
      case SearchType.album:
        final Map<String, Object?> result = asJsonMap(data['result']);
        final List<Object?> albums = asJsonList(result['albums']);
        final List<SongListInfo> results = albums
            .map((Object? item) => _parseAlbum(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          results,
          info: info,
          ranges: buildCurrentPageRange(
            start: start,
            itemCount: results.length,
          ),
        );
      case SearchType.songlist:
        final Map<String, Object?> result = asJsonMap(data['result']);
        final List<Object?> playlists = asJsonList(result['playlists']);
        final List<SongListInfo> results = playlists
            .map((Object? item) => _parseSonglist(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          results,
          info: info,
          ranges: buildCurrentPageRange(
            start: start,
            itemCount: results.length,
          ),
        );
      default:
        throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    late final List<SongInfo> songs;
    switch (songListInfo.type) {
      case SongListType.album:
        final String plainText = 'e_r=true&id=${songListInfo.id}';
        final Map<String, Object?> data = await _request(
          path: '/eapi/album/v3/detail',
          params: <String, Object?>{
            'id': songListInfo.id,
            'cache_key': eapiGetCacheKey(
              Uint8List.fromList(utf8.encode(plainText)),
            ),
          },
        );
        songs = _formatSongInfos(data['songs']);
      case SongListType.songlist:
        final String plainText = 'e_r=true&id=${songListInfo.id}&n=0&s=0';
        final Map<String, Object?> playlistData = await _request(
          path: '/eapi/v1/playlist/detail',
          params: <String, Object?>{
            'id': songListInfo.id,
            'n': '0',
            's': '0',
            'cache_key': eapiGetCacheKey(
              Uint8List.fromList(utf8.encode(plainText)),
            ),
          },
        );
        final List<Object?> trackIds = asJsonList(
          asJsonMap(playlistData['playlist'])['trackIds'],
        );
        if (trackIds.isEmpty) {
          songs = <SongInfo>[];
          break;
        }
        final List<Map<String, Object?>> compact = trackIds
            .map(
              (Object? item) => <String, Object?>{
                'id': asJsonMap(item)['id']?.toString() ?? '',
                'v': 0,
              },
            )
            .toList(growable: false);
        final Map<String, Object?> songsData = await _request(
          path: '/eapi/v3/song/detail',
          params: <String, Object?>{
            'c': jsonEncode(compact),
            'trialMode': '-1',
          },
        );
        songs = _formatSongInfos(songsData['songs']);
    }

    return APIResultList<SongInfo>(
      songs,
      info: songListInfo,
      ranges: SourceRange(
        start: 0,
        end: songs.isEmpty ? -1 : songs.length - 1,
        total: songs.length,
      ),
    );
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw const LddcApiNotSupportedException('来源 NE 不支持歌词候选列表');
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    if (info is! SongInfo) {
      throw const LddcApiParamsException('NE getLyrics 仅支持 SongInfo');
    }
    final SongInfo songInfo = info;
    if (songInfo.id == null || songInfo.id!.isEmpty) {
      throw const LddcApiParamsException('歌曲id为空');
    }

    final Map<String, Object?> data = await _request(
      path: '/eapi/song/lyric/v1',
      params: <String, Object?>{
        'id': _requireSongId(songInfo.id!),
        'lv': '-1',
        'tv': '-1',
        'rv': '-1',
        'yv': '-1',
      },
    );

    final Map<String, String> tags = <String, String>{};
    if (songInfo.artist != null && songInfo.artist!.isNotEmpty) {
      tags['ar'] = songInfo.artist!.join('/');
    }
    if (songInfo.album != null && songInfo.album!.isNotEmpty) {
      tags['al'] = songInfo.album!;
    }
    if (songInfo.title != null && songInfo.title!.isNotEmpty) {
      tags['ti'] = songInfo.title!;
    }

    final String lyricBy =
        asJsonMap(data['lyricUser'])['nickname']?.toString() ?? '';
    final String transBy =
        asJsonMap(data['transUser'])['nickname']?.toString() ?? '';
    if (lyricBy.isNotEmpty) {
      tags['by'] = lyricBy;
    }
    if (transBy.isNotEmpty) {
      if (tags.containsKey('by') && tags['by'] != transBy) {
        tags['by'] = '${tags['by']} & $transBy';
      } else if (!tags.containsKey('by')) {
        tags['by'] = transBy;
      }
    }

    final bool hasYrc =
        asJsonMap(data['yrc'])['lyric']?.toString().isNotEmpty ?? false;
    final List<({String key, String field})> mapping = hasYrc
        ? <({String key, String field})>[
            (key: 'orig', field: 'yrc'),
            (key: 'ts', field: 'tlyric'),
            (key: 'roma', field: 'romalrc'),
            (key: 'orig_lrc', field: 'lrc'),
          ]
        : <({String key, String field})>[
            (key: 'orig', field: 'lrc'),
            (key: 'ts', field: 'tlyric'),
            (key: 'roma', field: 'romalrc'),
          ];

    final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
    final Map<String, LyricsType> lyricsTypes = <String, LyricsType>{};

    for (final ({String key, String field}) item in mapping) {
      final String lyricText =
          asJsonMap(data[item.field])['lyric']?.toString() ?? '';
      if (lyricText.isEmpty) {
        continue;
      }

      final LyricsData parsed;
      if (item.field == 'yrc') {
        parsed =
            parseYrcToMultiResult(lyricText).lyricsData['orig'] ??
            <LyricsLine>[];
      } else if (lyricText.contains('[') && lyricText.contains(']')) {
        parsed = parseLrcToData(lyricText, source: Source.ne).lyricsData;
      } else {
        parsed = plaintextToData(lyricText);
      }

      lyricsData[item.key] = parsed;
      lyricsTypes[item.key] = judgeLyricsType(parsed);
    }

    return Lyrics(
      songInfo: songInfo,
      source: source,
      data: lyricsData,
      types: lyricsTypes,
      tags: tags,
    );
  }

  Future<Map<String, Object?>> _request({
    required String path,
    required Map<String, Object?> params,
  }) async {
    try {
      return await _requestExecutor(path: path, params: params);
    } on LddcApiRequestException {
      rethrow;
    } catch (error) {
      throw LddcApiRequestException('NE API请求失败: $error');
    }
  }

  List<SongInfo> _formatSongInfos(Object? songInfos) {
    final List<SongInfo> songs = <SongInfo>[];
    for (final Object? item in asJsonList(songInfos)) {
      final Map<String, Object?> info = asJsonMap(item);
      final List<Object?> aliases = asJsonList(info['alia']);
      final String subtitle = aliases.isNotEmpty
          ? aliases.first.toString()
          : '';
      final List<String> artists = <String>[
        for (final Object? artist in asJsonList(info['ar']))
          if (asJsonMap(artist)['name']?.toString().isNotEmpty ?? false)
            asJsonMap(artist)['name']!.toString(),
      ];

      songs.add(
        SongInfo(
          source: source,
          id: info['id']?.toString(),
          title: info['name']?.toString(),
          subtitle: subtitle,
          artist: SongArtist(artists),
          album: asJsonMap(info['al'])['name']?.toString(),
          imgUrl: NeCoverRequestPolicy.normalizeUrl(
            asJsonMap(info['al'])['picUrl']?.toString(),
          ),
          durationMs: _parseInt(info['dt']),
        ),
      );
    }
    return songs;
  }

  SongListInfo _parseAlbum(Map<String, Object?> album) {
    final List<Object?> artists = asJsonList(album['artists']);
    final String author = artists.isEmpty
        ? ''
        : asJsonMap(artists.first)['name']?.toString() ?? '';
    return SongListInfo(
      source: source,
      type: SongListType.album,
      id: album['id']?.toString() ?? '',
      title: album['name']?.toString() ?? '',
      imgUrl:
          NeCoverRequestPolicy.normalizeUrl(album['picUrl']?.toString()) ?? '',
      songCount: _parseInt(album['size']),
      publishTimeS: _parseInt(album['publishTime']) == null
          ? null
          : _parseInt(album['publishTime'])! ~/ 1000,
      author: author,
    );
  }

  SongListInfo _parseSonglist(Map<String, Object?> songlist) {
    return SongListInfo(
      source: source,
      type: SongListType.songlist,
      id: songlist['id']?.toString() ?? '',
      title: songlist['name']?.toString() ?? '',
      imgUrl:
          NeCoverRequestPolicy.normalizeUrl(
            songlist['coverImgUrl']?.toString(),
          ) ??
          '',
      songCount: _parseInt(songlist['trackCount']),
      publishTimeS: null,
      author: asJsonMap(songlist['creator'])['nickname']?.toString() ?? '',
    );
  }

  static int? _parseInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  int _requireSongId(String rawId) {
    final int? id = int.tryParse(rawId.trim());
    if (id == null) {
      throw LddcApiParamsException('歌曲id格式不正确: $rawId');
    }
    return id;
  }
}
