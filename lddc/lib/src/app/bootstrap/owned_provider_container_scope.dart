import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 在 Widget 生命周期内拥有并释放外部创建的 [ProviderContainer]。
///
/// `UncontrolledProviderScope` 只把现有容器暴露给子树，不会主动调用
/// `ProviderContainer.dispose`。桌面入口需要在 `runApp` 前读取 provider 来启动
/// 服务，因此不能改用普通 `ProviderScope` 延迟创建容器；这个组件补齐根树卸载、
/// 多引擎销毁和容器替换时的资源释放责任。
class OwnedProviderContainerScope extends StatefulWidget {
  const OwnedProviderContainerScope({
    required this.container,
    required this.child,
    super.key,
  });

  final ProviderContainer container;
  final Widget child;

  @override
  State<OwnedProviderContainerScope> createState() =>
      _OwnedProviderContainerScopeState();
}

class _OwnedProviderContainerScopeState
    extends State<OwnedProviderContainerScope> {
  @override
  void didUpdateWidget(OwnedProviderContainerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.container, widget.container)) {
      oldWidget.container.dispose();
    }
  }

  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: widget.container,
      child: widget.child,
    );
  }
}
