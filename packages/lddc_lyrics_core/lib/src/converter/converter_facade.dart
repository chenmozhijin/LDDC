import 'dart:convert';

import '../algorithm/algorithm.dart';
import '../error/lddc_exceptions.dart';
import '../models/models.dart';
import 'ass_converter.dart';
import 'converter_capability.dart';
import 'lrc_converter.dart';
import 'lyrics_convert_options.dart';
import 'srt_converter.dart';

const LyricsLineMatcher _lyricsLineMatcher = LyricsLineMatcher();

/// 对齐Python版 `core/converter/__init__.py::convert2`。
String convert2({
  required Lyrics lyrics,
  List<String>? langs,
  LyricsFormat lyricsFormat = LyricsFormat.verbatimLrc,
  int offsetMs = 0,
  LyricsConvertOptions? options,
}) {
  if (lyricsFormat == LyricsFormat.json) {
    if (langs != null && langs.isNotEmpty) {
      throw const LddcLyricsFormatException('JSON 格式不支持按语言筛选导出');
    }
    if (offsetMs != 0) {
      throw const LddcLyricsFormatException('JSON 格式不支持时间偏移导出');
    }
    return _pythonStyleJsonEncode(_encodeJsonLyrics(lyrics));
  }

  if (lyricsFormat == LyricsFormat.qrc ||
      lyricsFormat == LyricsFormat.krc ||
      lyricsFormat == LyricsFormat.yrc) {
    throw LddcLyricsFormatException('不支持导出歌词格式: ${lyricsFormat.value}');
  }

  if (langs == null || langs.isEmpty) {
    return '';
  }

  final LyricsConvertOptions effectiveOptions =
      options ?? LyricsConvertOptions();

  final _LyricsExportProjection projection = _selectLyricsForExport(
    lyrics: lyrics,
    requestedLangs: langs,
    configLangOrder: effectiveOptions.languageOrder,
    offsetMs: offsetMs,
  );

  if (projection.langsOrder.isEmpty) {
    return '';
  }
  final LyricsData? origLyrics = projection.data['orig'];
  if (origLyrics == null) {
    throw const LddcLyricsFormatException('歌词数据缺少 orig 语言，无法执行转换');
  }

  final Map<String, Map<int, int>> langsMapping = <String, Map<int, int>>{
    for (final String lang in projection.langsOrder)
      if (lang != 'orig' && lang != 'orig_lrc')
        lang: _lyricsLineMatcher.findClosestMatch(
          origLyrics,
          projection.data[lang] ?? <LyricsLine>[],
          data3: projection.data['orig_lrc'],
          source: lyrics.source,
        ),
  };

  LyricsFormat actualFormat = lyricsFormat;
  // 文件格式边界允许旧数据缺少类型信息，此时按逐行歌词处理；明确标记为
  // 纯文本时只能导出 LRC，避免用户选择 SRT/ASS 却得到扩展名与内容不符的文件。
  final LyricsType origType = projection.origType ?? LyricsType.lineByLine;
  if (origType == LyricsType.plainText) {
    if (!LyricsFormatCapabilities.isLrcFamily(lyricsFormat)) {
      throw const LddcLyricsFormatException('纯文本歌词缺少时间轴，无法导出为 SRT 或 ASS');
    }
    actualFormat = LyricsFormat.lineByLineLrc;
  }

  switch (actualFormat) {
    case LyricsFormat.verbatimLrc:
    case LyricsFormat.lineByLineLrc:
    case LyricsFormat.enhancedLrc:
      return lrcConverter(
        tags: lyrics.tags,
        lyricsData: projection.data,
        lyricsFormat: actualFormat,
        langsMapping: langsMapping,
        langsOrder: projection.langsOrder,
        lrcMsDigitCount: effectiveOptions.millisecondDigits,
        addEndTimestampLine: effectiveOptions.addEndTimestampLine,
        lastRefLineTimeStyle: effectiveOptions.lastReferenceLineStyle,
        lddcVersion: effectiveOptions.generatorVersion,
      );
    case LyricsFormat.srt:
      return srtConverter(
        lyricsData: projection.data,
        langsMapping: langsMapping,
        langsOrder: projection.langsOrder,
        durationMs: lyrics.durationMs,
      );
    case LyricsFormat.ass:
      return assConverter(
        title: lyrics.songInfo.title ?? lyrics.tags['ti'],
        durationMs: lyrics.durationMs,
        lyricsData: projection.data,
        langsMapping: langsMapping,
        langsOrder: projection.langsOrder,
        lddcVersion: effectiveOptions.generatorVersion,
      );
    case LyricsFormat.qrc:
    case LyricsFormat.krc:
    case LyricsFormat.yrc:
    case LyricsFormat.json:
      throw LddcLyricsFormatException('不支持导出歌词格式: ${actualFormat.value}');
  }
}

final class _LyricsExportProjection {
  const _LyricsExportProjection({
    required this.data,
    required this.origType,
    required this.langsOrder,
  });

  final MultiLyricsData data;
  final LyricsType? origType;
  final List<String> langsOrder;
}

