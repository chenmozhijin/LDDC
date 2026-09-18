import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_state.dart';
import 'package:lddc/src/features/local_match/presentation/local_match_notice_text.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 通知文案是安卓编码 URI 可读化的唯一收口。
///
/// 这里逐个通知码跑一遍：既保证新增通知码不会漏写文案，也保证"编码 URI → 可读路径"
/// 的还原发生在所有出口，而不是个别页面各自打补丁。
void main() {
  const String treeUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic';
  const String songUri =
      'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2Fdemo.lrc';

  testWidgets('本地匹配所有通知码都能解析为不含编码 URI 的文案', (WidgetTester tester) async {
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
          detail: songUri,
          // 校验失败通知把 issue 列表放在 extra 里，这里一并覆盖该分支。
          extra: const <LocalMatchRunValidationIssue>[
            LocalMatchRunValidationIssue(
              code: LocalMatchRunValidationCode.emptyQueue,
            ),
          ],
        ),
      );
      expect(text, isNotEmpty, reason: code.name);
      expect(text, isNot(contains('content://')), reason: code.name);
      expect(text, isNot(contains('%2F')), reason: code.name);
    }
  });

  testWidgets('传入授权树标签时通知详情还原为树名层级路径', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox(),
      ),
    );
    final BuildContext context = tester.element(find.byType(SizedBox));

    final String text = localMatchNoticeText(
      context,
      const LocalMatchNotice(
        code: LocalMatchNoticeCode.scanFailed,
        detail: '读取失败：$songUri（权限不足）',
      ),
      songTree: const AndroidSafTreeLabel(uri: treeUri, label: '内部存储'),
    );

    // 编码 URI 被替换成"树名 / 相对目录 / 文件名"，其余文字保留。
    expect(text, contains('内部存储 / Album / demo.lrc'));
    expect(text, contains('权限不足'));
    expect(text, isNot(contains('content://')));
    expect(text, isNot(contains('%2F')));
  });
}
