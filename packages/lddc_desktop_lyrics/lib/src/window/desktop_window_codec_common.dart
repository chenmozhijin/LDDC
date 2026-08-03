import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../models/desktop_style_models.dart';
import '../projection/desktop_lyrics_projection_runtime.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_payload_codec.dart';

typedef DesktopPlaybackAnchorFields = ({
  int pluginPlaybackTimeMs,
  int? pluginSendTimeMs,
  int hostReceivedAtMs,
  bool isPlaying,
  int syncRevision,
  DesktopPlaybackEventKind eventKind,
  String? sceneId,
  String? songToken,
});

typedef DesktopSessionStyleFields = ({
  List<String> enabledLangs,
  List<RgbColor> playedColors,
  List<RgbColor> unplayedColors,
  String fontFamily,
  double fontSize,
  bool showFurigana,
  int refreshRate,
  DesktopWindowActionSnapshot actions,
  int sessionRevision,
});

Map<String, Object?> encodePlaybackAnchorFields({
  required int pluginPlaybackTimeMs,
  required int? pluginSendTimeMs,
  required int hostReceivedAtMs,
  required bool isPlaying,
  required int syncRevision,
  required DesktopPlaybackEventKind eventKind,
  required String? sceneId,
  required String? songToken,
}) {
  return <String, Object?>{
    'pluginPlaybackTimeMs': pluginPlaybackTimeMs,
    'pluginSendTimeMs': pluginSendTimeMs,
    'hostReceivedAtMs': hostReceivedAtMs,
    'isPlaying': isPlaying,
    'syncRevision': syncRevision,
    'eventKind': eventKind.name,
    'sceneId': sceneId,
    'songToken': songToken,
  };
}

DesktopPlaybackAnchorFields decodePlaybackAnchorFields(Object? payload) {
  final Map<Object?, Object?> map = DesktopWindowPayloadCodec.asMap(payload);
  return (
    pluginPlaybackTimeMs:
        DesktopWindowPayloadCodec.asInt(map['pluginPlaybackTimeMs']) ?? 0,
    pluginSendTimeMs: DesktopWindowPayloadCodec.asInt(map['pluginSendTimeMs']),
    hostReceivedAtMs:
        DesktopWindowPayloadCodec.asInt(map['hostReceivedAtMs']) ?? 0,
    isPlaying: DesktopWindowPayloadCodec.asBool(map['isPlaying']) ?? false,
    syncRevision: DesktopWindowPayloadCodec.asInt(map['syncRevision']) ?? 0,
    eventKind: _decodePlaybackEventKind(
      DesktopWindowPayloadCodec.asString(map['eventKind']),
    ),
    sceneId: DesktopWindowPayloadCodec.asString(map['sceneId']),
    songToken: DesktopWindowPayloadCodec.asString(map['songToken']),
  );
}

DesktopPlaybackEventKind _decodePlaybackEventKind(String? raw) {
  for (final DesktopPlaybackEventKind kind in DesktopPlaybackEventKind.values) {
    if (kind.name == raw) {
      return kind;
    }
  }
  return DesktopPlaybackEventKind.other;
}

Map<String, Object?> encodeSessionStyleFields(
  DesktopSessionStyleFields fields,
) {
  return <String, Object?>{
    'enabledLangs': fields.enabledLangs,
    'playedColors': DesktopWindowPayloadCodec.encodeRgbColorList(
      fields.playedColors,
    ),
    'unplayedColors': DesktopWindowPayloadCodec.encodeRgbColorList(
      fields.unplayedColors,
    ),
    'fontFamily': fields.fontFamily,
    'fontSize': fields.fontSize,
    'showFurigana': fields.showFurigana,
    'refreshRate': fields.refreshRate,
    'actions': DesktopWindowPayloadCodec.encodeWindowActionSnapshot(
      fields.actions,
    ),
    'sessionRevision': fields.sessionRevision,
  };
}

