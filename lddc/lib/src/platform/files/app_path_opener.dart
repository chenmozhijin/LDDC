import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show AppPathOpener;

/// 默认路径打开实现：桌面端调用系统文件管理器，移动端保持显式不支持。
final class AppPathOpenerImpl implements AppPathOpener {
  AppPathOpenerImpl({
    Future<void> Function(String executable, List<String> arguments)?
    processStarter,
    TargetPlatform Function()? platformResolver,
  }) : _processStarter = processStarter ?? _startDetached,
       _platformResolver = platformResolver ?? _defaultPlatformResolver;

  final Future<void> Function(String executable, List<String> arguments)
  _processStarter;
  final TargetPlatform Function() _platformResolver;

  @override
  Future<void> openFile(String path) {
    return _openPath(path);
  }

  @override
  Future<void> openDirectory(String path) {
    return _openPath(path);
  }

  Future<void> _openPath(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('当前平台不支持打开系统路径');
    }
    final String normalized = path.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(path, 'path', '路径不能为空');
    }
    final TargetPlatform platform = _platformResolver();
    final (String executable, List<String> arguments) = switch (platform) {
      TargetPlatform.windows => ('explorer', <String>[normalized]),
      TargetPlatform.macOS => ('open', <String>[normalized]),
      TargetPlatform.linux => ('xdg-open', <String>[normalized]),
      _ => throw UnsupportedError('当前平台不支持打开系统路径'),
    };
    // 系统打开命令成功拉起即视为完成；默认使用 detached 模式，不创建需要
    // Flutter 继续消费的 stdout/stderr 管道，也不持有无业务用途的 Process。
    await _processStarter(executable, arguments);
  }

  static TargetPlatform _defaultPlatformResolver() => defaultTargetPlatform;

  static Future<void> _startDetached(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }
}
