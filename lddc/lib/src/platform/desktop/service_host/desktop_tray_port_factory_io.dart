import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show ValueChanged, VoidCallback;
import 'package:tray_manager/tray_manager.dart';

import 'desktop_tray_port_types.dart';

DesktopTrayPort createDesktopTrayPort() => TrayManagerDesktopTrayPort();

final class TrayManagerDesktopTrayPort implements DesktopTrayPort {
  TrayManagerDesktopTrayPort() : _listener = _TrayManagerListener();

  final _TrayManagerListener _listener;
  VoidCallback? _onPrimaryAction;
  VoidCallback? _onSecondaryAction;
  ValueChanged<String>? _onSelected;
  bool _initialized = false;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  @override
  Future<void> initialize({required String iconAsset, String? toolTip}) async {
    if (_disposed) {
      throw StateError('TrayManagerDesktopTrayPort 已释放');
    }
    if (_initialized) {
      return;
    }
    _initialized = true;
    _listener.owner = this;
    trayManager.addListener(_listener);
    await trayManager.setIcon(iconAsset);
    if (toolTip != null && toolTip.trim().isNotEmpty) {
      try {
        await trayManager.setToolTip(toolTip.trim());
      } on Object {
        // 部分平台不支持 tooltip，忽略即可。
      }
    }
  }

  @override
  void setOnMenuItemSelected(ValueChanged<String>? onSelected) {
    _onSelected = onSelected;
  }

  @override
  void setOnPrimaryAction(VoidCallback? onPrimaryAction) {
    _onPrimaryAction = onPrimaryAction;
  }

  @override
  void setOnSecondaryAction(VoidCallback? onSecondaryAction) {
    _onSecondaryAction = onSecondaryAction;
  }

  @override
  Future<void> updateMenu(List<DesktopTrayMenuEntry> entries) async {
    await trayManager.setContextMenu(
      Menu(items: entries.map(_buildMenuItem).toList(growable: false)),
    );
  }

  @override
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _listener.owner = null;
    trayManager.removeListener(_listener);
    _onPrimaryAction = null;
    _onSecondaryAction = null;
    _onSelected = null;
    if (_initialized) {
      await trayManager.destroy();
      _initialized = false;
    }
  }

  void handleMenuItemClick(String key) {
    final ValueChanged<String>? onSelected = _onSelected;
    if (onSelected != null) {
      onSelected(key);
    }
  }

  void handlePrimaryAction() {
    _onPrimaryAction?.call();
  }

  void handleSecondaryAction() {
    _onSecondaryAction?.call();
  }

  @override
  Future<void> showContextMenu() async {
    await trayManager.popUpContextMenu();
  }

  @override
  Future<Rect?> getBounds() {
    return trayManager.getBounds();
  }

  MenuItem _buildMenuItem(DesktopTrayMenuEntry entry) {
    return switch (entry.kind) {
      DesktopTrayMenuEntryKind.action => MenuItem(
        key: entry.key,
        label: entry.label,
        disabled: !entry.enabled,
      ),
      DesktopTrayMenuEntryKind.checkbox => MenuItem.checkbox(
        key: entry.key,
        label: entry.label,
        checked: entry.checked,
        disabled: !entry.enabled,
      ),
      DesktopTrayMenuEntryKind.separator => MenuItem.separator(),
      DesktopTrayMenuEntryKind.submenu => MenuItem.submenu(
        key: entry.key,
        label: entry.label,
        submenu: Menu(
          items: entry.children.map(_buildMenuItem).toList(growable: false),
        ),
        disabled: !entry.enabled,
      ),
    };
  }
}

final class _TrayManagerListener with TrayListener {
  TrayManagerDesktopTrayPort? owner;

  @override
  void onTrayIconMouseDown() {
    final TrayManagerDesktopTrayPort? currentOwner = owner;
    if (currentOwner != null) {
      currentOwner.handlePrimaryAction();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    final TrayManagerDesktopTrayPort? currentOwner = owner;
    if (currentOwner != null) {
      currentOwner.handleSecondaryAction();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    final TrayManagerDesktopTrayPort? currentOwner = owner;
    final String? key = item.key;
    if (currentOwner != null && key != null && key.isNotEmpty) {
      currentOwner.handleMenuItemClick(key);
    }
  }
}
