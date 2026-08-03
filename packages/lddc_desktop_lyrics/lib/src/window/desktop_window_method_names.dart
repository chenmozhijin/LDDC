/// 桌面多窗口公共方法名约束。
///
/// 所有消息都走 controller 级别的 `invokeMethod/setWindowMethodHandler`，
/// 避免把平台调用名散落到 reducer 或 widget 层。
class DesktopWindowMethodNames {
  const DesktopWindowMethodNames._();

  static const String floatingApplyContent =
      'lddc.desktop.floating.apply_content';
  static const String floatingAwaitReady = 'lddc.desktop.floating.await_ready';
  static const String floatingSyncAnchor = 'lddc.desktop.floating.sync_anchor';
  static const String floatingUpdateFlags =
      'lddc.desktop.floating.update_flags';
  static const String floatingFlushGeometry =
      'lddc.desktop.floating.flush_geometry';
  static const String floatingMetricsCommittedIntent =
      'lddc.desktop.floating.intent.metrics_committed';
  static const String floatingActionIntent =
      'lddc.desktop.floating.intent.action';

  static const String panelApplyContent = 'lddc.desktop.panel.apply_content';
  static const String panelSyncAnchor = 'lddc.desktop.panel.sync_anchor';
  static const String panelRuntimeReady = 'lddc.desktop.panel.runtime.ready';
  static const String panelSurfaceStateSync =
      'lddc.desktop.panel.surface_state';
  static const String panelPresentationReady =
      'lddc.desktop.panel.presentation_ready';
  static const String panelActionIntent = 'lddc.desktop.panel.intent.action';

  static const String selectorShow = 'lddc.desktop.selector.show';
  static const String selectorPresent = 'lddc.desktop.selector.present';
  static const String selectorRefresh = 'lddc.desktop.selector.refresh';
  static const String selectorConfigChanged =
      'lddc.desktop.selector.config_changed';
  static const String selectorRuntimeDiagnostics =
      'lddc.desktop.selector.runtime_diagnostics';
  static const String selectorHiddenIntent =
      'lddc.desktop.selector.intent.hidden';
  static const String selectorLyricsSelectedIntent =
      'lddc.desktop.selector.intent.lyrics_selected';
}
