import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../logging/desktop_lyrics_logger.dart';

import '../projection/desktop_lyrics_scene.dart';
import '../render/desktop_lyrics_perf_stats.dart';
import 'desktop_panel_host.dart';
import 'desktop_window_interaction.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_method_names.dart';
import 'desktop_window_payload_codec.dart';

typedef EmbeddedPanelMethodCallHandler =
    Future<dynamic> Function(MethodCall call);

/// Embedded Panel 运行时所需的最小双向通道。
///
/// Windows 原生 channel 的注册、owner token 和异常转换仍由 LDDC 宿主实现；
/// 共享包只消费此端口，因此第三方应用可以接入自己的 child-engine 宿主。
abstract interface class EmbeddedPanelMethodChannelPort {
  Future<T?> invokeMethod<T>(String method, [Object? arguments]);

  Future<void> setMethodCallHandler(EmbeddedPanelMethodCallHandler? handler);
}

class DesktopEmbeddedPanelLaunchPayload {
  const DesktopEmbeddedPanelLaunchPayload({
    required this.instanceId,
    required this.panelId,
    required this.hostWindowId,
    required this.channelName,
    required this.generation,
  });

  final int instanceId;
  final int panelId;
  final int hostWindowId;
  final String channelName;
  final int generation;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'instanceId': instanceId,
      'panelId': panelId,
      'hostWindowId': hostWindowId,
      'channelName': channelName,
      'generation': generation,
    };
  }

  String encode() => jsonEncode(toJson());

  factory DesktopEmbeddedPanelLaunchPayload.decode(Object? raw) {
    if (raw is DesktopEmbeddedPanelLaunchPayload) {
      return raw;
    }
    if (raw is String) {
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('embedded panel launch payload is empty');
      }
      final Object? decoded = jsonDecode(trimmed);
      if (decoded is Map<Object?, Object?>) {
        return DesktopEmbeddedPanelLaunchPayload.fromMap(decoded);
      }
    }
    if (raw is Map<Object?, Object?>) {
      return DesktopEmbeddedPanelLaunchPayload.fromMap(raw);
    }
    throw FormatException('invalid embedded panel launch payload: $raw');
  }

  factory DesktopEmbeddedPanelLaunchPayload.fromMap(Map<Object?, Object?> map) {
    return DesktopEmbeddedPanelLaunchPayload(
      instanceId: DynamicReader.asInt(map['instanceId']) ?? 0,
      panelId: DynamicReader.asInt(map['panelId']) ?? 0,
      hostWindowId: DynamicReader.asInt(map['hostWindowId']) ?? 0,
      channelName: map['channelName']?.toString() ?? '',
      generation: DynamicReader.asInt(map['generation']) ?? 0,
    );
  }

  static DesktopEmbeddedPanelLaunchPayload fromEntrypointArgs(
    List<String> args,
  ) {
    if (args.length < 2 || args.first != 'embedded_panel') {
      throw FormatException('invalid embedded panel args: $args');
    }
    return DesktopEmbeddedPanelLaunchPayload.decode(args[1]);
  }
}

class DesktopEmbeddedPanelRuntime {
  DesktopEmbeddedPanelRuntime._();

  static final DesktopEmbeddedPanelRuntime instance =
      DesktopEmbeddedPanelRuntime._();

  DesktopEmbeddedPanelLaunchPayload? _launch;
  EmbeddedPanelMethodChannelPort? _channel;
  DesktopLyricsLogger _logger = const DesktopLyricsLogger(
    scope: 'desktop-lyrics/embedded-panel-runtime',
  );

  bool get isInitialized => _launch != null;

  DesktopEmbeddedPanelLaunchPayload get launch =>
      _launch ??
      (throw StateError('embedded panel runtime has not been initialized'));

  DesktopWindowLaunchArguments get windowLaunch => DesktopWindowLaunchArguments(
    role: DesktopWindowRole.panel,
    instanceId: launch.instanceId,
    panelId: launch.panelId,
    hostWindowId: launch.hostWindowId.toString(),
    generation: launch.generation,
  );

  final ValueNotifier<DesktopPanelContentState?> panelContent =
      ValueNotifier<DesktopPanelContentState?>(null);
  final ValueNotifier<DesktopPanelSurfaceState?> panelSurfaceState =
      ValueNotifier<DesktopPanelSurfaceState?>(null);

