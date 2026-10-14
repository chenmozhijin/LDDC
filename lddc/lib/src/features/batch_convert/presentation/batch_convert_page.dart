import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/accessibility/app_action_semantics.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../shared/ui/components/components.dart';
import '../../../shared/ui/drag_drop/desktop_drop_region_scaffold.dart';
import '../application/batch_convert_dependencies.dart';
import '../application/batch_convert_page_controller.dart';
import '../application/batch_convert_page_state.dart';
import 'batch_convert_notice_text.dart';
import 'widgets/batch_convert_layouts.dart';

class BatchConvertPage extends ConsumerStatefulWidget {
  const BatchConvertPage({super.key});

  @override
  ConsumerState<BatchConvertPage> createState() => _BatchConvertPageState();
}

class _BatchConvertPageState extends ConsumerState<BatchConvertPage> {
  bool _mobileControlsExpanded = false;

  static const double _desktopBreakpoint = 1080;

  @override
  Widget build(BuildContext context) {
    ref.listen<BatchConvertPageState>(batchConvertPageControllerProvider, (
      BatchConvertPageState? previous,
      BatchConvertPageState next,
    ) {
      final BatchConvertNotice? notice = next.notice;
      if (notice == null || previous?.notice?.id == notice.id || !mounted) {
        return;
      }
      _showNotice(context, notice);
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        ref
            .read(batchConvertPageControllerProvider.notifier)
            .dismissNotice(notice.id);
      });
    });

    final BatchConvertPageController controller = ref.read(
      batchConvertPageControllerProvider.notifier,
    );
    final BatchConvertDependencies dependencies = ref.watch(
      batchConvertDependenciesProvider,
    );
    final bool isDesktopPlatform = dependencies.capability.multiWindow;
    final String? selectedItemId = ref.watch(
      batchConvertPageControllerProvider.select(
        (BatchConvertPageState state) => state.selectedItemId,
      ),
    );

    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = constraints.maxWidth >= _desktopBreakpoint;
        return Padding(
          padding: EdgeInsets.all(isDesktop ? 12 : 16),
          child: isDesktop
              ? BatchConvertDesktopLayout(
                  controller: controller,
                  selectedItemId: selectedItemId,
                  onSelectItem: controller.selectQueueItem,
                )
              : BatchConvertCompactLayout(
                  controller: controller,
                  selectedItemId: selectedItemId,
                  onSelectItem: controller.selectQueueItem,
                  controlsExpanded: _mobileControlsExpanded,
                  onControlsExpanded: (bool value) {
                    setState(() {
                      _mobileControlsExpanded = value;
                    });
                  },
                ),
        );
      },
    );
    final Widget withShortcuts = isDesktopPlatform
        ? DesktopPageInteractionScope(
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
              ): () {
                controller.addFiles();
              },
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
                shift: true,
              ): () {
                controller.addDirectories();
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                final String? selected = controller.currentState.selectedItemId;
                if (selected != null && selected.trim().isNotEmpty) {
                  controller.openInOpenLyrics(selected);
                } else if (controller.currentState.canStart ||
                    controller.currentState.isRunning) {
                  controller.startOrCancel();
                }
              },
              const SingleActivator(LogicalKeyboardKey.delete): () {
                final String? selected = controller.currentState.selectedItemId;
                if (selected != null && selected.trim().isNotEmpty) {
                  controller.removeQueueItem(selected);
                }
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                controller.clearSelectedQueueItem();
              },
            },
            child: page,
          )
        : page;
    if (!isDesktopPlatform) {
      return withShortcuts;
    }
    final DragDropPort dragDropPort = dependencies.dragDropPort;
    return DesktopDropRegionScaffold(
      dragDropPort: dragDropPort,
      semanticsIdentifier: AppSemanticsIdentifiers.batchConvertDropRegion,
      onDrop: (DragDropParseResult result) => _handleDrop(result, controller),
      unsupportedItemMessage: context.l10n.batchConvertDropUnsupported,
      errorMessageBuilder: (BuildContext context, Object error) =>
          context.l10n.batchConvertDropFailed('$error'),
      child: withShortcuts,
    );
  }

  void _showNotice(BuildContext context, BatchConvertNotice notice) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final (Color backgroundColor, Color foregroundColor) colors =
        switch (notice.severity) {
          PageNoticeSeverity.success => (
            colorScheme.primaryContainer,
            colorScheme.onPrimaryContainer,
          ),
          PageNoticeSeverity.warning => (
            colorScheme.tertiaryContainer,
            colorScheme.onTertiaryContainer,
          ),
          PageNoticeSeverity.error => (
            colorScheme.errorContainer,
            colorScheme.onErrorContainer,
          ),
          PageNoticeSeverity.info => (
            colorScheme.surfaceContainerHighest,
            colorScheme.onSurface,
          ),
        };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.$1,
          content: Text(
            batchConvertNoticeText(context, notice),
            style: TextStyle(color: colors.$2),
          ),
        ),
      );
  }

  Future<bool> _handleDrop(
    DragDropParseResult result,
    BatchConvertPageController controller,
  ) async {
    final List<String> inputPaths = result.items
        .where(
          (DragDropItemDescriptor item) =>
              item.kind == DragDropItemKind.localFile ||
              item.kind == DragDropItemKind.directory,
        )
        .map((DragDropItemDescriptor item) => item.path)
        .toList(growable: false);
    if (inputPaths.isEmpty) {
      return false;
    }
    await controller.importExternalPaths(inputPaths);
    return true;
  }
}
