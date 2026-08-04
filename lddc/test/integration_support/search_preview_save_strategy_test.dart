import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/integration_harness.dart';
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

  test('步骤超时会先等待受保护动作收口再抛出原始超时', () async {
    bool actionCompleted = false;

    await expectLater(
      runStepWithTimeout<void>(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          actionCompleted = true;
        },
        timeout: const Duration(milliseconds: 1),
        label: 'guarded_action',
      ),
      throwsA(
        isA<TimeoutException>().having(
          (TimeoutException error) => error.message,
          'message',
          'guarded_action 超时',
        ),
      ),
    );
    expect(actionCompleted, isTrue);
  });
}
