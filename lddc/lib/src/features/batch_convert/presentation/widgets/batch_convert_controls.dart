import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/accessibility/app_action_semantics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../application/batch_convert_page_controller.dart';
import 'batch_convert_presentation_helpers.dart';

class BatchConvertControlSidebar extends StatelessWidget {
  const BatchConvertControlSidebar({
    required this.view,
    required this.controller,
    super.key,
  });

  final BatchConvertControlsView view;
  final BatchConvertPageController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.batchConvertControlsTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _ImportActions(view: view, controller: controller, compact: false),
            const SizedBox(height: 16),
            _OutputSettings(view: view, controller: controller),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AppActionSemantics(
                identifier: AppSemanticsIdentifiers.batchStart,
                label: view.isRunning
                    ? l10n.batchConvertCancel
                    : l10n.batchConvertStart,
                onTap: _startAction(view, controller),
                child: FilledButton.icon(
                  key: const ValueKey<String>('batch_convert_start_or_cancel'),
                  onPressed: _startAction(view, controller),
                  icon: Icon(
                    view.isRunning
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow_outlined,
                  ),
                  label: Text(
                    view.isRunning
                        ? l10n.batchConvertCancel
                        : l10n.batchConvertStart,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BatchConvertCompactControlsCard extends StatelessWidget {
  const BatchConvertCompactControlsCard({
    super.key,
    required this.view,
    required this.controller,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final BatchConvertControlsView view;
  final BatchConvertPageController controller;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      key: const ValueKey<String>('batch_convert_compact_controls'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: expanded,
            label: l10n.batchConvertCompactControlsTitle,
            child: InkWell(
              key: const ValueKey<String>(
                'batch_convert_compact_controls_toggle',
              ),
              onTap: () => onExpandedChanged(!expanded),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l10n.batchConvertCompactControlsTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.batchConvertCompactControlsSubtitle(
                              l10n.lyricsFormatLabel(view.targetFormat),
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      expanded
                          ? Icons.expand_less_outlined
                          : Icons.expand_more_outlined,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _ImportActions(
                    view: view,
                    controller: controller,
                    compact: true,
                  ),
                  const SizedBox(height: 16),
                  _OutputSettings(view: view, controller: controller),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportActions extends StatelessWidget {
  const _ImportActions({
    required this.view,
    required this.controller,
    required this.compact,
  });

  final BatchConvertControlsView view;
  final BatchConvertPageController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.batchConvertImportTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _optionalActionSemantics(
              enabled: !compact,
              identifier: AppSemanticsIdentifiers.batchPickFiles,
              label: l10n.commonAddFiles,
              onTap: view.isBusy ? null : controller.addFiles,
              child: FilledButton.icon(
                key: const ValueKey<String>('batch_convert_pick_files'),
                onPressed: view.isBusy ? null : controller.addFiles,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(l10n.commonAddFiles),
              ),
            ),
            AppActionSemantics(
              identifier: AppSemanticsIdentifiers.batchPickDirectories,
              label: l10n.batchConvertAddFolders,
              onTap: view.isBusy ? null : controller.addDirectories,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('batch_convert_pick_dirs'),
                onPressed: view.isBusy ? null : controller.addDirectories,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(l10n.batchConvertAddFolders),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey<String>('batch_convert_clear_queue'),
              onPressed: view.isBusy || !view.hasQueue
                  ? null
                  : controller.clearQueue,
              icon: const Icon(Icons.clear_all_outlined),
              label: Text(l10n.commonClearQueue),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutputSettings extends StatelessWidget {
  const _OutputSettings({required this.view, required this.controller});

  final BatchConvertControlsView view;
  final BatchConvertPageController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.batchConvertOutputSettingsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<LyricsFormat>(
          key: const ValueKey<String>('batch_convert_target_format'),
          initialValue: view.targetFormat,
          // InputDecorator 在窄屏仍要为下拉箭头和边距预留空间；展开内容宽度
          // 后，较长的格式名称会在剩余区域布局，不再把内部 Row 挤出右边界。
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.batchConvertTargetFormat,
            border: OutlineInputBorder(),
          ),
          items: batchConvertTargetFormats
              .map(
                (LyricsFormat format) => DropdownMenuItem<LyricsFormat>(
                  value: format,
                  child: Text(l10n.lyricsFormatLabel(format)),
                ),
              )
              .toList(growable: false),
          onChanged: view.isBusy
              ? null
              : (LyricsFormat? value) {
                  if (value != null) {
                    controller.updateTargetFormat(value);
                  }
                },
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.batchConvertSaveDirectoryTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                view.saveRootPath ?? l10n.batchConvertSaveDirectoryDefault,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  AppActionSemantics(
                    actionKey: const ValueKey<String>(
                      'batch_convert_select_save_root',
                    ),
                    identifier: AppSemanticsIdentifiers.batchSaveRoot,
                    label: l10n.batchConvertSelectSaveDirectory,
                    onTap: view.isBusy
                        ? null
                        : controller.selectSaveRootDirectory,
                    child: OutlinedButton.icon(
                      onPressed: view.isBusy
                          ? null
                          : controller.selectSaveRootDirectory,
                      icon: const Icon(Icons.drive_folder_upload_outlined),
                      label: Text(l10n.batchConvertSelectSaveDirectory),
                    ),
                  ),
                  TextButton(
                    onPressed: view.isBusy || view.saveRootPath == null
                        ? null
                        : controller.clearSaveRootDirectory,
                    child: Text(l10n.batchConvertRestoreOriginalDirectory),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const ValueKey<String>('batch_convert_recursive_switch'),
          contentPadding: EdgeInsets.zero,
          value: view.recursive,
          onChanged: view.isBusy ? null : controller.toggleRecursive,
          title: Text(l10n.batchConvertRecursiveTitle),
          subtitle: Text(l10n.batchConvertRecursiveSubtitle),
        ),
      ],
    );
  }
}

class BatchConvertBottomActionBar extends StatelessWidget {
  const BatchConvertBottomActionBar({
    required this.view,
    required this.controller,
    super.key,
  });

  final BatchConvertControlsView view;
  final BatchConvertPageController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      top: false,
      child: Row(
        children: <Widget>[
          Expanded(
            child: AppActionSemantics(
              actionKey: const ValueKey<String>(
                'batch_convert_compact_start_or_cancel',
              ),
              identifier: AppSemanticsIdentifiers.batchStart,
              label: view.isRunning
                  ? l10n.batchConvertCancel
                  : l10n.batchConvertStart,
              onTap: _startAction(view, controller),
              child: FilledButton.icon(
                onPressed: _startAction(view, controller),
                icon: Icon(
                  view.isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_outlined,
                ),
                label: Text(
                  view.isRunning
                      ? l10n.batchConvertCancel
                      : l10n.batchConvertStart,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppActionSemantics(
              identifier: AppSemanticsIdentifiers.batchPickFiles,
              label: l10n.commonAddFiles,
              onTap: view.isBusy ? null : controller.addFiles,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('batch_convert_compact_pick_files'),
                onPressed: view.isBusy ? null : controller.addFiles,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(
                  l10n.commonAddFiles,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

VoidCallback? _startAction(
  BatchConvertControlsView view,
  BatchConvertPageController controller,
) => view.isScanning || (!view.isRunning && !view.canStart)
    ? null
    : controller.startOrCancel;

Widget _optionalActionSemantics({
  required bool enabled,
  required String identifier,
  required String label,
  required VoidCallback? onTap,
  required Widget child,
}) => enabled
    ? AppActionSemantics(
        identifier: identifier,
        label: label,
        onTap: onTap,
        child: child,
      )
    : child;
