import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'model_helpers.dart';
import 'model_enums.dart';
import 'song_info.dart';

/// 歌词信息实体，对齐Python版 `LyricInfo`。
class LyricInfo implements SourceAware {
  LyricInfo({
    required this.source,
    required this.songInfo,
    this.id,
    this.accessKey,
    this.durationMs,
    this.creator,
    this.score,
    this.path,
    Uint8List? data,
    this.cached = false,
  }) : _data = data == null ? null : Uint8List.fromList(data);

  @override
  final Source source;
  final SongInfo songInfo;
  final String? id;
  final String? accessKey;
  final int? durationMs;
  final String? creator;
  final int? score;
  final String? path;
  final Uint8List? _data;
  final bool cached;

  /// 歌词原始字节副本。
  ///
  /// getter 每次返回新列表，避免调用方原地修改后破坏模型相等性、hashCode 或缓存键。
  Uint8List? get data => _data == null ? null : Uint8List.fromList(_data);

  /// 时长格式化输出（`mm:ss`）。
  String get formattedDuration {
    return formatDurationMmSs(durationMs);
  }

  LyricInfo copyWith({
    Source? source,
    SongInfo? songInfo,
    Object? id = copyWithSentinel,
    Object? accessKey = copyWithSentinel,
    Object? durationMs = copyWithSentinel,
    Object? creator = copyWithSentinel,
    Object? score = copyWithSentinel,
    Object? path = copyWithSentinel,
    Object? data = copyWithSentinel,
    bool? cached,
  }) {
    return LyricInfo(
      source: source ?? this.source,
      songInfo: songInfo ?? this.songInfo,
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
      data: identical(data, copyWithSentinel) ? _data : data as Uint8List?,
      cached: cached ?? this.cached,
    );
  }

  /// 转换为可序列化字典，键名与Python版保持一致。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'source': source.value,
      'songinfo': songInfo.toMap(),
      if (id != null) 'id': id,
      if (accessKey != null) 'accesskey': accessKey,
      if (durationMs != null) 'duration': durationMs,
      if (creator != null) 'creator': creator,
      if (score != null) 'score': score,
      if (path != null) 'path': path,
      if (_data != null) 'data': Uint8List.fromList(_data),
      'cached': cached,
    };
  }

  factory LyricInfo.fromMap(Map<String, Object?> map) {
    final Object? source = map['source'];
    if (source == null) {
      throw ArgumentError.value(map, 'map', 'source is required');
    }

    final SongInfo songInfo;
    final Object? songInfoRaw = map['songinfo'];
    if (songInfoRaw is Map<String, Object?>) {
      songInfo = SongInfo.fromMap(songInfoRaw);
    } else if (songInfoRaw is SongInfo) {
      songInfo = songInfoRaw;
    } else {
      songInfo = SongInfo.fromMap(map);
    }

    return LyricInfo(
      source: Source.fromValue(source),
      songInfo: songInfo,
      id: map['id']?.toString(),
      accessKey: map['accesskey']?.toString(),
      durationMs: parseNullableInt(map['duration']),
      creator: map['creator']?.toString(),
      score: parseNullableInt(map['score']),
      path: _parsePath(map['path']),
      data: _parseData(map['data']),
      cached: map['cached'] is bool ? map['cached']! as bool : false,
    );
  }

  static String? _parsePath(Object? value) {
    if (value == null) {
      return null;
    }
    final String raw = value.toString();
    if (raw.startsWith('file://')) {
      return raw.substring('file://'.length);
    }
    return raw;
  }

  static Uint8List? _parseData(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Uint8List) {
      return Uint8List.fromList(value);
    }
    if (value is List<int>) {
      return _parseByteList(value);
    }
    if (value is List<Object?>) {
      return _parseByteList(value);
    }
    if (value is String) {
      return Uint8List.fromList(utf8.encode(value));
    }
    return null;
  }

  static Uint8List _parseByteList(Iterable<Object?> values) {
    final List<int> bytes = <int>[];
    int index = 0;
    for (final Object? value in values) {
      if (value is! int || value < 0 || value > 255) {
        throw ArgumentError.value(value, 'data[$index]', '必须是 0..255 的整数字节');
      }
      bytes.add(value);
      index += 1;
    }
    return Uint8List.fromList(bytes);
  }

  static bool _bytesEqual(Uint8List? left, Uint8List? right) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null) {
      return false;
    }
    return const ListEquality<int>().equals(left, right);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LyricInfo &&
            source == other.source &&
            songInfo == other.songInfo &&
            id == other.id &&
            accessKey == other.accessKey &&
            durationMs == other.durationMs &&
            creator == other.creator &&
            score == other.score &&
            path == other.path &&
            _bytesEqual(_data, other._data) &&
            cached == other.cached);
  }

  @override
  int get hashCode => Object.hash(
    source,
    songInfo,
    id,
    accessKey,
    durationMs,
    creator,
    score,
    path,
    _data == null ? null : Object.hashAll(_data),
    cached,
  );
}
