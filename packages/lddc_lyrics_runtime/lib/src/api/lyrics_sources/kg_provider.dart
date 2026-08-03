import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../lyrics_source/lyrics_source.dart';
import '../../network/request_cancellation.dart';
import '../json_api_reader.dart';
import 'lyrics_source_response_helpers.dart';
import 'kg_request_executor.dart';

/// Kugou provider，实现 `search/get_songlist/get_lyrics/get_lyricslist`。
class KgLyricsProvider
    implements LyricsCloudSourceProvider, ClosableLyricsSourceProvider {
  KgLyricsProvider({
    KgRequestExecutor? requestExecutor,
    Future<void> Function()? close,
    LyricsDecryptor? decryptor,
  }) : this._fromParts(
         parts: _resolveRequestExecutor(requestExecutor, close),
         decryptor: decryptor,
       );

  KgLyricsProvider._fromParts({
    required ({KgRequestExecutor executor, Future<void> Function() close})
    parts,
    LyricsDecryptor? decryptor,
  }) : this._(
         requestExecutor: parts.executor,
         close: parts.close,
         decryptor: decryptor,
       );

  KgLyricsProvider._({
    required this._requestExecutor,
    required this._close,
    LyricsDecryptor? decryptor,
  }) : _decryptor = decryptor ?? LyricsDecryptor();

  static ({KgRequestExecutor executor, Future<void> Function() close})
  _resolveRequestExecutor(
    KgRequestExecutor? requestExecutor,
    Future<void> Function()? close,
  ) {
    if (requestExecutor != null) {
      return (executor: requestExecutor, close: close ?? _noopClose);
    }
    final KgRequestExecutorImpl executor = KgRequestExecutorImpl();
    return (executor: executor, close: close ?? executor.close);
  }

  static Future<void> _noopClose() async {}

  static const int _pageSize = 20;

  static const Map<SearchType, ({String url, String module})>
  _searchTypeMapping = <SearchType, ({String url, String module})>{
    SearchType.song: (
      url: 'http://complexsearch.kugou.com/v2/search/song',
      module: 'SearchSong',
    ),
    SearchType.album: (
      url: 'http://complexsearch.kugou.com/v1/search/album',
      module: 'SearchAlbum',
    ),
    SearchType.songlist: (
      url: 'http://complexsearch.kugou.com/v1/search/special',
      module: 'SearchSongRecommand',
    ),
  };

  static const Map<String, Language> _languageMapping = <String, Language>{
    '伴奏': Language.instrumental,
    '纯音乐': Language.instrumental,
    '英语': Language.english,
    '韩语': Language.korean,
    '日语': Language.japanese,
    '粤语': Language.chinese,
    '国语': Language.chinese,
  };

  final KgRequestExecutor _requestExecutor;
  final Future<void> Function() _close;
  final LyricsDecryptor _decryptor;

  @override
  Future<void> close() => _close();

  @override
  Source get source => Source.kg;

  @override
  bool get supportsLyricsList => true;

  @override
  Set<SearchType> get supportedSearchTypes => const <SearchType>{
    SearchType.song,
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

    final SearchInfo info = SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final int start = (page - 1) * _pageSize;

    final ({String url, String module}) mapping =
        _searchTypeMapping[searchType]!;
    final Map<String, Object?> params = <String, Object?>{
      'sorttype': '0',
      'keyword': keyword,
      'pagesize': _pageSize,
      'page': page,
    };

    Map<String, Object?> data;
    try {
      data = await _request(
        uri: Uri.parse(mapping.url),
        params: params,
        module: mapping.module,
        headers: const <String, String>{'x-router': 'complexsearch.kugou.com'},
      );
    } on LddcApiRequestException {
      // 对齐Python版：新搜索接口异常时自动回退旧接口。
      return _searchWithLegacyApi(
        keyword: keyword,
        searchType: searchType,
        page: page,
      );
    }

    final List<Object?> lists = asJsonList(asJsonMap(data['data'])['lists']);

    switch (searchType) {
      case SearchType.song:
        final List<SongInfo> songs = lists
            .map((Object? item) => _parseSongFromNewSearch(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          songs,
          info: info,
          ranges: buildCurrentPageRange(start: start, itemCount: songs.length),
        );
      case SearchType.album:
        final List<SongListInfo> albums = lists
            .map((Object? item) => _parseAlbumFromNewSearch(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          albums,
          info: info,
          ranges: buildCurrentPageRange(start: start, itemCount: albums.length),
        );
      case SearchType.songlist:
        final List<SongListInfo> songlists = lists
            .map((Object? item) => _parseSonglistFromNewSearch(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          songlists,
          info: info,
          ranges: buildCurrentPageRange(
            start: start,
            itemCount: songlists.length,
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
        final Map<String, Object?> payload = <String, Object?>{
          'pagesize': '2147483647',
          'album_id': songListInfo.id,
          'page': '1',
        };
        final String bodyText = const JsonEncoder.withIndent(
          '    ',
        ).convert(payload);
        final Map<String, Object?> data = await _request(
          uri: Uri.parse('http://openapi.kugou.com/kmr/v1/album_songlist'),
          params: const <String, Object?>{},
          module: 'album_song_list',
          method: 'POST',
          data: bodyText,
        );
        songs = asJsonList(asJsonMap(data['data'])['songs'])
            .map((Object? item) {
              return _parseSongFromAlbumSonglist(asJsonMap(item));
            })
            .toList(growable: false);
      case SongListType.songlist:
        final Map<String, Object?> data = await _request(
          uri: Uri.parse(
            'https://pubsongscdn.kugou.com/v4/get_other_list_file',
          ),
          params: <String, Object?>{
            'specialid': songListInfo.id,
            'need_sort': '1',
            'module': 'CloudMusic',
            'pagesize': '-1',
            'global_collection_id': songListInfo.id,
            'page': '1',
            'type': '0',
          },
          module: 'SongList',
        );
        songs = asJsonList(asJsonMap(data['data'])['info'])
            .map((Object? item) {
              return _parseSongFromSonglistSongs(asJsonMap(item));
            })
            .toList(growable: false);
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
    if (!_isNonEmpty(songInfo.id)) {
      throw const LddcApiParamsException('歌曲id为空');
    }
    if (!_isNonEmpty(songInfo.hash)) {
      throw const LddcApiParamsException('歌曲hash为空');
    }
    if (songInfo.durationMs == null) {
      throw const LddcApiParamsException('歌曲时长为空');
    }

    final String artistText = songInfo.artist?.join('、') ?? '';
    final String titleText = songInfo.title ?? '';
    final Map<String, Object?> data = await _request(
      uri: Uri.parse('https://lyrics.kugou.com/v1/search'),
      params: <String, Object?>{
        'album_audio_id': songInfo.id!,
        'duration': songInfo.durationMs!,
        'hash': songInfo.hash!,
        'keyword': '$artistText - $titleText',
        'lrctxt': '1',
        'man': 'no',
      },
      module: 'Lyric',
    );

    final List<LyricInfo> lyrics = asJsonList(data['candidates'])
        .map((Object? item) {
          final Map<String, Object?> lyric = asJsonMap(item);
          return LyricInfo(
            source: source,
            id: lyric['id']?.toString(),
            accessKey: lyric['accesskey']?.toString(),
            creator: lyric['nickname']?.toString(),
            durationMs: _parseInt(lyric['duration']),
            score: _parseInt(lyric['score']),
            songInfo: songInfo,
          );
        })
        .toList(growable: false);

    return APIResultList<LyricInfo>(
      lyrics,
      info: songInfo,
      ranges: SourceRange(
        start: 0,
        end: lyrics.isEmpty ? -1 : lyrics.length - 1,
        total: lyrics.length,
      ),
    );
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    LyricInfo lyricInfo;
    if (info is SongInfo) {
      final APIResultList<LyricInfo> infos = await getLyricslist(info);
      if (infos.isEmpty) {
        throw const LddcLyricsNotFoundException('没有找到歌词');
      }
      lyricInfo = infos.first;
    } else if (info is LyricInfo) {
      lyricInfo = info;
    } else {
      throw const LddcApiParamsException('KG getLyrics 仅支持 SongInfo/LyricInfo');
    }

    if (!_isNonEmpty(lyricInfo.id) || !_isNonEmpty(lyricInfo.accessKey)) {
      throw const LddcApiParamsException('歌词id或accessKey为空');
    }

    final Map<String, Object?> data = await _request(
      uri: Uri.parse('http://lyrics.kugou.com/download'),
      params: <String, Object?>{
        'accesskey': lyricInfo.accessKey!,
        'charset': 'utf8',
        'client': 'mobi',
        'fmt': 'krc',
        'id': lyricInfo.id!,
        'ver': '1',
      },
      module: 'Lyric',
    );

    final String content = data['content']?.toString() ?? '';
    if (content.isEmpty) {
      throw const LddcApiRequestException('KG 歌词内容为空');
    }

    final Uint8List lyricBytes;
    try {
      lyricBytes = base64Decode(content);
    } catch (error) {
      throw LddcApiRequestException('KG 歌词解码失败:$error');
    }

    final Map<String, String> tags = <String, String>{};
    final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
    final Map<String, LyricsType> lyricsTypes = <String, LyricsType>{};

    if ((_parseInt(data['contenttype']) ?? 0) == 2) {
      final LyricsData plain = plaintextToData(
        utf8.decode(lyricBytes, allowMalformed: true),
      );
      lyricsData['orig'] = plain;
      lyricsTypes['orig'] = judgeLyricsType(plain);
    } else {
      final String krcText = _decryptor.decryptKrc(lyricBytes);
      final ParsedLyricsPayload parsed = parseKrcToMultiResult(krcText);
      tags.addAll(parsed.tags);
      parsed.lyricsData.forEach((String key, LyricsData value) {
        lyricsData[key] = value;
        lyricsTypes[key] = judgeLyricsType(value);
      });
    }

    return Lyrics(
      songInfo: lyricInfo.songInfo,
      source: source,
      data: lyricsData,
      types: lyricsTypes,
      tags: tags,
      id: lyricInfo.id,
      accessKey: lyricInfo.accessKey,
      durationMs: lyricInfo.durationMs,
      creator: lyricInfo.creator,
      score: lyricInfo.score,
      path: lyricInfo.path,
      cached: lyricInfo.cached,
    );
  }

  Future<APIResultList<SourceAware>> _searchWithLegacyApi({
    required String keyword,
    required SearchType searchType,
    required int page,
  }) async {
    final Map<String, Object?> data = await _requestExecutor.legacySearch(
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final SearchInfo info = SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final Map<String, Object?> payload = asJsonMap(data['data']);
    final List<Object?> items = asJsonList(payload['info']);
    final int start = (page - 1) * _pageSize;

    switch (searchType) {
      case SearchType.song:
        final List<SongInfo> songs = items
            .map((Object? item) => _parseSongFromLegacySearch(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          songs,
          info: info,
          ranges: buildCurrentPageRange(start: start, itemCount: songs.length),
        );
      case SearchType.album:
        final List<SongListInfo> albums = items
            .map((Object? item) => _parseAlbumFromLegacySearch(asJsonMap(item)))
            .toList(growable: false);
        return APIResultList<SourceAware>(
          albums,
          info: info,
          ranges: buildCurrentPageRange(start: start, itemCount: albums.length),
        );
      case SearchType.songlist:
        final List<SongListInfo> songlists = items
            .map(
              (Object? item) => _parseSonglistFromLegacySearch(asJsonMap(item)),
            )
            .toList(growable: false);
        return APIResultList<SourceAware>(
          songlists,
          info: info,
          ranges: buildCurrentPageRange(
            start: start,
            itemCount: songlists.length,
          ),
        );
      default:
        throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }
  }

  Future<Map<String, Object?>> _request({
    required Uri uri,
    required Map<String, Object?> params,
    required String module,
    String method = 'GET',
    String? data,
    Map<String, String>? headers,
  }) async {
    try {
      return await _requestExecutor.execute(
        uri: uri,
        params: params,
        module: module,
        method: method,
        data: data,
        headers: headers,
      );
    } on LddcApiRequestException {
      rethrow;
    } catch (error) {
      throw LddcApiRequestException('KG API请求失败: $error');
    }
  }

  SongInfo _parseSongFromNewSearch(Map<String, Object?> song) {
    final List<String> artists = <String>[
      for (final Object? singer in asJsonList(song['Singers']))
        if (asJsonMap(singer)['name']?.toString().isNotEmpty ?? false)
          asJsonMap(singer)['name']!.toString(),
    ];
    final int? durationS = _parseInt(song['Duration']);
    return SongInfo(
      source: source,
      id: song['ID']?.toString(),
      hash: song['FileHash']?.toString(),
      title: song['SongName']?.toString(),
      subtitle: song['Auxiliary']?.toString(),
      artist: SongArtist(artists),
      album: song['AlbumName']?.toString(),
      durationMs: durationS == null ? null : durationS * 1000,
      imgUrl: _normalizeCoverUrl(song['Image']),
      language: _parseLanguage(asJsonMap(song['trans_param'])['language']),
    );
  }

  SongInfo _parseSongFromLegacySearch(Map<String, Object?> song) {
    final List<String> artists =
        song['singername']?.toString().split('、') ?? const <String>[];
    final int? durationS = _parseInt(song['duration']);
    return SongInfo(
      source: source,
      id: song['album_audio_id']?.toString(),
      hash: song['hash']?.toString(),
      title: song['songname']?.toString(),
      subtitle: song['topic']?.toString(),
      artist: SongArtist(artists.where((String item) => item.isNotEmpty)),
      album: song['album_name']?.toString(),
      durationMs: durationS == null ? null : durationS * 1000,
      imgUrl: _normalizeCoverUrl(asJsonMap(song['trans_param'])['union_cover']),
      language: _parseLanguage(asJsonMap(song['trans_param'])['language']),
    );
  }

  SongListInfo _parseAlbumFromNewSearch(Map<String, Object?> album) {
    return SongListInfo(
      source: source,
      type: SongListType.album,
      id: album['albumid']?.toString() ?? '',
      title: album['albumname']?.toString() ?? '',
      imgUrl: album['img']?.toString() ?? '',
      songCount: _resolveAlbumSongCount(album),
      publishTimeS: _parseUtc8DateToEpochSeconds(album['publish_time']),
      // 对齐线上字段漂移：新旧接口统一按 singer -> singername -> nickname 回退。
      author: _resolveAlbumAuthor(album),
    );
  }

  SongListInfo _parseAlbumFromLegacySearch(Map<String, Object?> album) {
    return SongListInfo(
      source: source,
      type: SongListType.album,
      id: album['albumid']?.toString() ?? '',
      title: album['albumname']?.toString() ?? '',
      imgUrl: album['imgurl']?.toString() ?? '',
      songCount: _resolveAlbumSongCount(album),
      publishTimeS: _parseUtc8DateToEpochSeconds(album['publishtime']),
      // 旧接口 album 在部分地域仅返回 singername，必须兼容以避免空作者或异常。
      author: _resolveAlbumAuthor(album),
    );
  }

  SongListInfo _parseSonglistFromNewSearch(Map<String, Object?> songlist) {
    return SongListInfo(
      source: source,
      type: SongListType.songlist,
      id: songlist['gid']?.toString() ?? '',
      title: songlist['specialname']?.toString() ?? '',
      imgUrl: songlist['img']?.toString() ?? '',
      songCount: _parseInt(songlist['song_count']),
      publishTimeS: _parseUtc8DateToEpochSeconds(songlist['publish_time']),
      author: songlist['nickname']?.toString() ?? '',
    );
  }

  SongListInfo _parseSonglistFromLegacySearch(Map<String, Object?> songlist) {
    return SongListInfo(
      source: source,
      type: SongListType.songlist,
      id: songlist['specialid']?.toString() ?? '',
      title: songlist['specialname']?.toString() ?? '',
      imgUrl: songlist['imgurl']?.toString() ?? '',
      songCount: _parseInt(songlist['songcount']),
      publishTimeS: _parseUtc8DateToEpochSeconds(songlist['publishtime']),
      author: songlist['nickname']?.toString() ?? '',
    );
  }

  SongInfo _parseSongFromAlbumSonglist(Map<String, Object?> song) {
    final Map<String, Object?> base = asJsonMap(song['base']);
    final Map<String, Object?> audioInfo = asJsonMap(song['audio_info']);
    final Map<String, Object?> albumInfo = asJsonMap(song['album_info']);
    final Map<String, Object?> transParam = asJsonMap(song['trans_param']);
    final String subtitle = transParam['songname_suffix']?.toString() ?? '';
    final String title = _removeSuffix(
      base['audio_name']?.toString() ?? '',
      subtitle,
    );

    return SongInfo(
      source: source,
      id: base['album_audio_id']?.toString(),
      hash: audioInfo['hash']?.toString(),
      title: title,
      subtitle: subtitle,
      artist: SongArtist(
        (base['author_name']?.toString() ?? '')
            .split('、')
            .where((String item) => item.isNotEmpty),
      ),
      album: albumInfo['album_name']?.toString(),
      durationMs: _parseInt(audioInfo['duration']),
      imgUrl: _normalizeCoverUrl(transParam['union_cover']),
      language: _parseLanguage(transParam['language']),
    );
  }

  SongInfo _parseSongFromSonglistSongs(Map<String, Object?> song) {
    final String name = song['name']?.toString() ?? '';
    final String title = _splitSonglistTitle(name);
    final List<String> artists = <String>[
      for (final Object? singer in asJsonList(song['singerinfo']))
        if (asJsonMap(singer)['name']?.toString().isNotEmpty ?? false)
          asJsonMap(singer)['name']!.toString(),
    ];

    return SongInfo(
      source: source,
      id: song['mixsongid']?.toString(),
      hash: song['hash']?.toString(),
      title: title,
      subtitle: song['remark']?.toString(),
      artist: SongArtist(artists),
      album: asJsonMap(song['albuminfo'])['name']?.toString(),
      durationMs: _parseInt(song['timelen']),
      imgUrl: _normalizeCoverUrl(song['cover']),
      language: _parseLanguage(asJsonMap(song['trans_param'])['language']),
    );
  }

  int? _parseUtc8DateToEpochSeconds(Object? value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    if (text.isEmpty || text == '0000-00-00' || text == '0000-00-00 00:00:00') {
      return null;
    }

    final RegExpMatch? match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}):(\d{2}))?$',
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);
    final int hour = int.tryParse(match.group(4) ?? '0') ?? 0;
    final int minute = int.tryParse(match.group(5) ?? '0') ?? 0;
    final int second = int.tryParse(match.group(6) ?? '0') ?? 0;

    // 对齐Python版：输入按东八区本地时间解释，再转换为 UTC 秒。
    final DateTime utc = DateTime.utc(
      year,
      month,
      day,
      hour - 8,
      minute,
      second,
    );
    return utc.millisecondsSinceEpoch ~/ 1000;
  }

  Language _parseLanguage(Object? value) {
    final String key = value?.toString() ?? '';
    return _languageMapping[key] ?? Language.other;
  }

  String _removeSuffix(String value, String suffix) {
    if (suffix.isEmpty || !value.endsWith(suffix)) {
      return value;
    }
    return value.substring(0, value.length - suffix.length);
  }

  String _splitSonglistTitle(String value) {
    final int index = value.indexOf(' - ');
    if (index < 0) {
      return value;
    }
    return value.substring(index + 3);
  }

  static bool _isNonEmpty(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  static String _resolveAlbumAuthor(Map<String, Object?> album) {
    for (final String key in <String>['singer', 'singername', 'nickname']) {
      final String? value = album[key]?.toString();
      if (_isNonEmpty(value)) {
        return value!.trim();
      }
    }
    return '';
  }

  static int? _resolveAlbumSongCount(Map<String, Object?> album) {
    return _parseInt(album['songcount']) ?? _parseInt(album['song_count']);
  }

  String? _normalizeCoverUrl(Object? rawValue) {
    final String value = rawValue?.toString().trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    // 对齐Python版：统一将占位尺寸替换为 240。
    return value.replaceAll('{size}', '240');
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
}