_LyricsExportProjection _selectLyricsForExport({
  required Lyrics lyrics,
  required List<String> requestedLangs,
  required List<String> configLangOrder,
  required int offsetMs,
}) {
  final MultiLyricsData normalizedData = _normalizeLddcTsData(lyrics.data);
  final Set<String> requestedLangSet = requestedLangs.toSet();
  final List<String> langsOrder = <String>[];
  final Set<String> addedLangs = <String>{};
  for (final String lang in configLangOrder) {
    if (requestedLangSet.contains(lang) &&
        normalizedData.containsKey(lang) &&
        addedLangs.add(lang)) {
      langsOrder.add(lang);
    }
  }
  for (final String lang in requestedLangs) {
    if (normalizedData.containsKey(lang) && addedLangs.add(lang)) {
      langsOrder.add(lang);
    }
  }

  final Set<String> workingLangs = <String>{
    ...langsOrder,
    if (normalizedData.containsKey('orig')) 'orig',
    if (langsOrder.contains('orig_lrc')) 'orig_lrc',
  };
  final MultiLyricsData data = <String, LyricsData>{};
  for (final String lang in workingLangs) {
    final LyricsData? lines = normalizedData[lang];
    if (lines == null) {
      continue;
    }
    data[lang] = _offsetLyricsData(lines, offsetMs);
  }

  return _LyricsExportProjection(
    data: data,
    origType: lyrics.types['orig'],
    langsOrder: List<String>.unmodifiable(langsOrder),
  );
}

MultiLyricsData _normalizeLddcTsData(Map<String, LyricsData> source) {
  final MultiLyricsData data = <String, LyricsData>{
    for (final MapEntry<String, LyricsData> entry in source.entries)
      if (entry.key != 'LDDC_ts') entry.key: entry.value,
  };
  final LyricsData? lddcTs = source['LDDC_ts'];
  if (lddcTs != null) {
    data['ts'] = lddcTs;
  }
  return data;
}

LyricsData _offsetLyricsData(LyricsData lines, int offsetMs) {
  if (offsetMs == 0) {
    return lines;
  }
  return lines
      .map((LyricsLine line) => line.withOffset(offsetMs))
      .toList(growable: false);
}

Map<String, Object?> _encodeJsonLyrics(Lyrics lyrics) {
  return <String, Object?>{
    'version': 1,
    'info': <String, Object?>{
      'source': lyrics.source.value,
      if (lyrics.id != null || lyrics.songInfo.id != null)
        'id': lyrics.id ?? lyrics.songInfo.id,
      if (lyrics.accessKey != null) 'accesskey': lyrics.accessKey,
      if (lyrics.durationMs != null || lyrics.songInfo.durationMs != null)
        'duration': lyrics.durationMs ?? lyrics.songInfo.durationMs,
      if (lyrics.creator != null) 'creator': lyrics.creator,
      if (lyrics.score != null) 'score': lyrics.score,
      'songinfo': _songInfoToPythonMap(lyrics.songInfo),
    },
    'tags': Map<String, String>.from(lyrics.tags),
    'lyrics': <String, Object?>{
      for (final MapEntry<String, LyricsData> entry in lyrics.data.entries)
        entry.key: _encodeLyricsData(entry.value),
    },
  };
}

Map<String, Object?> _songInfoToPythonMap(SongInfo songInfo) {
  return <String, Object?>{
    'source': songInfo.source.value,
    if (songInfo.title != null) 'title': songInfo.title,
    if (songInfo.subtitle != null) 'subtitle': songInfo.subtitle,
    if (songInfo.artist != null) 'artist': songInfo.artist!.values,
    if (songInfo.album != null) 'album': songInfo.album,
    if (songInfo.durationMs != null) 'duration': songInfo.durationMs,
    if (songInfo.id != null) 'id': songInfo.id,
    if (songInfo.mid != null) 'mid': songInfo.mid,
    if (songInfo.hash != null) 'hash': songInfo.hash,
    if (songInfo.path != null) 'path': songInfo.path,
    'from_cue': songInfo.fromCue,
    if (songInfo.language != null) 'language': songInfo.language!.value,
  };
}

List<Object?> _encodeLyricsData(LyricsData lines) {
  return <Object?>[
    for (final LyricsLine line in lines)
      <Object?>[
        line.startMs,
        line.endMs,
        <Object?>[
          for (final LyricsWord word in line.words)
            <Object?>[word.startMs, word.endMs, word.text],
        ],
      ],
  ];
}

/// 对齐 Python `json.dumps(..., ensure_ascii=False)` 的默认分隔符风格：
/// - 对象键值 `": "`
/// - 数组/对象元素 `", "`
String _pythonStyleJsonEncode(Object? value) {
  if (value is Map) {
    final List<String> parts = <String>[];
    for (final MapEntry<dynamic, dynamic> entry in value.entries) {
      parts.add(
        '${jsonEncode(entry.key.toString())}: ${_pythonStyleJsonEncode(entry.value)}',
      );
    }
    return '{${parts.join(', ')}}';
  }
  if (value is List) {
    return '[${value.map<String>(_pythonStyleJsonEncode).join(', ')}]';
  }
  return jsonEncode(value);
}
