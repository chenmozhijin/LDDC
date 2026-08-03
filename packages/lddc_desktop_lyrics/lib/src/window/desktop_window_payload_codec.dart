import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_scene.dart';
import 'desktop_panel_host.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_codec_common.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_method_names.dart';

/// 桌面多窗口负载编解码。
class DesktopWindowPayloadCodec {
  const DesktopWindowPayloadCodec._();

  static Map<String, Object?> encodeFloatingContentPayload(
    DesktopFloatingContentPayload payload,
  ) {
    return <String, Object?>{
      'contentRevision': payload.contentRevision,
      'session': _encodeFloatingSessionSnapshot(payload.session),
      'sceneRef': payload.sceneRef?.toJson(),
      'sceneBytes': payload.sceneBytes,
    };
  }

  static DesktopFloatingContentPayload decodeFloatingContentPayload(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopFloatingContentPayload(
      contentRevision: asInt(map['contentRevision']) ?? 0,
      session: _decodeFloatingSessionSnapshot(map['session']),
      sceneRef: DesktopSceneRef.fromMap(map['sceneRef']),
      sceneBytes: _decodeSceneBytes(map['sceneBytes']),
    );
  }

  static Map<String, Object?> encodeFloatingFlagsPayload(
    DesktopFloatingFlagsPayload payload,
  ) {
    return <String, Object?>{
      'revision': payload.revision,
      'flags': _encodeFloatingWindowFlags(payload.flags),
    };
  }

  static DesktopFloatingFlagsPayload decodeFloatingFlagsPayload(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopFloatingFlagsPayload(
      revision: asInt(map['revision']) ?? 0,
      flags: _decodeFloatingWindowFlags(map['flags']),
    );
  }

  static Map<String, Object?> _encodeFloatingWindowFlags(
    DesktopFloatingWindowFlags flags,
  ) {
    return <String, Object?>{
      'visible': flags.visible,
      'alwaysOnTop': flags.alwaysOnTop,
      'clickThrough': flags.clickThrough,
      'frameless': flags.frameless,
      'opacity': flags.opacity,
    };
  }

  static DesktopFloatingWindowFlags _decodeFloatingWindowFlags(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopFloatingWindowFlags(
      visible: asBool(map['visible']) ?? false,
      alwaysOnTop: asBool(map['alwaysOnTop']) ?? true,
      clickThrough: asBool(map['clickThrough']) ?? false,
      frameless: asBool(map['frameless']) ?? true,
      opacity: asDouble(map['opacity']) ?? 1.0,
    );
  }

  static Map<String, Object?> _encodeFloatingSessionSnapshot(
    DesktopFloatingSessionSnapshot snapshot,
  ) {
    return <String, Object?>{
      'songId': snapshot.songId,
      'songTitle': snapshot.songTitle,
      'artistText': snapshot.artistText,
      ...encodeSessionStyleFields((
        enabledLangs: snapshot.enabledLangs,
        playedColors: snapshot.playedColors,
        unplayedColors: snapshot.unplayedColors,
        fontFamily: snapshot.fontFamily,
        fontSize: snapshot.fontSize,
        showFurigana: snapshot.showFurigana,
        refreshRate: snapshot.refreshRate,
        actions: snapshot.actions,
        sessionRevision: 0,
      )),
      'isPlaying': snapshot.isPlaying,
      'isInstrumental': snapshot.isInstrumental,
      'hasStaticDisplay': snapshot.hasStaticDisplay,
      'infoBadge': encodeLyricsInfoBadgeFields(snapshot.infoBadge),
    };
  }

  static DesktopFloatingSessionSnapshot _decodeFloatingSessionSnapshot(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    final DesktopSessionStyleFields styleFields = decodeSessionStyleFields(
      map,
      defaultFontSize: 30.0,
    );
    return DesktopFloatingSessionSnapshot(
      songId: map['songId']?.toString(),
      songTitle: map['songTitle']?.toString(),
      artistText: map['artistText']?.toString(),
      enabledLangs: styleFields.enabledLangs,
      playedColors: styleFields.playedColors,
      unplayedColors: styleFields.unplayedColors,
      fontFamily: styleFields.fontFamily,
      fontSize: styleFields.fontSize,
      showFurigana: styleFields.showFurigana,
      isPlaying: asBool(map['isPlaying']) ?? false,
      isInstrumental: asBool(map['isInstrumental']) ?? false,
      hasStaticDisplay: asBool(map['hasStaticDisplay']) ?? false,
      refreshRate: styleFields.refreshRate,
      actions: styleFields.actions,
      infoBadge: decodeLyricsInfoBadgeSnapshot(map['infoBadge']),
    );
  }

