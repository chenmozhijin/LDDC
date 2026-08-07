import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/accessibility/app_action_semantics.dart';

void main() {
  test('原生平台控件 identifier 全局唯一且数量保持在收口范围', () {
    expect(
      AppSemanticsIdentifiers.all,
      hasLength(28),
      reason: '28 项包含原生操作入口、四个拖放目标以及预览结果证据；新增协议项必须重新审计',
    );
    expect(
      AppSemanticsIdentifiers.all.toSet(),
      hasLength(AppSemanticsIdentifiers.all.length),
    );
  });

  testWidgets('动作语义只暴露一个可点击节点并保留读屏标签', (WidgetTester tester) async {
    int tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppActionSemantics(
            identifier: AppSemanticsIdentifiers.openLyricsFile,
            label: '打开歌词文件',
            onTap: () => tapCount += 1,
            child: FilledButton(
              onPressed: () => tapCount += 1,
              child: const Text('打开歌词文件'),
            ),
          ),
        ),
      ),
    );

    final Finder action = find.bySemanticsIdentifier(
      AppSemanticsIdentifiers.openLyricsFile,
    );
    expect(action, findsOneWidget);
    expect(find.bySemanticsLabel('打开歌词文件'), findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    expect(tapCount, 1);
  });

  testWidgets('禁用动作仍可被原生框架发现但不会暴露点击动作', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppActionSemantics(
            identifier: AppSemanticsIdentifiers.saveLyricsFile,
            label: '保存歌词',
            onTap: null,
            child: FilledButton(onPressed: null, child: Text('保存歌词')),
          ),
        ),
      ),
    );

    final SemanticsNode node = tester.getSemantics(
      find.bySemanticsIdentifier(AppSemanticsIdentifiers.saveLyricsFile),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(node.getSemanticsData().flagsCollection.isEnabled, Tristate.isFalse);
  });
}
