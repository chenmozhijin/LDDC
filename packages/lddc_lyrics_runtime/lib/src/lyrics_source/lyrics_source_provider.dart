import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../network/request_cancellation.dart';

/// 云端歌词源适配器端口。
abstract interface class LyricsCloudSourceProvider {
  Source get source;

  /// 是否支持“同一歌曲返回多条歌词候选”。
  ///
  /// 对齐Python版现状：
  /// - `KG` 支持候选歌词列表
  /// - 其余来源通常直接返回单条最佳歌词
  bool get supportsLyricsList;

  /// 当前来源支持的搜索类型集合。
  Set<SearchType> get supportedSearchTypes;

  /// 搜索入口：根据 [searchType] 返回歌曲或歌单结果。
  Future<APIResultList<SourceAware>> search({
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  });

  /// 获取歌单/专辑内歌曲列表。
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo);

  /// 获取某首歌可选歌词列表。
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo);

  /// 获取歌词详情。
  ///
  /// 入参语义对齐Python版：
  /// - `SongInfo`：由提供方自行选择歌词（通常首条）
  /// - `LyricInfo`：按指定歌词 id/accessKey 获取
  Future<Lyrics> getLyrics(Object info);
}

/// 可释放资源的歌词 provider。
///
/// 云端 provider 通常会间接持有 `HttpClient`。注册表销毁时只检查这个
/// 轻量接口，避免把“所有 provider 都必须有网络资源”的假设写死到业务端口里。
abstract interface class ClosableLyricsSourceProvider {
  Future<void> close();
}

/// 本地歌词请求上下文。
class LocalLyricsRequest {
  LocalLyricsRequest({this.info, this.path, Uint8List? data})
    : data = data == null ? null : Uint8List.fromList(data);

  final LyricInfo? info;
  final String? path;
  final Uint8List? data;
}

/// 本地歌词适配器端口。
abstract interface class LyricsLocalSourceProvider {
  Future<Lyrics> getLyrics(LocalLyricsRequest request);
}
