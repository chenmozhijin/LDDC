import 'dart:collection';

import 'lyrics_models.dart';
import 'model_helpers.dart';
import 'model_enums.dart';
import 'song_info.dart';

/// 歌词聚合实体，对齐Python版 `Lyrics`/`LyricsBase` 的核心语义。
class Lyrics {
  Lyrics({
    required this.songInfo,
    required this.source,
    Map<String, LyricsData> data = const <String, LyricsData>{},
    Map<String, LyricsType> types = const <String, LyricsType>{},
    Map<String, String> tags = const <String, String>{},
    this.id,
    this.accessKey,
    this.durationMs,
    this.creator,
    this.score,
    this.path,
    this.cached = false,
  }) : data = _freezeData(data),
       types = UnmodifiableMapView<String, LyricsType>(
         Map<String, LyricsType>.from(types),
       ),
       tags = UnmodifiableMapView<String, String>(
         Map<String, String>.from(tags),
       );

  Lyrics._frozen({
    required this.songInfo,
    required this.source,
    required this.data,
    required this.types,
    required this.tags,
    required this.id,
    required this.accessKey,
    required this.durationMs,
    required this.creator,
    required this.score,
    required this.path,
    required this.cached,
  });

  final SongInfo songInfo;
  final Source source;
  final UnmodifiableMapView<String, LyricsData> data;
  final UnmodifiableMapView<String, LyricsType> types;
  final UnmodifiableMapView<String, String> tags;

  final String? id;
  final String? accessKey;
  final int? durationMs;
  final String? creator;
  final int? score;
  final String? path;
  final bool cached;

  /// 与Python版兼容的歌词级 mid 访问口。
  ///
  /// 当前 Flutter 模型未单独持有歌词级 mid，先复用 `songInfo.mid`
  /// 以保持桌面歌词自动缓存链路的回退顺序稳定。
  String? get mid => songInfo.mid;

  /// 按语言读取歌词数据（如 `orig/ts/roma`）。
  LyricsData? operator [](String key) => data[key];

  bool get hasLyrics =>
      data.values.any((LyricsData lyrics) => lyrics.isNotEmpty);

  bool get isEmpty => !hasLyrics;

  /// 纯音乐判定逻辑：
  /// 1. 语言被标记为 instrumental
  /// 2. 原文末行命中纯音乐提示文案
  bool isInstrumental() {
    if (songInfo.language == Language.instrumental) {
      return true;
    }
    final LyricsData? orig = data['orig'];
    if (orig == null || orig.isEmpty || orig.length >= 10) {
      return false;
    }
    final String tailText = orig.last.text.trim();
    return tailText == '此歌曲为没有填词的纯音乐，请您欣赏' || tailText == '纯音乐，请欣赏';
  }

  /// 获取歌词时长（毫秒）。
  ///
  /// 优先级：
  /// 1. `durationMs`
  /// 2. `songInfo.durationMs`
  /// 3. 从末行/末词时间戳回推
  ///
  /// 说明：这里保持毫秒单位，不做额外乘法。
  int getDurationMs() {
    if (durationMs != null) {
      return durationMs!;
    }
    if (songInfo.durationMs != null) {
      return songInfo.durationMs!;
    }

    final LyricsData? orig = data['orig'];
    if (orig != null && orig.isNotEmpty) {
      return _resolveLineEnd(orig.last) ?? 0;
    }

    for (final LyricsData lines in data.values) {
      if (lines.isNotEmpty) {
        return _resolveLineEnd(lines.last) ?? 0;
      }
    }
    return 0;
  }

  /// 对所有语言的行/词统一应用偏移量。
  Lyrics withOffset(int offsetMs) {
    final Map<String, LyricsData> shifted = <String, LyricsData>{};
    data.forEach((String lang, LyricsData lines) {
      shifted[lang] = lines
          .map((LyricsLine line) => line.withOffset(offsetMs))
          .toList(growable: false);
    });
    return copyWith(data: shifted);
  }

  /// 生成浅拷贝并覆写部分字段。
  Lyrics copyWith({
    SongInfo? songInfo,
    Source? source,
    Map<String, LyricsData>? data,
    Map<String, LyricsType>? types,
    Map<String, String>? tags,
    Object? id = copyWithSentinel,
    Object? accessKey = copyWithSentinel,
    Object? durationMs = copyWithSentinel,
    Object? creator = copyWithSentinel,
    Object? score = copyWithSentinel,
    Object? path = copyWithSentinel,
    bool? cached,
  }) {
    final UnmodifiableMapView<String, LyricsData> resolvedData =
        data == null || identical(data, this.data)
        ? this.data
        : _freezeData(data);
    final UnmodifiableMapView<String, LyricsType> resolvedTypes =
        types == null || identical(types, this.types)
        ? this.types
        : _freezeMap(types);
    final UnmodifiableMapView<String, String> resolvedTags =
        tags == null || identical(tags, this.tags)
        ? this.tags
        : _freezeMap(tags);
    return Lyrics._frozen(
      songInfo: songInfo ?? this.songInfo,
      source: source ?? this.source,
      data: resolvedData,
      types: resolvedTypes,
      tags: resolvedTags,
      id: identical(id, copyWithSentinel) ? this.id : id as String?,
      accessKey: identical(accessKey, copyWithSentinel)
          ? this.accessKey
          : accessKey as String?,
      durationMs: identical(durationMs, copyWithSentinel)
          ? this.durationMs
          : durationMs as int?,
      creator: identical(creator, copyWithSentinel)
          ? this.creator
          : creator as String?,
      score: identical(score, copyWithSentinel) ? this.score : score as int?,
      path: identical(path, copyWithSentinel) ? this.path : path as String?,
      cached: cached ?? this.cached,
    );
  }

  /// 构造纯音乐占位歌词。
  factory Lyrics.instrumental({required SongInfo songInfo, Source? source}) {
    return Lyrics(
      songInfo: songInfo,
      source: source ?? songInfo.source,
      // 对齐Python版修复：纯音乐占位歌词也应显式声明 orig 类型，避免转换链路缺键。
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      data: <String, LyricsData>{
        'orig': <LyricsLine>[
          LyricsLine(
            startMs: null,
            endMs: null,
            words: const <LyricsWord>[
              LyricsWord(startMs: null, endMs: null, text: '纯音乐，请欣赏'),
            ],
          ),
        ],
      },
    );
  }

  /// 冻结歌词数据，避免外部修改内部结构。
  static UnmodifiableMapView<String, LyricsData> _freezeData(
    Map<String, LyricsData> raw,
  ) {
    final Map<String, LyricsData> frozen = <String, LyricsData>{};
    raw.forEach((String lang, LyricsData lines) {
      frozen[lang] = List<LyricsLine>.unmodifiable(lines);
    });
    return UnmodifiableMapView<String, LyricsData>(frozen);
  }

  static UnmodifiableMapView<String, T> _freezeMap<T>(Map<String, T> raw) {
    return UnmodifiableMapView<String, T>(Map<String, T>.from(raw));
  }

  /// 从行结尾/末词时间推导行的结束时间。
  static int? _resolveLineEnd(LyricsLine line) {
    if (line.endMs != null) {
      return line.endMs;
    }
    if (line.words.isNotEmpty) {
      final LyricsWord tailWord = line.words.last;
      if (tailWord.endMs != null) {
        return tailWord.endMs;
      }
      if (tailWord.startMs != null) {
        return tailWord.startMs;
      }
    }
    return line.startMs;
  }
}
