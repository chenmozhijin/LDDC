import 'package:flutter/services.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../render/desktop_lyrics_perf_stats.dart';
import 'desktop_lyrics_timing_math.dart';

typedef DesktopLyricsMapping = Map<String, Map<int, LyricsLine>>;
typedef DesktopAssignedLyricsSlots =
    Map<(Direction, int), List<(int, LyricsLine)>>;
typedef DesktopRubyMapping = Map<int, List<RubySpan>>;

/// 桌面歌词场景模式。
enum DesktopLyricsSceneMode { lyrics, staticText }

/// 跨引擎传递的大对象引用。
class DesktopSceneRef {
  const DesktopSceneRef({
    required this.sceneId,
    required this.sceneRevision,
    required this.checksum,
  });

  final String sceneId;
  final int sceneRevision;
  final String checksum;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sceneId': sceneId,
      'sceneRevision': sceneRevision,
      'checksum': checksum,
    };
  }

  DesktopSceneRef copyWith({
    String? sceneId,
    int? sceneRevision,
    String? checksum,
  }) {
    return DesktopSceneRef(
      sceneId: sceneId ?? this.sceneId,
      sceneRevision: sceneRevision ?? this.sceneRevision,
      checksum: checksum ?? this.checksum,
    );
  }

  static DesktopSceneRef? fromMap(Object? payload) {
    if (payload == null) {
      return null;
    }
    final Map<Object?, Object?> map = payload is Map
        ? Map<Object?, Object?>.from(payload)
        : const <Object?, Object?>{};
    final String sceneId = map['sceneId']?.toString() ?? '';
    if (sceneId.isEmpty) {
      return null;
    }
    final int sceneRevision = switch (map['sceneRevision']) {
      int value => value,
      num value => value.toInt(),
      _ => int.tryParse(map['sceneRevision']?.toString() ?? '') ?? 0,
    };
    return DesktopSceneRef(
      sceneId: sceneId,
      sceneRevision: sceneRevision,
      checksum: map['checksum']?.toString() ?? '',
    );
  }
}

bool desktopSceneRefEquals(DesktopSceneRef? left, DesktopSceneRef? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.sceneId == right.sceneId &&
      left.sceneRevision == right.sceneRevision &&
      left.checksum == right.checksum;
}

/// 低频歌词语义文档。
class DesktopLyricsSceneDocument {
  DesktopLyricsSceneDocument({
    required this.mode,
    required List<String> selectedLangs,
    required List<String> langOrder,
    required this.durationMs,
    MultiLyricsData multiLyricsData = const <String, LyricsData>{},
    DesktopLyricsMapping lyricsMapping = const <String, Map<int, LyricsLine>>{},
    DesktopAssignedLyricsSlots assignedLyricsSlots =
        const <(Direction, int), List<(int, LyricsLine)>>{},
    DesktopRubyMapping rubyMapping = const <int, List<RubySpan>>{},
    List<String> staticDisplayLines = const <String>[],
  }) : selectedLangs = List<String>.unmodifiable(selectedLangs),
       langOrder = List<String>.unmodifiable(langOrder),
       multiLyricsData = _freezeMultiLyricsData(multiLyricsData),
       lyricsMapping = _freezeLyricsMapping(lyricsMapping),
       assignedLyricsSlots = _freezeAssignedLyricsSlots(assignedLyricsSlots),
       rubyMapping = _freezeRubyMapping(rubyMapping),
       staticDisplayLines = List<String>.unmodifiable(staticDisplayLines);

  final DesktopLyricsSceneMode mode;
  final List<String> selectedLangs;
  final List<String> langOrder;
  final int? durationMs;
  final MultiLyricsData multiLyricsData;
  final DesktopLyricsMapping lyricsMapping;
  final DesktopAssignedLyricsSlots assignedLyricsSlots;
  final DesktopRubyMapping rubyMapping;
  final List<String> staticDisplayLines;

