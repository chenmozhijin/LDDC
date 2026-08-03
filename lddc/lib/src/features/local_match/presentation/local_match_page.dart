import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/accessibility/app_action_semantics.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../shared/ui/components/components.dart';
import '../../../shared/ui/drag_drop/desktop_drop_region_scaffold.dart';
import '../application/local_match_dependencies.dart';
import '../application/local_match_page_controller.dart';
import '../application/local_match_page_state.dart';
import 'local_match_notice_text.dart';
import 'widgets/local_match_bottom_and_helpers.dart';
import 'widgets/local_match_compact.dart';
import 'widgets/local_match_desktop.dart';

class LocalMatchPage extends ConsumerStatefulWidget {
  const LocalMatchPage({super.key});

  @override
  ConsumerState<LocalMatchPage> createState() => _LocalMatchPageState();
}

class _LocalMatchPageState extends ConsumerState<LocalMatchPage> {
  // 桌面平台需要更早切到桌面布局；否则壳层的 NavigationRail 吃掉一部分宽度后，
  // 内容区会落到“壳层是桌面、页面却按移动/中等布局渲染”的夹层。
  static const double _desktopPlatformBreakpoint = 960;
  static const double _desktopBreakpoint = 1080;

  @override
  Widget build(BuildContext context) {
    ref.listen<LocalMatchPageState>(localMatchPageControllerProvider, (
      LocalMatchPageState? previous,
      LocalMatchPageState next,
    ) {
      final LocalMatchNotice? notice = next.notice;
      if (notice == null || previous?.notice?.id == notice.id || !mounted) {
        return;
      }
      _showNotice(context, notice);
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        ref
            .read(localMatchPageControllerProvider.notifier)
            .dismissNotice(notice.id);
      });
    });

    final bool isDesktopPlatform = ref.watch(
      localMatchPageControllerProvider.select(
        (LocalMatchPageState state) => state.isDesktopMode,
      ),
    );
    final LocalMatchPageController controller = ref.read(
      localMatchPageControllerProvider.notifier,
    );

    final Widget page = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isDesktop = isDesktopPlatform
            ? constraints.maxWidth >= _desktopPlatformBreakpoint
            : constraints.maxWidth >= _desktopBreakpoint;
        final bool showIntro = !isDesktopPlatform && !isDesktop;
        final Widget body = isDesktop
            ? LocalMatchDesktopLayout(controller: controller)
            : LocalMatchCompactLayout(controller: controller);

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (showIntro) ...<Widget>[
                Text(
                  context.l10n.navLocalMatch,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.localMatchIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              Expanded(child: body),
              if (!isDesktop) ...<Widget>[
                const SizedBox(height: 12),
                Consumer(
                  builder:
                      (BuildContext context, WidgetRef ref, Widget? child) {
                        final LocalMatchPageState state = ref.watch(
                          localMatchPageControllerProvider,
                        );
                        return LocalMatchBottomActionBar(
                          state: state,
                          controller: controller,
                        );
                      },
                ),
              ],
            ],
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
                controller.addSongFiles();
              },
              const SingleActivator(
                LogicalKeyboardKey.keyO,
                control: true,
                shift: true,
              ): () {
                controller.addSongDirectories();
              },
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (controller.currentState.canStart) {
                  controller.startOrCancel();
                }
              },
              const SingleActivator(LogicalKeyboardKey.escape): () {
                controller.exitSelectionMode();
              },
              const SingleActivator(LogicalKeyboardKey.delete): () {
                if (controller.currentState.selectedItemIds.isNotEmpty) {
                  controller.removeSelectedItems();
                } else if (controller.currentState.focusedItemId != null) {
                  controller.enterSelectionMode(
                    controller.currentState.focusedItemId,
                  );
                  controller.removeSelectedItems();
                }
              },
            },
            child: page,
          )
        : page;
    if (!isDesktopPlatform) {
      return withShortcuts;
    }
    final DragDropPort dragDropPort = ref.watch(
      localMatchDependenciesProvider.select(
        (LocalMatchDependencies dependencies) => dependencies.dragDropPort,
      ),
    );
    return DesktopDropRegionScaffold(
      dragDropPort: dragDropPort,
      semanticsIdentifier: AppSemanticsIdentifiers.localMatchDropRegion,
      onDrop: (DragDropParseResult result) => _handleDrop(result, controller),
      unsupportedItemMessage: context.l10n.localMatchDropUnsupportedItem,
      errorMessageBuilder: (BuildContext context, Object error) =>
          context.l10n.commonDropFailed('$error'),
      child: withShortcuts,
    );
  }

  void _showNotice(BuildContext context, LocalMatchNotice notice) {
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
          key: ValueKey<String>('local_match_notice_${notice.code.name}'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.$1,
          content: Text(
            localMatchNoticeText(context, notice),
            style: TextStyle(color: colors.$2),
          ),
        ),
      );
  }

  Future<bool> _handleDrop(
    DragDropParseResult result,
    LocalMatchPageController controller,
  ) async {
    await controller.importExternalDesktopItems(result.items);
    return true;
  }
}
