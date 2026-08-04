import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/accessibility/app_action_semantics.dart';
import '../../../../core/i18n/lyrics_ui_host_mapper.dart';
import '../../../../shared/ui/components/components.dart';
import '../../application/local_match_page_controller.dart';
import '../../application/local_match_page_state.dart';
import '../../application/local_match_run_validator.dart';
import 'local_match_bottom_and_helpers.dart';

class LocalMatchQueueHeader extends StatelessWidget {
  const LocalMatchQueueHeader({
    super.key,
    required this.queueLength,
    required this.desktopMode,
    required this.controller,
  });

  final int queueLength;
  final bool desktopMode;
  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.localMatchQueueTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                queueLength == 0
                    ? context.l10n.localMatchQueueEmptyHint
                    : desktopMode
                    ? context.l10n.localMatchQueueDesktopHint(queueLength)
                    : context.l10n.localMatchQueueMobileHint(queueLength),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey<String>('local_match_toggle_selection_mode'),
          onPressed: queueLength == 0 ? null : controller.enterSelectionMode,
          icon: const Icon(Icons.checklist_outlined),
          label: Text(context.l10n.localMatchActionBulkSelect),
        ),
      ],
    );
  }
}

class LocalMatchBulkSelectionToolbar extends StatelessWidget {
  const LocalMatchBulkSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.selectedItemIds,
    required this.hasQueue,
    required this.isDesktopMode,
    required this.controller,
    required this.allSelected,
  });

  final int selectedCount;
  final Set<String> selectedItemIds;
  final bool hasQueue;
  final bool isDesktopMode;
  final LocalMatchPageController controller;
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.localMatchSelectedCount(selectedCount),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.localMatchBulkActionHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey<String>('local_match_selection_close'),
              tooltip: context.l10n.localMatchActionExitSelection,
              onPressed: controller.exitSelectionMode,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton(
              key: const ValueKey<String>('local_match_selection_toggle_all'),
              onPressed: !hasQueue ? null : controller.toggleSelectAll,
              child: Text(
                allSelected
                    ? context.l10n.localMatchActionDeselectAll
                    : context.l10n.localMatchActionSelectAll,
              ),
            ),
            OutlinedButton(
              key: const ValueKey<String>('local_match_selection_delete'),
              onPressed: selectedItemIds.isEmpty
                  ? null
                  : controller.removeSelectedItems,
              child: Text(context.l10n.commonDelete),
            ),
            OutlinedButton(
              key: const ValueKey<String>('local_match_selection_set_root'),
              onPressed: !isDesktopMode || selectedItemIds.isEmpty
                  ? null
                  : controller.setRootPathForSelected,
              child: Text(context.l10n.localMatchActionSetRoot),
            ),
            OutlinedButton(
              key: const ValueKey<String>('local_match_selection_restore_root'),
              onPressed: !isDesktopMode || selectedItemIds.isEmpty
                  ? null
                  : controller.restoreDefaultRootPathForSelected,
              child: Text(context.l10n.commonRestoreDefault),
            ),
          ],
        ),
      ],
    );
  }
}

class LocalMatchCompactQueueStatusSummary extends StatelessWidget {
  const LocalMatchCompactQueueStatusSummary({super.key, required this.state});

  final LocalMatchPageState state;