  bool get isStaticText => mode == DesktopLyricsSceneMode.staticText;

  DesktopLyricsSceneDocument copyWith({
    DesktopLyricsSceneMode? mode,
    List<String>? selectedLangs,
    List<String>? langOrder,
    int? durationMs,
    MultiLyricsData? multiLyricsData,
    DesktopLyricsMapping? lyricsMapping,
    DesktopAssignedLyricsSlots? assignedLyricsSlots,
    DesktopRubyMapping? rubyMapping,
    List<String>? staticDisplayLines,
  }) {
    return DesktopLyricsSceneDocument(
      mode: mode ?? this.mode,
      selectedLangs: selectedLangs ?? this.selectedLangs,
      langOrder: langOrder ?? this.langOrder,
      durationMs: durationMs ?? this.durationMs,
      multiLyricsData: multiLyricsData ?? this.multiLyricsData,
      lyricsMapping: lyricsMapping ?? this.lyricsMapping,
      assignedLyricsSlots: assignedLyricsSlots ?? this.assignedLyricsSlots,
      rubyMapping: rubyMapping ?? this.rubyMapping,
      staticDisplayLines: staticDisplayLines ?? this.staticDisplayLines,
    );
  }
}

MultiLyricsData _freezeMultiLyricsData(MultiLyricsData value) {
  return <String, LyricsData>{
    for (final MapEntry<String, LyricsData> entry in value.entries)
      entry.key: List<LyricsLine>.unmodifiable(entry.value),
  };
}

DesktopLyricsMapping _freezeLyricsMapping(DesktopLyricsMapping value) {
  return <String, Map<int, LyricsLine>>{
    for (final MapEntry<String, Map<int, LyricsLine>> entry in value.entries)
      entry.key: Map<int, LyricsLine>.unmodifiable(entry.value),
  };
}

DesktopAssignedLyricsSlots _freezeAssignedLyricsSlots(
  DesktopAssignedLyricsSlots value,
) {
  return <(Direction, int), List<(int, LyricsLine)>>{
    for (final MapEntry<(Direction, int), List<(int, LyricsLine)>> entry
        in value.entries)
      entry.key: _sortAssignedSlotEntries(entry.value),
  };
}

List<(int, LyricsLine)> _sortAssignedSlotEntries(
  List<(int, LyricsLine)> items,
) {
  final List<(int, LyricsLine)> sorted = List<(int, LyricsLine)>.of(items);
  sorted.sort(((int, LyricsLine) left, (int, LyricsLine) right) {
    final int leftStart = resolveDesktopLyricsLineStartMs(left.$2) ?? 0;
    final int rightStart = resolveDesktopLyricsLineStartMs(right.$2) ?? 0;
    final int startCompare = leftStart.compareTo(rightStart);
    if (startCompare != 0) {
      return startCompare;
    }
    final int leftEnd = resolveDesktopLyricsLineEndMs(left.$2) ?? leftStart;
    final int rightEnd = resolveDesktopLyricsLineEndMs(right.$2) ?? rightStart;
    final int endCompare = leftEnd.compareTo(rightEnd);
    if (endCompare != 0) {
      return endCompare;
    }
    return left.$1.compareTo(right.$1);
  });
  return List<(int, LyricsLine)>.unmodifiable(sorted);
}

DesktopRubyMapping _freezeRubyMapping(DesktopRubyMapping value) {
  return <int, List<RubySpan>>{
    for (final MapEntry<int, List<RubySpan>> entry in value.entries)
      entry.key: List<RubySpan>.unmodifiable(entry.value),
  };
}

/// 场景编解码器。
///
/// 这里使用 `StandardMessageCodec` 生成紧凑二进制，
/// 避免在窗口消息里重复走大 Map/JSON 字符串。
class DesktopLyricsSceneCodec {
  const DesktopLyricsSceneCodec();