  static Map<String, Object?> encodeFloatingAnchorSnapshot(
    DesktopFloatingAnchorSnapshot snapshot,
  ) {
    return encodePlaybackAnchorFields(
      pluginPlaybackTimeMs: snapshot.pluginPlaybackTimeMs,
      pluginSendTimeMs: snapshot.pluginSendTimeMs,
      hostReceivedAtMs: snapshot.hostReceivedAtMs,
      isPlaying: snapshot.isPlaying,
      syncRevision: snapshot.syncRevision,
      eventKind: snapshot.eventKind,
      sceneId: snapshot.sceneId,
      songToken: snapshot.songToken,
    );
  }

  static DesktopFloatingAnchorSnapshot decodeFloatingAnchorSnapshot(
    Object? payload,
  ) {
    final DesktopPlaybackAnchorFields fields = decodePlaybackAnchorFields(
      payload,
    );
    return DesktopFloatingAnchorSnapshot(
      pluginPlaybackTimeMs: fields.pluginPlaybackTimeMs,
      pluginSendTimeMs: fields.pluginSendTimeMs,
      hostReceivedAtMs: fields.hostReceivedAtMs,
      isPlaying: fields.isPlaying,
      syncRevision: fields.syncRevision,
      eventKind: fields.eventKind,
      sceneId: fields.sceneId,
      songToken: fields.songToken,
    );
  }

  static Map<String, Object?> encodePanelContentPayload(
    DesktopPanelContentPayload payload,
  ) {
    return <String, Object?>{
      'contentRevision': payload.contentRevision,
      'session': _encodePanelSessionSnapshot(payload.session),
      'sceneRef': payload.sceneRef?.toJson(),
      'sceneBytes': payload.sceneBytes,
    };
  }