  @override
  Widget build(BuildContext context) {
    final double? progress = state.progressTotal > 0
        ? state.progressCurrent / state.progressTotal
        : (state.isBusy ? null : 0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${localMatchPhaseLabel(context, state.taskPhase)} · ${state.progressCurrent} / ${state.progressTotal}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  localMatchProgressMessageText(context, state),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TaskMetricBadge(
                label: context.l10n.commonTotal,
                value: state.totalCount,
                icon: Icons.queue_music_outlined,
              ),
              TaskMetricBadge(
                label: context.l10n.commonSuccess,
                value: state.successCount,
                icon: Icons.check_circle_outline,
              ),
              TaskMetricBadge(
                label: context.l10n.commonSkipped,
                value: state.skipCount,
                icon: Icons.fast_forward_outlined,
              ),
              TaskMetricBadge(
                label: context.l10n.commonFailed,
                value: state.failCount,
                icon: Icons.error_outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LocalMatchImportActions extends StatelessWidget {
  const LocalMatchImportActions({
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
    final bool needsSaveRoot =
        state.isDesktopMode && state.saveMode != LocalMatchSaveMode.song;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        if (state.isDesktopMode) ...<Widget>[
          AppActionSemantics(
            identifier: AppSemanticsIdentifiers.localMatchPickFiles,
            label: context.l10n.commonAddFiles,
            onTap: state.isBusy ? null : controller.addSongFiles,
            child: FilledButton.icon(
              key: const ValueKey<String>('local_match_pick_files'),
              onPressed: state.isBusy ? null : controller.addSongFiles,
              icon: const Icon(Icons.queue_music_outlined),
              label: Text(context.l10n.commonAddFiles),
            ),
          ),
          AppActionSemantics(
            identifier: AppSemanticsIdentifiers.localMatchPickDirectories,
            label: context.l10n.localMatchActionAddFolders,
            onTap: state.isBusy ? null : controller.addSongDirectories,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('local_match_pick_dirs'),
              onPressed: state.isBusy ? null : controller.addSongDirectories,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(context.l10n.localMatchActionAddFolders),
            ),
          ),
          if (needsSaveRoot)
            AppActionSemantics(
              identifier: AppSemanticsIdentifiers.localMatchSaveRoot,
              label: context.l10n.localMatchActionSelectSaveRoot,
              onTap: state.isBusy ? null : controller.selectSaveRootDirectory,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('local_match_select_save_root'),
                onPressed: state.isBusy
                    ? null
                    : controller.selectSaveRootDirectory,
                icon: const Icon(Icons.drive_folder_upload_outlined),
                label: Text(context.l10n.localMatchActionSelectSaveRoot),
              ),
            ),
        ] else
          AppActionSemantics(
            identifier: AppSemanticsIdentifiers.localMatchPickTree,
            label: state.androidTreeToken == null
                ? context.l10n.localMatchActionSelectTree
                : context.l10n.localMatchActionReselectTree,
            onTap: state.isBusy ? null : controller.selectAndroidTree,
            child: FilledButton.icon(
              key: const ValueKey<String>('local_match_pick_tree'),
              onPressed: state.isBusy ? null : controller.selectAndroidTree,
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(
                state.androidTreeToken == null
                    ? context.l10n.localMatchActionSelectTree
                    : context.l10n.localMatchActionReselectTree,
              ),
            ),
          ),
        OutlinedButton.icon(
          key: const ValueKey<String>('local_match_clear_queue'),
          onPressed: state.isBusy ? null : controller.clearQueue,
          icon: const Icon(Icons.clear_all_outlined),
          label: Text(context.l10n.commonClearQueue),
        ),
        if (showInlineStartAction)
          AppActionSemantics(
            identifier: AppSemanticsIdentifiers.localMatchStart,
            label: state.isBusy
                ? context.l10n.actionCancel
                : context.l10n.localMatchActionStart,
            onTap: localMatchResolveStartAction(state)
                ? controller.startOrCancel
                : null,
            child: FilledButton.icon(
              key: const ValueKey<String>('local_match_header_start'),
              onPressed: localMatchResolveStartAction(state)
                  ? controller.startOrCancel
                  : null,
              icon: Icon(
                state.isBusy
                    ? Icons.stop_circle_outlined
                    : Icons.play_arrow_outlined,
              ),
              label: Text(
                state.isBusy
                    ? context.l10n.actionCancel
                    : context.l10n.localMatchActionStart,
              ),
            ),
          ),
      ],
    );
  }
}

class LocalMatchPathNotice extends StatelessWidget {
  const LocalMatchPathNotice({
    super.key,
    required this.state,
    this.dense = false,
  });

  final LocalMatchPageState state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (state.isAndroidMode) {
      final String label =
          state.androidTreeToken?.displayName ??
          context.l10n.localMatchTreeNotSelected;
      return TonalInlineNotice(icon: Icons.account_tree_outlined, text: label);
    }
    if (state.saveMode == LocalMatchSaveMode.song) {
      return TonalInlineNotice(
        icon: Icons.info_outline,
        text: context.l10n.localMatchSaveToSongDirectoryHint,
      );
    }