  static const StandardMessageCodec _codec = StandardMessageCodec();

  Uint8List encode(DesktopLyricsSceneDocument document) {
    final ByteData? data = _codec.encodeMessage(_encodeDocument(document));
    if (data == null) {
      return Uint8List(0);
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  DesktopLyricsSceneDocument decode(Uint8List bytes) {
    final Object? decoded = _codec.decodeMessage(ByteData.sublistView(bytes));
    return _decodeDocument(decoded);
  }

  String checksumForBytes(Uint8List bytes) {
    int hash = 0x811c9dc5;
    for (final int byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, Object?> _encodeDocument(DesktopLyricsSceneDocument document) {
    return <String, Object?>{
      'mode': document.mode.name,
      'selectedLangs': document.selectedLangs,
      'langOrder': document.langOrder,
      'durationMs': document.durationMs,
      'multiLyricsData': <String, Object?>{
        for (final MapEntry<String, LyricsData> entry
            in document.multiLyricsData.entries)
          entry.key: entry.value
              .map<Map<String, Object?>>(_encodeLyricsLine)
              .toList(growable: false),
      },
      'lyricsMapping': <String, Object?>{
        for (final MapEntry<String, Map<int, LyricsLine>> entry
            in document.lyricsMapping.entries)
          entry.key: <String, Object?>{
            for (final MapEntry<int, LyricsLine> mapped in entry.value.entries)
              mapped.key.toString(): _encodeLyricsLine(mapped.value),
          },
      },
      'assignedLyricsSlots': <Map<String, Object?>>[
        for (final MapEntry<(Direction, int), List<(int, LyricsLine)>> entry
            in document.assignedLyricsSlots.entries)
          <String, Object?>{
            'side': entry.key.$1.name,
            'track': entry.key.$2,
            'items': <Map<String, Object?>>[
              for (final (int, LyricsLine) item in entry.value)
                <String, Object?>{
                  'origIndex': item.$1,
                  'line': _encodeLyricsLine(item.$2),
                },
            ],
          },
      ],
      'rubyMapping': <String, Object?>{
        for (final MapEntry<int, List<RubySpan>> entry
            in document.rubyMapping.entries)
          entry.key.toString(): <Map<String, Object?>>[
            for (final RubySpan span in entry.value)
              <String, Object?>{
                'start': span.start,
                'end': span.end,
                'ruby': span.ruby,
              },
          ],
      },
      'staticDisplayLines': document.staticDisplayLines,
    };
  }

  DesktopLyricsSceneDocument _decodeDocument(Object? payload) {
    final Map<Object?, Object?> map = _asMap(payload);
    final DesktopLyricsSceneMode mode = _decodeMode(map['mode']);
    final MultiLyricsData multiLyricsData = <String, LyricsData>{};
    _asMap(map['multiLyricsData']).forEach((Object? key, Object? value) {
      final List<Object?> lines = value is List<Object?>
          ? value
          : value is List
          ? value.cast<Object?>()
          : const <Object?>[];
      multiLyricsData[key?.toString() ?? ''] = lines
          .map((Object? item) => _decodeLyricsLine(_asMap(item)))
          .toList(growable: false);
    });

    final DesktopLyricsMapping lyricsMapping = <String, Map<int, LyricsLine>>{};
    _asMap(map['lyricsMapping']).forEach((Object? key, Object? value) {
      final Map<int, LyricsLine> mapped = <int, LyricsLine>{};
      _asMap(value).forEach((Object? indexKey, Object? lineValue) {
        final int? index = _asInt(indexKey);
        if (index == null) {
          return;
        }
        mapped[index] = _decodeLyricsLine(_asMap(lineValue));
      });
      lyricsMapping[key?.toString() ?? ''] = mapped;
    });

    final DesktopAssignedLyricsSlots assignedLyricsSlots =
        <(Direction, int), List<(int, LyricsLine)>>{};
    final List<Object?> rawSlots = map['assignedLyricsSlots'] is List<Object?>
        ? map['assignedLyricsSlots']! as List<Object?>
        : map['assignedLyricsSlots'] is List
        ? (map['assignedLyricsSlots']! as List).cast<Object?>()
        : const <Object?>[];
    for (final Object? rawSlot in rawSlots) {
      final Map<Object?, Object?> slotMap = _asMap(rawSlot);
      final Direction side = Direction.fromValue(slotMap['side']);
      final int track = _asInt(slotMap['track']) ?? 0;
      final List<Object?> rawItems = slotMap['items'] is List<Object?>
          ? slotMap['items']! as List<Object?>
          : slotMap['items'] is List
          ? (slotMap['items']! as List).cast<Object?>()
          : const <Object?>[];
      assignedLyricsSlots[(side, track)] = rawItems
          .map<(int, LyricsLine)>((Object? rawItem) {
            final Map<Object?, Object?> itemMap = _asMap(rawItem);
            return (
              _asInt(itemMap['origIndex']) ?? 0,
              _decodeLyricsLine(_asMap(itemMap['line'])),
            );
          })
          .toList(growable: false);
    }

    final DesktopRubyMapping rubyMapping = <int, List<RubySpan>>{};
    _asMap(map['rubyMapping']).forEach((Object? key, Object? value) {
      final int? index = _asInt(key);
      if (index == null) {
        return;
      }
      final List<Object?> rawSpans = value is List<Object?>
          ? value
          : value is List
          ? value.cast<Object?>()
          : const <Object?>[];
      rubyMapping[index] = rawSpans
          .map((Object? rawSpan) {
            final Map<Object?, Object?> spanMap = _asMap(rawSpan);
            return RubySpan(
              start: _asInt(spanMap['start']) ?? 0,
              end: _asInt(spanMap['end']) ?? 0,
              ruby: spanMap['ruby']?.toString() ?? '',
            );
          })
          .toList(growable: false);
    });

    return DesktopLyricsSceneDocument(
      mode: mode,
      selectedLangs: _asLangList(map['selectedLangs']),
      langOrder: _asLangList(map['langOrder']),
      durationMs: _asInt(map['durationMs']),
      multiLyricsData: multiLyricsData,
      lyricsMapping: lyricsMapping,
      assignedLyricsSlots: assignedLyricsSlots,
      rubyMapping: rubyMapping,
      staticDisplayLines: _asStringListPreserveEmpty(map['staticDisplayLines']),
    );
  }

  Map<String, Object?> _encodeLyricsLine(LyricsLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'words': <Map<String, Object?>>[
        for (final LyricsWord word in line.words)
          <String, Object?>{
            'startMs': word.startMs,
            'endMs': word.endMs,
            'text': word.text,
          },
      ],
    };
  }

  LyricsLine _decodeLyricsLine(Map<Object?, Object?> payload) {
    final List<Object?> rawWords = payload['words'] is List<Object?>
        ? payload['words']! as List<Object?>
        : payload['words'] is List
        ? (payload['words']! as List).cast<Object?>()
        : const <Object?>[];
    return LyricsLine(
      startMs: _asInt(payload['startMs']),
      endMs: _asInt(payload['endMs']),
      words: rawWords
          .map((Object? rawWord) {
            final Map<Object?, Object?> wordMap = _asMap(rawWord);
            return LyricsWord(
              startMs: _asInt(wordMap['startMs']),
              endMs: _asInt(wordMap['endMs']),
              text: wordMap['text']?.toString() ?? '',
            );
          })
          .toList(growable: false),
    );
  }

  DesktopLyricsSceneMode _decodeMode(Object? value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final DesktopLyricsSceneMode mode in DesktopLyricsSceneMode.values) {
      if (mode.name.toLowerCase() == normalized) {
        return mode;
      }
    }
    return DesktopLyricsSceneMode.lyrics;
  }

  Map<Object?, Object?> _asMap(Object? value) {
    return DynamicReader.asMap(value);
  }

  int? _asInt(Object? value) {
    return DynamicReader.asInt(value);
  }

  List<String> _asStringListPreserveEmpty(Object? value) {
    return DynamicReader.asStringListPreserveEmpty(value);
  }

  List<String> _asLangList(Object? value) {
    return DynamicReader.readTokenList(
      value,
      normalizer: LyricsLanguageRegistry.normalizeKey,
    );
  }
}

/// 场景存储抽象。
abstract interface class DesktopSceneStorePort {
  void putScene(
    String sceneId,
    Uint8List bytes, {
    required int revision,
    required String checksum,
  });

  Uint8List? getScene(String sceneId);

  void releaseScene(String sceneId);

  void evictScenes(int instanceId);

  DesktopSceneStoreStats get stats;
}

class DesktopSceneStoreStats {
  const DesktopSceneStoreStats({
    required this.sceneCount,
    required this.totalBytes,
  });

  final int sceneCount;
  final int totalBytes;
}

/// 主窗口侧的进程内场景缓存。
class DesktopInMemorySceneStore implements DesktopSceneStorePort {
  DesktopInMemorySceneStore();

  final Map<String, Uint8List> _scenes = <String, Uint8List>{};
  final Map<int, String> _currentSceneIds = <int, String>{};

  @override
  DesktopSceneStoreStats get stats => DesktopSceneStoreStats(
    sceneCount: _scenes.length,
    totalBytes: _scenes.values.fold<int>(
      0,
      (int total, Uint8List bytes) => total + bytes.lengthInBytes,
    ),
  );

  @override
  Uint8List? getScene(String sceneId) {
    final Uint8List? scene = _scenes[sceneId];
    if (scene != null) {
      DesktopLyricsPerfStats.instance.bump('sceneGet');
    }
    return scene;
  }

  @override
  void putScene(
    String sceneId,
    Uint8List bytes, {
    required int revision,
    required String checksum,
  }) {
    final int? instanceId = _parseInstanceId(sceneId);
    final String? previousSceneId = instanceId == null
        ? null
        : _currentSceneIds[instanceId];
    if (previousSceneId != null && previousSceneId != sceneId) {
      _scenes.remove(previousSceneId);
    }
    if (instanceId != null) {
      _currentSceneIds[instanceId] = sceneId;
    }
    _scenes[sceneId] = bytes;
    DesktopLyricsPerfStats.instance
      ..bump('scenePublish')
      ..recordPeak('sceneStoreSceneCount', _scenes.length)
      ..recordPeak('sceneStoreBytes', stats.totalBytes);
  }

  @override
  void releaseScene(String sceneId) {
    final Uint8List? removed = _scenes.remove(sceneId);
    if (removed == null) {
      return;
    }
    final int? instanceId = _parseInstanceId(sceneId);
    if (instanceId != null && _currentSceneIds[instanceId] == sceneId) {
      _currentSceneIds.remove(instanceId);
    }
    DesktopLyricsPerfStats.instance.bump('sceneRelease');
  }

  @override
  void evictScenes(int instanceId) {
    final String prefix = '$instanceId:';
    final List<String> keys = _scenes.keys
        .where((String sceneId) => sceneId.startsWith(prefix))
        .toList(growable: false);
    for (final String sceneId in keys) {
      _scenes.remove(sceneId);
    }
    _currentSceneIds.remove(instanceId);
    if (keys.isNotEmpty) {
      DesktopLyricsPerfStats.instance.bump('sceneEvict', keys.length);
    }
  }

  int? _parseInstanceId(String sceneId) {
    final int separatorIndex = sceneId.indexOf(':');
    if (separatorIndex <= 0) {
      return null;
    }
    return int.tryParse(sceneId.substring(0, separatorIndex));
  }
}
