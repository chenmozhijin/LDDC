import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

enum DesktopTrayMenuEntryKind { action, checkbox, separator, submenu }

final class DesktopTrayMenuEntry {
  const DesktopTrayMenuEntry.action({
    required this.key,
    required this.label,
    this.enabled = true,
  }) : kind = DesktopTrayMenuEntryKind.action,
       checked = false,
       children = const <DesktopTrayMenuEntry>[];

  const DesktopTrayMenuEntry.checkbox({
    required this.key,
    required this.label,
    required this.checked,
    this.enabled = true,
  }) : kind = DesktopTrayMenuEntryKind.checkbox,
       children = const <DesktopTrayMenuEntry>[];

  const DesktopTrayMenuEntry.separator()
    : kind = DesktopTrayMenuEntryKind.separator,
      key = '',
      label = '',
      enabled = false,
      checked = false,
      children = const <DesktopTrayMenuEntry>[];

  const DesktopTrayMenuEntry.submenu({
    required this.key,
    required this.label,
    required this.children,
    this.enabled = true,
  }) : kind = DesktopTrayMenuEntryKind.submenu,
       checked = false;

  final DesktopTrayMenuEntryKind kind;
  final String key;
  final String label;
  final bool enabled;
  final bool checked;
  final List<DesktopTrayMenuEntry> children;
}

abstract interface class DesktopTrayPort {
  Future<void> initialize({required String iconAsset, String? toolTip});

  Future<void> updateMenu(List<DesktopTrayMenuEntry> entries);

  void setOnPrimaryAction(VoidCallback? onPrimaryAction);

  void setOnSecondaryAction(VoidCallback? onSecondaryAction);

  void setOnMenuItemSelected(ValueChanged<String>? onSelected);

  Future<void> showContextMenu();

  Future<Rect?> getBounds();

  Future<void> dispose();
}

typedef DesktopTrayPortFactory = DesktopTrayPort Function();

final class DesktopNoopTrayPort implements DesktopTrayPort {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize({required String iconAsset, String? toolTip}) async {}

  @override
  void setOnPrimaryAction(VoidCallback? onPrimaryAction) {}

  @override
  void setOnSecondaryAction(VoidCallback? onSecondaryAction) {}

  @override
  void setOnMenuItemSelected(ValueChanged<String>? onSelected) {}

  @override
  Future<void> showContextMenu() async {}

  @override
  Future<Rect?> getBounds() async => null;

  @override
  Future<void> updateMenu(List<DesktopTrayMenuEntry> entries) async {}
}
