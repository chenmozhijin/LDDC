import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../application/batch_convert_page_controller.dart';
import 'batch_convert_controls.dart';
import 'batch_convert_presentation_helpers.dart';
import 'batch_convert_queue.dart';
import 'batch_convert_status_strip.dart';

// 布局层只决定桌面双栏或移动单栏的组件摆放，不直接处理导入、转换或文件系统操作。
// 这样 route 壳、控制器和队列行可以分别维护，避免一个页面文件继续无限膨胀。
class BatchConvertDesktopLayout extends StatelessWidget {
  const BatchConvertDesktopLayout({
    super.key,
    required this.controller,
    required this.selectedItemId,
    required this.onSelectItem,
  });

  final BatchConvertPageController controller;
  final String? selectedItemId;
  final ValueChanged<String> onSelectItem;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? child) {
                  final BatchConvertStatusView statusView = ref.watch(
                    batchConvertPageControllerProvider.select(
                      batchConvertStatusViewOf,
                    ),
                  );
                  return BatchConvertStatusStrip(
                    view: statusView,
                    controller: controller,
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: BatchConvertQueueCard(
                  controller: controller,
                  compact: false,
                  selectedItemId: selectedItemId,
                  onSelectItem: onSelectItem,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 380,
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final BatchConvertControlsView controlsView = ref.watch(
                batchConvertPageControllerProvider.select(
                  batchConvertControlsViewOf,
                ),
              );
              return SingleChildScrollView(
                child: BatchConvertControlSidebar(
                  view: controlsView,
                  controller: controller,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class BatchConvertCompactLayout extends StatelessWidget {
  const BatchConvertCompactLayout({
    super.key,
    required this.controller,
    required this.selectedItemId,
    required this.onSelectItem,
    required this.controlsExpanded,
    required this.onControlsExpanded,
  });

  final BatchConvertPageController controller;
  final String? selectedItemId;
  final ValueChanged<String> onSelectItem;
  final bool controlsExpanded;
  final ValueChanged<bool> onControlsExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.navBatchConvert,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final BatchConvertStatusView statusView = ref.watch(
              batchConvertPageControllerProvider.select(
                batchConvertStatusViewOf,
              ),
            );
            return BatchConvertStatusStrip(
              view: statusView,
              controller: controller,
              compact: true,
            );
          },
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // 窄桌面和横屏手机的剩余高度可能不足以同时容纳展开设置与队列。
              // 两者放入同一个外层滚动区，队列再获得稳定的紧约束，避免内部
              // Expanded 落入无界高度，同时保证保存目录等控件可滚动到可点击位置。
              final double queueHeight = constraints.maxHeight < 320
                  ? 320
                  : constraints.maxHeight;
              return SingleChildScrollView(
                key: const ValueKey<String>(
                  'batch_convert_compact_workspace_scroll',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Consumer(
                      builder:
                          (BuildContext context, WidgetRef ref, Widget? child) {
                            final BatchConvertControlsView controlsView = ref
                                .watch(
                                  batchConvertPageControllerProvider.select(
                                    batchConvertControlsViewOf,
                                  ),
                                );
                            return BatchConvertCompactControlsCard(
                              view: controlsView,
                              controller: controller,
                              expanded: controlsExpanded,
                              onExpandedChanged: onControlsExpanded,
                            );
                          },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: queueHeight,
                      child: BatchConvertQueueCard(
                        controller: controller,
                        compact: true,
                        selectedItemId: selectedItemId,
                        onSelectItem: onSelectItem,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final BatchConvertControlsView controlsView = ref.watch(
              batchConvertPageControllerProvider.select(
                batchConvertControlsViewOf,
              ),
            );
            return BatchConvertBottomActionBar(
              view: controlsView,
              controller: controller,
            );
          },
        ),
      ],
    );
  }
}
