import 'package:flutter/services.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

int _nextWindowsPanelHostOwnerToken = 1;

/// Windows embedded panel 原生宿主适配器。
class WindowsDesktopPanelHostAdapter implements DesktopWindowsPanelShellPort {
  WindowsDesktopPanelHostAdapter({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel,
      _ownerToken = _nextWindowsPanelHostOwnerToken++;

  static const MethodChannel _defaultChannel = MethodChannel(
    'lddc/windows_desktop_panel_host',
  );

  final MethodChannel _channel;
  final int _ownerToken;
  bool _disposed = false;

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
  }

  @override
  Future<DesktopPanelSurfaceState> createPanel({
    required DesktopPanelCreateRequest request,
  }) async {
    late final Object? payload;
    try {
      payload = await _channel
          .invokeMethod<Object?>('createPanel', <String, Object?>{
            'instanceId': request.instanceId,
            'panelId': request.panelId,
            'ownerToken': _ownerToken,
            'hostWindowId': request.hostWindowId,
            'channelName': request.channelName,
            'generation': request.generation,
            'requestedWidth': request.initialSurface?.width,
            'requestedHeight': request.initialSurface?.height,
            'requestedSizeSpace': request.initialSurface?.sizeSpace.name,
            'requestedVisible': request.initialSurface?.visible,
          });
    } on PlatformException catch (error) {
      if (error.code == 'surface_unready') {
        throw const DesktopPanelSurfaceUnavailable();
      }
      rethrow;
    }
    return DesktopPanelSurfaceState.fromPayload(payload) ??
        (throw StateError('embedded panel native create 未返回 surface state'));
  }

  @override
  Future<DesktopPanelSurfaceState> updatePanelSurface({
    required int instanceId,
    required int panelId,
    required PanelSurfaceUpdate update,
  }) async {
    final Object? payload = await _channel
        .invokeMethod<Object?>('updatePanelSurface', <String, Object?>{
          'instanceId': instanceId,
          'panelId': panelId,
          'ownerToken': _ownerToken,
          'width': update.width,
          'height': update.height,
          'sizeSpace': update.sizeSpace.name,
          'visible': update.visible,
        });
    return DesktopPanelSurfaceState.fromPayload(payload) ??
        (throw StateError('embedded panel surface 更新未返回 surface state'));
  }

  @override
  Future<void> setPanelVisibility({
    required int instanceId,
    required int panelId,
    required bool visible,
  }) {
    return _channel.invokeMethod<void>('setPanelVisibility', <String, Object?>{
      'instanceId': instanceId,
      'panelId': panelId,
      'ownerToken': _ownerToken,
      'visible': visible,
    });
  }

  @override
  Future<void> destroyPanel({required int instanceId, required int panelId}) {
    return _channel.invokeMethod<void>('destroyPanel', <String, Object?>{
      'instanceId': instanceId,
      'panelId': panelId,
      'ownerToken': _ownerToken,
    });
  }
}
