import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  test('PageNotice 只保留统一统计字段且可作为 const 状态', () {
    const PageNotice<_NoticeCode> notice = PageNotice<_NoticeCode>(
      code: _NoticeCode.completed,
      successCount: 3,
      failureCount: 1,
      skippedCount: 2,
    );

    expect(notice.successCount, 3);
    expect(notice.failureCount, 1);
    expect(notice.skippedCount, 2);
  });

  test('OperationEpochGroup 未启动通道不接受 token 0', () {
    final OperationEpochGroup epochs = OperationEpochGroup();

    expect(epochs.isCurrent('missing', 0), isFalse);
  });

  test('OperationEpochGroup invalidateAll 只失效已启动通道', () {
    final OperationEpochGroup epochs = OperationEpochGroup();
    final int search = epochs.next('search');
    final int preview = epochs.next('preview');

    epochs.invalidateAll();

    expect(epochs.isCurrent('search', search), isFalse);
    expect(epochs.isCurrent('preview', preview), isFalse);
    expect(epochs.next('save'), 1);
  });
}

enum _NoticeCode { completed }