  static DesktopPanelContentPayload decodePanelContentPayload(Object? payload) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopPanelContentPayload(
      contentRevision: asInt(map['contentRevision']) ?? 0,
      session: _decodePanelSessionSnapshot(map['session']),
      sceneRef: DesktopSceneRef.fromMap(map['sceneRef']),
      sceneBytes: _decodeSceneBytes(map['sceneBytes']),
    );
  }

  static Map<String, Object?> _encodePanelSessionSnapshot(
    DesktopPanelSessionSnapshot snapshot,
  ) {
    return <String, Object?>{
      'songId': snapshot.songId,
      ...encodeSessionStyleFields((
        enabledLangs: snapshot.enabledLangs,
        playedColors: snapshot.playedColors,
        unplayedColors: snapshot.unplayedColors,
        fontFamily: snapshot.fontFamily,
        fontSize: snapshot.fontSize,
        showFurigana: snapshot.showFurigana,
        refreshRate: snapshot.refreshRate,
        actions: snapshot.actions,
        sessionRevision: 0,
      )),
      'visible': snapshot.visible,
    };
  }

  static DesktopPanelSessionSnapshot _decodePanelSessionSnapshot(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    final DesktopSessionStyleFields styleFields = decodeSessionStyleFields(
      map,
      defaultFontSize: 12.0,
    );
    return DesktopPanelSessionSnapshot(
      songId: asString(map['songId']),
      enabledLangs: styleFields.enabledLangs,
      playedColors: styleFields.playedColors,
      unplayedColors: styleFields.unplayedColors,
      fontFamily: styleFields.fontFamily,
      fontSize: styleFields.fontSize,
      showFurigana: styleFields.showFurigana,
      refreshRate: styleFields.refreshRate,
      visible: asBool(map['visible']) ?? true,
      actions: styleFields.actions,
    );
  }

  static Map<String, Object?> encodePanelPresentationReady(
    DesktopPanelPresentationReady ready,
  ) {
    return <String, Object?>{
      'contentRevision': ready.contentRevision,
      'surfaceRevision': ready.surfaceRevision,
    };
  }

  static DesktopPanelPresentationReady decodePanelPresentationReady(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopPanelPresentationReady(
      contentRevision: asInt(map['contentRevision']) ?? 0,
      surfaceRevision: asInt(map['surfaceRevision']) ?? 0,
    );
  }

  static Map<String, Object?> encodeWindowActionSnapshot(
    DesktopWindowActionSnapshot snapshot,
  ) {
    return encodeWindowActionFields(snapshot);
  }

  static DesktopWindowActionSnapshot decodeWindowActionSnapshot(
    Object? payload,
  ) {
    return decodeWindowActionFields(asMap(payload));
  }

  static Map<String, Object?> encodeLyricsInfoBadgeSnapshot(
    DesktopLyricsInfoBadgeSnapshot snapshot,
  ) {
    return encodeLyricsInfoBadgeFields(snapshot);
  }

  static DesktopLyricsInfoBadgeSnapshot decodeLyricsInfoBadgeSnapshot(
    Object? payload,
  ) {
    return decodeLyricsInfoBadgeFields(asMap(payload));
  }

  static Map<String, Object?> encodePanelAnchorSnapshot(
    DesktopPanelAnchorSnapshot snapshot,
  ) {
    return encodePlaybackAnchorFields(
      pluginPlaybackTimeMs: snapshot.pluginPlaybackTimeMs,
      pluginSendTimeMs: snapshot.pluginSendTimeMs,
      hostReceivedAtMs: snapshot.hostReceivedAtMs,
      isPlaying: snapshot.isPlaying,
      syncRevision: snapshot.syncRevision,
      eventKind: snapshot.eventKind,
      sceneId: snapshot.sceneId,
      songToken: snapshot.songToken,
    );
  }

  static DesktopPanelAnchorSnapshot decodePanelAnchorSnapshot(Object? payload) {
    final DesktopPlaybackAnchorFields fields = decodePlaybackAnchorFields(
      payload,
    );
    return DesktopPanelAnchorSnapshot(
      pluginPlaybackTimeMs: fields.pluginPlaybackTimeMs,
      pluginSendTimeMs: fields.pluginSendTimeMs,
      hostReceivedAtMs: fields.hostReceivedAtMs,
      isPlaying: fields.isPlaying,
      syncRevision: fields.syncRevision,
      eventKind: fields.eventKind,
      sceneId: fields.sceneId,
      songToken: fields.songToken,
    );
  }

  static Map<String, Object?> encodeSelectorContext(
    DesktopSelectorWindowContext context,
  ) {
    return <String, Object?>{
      'keyword': context.keyword,
      'lyrics': context.lyrics == null ? null : _encodeLyrics(context.lyrics!),
      'langs': context.langs,
      'offsetMs': context.offsetMs,
      'refreshToken': context.refreshToken,
    };
  }

  static DesktopSelectorWindowContext decodeSelectorContext(Object? payload) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopSelectorWindowContext(
      keyword: map['keyword']?.toString(),
      lyrics: map['lyrics'] == null
          ? null
          : _decodeLyrics(asMap(map['lyrics'])),
      langs: asLangList(map['langs']),
      offsetMs: asInt(map['offsetMs']) ?? 0,
      refreshToken: asInt(map['refreshToken']) ?? 0,
    );
  }

  /// 编码选择器配置失效通知。这里只传版本号，配置内容仍由各 engine 的仓储读取。
  static Map<String, Object?> encodeSelectorConfigRevision(int revision) {
    if (revision <= 0) {
      throw ArgumentError.value(revision, 'revision', '必须大于 0');
    }
    return <String, Object?>{'revision': revision};
  }

  /// 解码选择器配置版本，并拒绝无效负载，避免错误通知覆盖已应用状态。
  static int decodeSelectorConfigRevision(Object? payload) {
    final Map<Object?, Object?> map = asMap(payload);
    final int? revision = asInt(map['revision']);
    if (revision == null || revision <= 0) {
      throw const FormatException('selector config revision 必须为正整数');
    }
    return revision;
  }

  static Map<String, Object?> encodeSelectorRuntimeDiagnostics(
    DesktopSelectorRuntimeDiagnostics diagnostics,
  ) {
    return <String, Object?>{
      'available': diagnostics.available,
      'hasActiveBatch': diagnostics.hasActiveBatch,
      'hasActiveRequest': diagnostics.hasActiveRequest,
      'hasPendingRequest': diagnostics.hasPendingRequest,
      'hasDebounceTimer': diagnostics.hasDebounceTimer,
      'isSearching': diagnostics.isSearching,
      'isLoadingMore': diagnostics.isLoadingMore,
      'searchBatchStartedCount': diagnostics.searchBatchStartedCount,
      'searchBatchSettledCount': diagnostics.searchBatchSettledCount,
      'sourceRequestStartedCount': diagnostics.sourceRequestStartedCount,
      'sourceRequestSettledCount': diagnostics.sourceRequestSettledCount,
    };
  }

  static DesktopSelectorRuntimeDiagnostics decodeSelectorRuntimeDiagnostics(
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    return DesktopSelectorRuntimeDiagnostics(
      available: asBool(map['available']) ?? false,
      hasActiveBatch: asBool(map['hasActiveBatch']) ?? false,
      hasActiveRequest: asBool(map['hasActiveRequest']) ?? false,
      hasPendingRequest: asBool(map['hasPendingRequest']) ?? false,
      hasDebounceTimer: asBool(map['hasDebounceTimer']) ?? false,
      isSearching: asBool(map['isSearching']) ?? false,
      isLoadingMore: asBool(map['isLoadingMore']) ?? false,
      searchBatchStartedCount: asInt(map['searchBatchStartedCount']) ?? 0,
      searchBatchSettledCount: asInt(map['searchBatchSettledCount']) ?? 0,
      sourceRequestStartedCount: asInt(map['sourceRequestStartedCount']) ?? 0,
      sourceRequestSettledCount: asInt(map['sourceRequestSettledCount']) ?? 0,
    );
  }

  static Map<String, Object?> encodeSelectorHiddenIntent(int instanceId) {
    return <String, Object?>{'instanceId': instanceId};
  }

  static Map<String, Object?> encodeFloatingMetricsCommittedIntent(
    DesktopFloatingMetricsCommittedIntent intent,
  ) {
    return <String, Object?>{
      'instanceId': intent.instanceId,
      'windowRect': intent.windowRect.toList(),
      'fontSize': intent.fontSize,
    };
  }

  static Map<String, Object?> encodeFloatingActionIntent(
    DesktopFloatingActionWindowIntent intent,
  ) {
    return <String, Object?>{
      'instanceId': intent.instanceId,
      'action': intent.action.value,
      'controlTask': intent.controlTask?.value,
    };
  }

  static Map<String, Object?> encodePanelActionIntent(
    DesktopPanelActionIntent intent,
  ) {
    return <String, Object?>{
      'instanceId': intent.instanceId,
      'panelId': intent.panelId,
      'action': intent.action.value,
      'controlTask': intent.controlTask?.value,
    };
  }

  static Map<String, Object?> encodeSelectorLyricsSelectedIntent(
    DesktopSelectorLyricsSelectedIntent intent,
  ) {
    return <String, Object?>{
      'instanceId': intent.instanceId,
      'lyrics': _encodeLyrics(intent.lyrics),
      'path': intent.path,
      'langs': intent.langs,
      'offsetMs': intent.offsetMs,
      'isInstrumental': intent.isInstrumental,
    };
  }

  static DesktopSelectorWindowIntent? decodeSelectorIntent(
    String method,
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    final int instanceId = asInt(map['instanceId']) ?? -1;
    if (instanceId < 0) {
      return null;
    }
    return switch (method) {
      DesktopWindowMethodNames.selectorHiddenIntent =>
        DesktopSelectorWindowHiddenIntent(instanceId: instanceId),
      DesktopWindowMethodNames.selectorLyricsSelectedIntent =>
        DesktopSelectorLyricsSelectedIntent(
          instanceId: instanceId,
          lyrics: _decodeLyrics(asMap(map['lyrics'])),
          path: map['path']?.toString(),
          langs: map['langs'] == null ? null : asLangList(map['langs']),
          offsetMs: asInt(map['offsetMs']) ?? 0,
          isInstrumental: asBool(map['isInstrumental']) ?? false,
        ),
      _ => null,
    };
  }

  static DesktopFloatingWindowIntent? decodeFloatingIntent(
    String method,
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    final int instanceId = asInt(map['instanceId']) ?? -1;
    if (instanceId < 0) {
      return null;
    }
    final WindowRect? windowRect = _decodeWindowRect(map['windowRect']);
    switch (method) {
      case DesktopWindowMethodNames.floatingMetricsCommittedIntent:
        if (windowRect == null) {
          return null;
        }
        return DesktopFloatingMetricsCommittedIntent(
          instanceId: instanceId,
          windowRect: windowRect,
          fontSize: asDouble(map['fontSize']) ?? 30.0,
        );
      case DesktopWindowMethodNames.floatingActionIntent:
        final DesktopWindowActionType? action =
            DesktopWindowActionType.tryParse(map['action']);
        if (action == null) {
          return null;
        }
        final DesktopPlaybackControlTask? controlTask =
            DesktopPlaybackControlTask.tryParse(
              map['controlTask']?.toString() ?? '',
            );
        return DesktopFloatingActionWindowIntent(
          instanceId: instanceId,
          action: action,
          controlTask: controlTask,
        );
      default:
        return null;
    }
  }

  static DesktopPanelWindowIntent? decodePanelIntent(
    String method,
    Object? payload,
  ) {
    final Map<Object?, Object?> map = asMap(payload);
    final int instanceId = asInt(map['instanceId']) ?? -1;
    final int panelId = asInt(map['panelId']) ?? -1;
    if (instanceId < 0 || panelId < 0) {
      return null;
    }
    switch (method) {
      case DesktopWindowMethodNames.panelActionIntent:
        final DesktopWindowActionType? action =
            DesktopWindowActionType.tryParse(map['action']);
        if (action == null) {
          return null;
        }
        final DesktopPlaybackControlTask? controlTask =
            DesktopPlaybackControlTask.tryParse(
              map['controlTask']?.toString() ?? '',
            );
        return DesktopPanelActionIntent(
          instanceId: instanceId,
          panelId: panelId,
          action: action,
          controlTask: controlTask,
        );
      default:
        return null;
    }
  }

  static Map<String, Object?> _encodeLyrics(Lyrics lyrics) {
    return <String, Object?>{
      'songInfo': lyrics.songInfo.toMap(),
      'source': lyrics.source.value,
      'data': _encodeLyricsData(lyrics.data),
      'types': lyrics.types.map(
        (String key, LyricsType value) =>
            MapEntry<String, Object?>(key, value.value),
      ),
      'tags': Map<String, Object?>.from(lyrics.tags),
      'id': lyrics.id,
      'accessKey': lyrics.accessKey,
      'durationMs': lyrics.durationMs,
      'creator': lyrics.creator,
      'score': lyrics.score,
      'path': lyrics.path,
      'cached': lyrics.cached,
    };
  }

  static Lyrics _decodeLyrics(Map<Object?, Object?> payload) {
    final Map<Object?, Object?> rawData = asMap(payload['data']);
    final Map<String, LyricsData> data = <String, LyricsData>{};
    rawData.forEach((Object? key, Object? value) {
      final String lang = key?.toString() ?? '';
      final List<Object?> lines = value is List<Object?> ? value : <Object?>[];
      data[lang] = lines
          .map((Object? item) => _decodeLyricsLine(asMap(item)))
          .toList(growable: false);
    });

    final Map<String, LyricsType> types = <String, LyricsType>{};
    final Map<Object?, Object?> rawTypes = asMap(payload['types']);
    rawTypes.forEach((Object? key, Object? value) {
      types[key?.toString() ?? ''] = LyricsType.fromValue(value);
    });

    final Map<String, String> tags = <String, String>{};
    final Map<Object?, Object?> rawTags = asMap(payload['tags']);
    rawTags.forEach((Object? key, Object? value) {
      tags[key?.toString() ?? ''] = value?.toString() ?? '';
    });

    return Lyrics(
      songInfo: SongInfo.fromMap(
        Map<String, Object?>.from(asMap(payload['songInfo'])),
      ),
      source: Source.fromValue(payload['source'] ?? Source.local),
      data: data,
      types: types,
      tags: tags,
      id: payload['id']?.toString(),
      accessKey: payload['accessKey']?.toString(),
      durationMs: asInt(payload['durationMs']),
      creator: payload['creator']?.toString(),
      score: asInt(payload['score']),
      path: payload['path']?.toString(),
      cached: asBool(payload['cached']) ?? false,
    );
  }

  static Map<String, Object?> _encodeLyricsData(Map<String, LyricsData> data) {
    return <String, Object?>{
      for (final MapEntry<String, LyricsData> entry in data.entries)
        entry.key: entry.value
            .map<Map<String, Object?>>(_encodeLyricsLine)
            .toList(growable: false),
    };
  }

  static Map<String, Object?> _encodeLyricsLine(LyricsLine line) {
    return <String, Object?>{
      'startMs': line.startMs,
      'endMs': line.endMs,
      'words': line.words
          .map<Map<String, Object?>>(
            (LyricsWord word) => <String, Object?>{
              'startMs': word.startMs,
              'endMs': word.endMs,
              'text': word.text,
            },
          )
          .toList(growable: false),
    };
  }

  static LyricsLine _decodeLyricsLine(Map<Object?, Object?> payload) {
    final List<Object?> words = payload['words'] is List<Object?>
        ? payload['words']! as List<Object?>
        : <Object?>[];
    return LyricsLine(
      startMs: asInt(payload['startMs']),
      endMs: asInt(payload['endMs']),
      words: words
          .map((Object? word) {
            final Map<Object?, Object?> map = asMap(word);
            return LyricsWord(
              startMs: asInt(map['startMs']),
              endMs: asInt(map['endMs']),
              text: map['text']?.toString() ?? '',
            );
          })
          .toList(growable: false),
    );
  }

  static Map<Object?, Object?> asMap(Object? value) {
    return DynamicReader.asMap(value);
  }

  static bool? asBool(Object? value) {
    return DynamicReader.asBool(value);
  }

  static double? asDouble(Object? value) {
    return DynamicReader.asDouble(value);
  }

  static int? asInt(Object? value) {
    return DynamicReader.asInt(value);
  }

  static String? asString(Object? value) {
    return DynamicReader.asString(value);
  }

  static List<String> asStringList(Object? value) {
    return DynamicReader.asStringList(value);
  }

  static List<String> asStringListPreserveEmpty(Object? value) {
    return DynamicReader.asStringListPreserveEmpty(value);
  }

  static List<String> asLangList(Object? value) {
    return DynamicReader.readTokenList(
      value,
      normalizer: LyricsLanguageRegistry.normalizeKey,
    );
  }

  static WindowRect? _decodeWindowRect(Object? value) {
    if (value is! List || value.length != 4) {
      return null;
    }
    final double? left = asDouble(value[0]);
    final double? top = asDouble(value[1]);
    final double? width = asDouble(value[2]);
    final double? height = asDouble(value[3]);
    if (left == null ||
        top == null ||
        width == null ||
        height == null ||
        width < 0 ||
        height < 0) {
      return null;
    }
    return WindowRect(left: left, top: top, width: width, height: height);
  }

  static List<List<int>> encodeRgbColorList(List<RgbColor> colors) {
    return colors
        .map((RgbColor color) => <int>[color.r, color.g, color.b])
        .toList(growable: false);
  }

  static List<RgbColor> decodeRgbColorList(Object? value) {
    final List<Object?> list = value is List
        ? value.cast<Object?>()
        : const <Object?>[];
    if (list.isEmpty) {
      return const <RgbColor>[RgbColor(0, 255, 255), RgbColor(0, 128, 255)];
    }
    return list
        .whereType<List>()
        .map(
          (List tuple) => RgbColor(
            asInt(tuple.elementAtOrNull(0)) ?? 0,
            asInt(tuple.elementAtOrNull(1)) ?? 0,
            asInt(tuple.elementAtOrNull(2)) ?? 0,
          ),
        )
        .toList(growable: false);
  }

  static Uint8List? _decodeSceneBytes(Object? value) {
    if (value is Uint8List) {
      return value;
    }
    if (value is ByteData) {
      return _sceneBytesFromByteData(value);
    }
    return null;
  }

  static Uint8List _sceneBytesFromByteData(ByteData data) {
    // MethodChannel 可能传入共享底层 buffer 的 ByteData 视图。
    // 必须按视图范围取 bytes，避免把前后哨兵或其它 payload 一起送进 scene codec。
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
