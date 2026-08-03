import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../application/local_match_page_controller.dart';
import '../../application/local_match_page_state.dart';
import 'local_match_queue.dart';
import 'local_match_rules.dart';

class LocalMatchCompactLayout extends StatelessWidget {
  const LocalMatchCompactLayout({super.key, required this.controller});

  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    final double queueHeight = math.max(
      320,
      MediaQuery.of(context).size.height * 0.42,
    );
    return ListView(
      children: <Widget>[
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final LocalMatchPageState state = ref.watch(
              localMatchPageControllerProvider,
            );
            return LocalMatchHeaderCard(
              state: state,
              controller: controller,
              showInlineStartAction: false,
            );
          },
        ),
        const SizedBox(height: 12),
        Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            final LocalMatchPageState state = ref.watch(
              localMatchPageControllerProvider,
            );
            return LocalMatchRuleCard(
              state: state,
              controller: controller,
              collapseAdvanced: false,
              collapseCard: true,
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: queueHeight,
          child: LocalMatchQueueCard(
            controller: controller,
            desktopMode: false,
            showEmbeddedStatusSummary: true,
          ),
        ),
      ],
    );
  }
}

class LocalMatchHeaderCard extends StatelessWidget {
  const LocalMatchHeaderCard({
    super.key,
    required this.state,
    required this.controller,
    required this.showInlineStartAction,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;
  final bool showInlineStartAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.l10n.localMatchImportAndRunTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LocalMatchImportActions(
              state: state,
              controller: controller,
              showInlineStartAction: showInlineStartAction,
            ),
            const SizedBox(height: 12),
            LocalMatchPathNotice(state: state),
          ],
        ),
      ),
    );
  }
}
