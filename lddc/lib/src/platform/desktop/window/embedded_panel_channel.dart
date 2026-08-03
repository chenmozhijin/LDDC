import 'package:flutter/services.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

class EmbeddedPanelChannelException implements Exception {
  EmbeddedPanelChannelException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() {
    if (details == null) {
      return 'EmbeddedPanelChannelException($code, $message)';
    }
    return 'EmbeddedPanelChannelException($code, $message, $details)';
  }
}

class EmbeddedPanelMethodChannel implements EmbeddedPanelMethodChannelPort {
  EmbeddedPanelMethodChannel(this.name)
    : _ownerToken = _nextEmbeddedPanelOwnerToken++;

  final String name;
  final int _ownerToken;

  @override
  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    _initializeEmbeddedPanelChannelManager();
    try {
      return await _embeddedPanelMethodChannel.invokeMethod<T>('invokeMethod', {
        'channel': name,
        'method': method,
        'arguments': arguments,
      });
    } on PlatformException catch (error) {
      throw EmbeddedPanelChannelException(
        error.code,
        error.message ??
            '调用 embedded panel channel 失败: channel=$name method=$method',
        error.details,
      );
    }
  }

  @override
  Future<void> setMethodCallHandler(
    EmbeddedPanelMethodCallHandler? handler,
  ) async {
    _initializeEmbeddedPanelChannelManager();
    if (handler != null) {
      final _EmbeddedPanelHandlerRegistration? current =
          _embeddedPanelHandlers[name];
      if (current != null) {
        if (current.ownerToken != _ownerToken) {
          throw EmbeddedPanelChannelException(
            'CHANNEL_OWNED',
            'embedded panel channel 已被其他 owner 注册: $name',
          );
        }
        _embeddedPanelHandlers[name] = _EmbeddedPanelHandlerRegistration(
          ownerToken: _ownerToken,
          handler: handler,
        );
        return;
      }
      try {
        await _embeddedPanelMethodChannel.invokeMethod<void>(
          'registerMethodHandler',
          <String, Object?>{'channel': name},
        );
      } on PlatformException catch (error) {
        throw EmbeddedPanelChannelException(
          error.code,
          error.message ?? '注册 embedded panel channel 失败: $name',
          error.details,
        );
      }
      _embeddedPanelHandlers[name] = _EmbeddedPanelHandlerRegistration(
        ownerToken: _ownerToken,
        handler: handler,
      );
      return;
    }

    final _EmbeddedPanelHandlerRegistration? current =
        _embeddedPanelHandlers[name];
    if (current == null || current.ownerToken != _ownerToken) {
      return;
    }
    try {
      await _embeddedPanelMethodChannel.invokeMethod<void>(
        'unregisterMethodHandler',
        <String, Object?>{'channel': name},
      );
    } on PlatformException {
      // 说明：这里即使原生侧已经先销毁，也要继续清本地 handler，
      // 避免旧 generation 的回调残留到新 channel 生命周期。
    } finally {
      final _EmbeddedPanelHandlerRegistration? latest =
          _embeddedPanelHandlers[name];
      if (latest != null && latest.ownerToken == _ownerToken) {
        _embeddedPanelHandlers.remove(name);
      }
    }
  }
}

const MethodChannel _embeddedPanelMethodChannel = MethodChannel(
  'lddc/embedded_panel_channels',
);
final Map<String, _EmbeddedPanelHandlerRegistration> _embeddedPanelHandlers =
    <String, _EmbeddedPanelHandlerRegistration>{};
bool _embeddedPanelChannelManagerInitialized = false;
int _nextEmbeddedPanelOwnerToken = 1;

final class _EmbeddedPanelHandlerRegistration {
  const _EmbeddedPanelHandlerRegistration({
    required this.ownerToken,
    required this.handler,
  });

  final int ownerToken;
  final EmbeddedPanelMethodCallHandler handler;
}

void _initializeEmbeddedPanelChannelManager() {
  if (_embeddedPanelChannelManagerInitialized) {
    return;
  }
  _embeddedPanelChannelManagerInitialized = true;
  _embeddedPanelMethodChannel.setMethodCallHandler((MethodCall call) async {
    if (call.method != 'methodCall') {
      throw MissingPluginException(
        '未实现的 embedded panel channel 方法: ${call.method}',
      );
    }
    final Map<Object?, Object?> arguments = call.arguments is Map
        ? Map<Object?, Object?>.from(call.arguments as Map<Object?, Object?>)
        : const <Object?, Object?>{};
    final String channelName = arguments['channel']?.toString() ?? '';
    final String method = arguments['method']?.toString() ?? '';
    final _EmbeddedPanelHandlerRegistration? registration =
        _embeddedPanelHandlers[channelName];
    if (registration == null) {
      throw EmbeddedPanelChannelException(
        'NO_HANDLER',
        '未找到 embedded panel channel handler: $channelName',
      );
    }
    return registration.handler(MethodCall(method, arguments['arguments']));
  });
}

bool isEmbeddedPanelChannelUnavailable(Object error) {
  return error is EmbeddedPanelChannelException &&
      (error.code == 'CHANNEL_UNREGISTERED' ||
          error.code == 'CHANNEL_NOT_FOUND');
}
