import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/settings/application/settings_page_models.dart';
import 'package:lddc/src/features/settings/presentation/settings_notice_text.dart';

/// 设置页通知文案映射层的完整性用例。
///
/// 逐个通知码跑一遍：新增通知码时如果忘了写文案会立刻失败；同时让映射层的每个分支
/// 在改动行覆盖率门禁下都有稳定覆盖（与本地匹配的同名用例保持一致的守卫方式）。
void main() {
  testWidgets('设置页所有通知码都能解析为当前语言文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    );
    final BuildContext context = tester.element(find.byType(SizedBox));

    for (final SettingsNoticeCode code in SettingsNoticeCode.values) {
      final String text = settingsNoticeText(context, code.name);
      expect(text, isNotEmpty, reason: code.name);
      // 未映射的码会原样返回码名（含驼峰），这条断言防止新增通知码时漏写 switch 分支。
      expect(text, isNot(code.name), reason: '${code.name} 未映射到本地化文案');
    }
  });

  testWidgets('平台不支持选择目录时渲染通用能力缺失文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    );
    final BuildContext context = tester.element(find.byType(SizedBox));
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('zh'));

    // 安卓端 pickDirectory 不支持时会写这个码：必须渲染成用户能看懂的能力缺失提示，
    // 而不是把内部码名直接抛给用户。
    expect(
      settingsNoticeText(context, SettingsNoticeCode.directoryPickerUnsupported.name),
      l10n.commonUnsupportedOperation,
    );
  });
}
