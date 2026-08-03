import 'dart:io';
import 'dart:typed_data';

import '../../lyrics_source/lyrics_source.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 本地歌词 provider：对齐Python版 `core/api/lyrics/local.py`。
class LocalLyricsProvider implements LyricsLocalSourceProvider {
  LocalLyricsProvider({
    LyricsParserPort? parser,
    LyricsAssembler? assembler,
    LocalLyricsInputNormalizer? normalizer,
  }) : _parser = parser ?? const LyricsParserEngine(),
       _assembler = assembler ?? const LyricsAssembler(),
       _normalizer =
           normalizer ??
           LocalLyricsInputNormalizer(fileReader: _readLocalFileBytes),
       _dispatcher = LyricsParserDispatcher(
         parser ?? const LyricsParserEngine(),
       );

  final LyricsParserPort _parser;
  final LyricsAssembler _assembler;
  final LocalLyricsInputNormalizer _normalizer;
  final LyricsParserDispatcher _dispatcher;

  static Future<Uint8List> _readLocalFileBytes(String path) {
    return File(path).readAsBytes();
  }

  static final RegExp _qrcCompanionPattern = RegExp(
    r'^(.*)_qm(Roma|ts)?\.qrc$',
    caseSensitive: false,
  );

  @override
  Future<Lyrics> getLyrics(LocalLyricsRequest request) async {
    final ResolvedLocalLyricsInput input = await _normalizer.resolve(request);
    final LyricsAssembleContext context = _buildAssembleContext(input);

    final Uint8List data = input.data;
    ParsedLyricsPayload payload;
    if (_normalizer.isQrc(data)) {
      payload = await _parseQrcPayload(input);
    } else {
      payload = _normalizer.parsePayload(
        data: data,
        path: input.path,
        parser: _parser,
        dispatcher: _dispatcher,
      );
    }

    return _assembler.assemble(payload, context: context);
  }

  Future<ParsedLyricsPayload> _parseQrcPayload(
    ResolvedLocalLyricsInput input,
  ) async {
    final String? path = input.path;
    if (path == null) {
      return _parseSingleLocalQrc(input.data, path: null);
    }

    final RegExpMatch? match = _qrcCompanionPattern.firstMatch(path);
    if (match == null) {
      return _parseSingleLocalQrc(input.data, path: path);
    }

    final String prefix = match.group(1) ?? '';
    final String currentType = _normalizeQrcCompanionType(match.group(2));
    final Map<String, Uint8List?> candidates = <String, Uint8List?>{
      currentType: input.data,
      ...<String, Uint8List?>{
        for (final String qrcType in <String>['', 'Roma', 'ts'])
          if (qrcType != currentType) qrcType: null,
      },
    };

    final Map<String, String> mergedTags = <String, String>{};
    final Map<String, LyricsData> mergedLyrics = <String, LyricsData>{};
    for (final MapEntry<String, Uint8List?> entry in candidates.entries) {
      Uint8List? qrcData = entry.value;
      qrcData ??= await _loadCompanionQrc(prefix: prefix, qrcType: entry.key);
      if (qrcData == null) {
        continue;
      }

      final ParsedLyricsPayload parsed = _parseSingleLocalQrc(
        qrcData,
        path: path,
      );
      mergedTags.addAll(parsed.tags);
      final LyricsData? orig = parsed.lyricsData['orig'];
      if (orig == null || orig.isEmpty) {
        continue;
      }

      final String lang = switch (entry.key) {
        'Roma' => 'roma',
        'ts' => 'ts',
        _ => 'orig',
      };
      mergedLyrics[lang] = orig;
    }

    return ParsedLyricsPayload(tags: mergedTags, lyricsData: mergedLyrics);
  }

  ParsedLyricsPayload _parseSingleLocalQrc(
    Uint8List encryptedQrc, {
    required String? path,
  }) {
    return _normalizer.parseDecryptedQrc(
      data: encryptedQrc,
      path: path,
      parser: _parser,
    );
  }

  Future<Uint8List?> _loadCompanionQrc({
    required String prefix,
    required String qrcType,
  }) async {
    final String candidatePath = '${prefix}_qm$qrcType.qrc';
    final File candidate = File(candidatePath);
    // QRC 伴随文件查找位于 UI/批量转换链路上，使用异步 stat 避免阻塞 UI isolate。
    // ignore: avoid_slow_async_io
    if (!await candidate.exists()) {
      return null;
    }
    final Uint8List data = await candidate.readAsBytes();
    if (!_normalizer.isQrc(data)) {
      return null;
    }
    return data;
  }

  LyricsAssembleContext _buildAssembleContext(ResolvedLocalLyricsInput input) {
    final LyricInfo? info = input.info;
    final SongInfo songInfo = _buildSongInfo(input);
    return LyricsAssembleContext(
      songInfo: songInfo,
      source: info?.source,
      id: info?.id,
      accessKey: info?.accessKey,
      durationMs: info?.durationMs,
      creator: info?.creator,
      score: info?.score,
      path: input.path,
      cached: info?.cached ?? false,
    );
  }

  SongInfo _buildSongInfo(ResolvedLocalLyricsInput input) {
    final SongInfo? existing = input.info?.songInfo;
    if (existing == null) {
      return SongInfo(source: Source.local, path: input.path);
    }
    if (existing.path == null && input.path != null) {
      return existing.copyWith(path: input.path);
    }
    return existing;
  }

  String _normalizeQrcCompanionType(String? rawType) {
    final String normalized = (rawType ?? '').trim().toLowerCase();
    if (normalized == 'roma') {
      return 'Roma';
    }
    if (normalized == 'ts') {
      return 'ts';
    }
    return '';
  }
}
