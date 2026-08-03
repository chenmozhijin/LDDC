import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/local_match_page_controller.dart';
import '../../application/local_match_page_state.dart';
import 'local_match_queue.dart';
import 'local_match_rules.dart';
import 'local_match_status.dart';

// 桌面端布局把队列和规则控制区并排展示；这里只负责桌面空间组织，
// 不直接读写文件或启动匹配任务，所有动作都转发给 controller。
class LocalMatchDesktopLayout extends StatelessWidget {
  const LocalMatchDesktopLayout({super.key, required this.controller});

  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              Consumer(
                builder: (BuildContext context, WidgetRef ref, Widget? child) {
                  final LocalMatchPageState state = ref.watch(
                    localMatchPageControllerProvider,
                  );
                  return LocalMatchStatusStrip(state: state, dense: true);
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LocalMatchQueueCard(
                  controller: controller,
                  desktopMode: true,
                  showEmbeddedStatusSummary: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 420,
          child: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final LocalMatchPageState state = ref.watch(
                localMatchPageControllerProvider,
              );
              return SingleChildScrollView(
                child: LocalMatchDesktopControlPanel(
                  state: state,
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

class LocalMatchDesktopControlPanel extends StatelessWidget {
  const LocalMatchDesktopControlPanel({
    super.key,
    required this.state,
    required this.controller,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('local_match_sidebar'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LocalMatchImportActions(
              state: state,
              controller: controller,
              showInlineStartAction: true,
            ),
            const SizedBox(height: 10),
            LocalMatchPathNotice(state: state, dense: true),
            const SizedBox(height: 10),
            LocalMatchRuleFields(
              state: state,
              controller: controller,
              collapseAdvanced: false,
              sourceWidth: 392,
              wideFieldWidth: 392,
              narrowFieldWidth: 190,
              includeSaveRootField: false,
              includeFooterHint: false,
            ),
          ],
        ),
      ),
    );
  }
}