  Future<DesktopEmbeddedPanelLaunchPayload> ensureInitialized({
    required DesktopEmbeddedPanelLaunchPayload payload,
    required EmbeddedPanelMethodChannelPort channel,
    DesktopLyricsLogger? logger,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _channel?.setMethodCallHandler(null);
    _launch = payload;
    _channel = channel;
    _logger =
        logger ??
        const DesktopLyricsLogger(
          scope: 'desktop-lyrics/embedded-panel-runtime',
        );
    await _channel!.setMethodCallHandler(_handleMethodCall);
    await _channel!.invokeMethod<bool>(
      DesktopWindowMethodNames.panelRuntimeReady,
      <String, Object?>{
        'instanceId': payload.instanceId,
        'panelId': payload.panelId,
        'generation': payload.generation,
      },
    );
    _logger.info(
      'embedded panel runtime ready'
      ' instance=${payload.instanceId}'
      ' panel=${payload.panelId}'
      ' generation=${payload.generation}'
      ' host=${payload.hostWindowId}',
    );
    return payload;
  }

  Future<void> dispose() async {
    await _channel?.setMethodCallHandler(null);
    _channel = null;
    _launch = null;
    panelContent.value = null;
    panelSurfaceState.value = null;
    _logger = const DesktopLyricsLogger(
      scope: 'desktop-lyrics/embedded-panel-runtime',
    );
  }

  @visibleForTesting
  void debugResetForTests() {
    final EmbeddedPanelMethodChannelPort? oldChannel = _channel;
    if (oldChannel != null) {
      unawaited(oldChannel.setMethodCallHandler(null));
    }
    _launch = null;
    _channel = null;
    panelContent.value = null;
    panelSurfaceState.value = null;
    _logger = const DesktopLyricsLogger(
      scope: 'desktop-lyrics/embedded-panel-runtime',
    );
  }

  Future<bool> notifyPanelAction(DesktopPanelActionIntent intent) async {
    return await _channel?.invokeMethod<bool>(
          DesktopWindowMethodNames.panelActionIntent,
          DesktopWindowPayloadCodec.encodePanelActionIntent(intent),
        ) ??
        false;
  }

  Future<bool> notifyPresentationReady(
    DesktopPanelPresentationReady ready,
  ) async {
    return await _channel?.invokeMethod<bool>(
          DesktopWindowMethodNames.panelPresentationReady,
          DesktopWindowPayloadCodec.encodePanelPresentationReady(ready),
        ) ??
        false;
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case DesktopWindowMethodNames.panelApplyContent:
        final DesktopPanelContentPayload payload =
            DesktopWindowPayloadCodec.decodePanelContentPayload(call.arguments);
        final DesktopPanelContentState current =
            panelContent.value ?? _emptyPanelContent();
        if (payload.contentRevision < current.snapshot.contentRevision) {
          return true;
        }
        if (payload.contentRevision == current.snapshot.contentRevision) {
          return true;
        }
        final bool keepsCurrentScene = desktopSceneRefEquals(
          current.snapshot.sceneRef,
          payload.sceneRef,
        );
        final DesktopLyricsSceneDocument? sceneDocument =
            payload.sceneBytes == null || payload.sceneBytes!.isEmpty
            ? (keepsCurrentScene ? current.sceneDocument : null)
            : _decodeSceneDocument(payload.sceneBytes);
        panelContent.value = DesktopPanelContentState(
          snapshot: DesktopPanelWindowSnapshot(
            session: payload.session,
            anchor: current.snapshot.anchor,
            contentRevision: payload.contentRevision,
            sceneRef: payload.sceneRef,
          ),
          sceneDocument: sceneDocument,
        );
        return true;
      case DesktopWindowMethodNames.panelSyncAnchor:
        final DesktopPanelAnchorSnapshot nextAnchor =
            DesktopWindowPayloadCodec.decodePanelAnchorSnapshot(call.arguments);
        final DesktopPanelContentState current =
            panelContent.value ?? _emptyPanelContent();
        if (!_shouldAcceptAnchor(current.snapshot, nextAnchor)) {
          return true;
        }
        panelContent.value = DesktopPanelContentState(
          snapshot: DesktopPanelWindowSnapshot(
            session: current.snapshot.session,
            anchor: nextAnchor,
            contentRevision: current.snapshot.contentRevision,
            sceneRef: current.snapshot.sceneRef,
          ),
          sceneDocument: current.sceneDocument,
        );
        return true;
      case DesktopWindowMethodNames.panelSurfaceStateSync:
        final DesktopPanelSurfaceState? next =
            DesktopPanelSurfaceState.fromPayload(call.arguments);
        final DesktopPanelSurfaceState? current = panelSurfaceState.value;
        if (next == null ||
            (current != null &&
                next.surfaceRevision < current.surfaceRevision)) {
          return true;
        }
        panelSurfaceState.value = next;
        return true;
      default:
        throw MissingPluginException('未实现的 embedded panel 方法: ${call.method}');
    }
  }

  DesktopPanelContentState _emptyPanelContent() {
    return const DesktopPanelContentState(
      snapshot: DesktopPanelWindowSnapshot(
        session: DesktopPanelSessionSnapshot.empty(),
        anchor: DesktopPanelAnchorSnapshot(),
      ),
      sceneDocument: null,
    );
  }

  bool _shouldAcceptAnchor(
    DesktopPanelWindowSnapshot current,
    DesktopPanelAnchorSnapshot next,
  ) {
    if (next.syncRevision < current.anchor.syncRevision) {
      return false;
    }
    final String? sceneId = current.sceneRef?.sceneId;
    if (sceneId != null && next.sceneId != null && next.sceneId != sceneId) {
      return false;
    }
    return true;
  }

  DesktopLyricsSceneDocument? _decodeSceneDocument(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    DesktopLyricsPerfStats.instance.bump('sceneDecode');
    return const DesktopLyricsSceneCodec().decode(bytes);
  }
}
