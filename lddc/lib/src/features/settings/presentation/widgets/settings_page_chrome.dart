import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../application/settings_page_models.dart';
import 'settings_data_helpers.dart';

class SettingsPageBounds extends StatelessWidget {
  const SettingsPageBounds({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: child,
      ),
    );
  }
}

class SettingsAnchorBar extends StatelessWidget {
  const SettingsAnchorBar({
    super.key,
    required this.sections,
    required this.activeSection,
    required this.onSelected,
  });

  final List<SettingsSection> sections;
  final SettingsSection activeSection;
  final ValueChanged<SettingsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: sections
              .map(
                (SettingsSection section) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey<String>('settings_anchor_${section.name}'),
                    selected: activeSection == section,
                    label: Text(
                      settingsSectionMeta(section, context.l10n).title,
                    ),
                    onSelected: (_) => onSelected(section),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class SettingsPinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SettingsPinnedHeaderDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant SettingsPinnedHeaderDelegate oldDelegate) {
    return oldDelegate.extent != extent || oldDelegate.child != child;
  }
}
