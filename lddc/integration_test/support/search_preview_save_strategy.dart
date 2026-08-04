enum IntegrationSearchPreviewSaveAction { file, directory }

IntegrationSearchPreviewSaveAction searchPreviewSaveActionForPlatform(
  String platform,
) {
  return switch (platform) {
    'android' || 'ios' => IntegrationSearchPreviewSaveAction.file,
    'windows' ||
    'macos' ||
    'linux' => IntegrationSearchPreviewSaveAction.directory,
    // 集成测试必须显式声明受支持平台。未知平台若静默走桌面分支，会再次把
    // 不存在的按钮误报为业务页面超时，因此这里立即失败并暴露 runner 错配。
    _ => throw UnsupportedError('不支持的集成测试平台: $platform'),
  };
}
