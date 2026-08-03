import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_sub_window_runtime.dart';
import 'desktop_window_backend.dart';
import 'desktop_window_launch.dart';
import 'desktop_window_style_channel.dart';
import 'desktop_window_shell_page.dart';

class DesktopSelectorWindowShellPage extends StatefulWidget {
  const DesktopSelectorWindowShellPage({
    super.key,
    required this.launch,
    required this.contentBuilder,
  });

  final DesktopWindowLaunchArguments launch;
  final DesktopSelectorWindowContentBuilder? contentBuilder;

  @override
  State<DesktopSelectorWindowShellPage> createState() =>
      DesktopSelectorWindowShellPageState();
}

class DesktopSelectorWindowShellPageState
    extends State<DesktopSelectorWindowShellPage>
    with WindowListener {
  final DesktopSubWindowRuntime _runtime = DesktopSubWindowRuntime.instance;
  DesktopSelectorWindowContext? _context;
  Future<void>? _configurationFuture;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _context = _runtime.selectorContext.value;
    _runtime.selectorContext.addListener(_handleContextChanged);
    _runtime.setPrepareCloseHandler(_prepareForClose);
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) {
        return;
      }
      _configurationFuture = _configureWindowSafely();
      unawaited(_configurationFuture);
    });
  }

  @override
  void dispose() {
    _closing = true;
    windowManager.removeListener(this);
    _runtime.selectorContext.removeListener(_handleContextChanged);
    _runtime.setPrepareCloseHandler(null);
    unawaited(
      _runtime.markCurrentWindowClosed(reason: 'selector-shell-dispose'),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DesktopSelectorWindowContentBuilder? contentBuilder =
        widget.contentBuilder;
    if (contentBuilder == null) {
      return const SizedBox.shrink();
    }
    return contentBuilder(
      context,
      DesktopSelectorWindowContentBuildData(
        instanceId: widget.launch.instanceId ?? 0,
        contextSnapshot: _context,
        onLyricsSelected: _runtime.notifySelectorLyricsSelected,
      ),
    );
  }

  @override
  Future<void> onWindowClose() async {
    // 标题栏关闭在选择器里只表示隐藏；真实销毁由宿主 destroy 统一管理，
    // 避免 hidden/closed 两套同义协议让 session 生命周期分叉。
    await _runtime.notifySelectorHidden();
    await windowManager.hide();
    await _runtime.markCurrentWindowHidden(reason: 'selector-close-request');
  }

  Future<void> _configureWindow() async {
    await windowManager.setPreventClose(true);
    if (!mounted || _closing) {
      return;
    }
    // desktop_multi_window 已把子窗口以 hidden-at-launch 方式创建，这里只需
    // 设置真正使用的尺寸与背景。window_manager 的 waitUntilReadyToShow
    // 会额外创建 ITaskbarList3，而该插件析构时不释放它，反复创建
    // 子 engine 会导致 COM 对象累积。
    // 选择器在紧凑布局下会把预览放入底部弹层，但搜索工具栏和底部主操作
    // 仍需要稳定的可用空间。限制极端缩放可以从原生窗口层阻止布局溢出，
    // 同时保留 560x480 小窗口场景，不强迫用户一直使用初始大尺寸。
    await windowManager.setMinimumSize(const Size(560, 480));
    await windowManager.setSize(const Size(1050, 720));
    await windowManager.setBackgroundColor(Colors.transparent);
    if (!mounted || _closing) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await desktopWindowStyleChannel.invokeMethod<bool>('centerWindow');
    } else {
      await windowManager.center();
    }
    if (!mounted || _closing) {
      return;
    }
    await _runtime.markCurrentWindowHidden(
      reason: 'selector-window-configured',
    );
  }

  Future<void> _configureWindowSafely() async {
    try {
      await _configureWindow();
    } on Object catch (error, stackTrace) {
      if (_closing) {
        return;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'LDDC desktop selector window',
          context: ErrorDescription('配置歌词选择器原生窗口时'),
        ),
      );
    }
  }

  Future<void> _prepareForClose() async {
    _closing = true;
    // 等待 waitUntilReadyToShow 等已发出的 native 调用返回，再允许宿主
    // 销毁 engine。Future 无法强制取消，仅检查 mounted 不能阻止晚到回调。
    await _configurationFuture;
  }

  void _handleContextChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _context = _runtime.selectorContext.value;
    });
  }
}
