import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 歌词操作按钮网格：把一组动作按钮按可用宽度排成一到两列。
///
/// 搜索预览抽屉与打开歌词页共用同一套操作区排布。此前的 `OverflowBar` 在窄屏上
/// 会把每个按钮挤成独立一行（真机上最后两个按钮还会被裁掉）；这里改为等宽网格：
/// 窄屏两列、宽屏最多 [maxCellWidth] 宽，极窄时退回单列。按钮内部文本允许换行，
/// 因此文本缩放放大后按钮变高而不是横向溢出。
final class LyricsActionGrid extends StatelessWidget {
  const LyricsActionGrid({
    super.key,
    required this.children,
    this.maxCellWidth = 148,
    this.spacing = 8,
  });

  final List<Widget> children;

  /// 单个按钮的最大宽度；超过后不再变宽，改为换行放下一列。
  final double maxCellWidth;

  final double spacing;

  /// 低于该宽度时两列会把按钮压得过窄，退回单列铺满可用宽度。
  static const double _minimumTwoColumnWidth = 96;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 无界宽度（例如被放进横向滚动容器）时按两列最大宽度布局，避免 0 宽。
        final double available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : maxCellWidth * 2 + spacing;
        final double twoColumnWidth = (available - spacing) / 2;
        final double cellWidth = twoColumnWidth >= _minimumTwoColumnWidth
            ? math.min(maxCellWidth, twoColumnWidth)
            : math.min(maxCellWidth, available);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(width: cellWidth, child: child),
          ],
        );
      },
    );
  }
}
