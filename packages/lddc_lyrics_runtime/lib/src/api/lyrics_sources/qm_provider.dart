import 'dart:convert';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../lyrics_source/lyrics_source.dart';
import '../../network/request_cancellation.dart';
import '../json_api_reader.dart';
import 'qm_request_executor.dart';

/// QM provider，实现 `search/get_songlist/get_lyrics` 主链路。
class QmLyricsProvider
    implements LyricsCloudSourceProvider, ClosableLyricsSourceProvider {
  QmLyricsProvider({required this._client, LyricsDecryptor? decryptor})
    : _decryptor = decryptor ?? LyricsDecryptor();

  static final RegExp _alnumPattern = RegExp(r'^[a-zA-Z0-9]+$');
  static final RegExp _searchHighlightPattern = RegExp(
    r'</?em>',
    caseSensitive: false,
  );
  static const int _searchPageSize = 20;

  static const Map<SearchType, int> _searchTypeMapping = <SearchType, int>{
    SearchType.song: 0,
    SearchType.artist: 1,
    SearchType.album: 2,
    SearchType.songlist: 3,
  };

  static const Map<int, Language> _languageMapping = <int, Language>{
    9: Language.instrumental,
    5: Language.english,
    4: Language.korean,
    3: Language.japanese,
    1: Language.chinese,
    0: Language.chinese,
  };

  final QmApiClient _client;
  final LyricsDecryptor _decryptor;

  @override
  Future<void> close() => _client.close();

  @override
  Source get source => Source.qm;

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
      final SongInfo songInfo = await _getSongInfo(keyword.trim());
      return APIResultList<SourceAware>(
        <SourceAware>[songInfo],
        info: SearchInfo(
          source: source,
          keyword: keyword,
          searchType: searchType,
          page: page,
        ),
        ranges: const SourceRange(start: 0, end: 0, total: 1),
      );
    }

    await _client.init();
    final Map<String, Object?> param = <String, Object?>{
      'ver': 0,
      'search_id': _buildSearchId(),
      'sub_searchid': 0,
      'search_type': _searchTypeMapping[searchType],
      'query': keyword,
      'page_id': page,
      'page_num': _searchPageSize,
      'remoteplace': '',
      'highlight': 0,
      'nqc_flag': 0,
      'grp': 1,
      'multi_zhida': 1,
      'auto_page': 1,
      'from': '8,',
      'seqno': page,
    };
    final Map<String, Object?> data = await _request(
      method: 'do_search_v2',
      module: 'music.adaptor.SearchAdaptorQMMobile',
      param: param,
    );

    final SearchInfo info = SearchInfo(
      source: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
    final Map<String, Object?> body = asJsonMap(data['body']);
    final int start = (page - 1) * _searchPageSize;

    switch (searchType) {
      case SearchType.song:
        final List<Object?> items = _searchItems(
          body,
          'item_song',
          page: page,
          pageSize: _searchPageSize,
        );
        final List<SongInfo> songs = _formatSongInfos(items);
        return APIResultList<SourceAware>(
          songs,
          info: info,
          // 空页没有条目可供 APIResultList 推断来源，因此必须显式携带 QM 来源，
          // 否则 Python 基线中的 `[start, start - 1, total]` 会被模型静默丢弃。
          ranges: <Source, SourceRange>{
            source: SourceRange(
              start: start,
              end: start + songs.length - 1,
              total: _searchTotal(
                data: data,
                body: body,
                key: 'item_song',
                itemCount: songs.length,
                start: start,
              ),
            ),
          },
        );
      case SearchType.album:
        final List<Object?> items = _searchItems(
          body,
          'item_album',
          page: page,
          pageSize: _searchPageSize,
        );
        final List<SongListInfo> albums = _parseAlbumSearchResult(items);
        return APIResultList<SourceAware>(
          albums,
          info: info,
          ranges: <Source, SourceRange>{
            source: SourceRange(
              start: start,
              end: start + albums.length - 1,
              total: _searchTotal(
                data: data,
                body: body,
                key: 'item_album',
                itemCount: albums.length,
                start: start,
              ),
            ),
          },
        );
      case SearchType.songlist:
        final List<Object?> items = _searchItems(
          body,
          'item_songlist',
          page: page,
          pageSize: _searchPageSize,
        );
        final List<SongListInfo> songlists = _parseSonglistSearchResult(items);
        return APIResultList<SourceAware>(
          songlists,
          info: info,
          ranges: <Source, SourceRange>{
            source: SourceRange(
              start: start,
              end: start + songlists.length - 1,
              total: _searchTotal(
                data: data,
                body: body,
                key: 'item_songlist',
                itemCount: songlists.length,
                start: start,
              ),
            ),
          },
        );
      default:
        throw LddcApiParamsException('不支持的搜索类型: ${searchType.value}');
    }
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    final Map<String, Object?> data = switch (songListInfo.type) {
      SongListType.album => await _request(
        method: 'GetAlbumSongList',
        module: 'music.musichallAlbum.AlbumSongList',
        param: <String, Object?>{
          'albumID': int.tryParse(songListInfo.id) ?? 0,
          'order': 2,
          'begin': 0,
          'num': -1,
        },
      ),
      SongListType.songlist => await _request(
        method: 'CgiGetDiss',
        module: 'srf_diss_info.DissInfoServer',
        param: <String, Object?>{
          'disstid': int.tryParse(songListInfo.id) ?? 0,
          'dirid': 0,
          'onlysonglist': 0,
          'song_begin': 0,
          'song_num': -1,
          'userinfo': 1,
          'pic_dpi': 800,
          'orderlist': 1,
        },
      ),
    };

    final List<SongInfo> songs = switch (songListInfo.type) {
      SongListType.album => _formatSongInfos(
        asJsonList(data['songList'])
            .map((Object? item) {
              return asJsonMap(item)['songInfo'];
            })
            .toList(growable: false),
      ),
      SongListType.songlist => _formatSongInfos(data['songlist']),
    };

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
    throw const LddcApiNotSupportedException('来源 QM 不支持歌词候选列表');
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    if (info is! SongInfo) {
      throw const LddcApiParamsException('QM getLyrics 仅支持 SongInfo');
    }
    final SongInfo songInfo = info;
    if (songInfo.title == null ||
        songInfo.album == null ||
        !_isNonEmpty(songInfo.id) ||
        songInfo.durationMs == null) {
      throw const LddcApiParamsException('缺少必要参数');
    }

    final String title = songInfo.title!;
    final String album = songInfo.album!;
    final String id = songInfo.id!;
    final String singerName = songInfo.artist == null
        ? ''
        : songInfo.artist!.toString();
    final Map<String, Object?> data = await _request(
      method: 'GetPlayLyricInfo',
      module: 'music.musichallSong.PlayLyricInfo',
      param: <String, Object?>{
        'ct': 11,
        'cv': 14100508,
        'gt': 1,
        'cid': '111',
        'cmd': 0,
        'num': 1,
        'songID': int.tryParse(id) ?? 0,
        'type': 1,
        'songName': base64Encode(utf8.encode(title)),
        'singerName': base64Encode(utf8.encode(singerName)),
        'albumName': base64Encode(utf8.encode(album)),
        'qrc': 1,
        'trans': 1,
        'roma': 1,
        'lrc_t': 0,
        'qrc_t': 0,
        'trans_t': 0,
        'roma_t': 0,
        'crypt': 0,
        'searchID': '618875166264707082',
        'modify': 0,
        'needSingingAnnotations': false,
        'singingAnnotationsTs': 0,
      },
    );

    final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
    final Map<String, LyricsType> lyricsTypes = <String, LyricsType>{};
    final Map<String, String> tags = <String, String>{};

    const List<({String lang, String field})> mapping =
        <({String lang, String field})>[
          (lang: 'orig', field: 'lyric'),
          (lang: 'ts', field: 'trans'),
          (lang: 'roma', field: 'roma'),
        ];

    for (final ({String lang, String field}) item in mapping) {
      final String rawLyric = data[item.field]?.toString() ?? '';
      final Object? lyricsToken = _resolveLyricsToken(
        payload: data,
        remoteField: item.field,
      );
      if (rawLyric.isEmpty || lyricsToken?.toString() == '0') {
        continue;
      }

      String lyricText;
      try {
        if (item.lang == 'ts' || !_alnumPattern.hasMatch(rawLyric)) {
          lyricText = utf8.decode(base64Decode(rawLyric));
        } else {
          lyricText = _decryptor.decryptQrc(
            rawLyric,
            type: QrcDecryptType.cloud,
          );
        }
      } catch (error) {
        if (error is Error) {
          rethrow;
        }
        // 对齐Python版：单语言解析失败时跳过，不阻断其他语言。
        continue;
      }

      final ({Map<String, String> tags, LyricsData lyricsData}) parsed =
          parseQrcString(lyricText);
      if (item.lang == 'orig') {
        tags.addAll(parsed.tags);
      }
      if (parsed.lyricsData.isEmpty) {
        continue;
      }
      lyricsData[item.lang] = parsed.lyricsData;
      lyricsTypes[item.lang] = judgeLyricsType(parsed.lyricsData);
    }

    return Lyrics(
      songInfo: songInfo,
      source: source,
      data: lyricsData,
      types: lyricsTypes,
      tags: tags,
    );
  }

  Future<SongInfo> _getSongInfo(String songId) async {
    if (songId.isEmpty || !RegExp(r'^\d+$').hasMatch(songId)) {
      throw LddcApiParamsException('歌曲id格式不正确: $songId');
    }
    final Map<String, Object?> data = await _request(
      method: 'CgiGetTrackInfo',
      module: 'music.trackInfo.UniformRuleCtrl',
      param: <String, Object?>{
        'ids': <int>[int.parse(songId)],
        'mids': const <Object?>[],
        'types': const <int>[1],
        'scene': 0,
        'modify_stamp': const <int>[0],
        'ctx': 0,
        'client': 1,
      },
    );
    final List<SongInfo> songs = _formatSongInfos(data['tracks']);
    if (songs.isEmpty) {
      throw LddcApiRequestException('获取歌曲信息失败 songid:$songId');
    }
    return songs.first;
  }

  Future<Map<String, Object?>> _request({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) async {
    try {
      return await _client.request(
        method: method,
        module: module,
        param: param,
      );
    } on LddcApiRequestException {
      rethrow;
    } catch (error) {
      throw LddcApiRequestException('QM API请求失败: $error');
    }
  }

  String _buildSearchId() {
    final DateTime now = DateTime.now();
    final DateTime yearStart = DateTime(now.year);
    final int secondsFromYearStart = now.difference(yearStart).inSeconds;
    final int uid = int.tryParse(_client.sessionUid) ?? 0;
    final BigInt value =
        ((BigInt.from(2147483647) * BigInt.from(secondsFromYearStart)) +
                BigInt.from(uid)) *
            BigInt.from(10) +
        BigInt.from(2);
    return '$value,';
  }

  List<Object?> _searchItems(
    Map<String, Object?> body,
    String key, {
    required int page,
    required int pageSize,
  }) {
    final Object? value = body[key];
    final List<Object?> items = value is Map
        ? asJsonList(asJsonMap(value)['items'])
        : asJsonList(value);
    if (items.length <= pageSize) {
      return items;
    }

    // QM 线上响应可能把前面页一起返回，例如第 2 页返回 40 条。
    // 必须在映射领域对象前截取当前 20 条窗口，否则范围会重叠、列表会重复，
    // 下一次分页还会因为累计数量被放大而跳过真实页码。
    final int start = (page - 1) * pageSize;
    if (start >= items.length) {
      return const <Object?>[];
    }
    final int requestedEnd = start + pageSize;
    final int end = requestedEnd < items.length ? requestedEnd : items.length;
    return items.sublist(start, end);
  }

  int _searchTotal({
    required Map<String, Object?> data,
    required Map<String, Object?> body,
    required String key,
    required int itemCount,
    required int start,
  }) {
    final Object? value = body[key];
    if (value is Map) {
      final Map<String, Object?> wrapped = asJsonMap(value);
      for (final String totalKey in const <String>[
        'total_num',
        'estimate_sum',
      ]) {
        final int? total = _parseInt(wrapped[totalKey]);
        if (total != null && total > 0) {
          final int loadedUpperBound = start + itemCount;
          return total < loadedUpperBound ? loadedUpperBound : total;
        }
      }
    }
    final int? metaTotal = _parseInt(asJsonMap(data['meta'])['sum']);
    if (metaTotal != null && metaTotal > 0) {
      final int loadedUpperBound = start + itemCount;
      return metaTotal < loadedUpperBound ? loadedUpperBound : metaTotal;
    }
    return start + itemCount;
  }

  Object? _resolveLyricsToken({
    required Map<String, Object?> payload,
    required String remoteField,
  }) {
    if (remoteField != 'lyric') {
      return payload['${remoteField}_t'];
    }
    final Object? qrcToken = payload['qrc_t'];
    if (qrcToken is int && qrcToken == 0) {
      return payload['lrc_t'];
    }
    return qrcToken;
  }

  List<SongInfo> _formatSongInfos(Object? rawSongInfos) {
    final List<SongInfo> songs = <SongInfo>[];
    for (final Object? item in asJsonList(rawSongInfos)) {
      final Map<String, Object?> info = asJsonMap(item);
      final Map<String, Object?> album = asJsonMap(info['album']);
      // 对齐 Python 版：只要 name 键存在就采用其值；只有键不存在时才回退 title。
      final String albumName = _plainSearchText(
        album.containsKey('name')
            ? album['name']?.toString() ?? ''
            : album['title']?.toString() ?? '',
      );
      final int? intervalS = _parseInt(info['interval']);
      final List<String> singers = <String>[];
      for (final Object? singerItem in asJsonList(info['singer'])) {
        final String singerName = _plainSearchText(
          asJsonMap(singerItem)['name']?.toString() ?? '',
        );
        if (singerName.isNotEmpty) {
          singers.add(singerName);
        }
      }
      songs.add(
        SongInfo(
          source: source,
          id: info['id']?.toString(),
          mid: info['mid']?.toString(),
          title: _plainSearchTextNullable(info['title']),
          subtitle: _plainSearchTextNullable(info['subtitle']),
          artist: SongArtist(singers),
          album: albumName,
          durationMs: intervalS == null ? null : intervalS * 1000,
          // 按每首歌曲的 album.pmid 生成封面地址。
          imgUrl: _buildSongCoverUrl(album['pmid']),
          language:
              _languageMapping[_parseInt(info['language']) ?? -1] ??
              Language.other,
        ),
      );
    }
    return songs;
  }

  List<SongListInfo> _parseAlbumSearchResult(Object? rawItems) {
    final List<SongListInfo> albums = <SongListInfo>[];
    for (final Object? item in asJsonList(rawItems)) {
      final Map<String, Object?> album = asJsonMap(item);
      albums.add(
        SongListInfo(
          source: source,
          type: SongListType.album,
          id: album['id']?.toString() ?? '',
          mid: album['albummid']?.toString(),
          title: _plainSearchText(album['name']?.toString()),
          imgUrl: album['pic']?.toString() ?? '',
          songCount: _parseInt(album['song_num']),
          publishTimeS: _parseUtc8DateToEpochSeconds(
            album['publish_date']?.toString(),
          ),
          author: _plainSearchText(album['singer']?.toString()),
        ),
      );
    }
    return albums;
  }

  List<SongListInfo> _parseSonglistSearchResult(Object? rawItems) {
    final List<SongListInfo> songlists = <SongListInfo>[];
    for (final Object? item in asJsonList(rawItems)) {
      final Map<String, Object?> songlist = asJsonMap(item);
      songlists.add(
        SongListInfo(
          source: source,
          type: SongListType.songlist,
          id: songlist['dissid']?.toString() ?? '',
          title: _plainSearchText(songlist['dissname']?.toString()),
          imgUrl: songlist['logo']?.toString() ?? '',
          songCount: _parseInt(songlist['songnum']),
          publishTimeS: _parseUtc8DateToEpochSeconds(
            songlist['createtime']?.toString(),
          ),
          author: _plainSearchText(songlist['nickname']?.toString()),
        ),
      );
    }
    return songlists;
  }

  String? _buildSongCoverUrl(Object? albumPmidRaw) {
    final String albumPmid = albumPmidRaw?.toString().trim() ?? '';
    if (albumPmid.isEmpty) {
      return null;
    }
    return 'https://y.qq.com/music/photo_new/T002R300x300M000$albumPmid.jpg';
  }

  /// QM 即使收到 `highlight=0`，部分搜索类型仍可能返回 `<em>` 标记。
  /// 这里只移除协议明确使用的高亮标签，不尝试解析任意 HTML，避免改变真实
  /// 歌名中的尖括号文本或引入额外解析依赖。
  static String _plainSearchText(String? value) {
    return (value ?? '').replaceAll(_searchHighlightPattern, '');
  }

  static String? _plainSearchTextNullable(Object? value) {
    if (value == null) {
      return null;
    }
    return _plainSearchText(value.toString());
  }

  int? _parseUtc8DateToEpochSeconds(String? text) {
    if (text == null) {
      return null;
    }
    final String normalized = text.trim();
    if (normalized.isEmpty || normalized == '0000-00-00') {
      return null;
    }
    final RegExpMatch? match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}):(\d{2}))?$',
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }

    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);
    final int hour = int.tryParse(match.group(4) ?? '0') ?? 0;
    final int minute = int.tryParse(match.group(5) ?? '0') ?? 0;
    final int second = int.tryParse(match.group(6) ?? '0') ?? 0;

    // Python版按东八区时间解析后转 UTC 秒，这里等效减去 8 小时。
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

  static bool _isNonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;

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
