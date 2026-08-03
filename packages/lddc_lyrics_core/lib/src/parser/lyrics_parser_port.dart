import 'dart:collection';
import 'dart:typed_data';

import '../models/models.dart';
import 'parser_format.dart';

/// 解析输入：歌词字节流与可选路径。
class LyricsParserRequest {
  LyricsParserRequest({required Uint8List data, this.path})
    : _data = Uint8List.fromList(data).asUnmodifiableView();

  final Uint8List _data;
  final String? path;

  /// 返回构造时冻结的只读字节视图。
  ///
  /// 请求会在构造边界复制调用方缓冲区，后续 dispatcher 和具体解析器可以共享
  /// 同一份只读数据，不必在每次格式探测时再次复制完整歌词文件。
  Uint8List get data => _data;

  /// 规范化扩展名（包含点号，例如 `.lrc`），不存在时返回 `null`。
  String? get normalizedExtension {
    final String? rawPath = path;
    if (rawPath == null || rawPath.trim().isEmpty) {
      return null;
    }

    final int queryIndex = rawPath.indexOf('?');
    final String pathWithoutQuery = queryIndex < 0
        ? rawPath
        : rawPath.substring(0, queryIndex);
    final String normalizedPath = pathWithoutQuery.replaceAll('\\', '/');
    final int slashIndex = normalizedPath.lastIndexOf('/');
    final String fileName = normalizedPath.substring(slashIndex + 1);
    final int dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
      return null;
    }
    return fileName.substring(dotIndex).toLowerCase();
  }
}

/// 解析层附带的歌词元信息（用于 JSON-LRC 等可内嵌 info 的格式）。
class ParsedLyricsMetadata {
  const ParsedLyricsMetadata({
    this.songInfo,
    this.source,
    this.id,
    this.accessKey,
    this.durationMs,
    this.creator,
    this.score,
    this.path,
    this.cached,
  });

  final SongInfo? songInfo;
  final Source? source;
  final String? id;
  final String? accessKey;
  final int? durationMs;
  final String? creator;
  final int? score;
  final String? path;
  final bool? cached;
}

/// 解析输出（中间载荷）：标签 + 多语言歌词 + 可选内嵌元信息。
class ParsedLyricsPayload {
  ParsedLyricsPayload({
    Map<String, String> tags = const <String, String>{},
    Map<String, LyricsData> lyricsData = const <String, LyricsData>{},
    this.embeddedInfo,
    this.sourceHint,
  }) : tags = UnmodifiableMapView<String, String>(
         Map<String, String>.from(tags),
       ),
       lyricsData = _freezeLyricsData(lyricsData);

  final UnmodifiableMapView<String, String> tags;
  final UnmodifiableMapView<String, LyricsData> lyricsData;
  final ParsedLyricsMetadata? embeddedInfo;
  final Source? sourceHint;

  static UnmodifiableMapView<String, LyricsData> _freezeLyricsData(
    Map<String, LyricsData> source,
  ) {
    final Map<String, LyricsData> frozen = <String, LyricsData>{};
    source.forEach((String key, LyricsData value) {
      frozen[key] = List<LyricsLine>.unmodifiable(value);
    });
    return UnmodifiableMapView<String, LyricsData>(frozen);
  }
}

/// 歌词解析器端口：后续具体格式实现统一挂接此接口。
abstract interface class LyricsParserPort {
  Set<LyricsParserFormat> get supportedFormats;

  ParsedLyricsPayload parse({
    required LyricsParserFormat format,
    required LyricsParserRequest request,
  });
}
