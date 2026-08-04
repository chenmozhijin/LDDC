import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/search_preview_save_strategy.dart';

void main() {
  test('移动平台使用保存文件，桌面平台使用保存目录', () {
    expect(
      searchPreviewSaveActionForPlatform('android'),
      IntegrationSearchPreviewSaveAction.file,
    );
    expect(
      searchPreviewSaveActionForPlatform('ios'),
      IntegrationSearchPreviewSaveAction.file,
    );
    for (final String platform in <String>['windows', 'macos', 'linux']) {
      expect(
        searchPreviewSaveActionForPlatform(platform),
        IntegrationSearchPreviewSaveAction.directory,
        reason: '$platform 必须使用桌面保存目录动作',
      );
    }
  });

  test('未知平台立即失败而不是自动降级到桌面动作', () {
    expect(
      () => searchPreviewSaveActionForPlatform('web'),
      throwsUnsupportedError,
    );
  });
}