DesktopSessionStyleFields decodeSessionStyleFields(
  Map<Object?, Object?> map, {
  required double defaultFontSize,
}) {
  return (
    enabledLangs: DesktopWindowPayloadCodec.asLangList(map['enabledLangs']),
    playedColors: DesktopWindowPayloadCodec.decodeRgbColorList(
      map['playedColors'],
    ),
    unplayedColors: DesktopWindowPayloadCodec.decodeRgbColorList(
      map['unplayedColors'],
    ),
    fontFamily: map['fontFamily']?.toString() ?? '',
    fontSize:
        DesktopWindowPayloadCodec.asDouble(map['fontSize']) ?? defaultFontSize,
    showFurigana: DesktopWindowPayloadCodec.asBool(map['showFurigana']) ?? true,
    refreshRate: DesktopWindowPayloadCodec.asInt(map['refreshRate']) ?? -1,
    actions: DesktopWindowPayloadCodec.decodeWindowActionSnapshot(
      map['actions'],
    ),
    sessionRevision:
        DesktopWindowPayloadCodec.asInt(map['sessionRevision']) ?? 0,
  );
}

Map<String, Object?> encodeWindowActionFields(
  DesktopWindowActionSnapshot snapshot,
) {
  return <String, Object?>{
    'isInstrumental': snapshot.isInstrumental,
    'isAutoSearchDisabled': snapshot.isAutoSearchDisabled,
    'canUnlinkLyrics': snapshot.canUnlinkLyrics,
    'canOpenSelector': snapshot.canOpenSelector,
    'canShowMainWindow': snapshot.canShowMainWindow,
    'canOpenAssociationManager': snapshot.canOpenAssociationManager,
    'availableControlTasks': snapshot.availableControlTasks
        .map((DesktopPlaybackControlTask task) => task.value)
        .toList(growable: false),
    'clickThroughEnabled': snapshot.clickThroughEnabled,
    'floatingVisibilityMode': snapshot.floatingVisibilityMode.value,
  };
}

DesktopWindowActionSnapshot decodeWindowActionFields(
  Map<Object?, Object?> map,
) {
  final Set<DesktopPlaybackControlTask> tasks = <DesktopPlaybackControlTask>{};
  for (final String raw in DesktopWindowPayloadCodec.asStringList(
    map['availableControlTasks'],
  )) {
    final DesktopPlaybackControlTask? task =
        DesktopPlaybackControlTask.tryParse(raw);
    if (task != null) {
      tasks.add(task);
    }
  }
  return DesktopWindowActionSnapshot(
    isInstrumental:
        DesktopWindowPayloadCodec.asBool(map['isInstrumental']) ?? false,
    isAutoSearchDisabled:
        DesktopWindowPayloadCodec.asBool(map['isAutoSearchDisabled']) ?? false,
    canUnlinkLyrics:
        DesktopWindowPayloadCodec.asBool(map['canUnlinkLyrics']) ?? false,
    canOpenSelector:
        DesktopWindowPayloadCodec.asBool(map['canOpenSelector']) ?? true,
    canShowMainWindow:
        DesktopWindowPayloadCodec.asBool(map['canShowMainWindow']) ?? true,
    canOpenAssociationManager:
        DesktopWindowPayloadCodec.asBool(map['canOpenAssociationManager']) ??
        true,
    availableControlTasks: Set<DesktopPlaybackControlTask>.unmodifiable(tasks),
    clickThroughEnabled:
        DesktopWindowPayloadCodec.asBool(map['clickThroughEnabled']) ?? false,
    floatingVisibilityMode: DesktopFloatingVisibilityMode.fromValue(
      map['floatingVisibilityMode'],
    ),
  );
}

Map<String, Object?> encodeLyricsInfoBadgeFields(
  DesktopLyricsInfoBadgeSnapshot snapshot,
) {
  return <String, Object?>{
    'source': snapshot.source?.name,
    'lyricsType': snapshot.lyricsType?.name,
    'isInstrumental': snapshot.isInstrumental,
  };
}

DesktopLyricsInfoBadgeSnapshot decodeLyricsInfoBadgeFields(
  Map<Object?, Object?> map,
) {
  return DesktopLyricsInfoBadgeSnapshot(
    source: _enumByName(map['source'], Source.values),
    lyricsType: _enumByName(map['lyricsType'], LyricsType.values),
    isInstrumental:
        DesktopWindowPayloadCodec.asBool(map['isInstrumental']) ?? false,
  );
}

T? _enumByName<T extends Enum>(Object? rawValue, List<T> values) {
  final String? name = DesktopWindowPayloadCodec.asString(rawValue)?.trim();
  if (name == null || name.isEmpty) {
    return null;
  }
  for (final T value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}
