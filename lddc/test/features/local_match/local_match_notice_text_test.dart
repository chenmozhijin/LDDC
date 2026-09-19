import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_state.dart';
import 'package:lddc/src/features/local_match/presentation/local_match_notice_text.dart';

/// 通知文案映射层的完整性用例。
///
/// 逐个通知码跑一遍：新增通知码时如果忘了写文案会立刻失败；同时让映射层的每个
/// 分支在改动行覆盖率门禁下都有稳定覆盖（撤回历史方案时这条用例曾被误删）。
void main() {
  testWidgets('本地匹配所有通知码都能解析为当前语言文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    );
    final BuildContext context = tester.element(find.byType(SizedBox));

    for (final LocalMatchNoticeCode code in LocalMatchNoticeCode.values) {
      final String text = localMatchNoticeText(
        context,
        LocalMatchNotice(
          code: code,
          detail: '测试详情',
          // 校验失败通知把 issue 列表放在 extra 里，这里一并覆盖该分支。
          extra: const <LocalMatchRunValidationIssue>[
            LocalMatchRunValidationIssue(
              code: LocalMatchRunValidationCode.emptyQueue,
            ),
          ],
        ),
      );
      expect(text, isNotEmpty, reason: code.name);
    }

    // `unsupportedOperation` 在无详情时使用通用文案，有详情时原样展示详情。
    expect(
      localMatchNoticeText(
        context,
        const LocalMatchNotice(code: LocalMatchNoticeCode.unsupportedOperation),
      ),
      isNotEmpty,
    );
    expect(
      localMatchNoticeText(
        context,
        const LocalMatchNotice(
          code: LocalMatchNoticeCode.unsupportedOperation,
          detail: '自定义不支持说明',
        ),
      ),
      '自定义不支持说明',
    );
  });
}
