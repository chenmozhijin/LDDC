import '../error/error.dart';
import '../models/models.dart';
import 'lyrics_parser_port.dart';

ParsedLyricsPayload parseJsonLrcToMultiResult(Object? jsonData) {
  if (jsonData is! Map<String, dynamic>) {
    throw const LddcLyricsFormatException('JSON歌词数据必须是一个字典');
  }

  for (final (String key, Type type) in <(String, Type)>[
    ('version', int),
    ('info', Map),
    ('tags', Map),
    ('lyrics', Map),
  ]) {
    if (!jsonData.containsKey(key)) {
      throw LddcLyricsFormatException('JSON歌词数据缺少必要的键: $key');
    }
    if (!_isTypeMatch(jsonData[key], type)) {
      throw LddcLyricsFormatException('JSON歌词数据中包含值类型不正确的键: $key');
    }
  }

  if ((jsonData['version'] as int) > 1) {
    throw const LddcLyricsFormatException('JSON歌词数据版本号不正确');
  }

  final Map<String, dynamic> info = jsonData['info'] as Map<String, dynamic>;
  for (final MapEntry<String, dynamic> entry in info.entries) {
    final String key = entry.key;
    final dynamic value = entry.value;

    if (key == 'source' && value is String) {
      if (!_isValidSourceMember(value)) {
        throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $value');
      }
      continue;
    }

    final bool wrongType =
        ((key == 'source' ||
                key == 'title' ||
                key == 'album' ||
                key == 'mid' ||
                key == 'accesskey') &&
            value is! String) ||
        (key == 'duration' && value is! int) ||
        (key == 'artist' && value is! String && value is! List) ||
        (key == 'id' && value is! String && value is! int);
    if (wrongType) {
      throw LddcLyricsFormatException('JSON歌词数据中包含值类型不正确的键: $key');
    }
  }

  final Map<String, String> tags = <String, String>{};
  final Map<dynamic, dynamic> rawTags =
      jsonData['tags'] as Map<dynamic, dynamic>;
  for (final MapEntry<dynamic, dynamic> entry in rawTags.entries) {
    if (entry.key is! String) {
      throw LddcLyricsFormatException('JSON歌词数据中包含值类型不正确的键: ${entry.key}');
    }
    if (entry.value is! String) {
      throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: ${entry.value}');
    }
    tags[entry.key as String] = entry.value as String;
  }

  final Map<String, LyricsData> lyricsData = <String, LyricsData>{};
  final Map<dynamic, dynamic> rawLyrics =
      jsonData['lyrics'] as Map<dynamic, dynamic>;
  for (final MapEntry<dynamic, dynamic> entry in rawLyrics.entries) {
    if (entry.key is! String) {
      throw LddcLyricsFormatException('JSON歌词数据中包含不正确的键: ${entry.key}');
    }
    final String key = entry.key as String;
    final dynamic value = entry.value;
    if (value is! List<dynamic>) {
      throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $value');
    }

    final LyricsData lines = <LyricsLine>[];
    for (final dynamic lineValue in value) {
      if (lineValue is! List<dynamic> || lineValue.length < 3) {
        throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $lineValue');
      }
      final int? lineStart = _asNullableInt(lineValue[0]);
      final int? lineEnd = _asNullableInt(lineValue[1]);
      final dynamic wordsValue = lineValue[2];
      if (wordsValue is! List<dynamic>) {
        throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $lineValue');
      }

      final List<LyricsWord> words = <LyricsWord>[
        for (final dynamic word in wordsValue) _parseWord(word),
      ];
      lines.add(LyricsLine(startMs: lineStart, endMs: lineEnd, words: words));
    }
    lyricsData[key] = lines;
  }

  final ParsedLyricsMetadata embeddedInfo = _parseEmbeddedInfo(info);

  return ParsedLyricsPayload(
    tags: tags,
    lyricsData: lyricsData,
    embeddedInfo: embeddedInfo,
    sourceHint: embeddedInfo.songInfo?.source ?? embeddedInfo.source,
  );
}

LyricsWord _parseWord(dynamic word) {
  if (word is! List<dynamic> || word.length < 3) {
    throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $word');
  }
  return LyricsWord(
    startMs: _asNullableInt(word[0]),
    endMs: _asNullableInt(word[1]),
    text: word[2].toString(),
  );
}

int? _asNullableInt(Object? value) {
  return switch (value) {
    null => null,
    int v => v,
    num v => v.toInt(),
    _ => throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $value'),
  };
}

bool _isTypeMatch(Object? value, Type expected) {
  if (expected == int) {
    return value is int;
  }
  if (expected == Map) {
    return value is Map;
  }
  return false;
}

bool _isValidSourceMember(String value) {
  const Set<String> members = <String>{
    'MULTI',
    'QM',
    'KG',
    'NE',
    'LRCLIB',
    'Local',
  };
  return members.contains(value);
}

ParsedLyricsMetadata _parseEmbeddedInfo(Map<String, dynamic> info) {
  SongInfo? songInfo;
  Source? source = _tryParseSource(info['source']);
  final Object? rawSongInfo = info['songinfo'];
  final Map<String, Object?>? nestedSongInfo = rawSongInfo is Map
      ? _stringObjectMap(rawSongInfo)
      : null;

  if (nestedSongInfo != null) {
    final Map<String, Object?> normalizedSongInfo = Map<String, Object?>.from(
      nestedSongInfo,
    );
    normalizedSongInfo['source'] ??= info['source'];
    if (normalizedSongInfo['source'] != null) {
      songInfo = _parseSongInfo(normalizedSongInfo);
      source = songInfo.source;
    }
  } else if (info['source'] != null) {
    // 兼容早期手写 JSON-LRC：歌曲字段直接平铺在 info 顶层时仍可读取。
    songInfo = _parseSongInfo(_stringObjectMap(info));
    source = songInfo.source;
  }

  return ParsedLyricsMetadata(
    songInfo: songInfo,
    source: source,
    id: info['id']?.toString(),
    accessKey: info['accesskey']?.toString(),
    durationMs: switch (info['duration']) {
      int v => v,
      num v => v.toInt(),
      _ => null,
    },
    creator: info['creator'] is String ? info['creator'] as String : null,
    score: switch (info['score']) {
      int v => v,
      num v => v.toInt(),
      _ => null,
    },
    path: info['path']?.toString(),
    cached: info['cached'] is bool ? info['cached'] as bool : null,
  );
}

Map<String, Object?> _stringObjectMap(Map<Object?, Object?> map) {
  return <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in map.entries)
      entry.key.toString(): entry.value,
  };
}

Source? _tryParseSource(Object? value) {
  if (value == null) {
    return null;
  }
  try {
    return Source.fromValue(value);
  } on ArgumentError {
    throw LddcLyricsFormatException('JSON歌词数据中包含不正确的值: $value');
  }
}

SongInfo _parseSongInfo(Map<String, Object?> info) {
  try {
    return SongInfo.fromMap(info);
  } on ArgumentError catch (error) {
    throw LddcLyricsFormatException('JSON歌词数据中包含不正确的歌曲信息: $error');
  }
}
