import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class DesktopPageInteractionScope extends StatefulWidget {
  const DesktopPageInteractionScope({
    super.key,
    required this.shortcuts,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> shortcuts;
  final Widget child;

  @override
  State<DesktopPageInteractionScope> createState() =>
      _DesktopPageInteractionScopeState();
}

final class _DesktopPageInteractionScopeState
    extends State<DesktopPageInteractionScope> {
  late final FocusNode _focusNode;
  bool _acceptShortcuts = true;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'DesktopPageInteractionScope');
    // EditableText 在自身内部注册了更近的文本编辑 Shortcuts，部分 Ctrl 组合会在
    // 事件冒泡到页面 CallbackShortcuts 之前被消费。early handler 仍使用 Flutter
    // 标准 ShortcutActivator 做匹配，但会在焦点树分发前给页面命令一次处理机会。
    FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKeyEvent);
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    // Windows UIA 可以把原生文本输入焦点交给 Flutter，但不会同步 FocusManager 的
    // primary focus。IndexedStack 已通过 Visibility.of 标出当前页，再叠加当前路由
    // 判断，既支持原生焦点，也不会触发隐藏页面或模态界面后的页面。
    if (!_acceptShortcuts) {
      return KeyEventResult.ignored;
    }
    for (final MapEntry<ShortcutActivator, VoidCallback> entry
        in widget.shortcuts.entries) {
      if (entry.key.accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _acceptShortcuts =
        Visibility.of(context) && (ModalRoute.of(context)?.isCurrent ?? true);
    return FocusTraversalGroup(
      child: Focus(focusNode: _focusNode, autofocus: true, child: widget.child),
    );
  }
}
