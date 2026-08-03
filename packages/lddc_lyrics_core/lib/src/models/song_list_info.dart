import 'model_helpers.dart';
import 'model_enums.dart';

/// 歌单/专辑信息实体，对齐Python版 `SongListInfo`。
class SongListInfo implements SourceAware {
  const SongListInfo({
    required this.source,
    required this.type,
    required this.id,
    required this.title,
    required this.imgUrl,
    required this.songCount,
    required this.publishTimeS,
    required this.author,
    this.mid,
  });

  @override
  final Source source;
  final SongListType type;
  final String id;
  final String title;
  final String imgUrl;
  final int? songCount;
  final int? publishTimeS;
  final String author;
  final String? mid;

  /// 发行日期（UTC）格式化输出，格式 `yyyy-MM-dd`。
  String get formattedPublishTime {
    if (publishTimeS == null) {
      return '';
    }
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(
      publishTimeS! * 1000,
      isUtc: true,
    );
    final String year = time.year.toString().padLeft(4, '0');
    final String month = time.month.toString().padLeft(2, '0');
    final String day = time.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  SongListInfo copyWith({
    Source? source,
    SongListType? type,
    String? id,
    String? title,
    String? imgUrl,
    Object? songCount = copyWithSentinel,
    Object? publishTimeS = copyWithSentinel,
    String? author,
    Object? mid = copyWithSentinel,
  }) {
    return SongListInfo(
      source: source ?? this.source,
      type: type ?? this.type,
      id: id ?? this.id,
      title: title ?? this.title,
      imgUrl: imgUrl ?? this.imgUrl,
      songCount: identical(songCount, copyWithSentinel)
          ? this.songCount
          : songCount as int?,
      publishTimeS: identical(publishTimeS, copyWithSentinel)
          ? this.publishTimeS
          : publishTimeS as int?,
      author: author ?? this.author,
      mid: identical(mid, copyWithSentinel) ? this.mid : mid as String?,
    );
  }

  /// 转换为可序列化字典，键名与Python版保持一致。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'source': source.value,
      'type': type.value,
      'id': id,
      'title': title,
      'imgurl': imgUrl,
      'songcount': songCount,
      'publishtime': publishTimeS,
      'author': author,
      if (mid != null) 'mid': mid,
    };
  }

  factory SongListInfo.fromMap(Map<String, Object?> map) {
    final Object? source = map['source'];
    final Object? type = map['type'];
    if (source == null || type == null) {
      throw ArgumentError.value(map, 'map', 'source/type is required');
    }
    return SongListInfo(
      source: Source.fromValue(source),
      type: SongListType.fromValue(type),
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      imgUrl: map['imgurl']?.toString() ?? '',
      songCount: parseNullableInt(map['songcount']),
      publishTimeS: parseNullableInt(map['publishtime']),
      author: map['author']?.toString() ?? '',
      mid: map['mid']?.toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SongListInfo &&
            source == other.source &&
            type == other.type &&
            id == other.id &&
            title == other.title &&
            imgUrl == other.imgUrl &&
            songCount == other.songCount &&
            publishTimeS == other.publishTimeS &&
            author == other.author &&
            mid == other.mid);
  }

  @override
  int get hashCode => Object.hash(
    source,
    type,
    id,
    title,
    imgUrl,
    songCount,
    publishTimeS,
    author,
    mid,
  );
}