    final String? path = state.saveRootPath?.trim();
    final bool hasPath = path?.isNotEmpty == true;
    final String message = hasPath
        ? context.l10n.localMatchSaveRootPath(path!)
        : context.l10n.localMatchSaveRootRequired;
    final Color color = hasPath
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : Theme.of(context).colorScheme.error;
    return Tooltip(
      message: message,
      child: Row(
        children: <Widget>[
          Icon(
            hasPath ? Icons.drive_folder_upload_outlined : Icons.error_outline,
            color: color,
            size: dense ? 16 : 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (dense
                          ? Theme.of(context).textTheme.bodySmall
                          : Theme.of(context).textTheme.bodyMedium)
                      ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class LocalMatchRuleFields extends StatelessWidget {
  const LocalMatchRuleFields({
    super.key,
    required this.state,
    required this.controller,
    required this.collapseAdvanced,
    required this.sourceWidth,
    required this.wideFieldWidth,
    required this.narrowFieldWidth,
    this.includeSaveRootField = true,
    this.includeFooterHint = true,
    this.includeValidation = true,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;
  final bool collapseAdvanced;
  final double sourceWidth;
  final double wideFieldWidth;
  final double narrowFieldWidth;
  final bool includeSaveRootField;
  final bool includeFooterHint;
  final bool includeValidation;

  @override
  Widget build(BuildContext context) {
    final List<String> validationMessages = localMatchVisualValidationMessages(
      context,
      state,
    );
    final List<Widget> visibleFields = <Widget>[
      LocalMatchRuleField(
        label: context.l10n.commonSource,
        width: sourceWidth,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: localMatchAvailableSources(context)
              .map((Source source) {
                return FilterChip(
                  label: Text(localMatchSourceLabel(context, source)),
                  selected: state.selectedSources.contains(source),
                  onSelected: state.isBusy
                      ? null
                      : (_) => controller.toggleSource(source),
                );
              })
              .toList(growable: false),
        ),
      ),
      LocalMatchRuleField(
        label: context.l10n.localMatchFieldLyricsType,
        width: wideFieldWidth,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: LyricsLanguageSegments(
            selected: state.selectedLangs.toSet(),
            strings: context.l10n.toLyricsUiStrings(),
            onSelectionChanged: controller.updateSelectedLangs,
          ),
        ),
      ),
      LocalMatchRuleField(
        label: context.l10n.localMatchFieldOutputStrategy,
        width: narrowFieldWidth,
        child: DropdownButtonFormField<LocalMatchSaveToTagMode>(
          key: const ValueKey<String>('local_match_save_to_tag_mode'),
          initialValue: state.saveToTagMode,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: LocalMatchSaveToTagMode.values
              .map(
                (LocalMatchSaveToTagMode value) =>
                    DropdownMenuItem<LocalMatchSaveToTagMode>(
                      value: value,
                      child: Text(localMatchSaveToTagModeLabel(context, value)),
                    ),
              )
              .toList(growable: false),
          onChanged: state.isBusy
              ? null
              : (LocalMatchSaveToTagMode? value) {
                  if (value != null) {
                    controller.updateSaveToTagMode(value);
                  }
                },
        ),
      ),
    ];
    final List<Widget> advancedFields = <Widget>[
      if (state.isDesktopMode)
        LocalMatchRuleField(
          label: context.l10n.localMatchFieldSaveMode,
          width: narrowFieldWidth,
          child: DropdownButtonFormField<LocalMatchSaveMode>(
            key: const ValueKey<String>('local_match_save_mode'),
            initialValue: state.saveMode,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: LocalMatchSaveMode.values
                .map(
                  (LocalMatchSaveMode value) =>
                      DropdownMenuItem<LocalMatchSaveMode>(
                        value: value,
                        child: Text(localMatchSaveModeLabel(context, value)),
                      ),
                )
                .toList(growable: false),
            onChanged: state.isBusy
                ? null
                : (LocalMatchSaveMode? value) {
                    if (value != null) {
                      controller.updateSaveMode(value);
                    }
                  },
          ),
        ),
      LocalMatchRuleField(
        label: context.l10n.localMatchFieldFileNameMode,
        width: narrowFieldWidth,
        helperText: localMatchFileNameModeHint(context, state.fileNameMode),
        child: DropdownButtonFormField<LocalMatchFileNameMode>(
          key: const ValueKey<String>('local_match_filename_mode'),
          initialValue: state.fileNameMode,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: LocalMatchFileNameMode.values
              .map(
                (LocalMatchFileNameMode value) =>
                    DropdownMenuItem<LocalMatchFileNameMode>(
                      value: value,
                      child: Text(localMatchFileNameModeLabel(context, value)),
                    ),
              )
              .toList(growable: false),
          onChanged: state.isBusy
              ? null
              : (LocalMatchFileNameMode? value) {
                  if (value != null) {
                    controller.updateFileNameMode(value);
                  }
                },
        ),
      ),
      LocalMatchRuleField(
        label: context.l10n.localMatchFieldLyricsFormat,
        width: narrowFieldWidth,
        child: LyricsFormatDropdown(
          key: const ValueKey<String>('local_match_format_dropdown'),
          value: state.lyricsFormat,
          strings: context.l10n.toLyricsUiStrings(),
          onChanged: controller.updateLyricsFormat,
        ),
      ),
      LocalMatchRuleField(
        label: context.l10n.localMatchFieldThreshold,
        width: wideFieldWidth,
        child: LocalMatchThresholdField(state: state, controller: controller),
      ),
      if (includeSaveRootField)
        LocalMatchRuleField(
          label: context.l10n.localMatchFieldSaveRoot,
          width: wideFieldWidth,
          child: LocalMatchPathNotice(state: state),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(spacing: 12, runSpacing: 12, children: visibleFields),
        if (collapseAdvanced) ...<Widget>[
          const SizedBox(height: 12),
          ExpansionTile(
            key: const ValueKey<String>('local_match_mobile_more_settings'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            title: Text(context.l10n.localMatchMoreSettings),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: advancedFields,
                ),
              ),
            ],
          ),
        ] else ...<Widget>[
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: advancedFields),
        ],
        if (includeFooterHint) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            state.isAndroidMode
                ? context.l10n.localMatchAndroidTreeSaveHint
                : state.saveMode == LocalMatchSaveMode.song
                ? context.l10n.localMatchSaveToSongDirectoryHint
                : context.l10n.localMatchFileNameTemplateHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (includeValidation && validationMessages.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          LocalMatchValidationNotice(messages: validationMessages),
        ],
      ],
    );
  }
}

class LocalMatchRuleCard extends StatelessWidget {
  const LocalMatchRuleCard({
    super.key,
    required this.state,
    required this.controller,
    required this.collapseAdvanced,
    required this.collapseCard,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;
  final bool collapseAdvanced;
  final bool collapseCard;

  @override
  Widget build(BuildContext context) {
    final Widget content = LocalMatchRuleFields(
      state: state,
      controller: controller,
      collapseAdvanced: collapseAdvanced,
      sourceWidth: collapseAdvanced ? 320 : 360,
      wideFieldWidth: 320,
      narrowFieldWidth: collapseAdvanced ? 320 : 220,
    );
    return Card(
      child: collapseCard
          ? ExpansionTile(
              key: const ValueKey<String>('local_match_rules_card'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(context.l10n.localMatchRulesTitle),
              subtitle: Text(
                context.l10n.localMatchRulesSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              children: <Widget>[content],
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.localMatchRulesTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  content,
                ],
              ),
            ),
    );
  }
}

class LocalMatchRuleField extends StatelessWidget {
  const LocalMatchRuleField({
    super.key,
    required this.label,
    required this.width,
    required this.child,
    this.helperText,
  });

  final String label;
  final double width;
  final Widget child;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          child,
          if (helperText case final String text) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LocalMatchThresholdField extends StatelessWidget {
  const LocalMatchThresholdField({
    super.key,
    required this.state,
    required this.controller,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    final bool skipConfigBlocked =
        localMatchSkipExistingConfigBlocked(state) && !state.skipExistingLyrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.localMatchMinScore,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  LocalMatchMinScoreControl(
                    value: state.minScore,
                    enabled: !state.isBusy,
                    onChanged: controller.updateMinScore,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.localMatchSkipExisting,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const ValueKey<String>(
                      'local_match_skip_existing_checkbox',
                    ),
                    value: state.skipExistingLyrics,
                    onChanged: state.isBusy || skipConfigBlocked
                        ? null
                        : (bool? value) => controller.updateSkipExistingLyrics(
                            value ?? false,
                          ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    title: Text(
                      state.skipExistingLyrics
                          ? context.l10n.commonEnabled
                          : context.l10n.commonDisabledByDefault,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (localMatchSkipExistingHint(context, state)
            case final String hint) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class LocalMatchMinScoreControl extends StatelessWidget {
  const LocalMatchMinScoreControl({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final int rounded = value.round().clamp(0, 100);
    return DecoratedBox(
      key: const ValueKey<String>('local_match_min_score_stepper'),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: enabled && rounded > 0
                ? () => onChanged((rounded - 1).toDouble())
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(
            child: Container(
              key: const ValueKey<String>('local_match_min_score_field'),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '$rounded',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: enabled && rounded < 100
                ? () => onChanged((rounded + 1).toDouble())
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

class LocalMatchValidationNotice extends StatelessWidget {
  const LocalMatchValidationNotice({super.key, required this.messages});

  final List<String> messages;

  @override
  Widget build(BuildContext context) {
    final List<String> visibleMessages = messages.length <= 3
        ? messages
        : <String>[
            ...messages.take(3),
            context.l10n.localMatchValidationMoreIssues(messages.length - 3),
          ];
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Text(
                context.l10n.localMatchValidationTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final String message in visibleMessages)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $message',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
