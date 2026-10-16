import 'package:flutter/material.dart';

import 'local_match_rules.dart';

/// 弹出"开始前需要处理的问题"完整清单。
///
/// 底部启动栏宽度有限，只能显示首条问题并用 `+N` 提示其余条数；明细必须放在
/// 用户点得开的地方。此前这些消息只写在可折叠的「匹配规则」卡片里，窄屏用户
/// 不展开卡片就看不到启动被阻止的原因。抽屉复用 [LocalMatchValidationNotice]
/// 渲染，标题与文案和桌面端卡片完全一致，不再维护第二份样式。
Future<void> showLocalMatchIssuesSheet({
  required BuildContext context,
  required List<String> messages,
}) async {
  if (messages.isEmpty) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) {
      // 问题可能同时包含语言、来源与目录树缺口；只让清单滚动，关闭按钮常驻。
      final double maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.6;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Flexible(
                  child: SingleChildScrollView(
                    child: LocalMatchValidationNotice(
                      messages: messages,
                      // 抽屉本身就是"看全部"的入口，不能再折叠成"还有 N 个"。
                      collapseOverflow: false,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(
                    MaterialLocalizations.of(sheetContext).closeButtonLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
