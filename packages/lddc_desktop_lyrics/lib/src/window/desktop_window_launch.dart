import 'dart:convert';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../models/desktop_style_models.dart';

/// 桌面子窗口角色。
enum DesktopWindowRole { main, floating, selector, panel }

/// 子窗口启动参数。
///
/// 约束：
/// - `instanceId` 把窗口绑定到具体桌面歌词实例。
/// - `hostWindowId` 用于子窗口向主窗口回传意图。
class DesktopWindowLaunchArguments {
  const DesktopWindowLaunchArguments({
    required this.role,
    this.instanceId,
    this.panelId,
    this.hostWindowId,
    this.generation,
    this.initialWindowRect,
  });

  const DesktopWindowLaunchArguments.main()
    : role = DesktopWindowRole.main,
      instanceId = null,
      panelId = null,
      hostWindowId = null,
      generation = null,
      initialWindowRect = null;

  final DesktopWindowRole role;
  final int? instanceId;
  final int? panelId;
  final String? hostWindowId;
  final int? generation;
  final WindowRect? initialWindowRect;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role.name,
      'instanceId': instanceId,
      'panelId': panelId,
      'hostWindowId': hostWindowId,
      'generation': generation,
      'initialWindowRect': initialWindowRect?.toList(),
    };
  }

  String encode() => jsonEncode(toJson());

  static bool isDesktopMultiWindowEntrypoint(List<String> args) {
    if (args.isEmpty) {
      return false;
    }
    // `desktop_multi_window` 原生插件固定把子 engine 的第一个参数写成
    // `multi_window`。它只表示窗口入口类型，不属于桌面 service CLI。
    return args.first.trim() == 'multi_window';
  }

  factory DesktopWindowLaunchArguments.decode(Object? raw) {
    if (raw == null) {
      return const DesktopWindowLaunchArguments.main();
    }
    if (raw is DesktopWindowLaunchArguments) {
      return raw;
    }
    if (raw is String) {
      final String trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return const DesktopWindowLaunchArguments.main();
      }
      Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        // 普通 multi-window 参数损坏时不能让子窗口在 runApp 前崩溃；
        // embedded panel 必需 payload 仍在专用入口校验，这里只做可恢复兜底。
        return const DesktopWindowLaunchArguments.main();
      }
      if (decoded is Map<Object?, Object?>) {
        return DesktopWindowLaunchArguments.fromMap(decoded);
      }
      return const DesktopWindowLaunchArguments.main();
    }
    if (raw is Map<Object?, Object?>) {
      return DesktopWindowLaunchArguments.fromMap(raw);
    }
    return const DesktopWindowLaunchArguments.main();
  }

  factory DesktopWindowLaunchArguments.fromMap(Map<Object?, Object?> map) {
    return DesktopWindowLaunchArguments(
      role: _decodeRole(map['role']),
      instanceId: _asInt(map['instanceId']),
      panelId: _asInt(map['panelId']),
      hostWindowId: _asString(map['hostWindowId']),
      generation: _asInt(map['generation']),
      initialWindowRect: _decodeWindowRect(map['initialWindowRect']),
    );
  }

  static DesktopWindowRole _decodeRole(Object? value) {
    final String normalized = value?.toString().trim().toLowerCase() ?? '';
    for (final DesktopWindowRole role in DesktopWindowRole.values) {
      if (role.name == normalized) {
        return role;
      }
    }
    return DesktopWindowRole.main;
  }

  static int? _asInt(Object? value) {
    return DynamicReader.asInt(value);
  }

  static String? _asString(Object? value) {
    final String text = DynamicReader.asString(value) ?? '';
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  static WindowRect? _decodeWindowRect(Object? value) {
    if (value is! List<Object?> || value.length != 4) {
      return null;
    }
    final double? left = DynamicReader.asDouble(value[0]);
    final double? top = DynamicReader.asDouble(value[1]);
    final double? width = DynamicReader.asDouble(value[2]);
    final double? height = DynamicReader.asDouble(value[3]);
    if (left == null ||
        top == null ||
        width == null ||
        height == null ||
        !left.isFinite ||
        !top.isFinite ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    return WindowRect(left: left, top: top, width: width, height: height);
  }
}
