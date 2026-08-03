import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide AsyncError, AsyncLoading;

import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../shared/ui/components/components.dart';
import '../application/about_page_controller.dart';
import '../application/about_page_models.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  static const double _compactBreakpoint = 600;
  static const double _expandedBreakpoint = 1024;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<PageViewState<AboutPagePayload>> asyncPageState = ref
        .watch(aboutPageControllerProvider);
    final AboutPageController controller = ref.read(
      aboutPageControllerProvider.notifier,
    );

    return asyncPageState.when(
      loading: () => _loadingState(l10n.uiLoadingStepFetching),
      error: (Object error, StackTrace stackTrace) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorState(
          message: l10n.aboutLoadFailed,
          retryLabel: l10n.actionRetry,
          onRetry: controller.reload,
        ),
      ),
      data: (PageViewState<AboutPagePayload> pageState) {
        final AsyncViewState<AboutPagePayload> view = pageState.view;
        if (view is AsyncLoading<AboutPagePayload>) {
          return _loadingState(view.message ?? l10n.uiLoadingStepFetching);
        }
        if (view is AsyncError<AboutPagePayload>) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorState(
              message: view.message,
              retryLabel: l10n.actionRetry,
              onRetry: controller.reload,
            ),
          );
        }
        if (view is AsyncEmpty<AboutPagePayload>) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: EmptyState(message: view.message ?? l10n.uiEmpty),
          );
        }

        final AboutPagePayload payload = switch (view) {
          AsyncSuccess<AboutPagePayload>(:final data) => data,
          AsyncPartial<AboutPagePayload>(:final data) => data,
          _ => throw StateError('unexpected-about-view-state'),
        };

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact = constraints.maxWidth < _compactBreakpoint;
            final bool expanded = constraints.maxWidth >= _expandedBreakpoint;
            final EdgeInsets padding = EdgeInsets.fromLTRB(
              compact ? 12 : 20,
              16,
              compact ? 12 : 20,
              24,
            );

            return SafeArea(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: !compact,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: padding,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildHero(
                            context,
                            payload,
                            busy: payload.isBusy,
                            checkingForUpdates: payload.isRunning(
                              AboutActionType.checkForUpdates,
                            ),
                            compact: compact,
                            controller: controller,
                          ),
                          const SizedBox(height: 16),
                          _buildLinksSection(
                            context,
                            payload,
                            busy: payload.isBusy,
                            expanded: expanded,
                            controller: controller,
                          ),
                          const SizedBox(height: 20),
                          _buildLegalFooter(context, payload),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _loadingState(String statusText) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ProgressPanel(
        title: context.l10n.uiLoading,
        currentValue: 1,
        maxValue: 1,
        statusText: statusText,
      ),
    );
  }

  Widget _buildHero(
    BuildContext context,
    AboutPagePayload payload, {
    required bool busy,
    required bool checkingForUpdates,
    required bool compact,
    required AboutPageController controller,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final double iconSize = compact ? 56 : 68;

    return Card(
      key: const ValueKey<String>('about_brand_hero'),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colorScheme.primaryContainer,
              colorScheme.surfaceContainerHigh,
            ],
          ),
        ),
        padding: EdgeInsets.all(compact ? 20 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                        color: colorScheme.primary.withValues(alpha: 0.14),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    payload.appIconAsset,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        payload.appName,
                        style: compact
                            ? theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              )
                            : theme.textTheme.displaySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        payload.headline,
                        style: compact
                            ? theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              )
                            : theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                payload.description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _badge(context, Icons.sell_outlined, payload.versionLabel),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                Tooltip(
                  message: payload.canCheckUpdate
                      ? l10n.aboutActionCheckUpdate
                      : l10n.aboutCheckUpdateUnavailable,
                  child: FilledButton.icon(
                    onPressed: payload.canCheckUpdate && !busy
                        ? () => _runAction(controller.checkForUpdates)
                        : null,
                    icon: checkingForUpdates
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_alt_rounded),
                    label: Text(l10n.aboutActionCheckUpdate),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: payload.canOpenExternalLinks && !busy
                      ? () => _runAction(controller.openRepository)
                      : null,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(l10n.aboutActionOpenRepository),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksSection(
    BuildContext context,
    AboutPagePayload payload, {
    required bool busy,
    required bool expanded,
    required AboutPageController controller,
  }) {
    final AppLocalizations l10n = context.l10n;

    return _sectionCard(
      context,
      key: const ValueKey<String>('about_resources_section'),
      title: l10n.aboutLinksSectionTitle,
      subtitle: l10n.aboutLinksSectionDescription,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth = expanded
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: payload.projectLinks
                .map((AboutActionLink link) {
                  return SizedBox(
                    width: itemWidth,
                    child: _resourceTile(
                      context,
                      key: ValueKey<String>('about_resource_${link.kind.name}'),
                      title: link.title,
                      supportingText: link.supportingText,
                      icon: switch (link.kind) {
                        AboutActionLinkKind.issues => Icons.bug_report_outlined,
                        AboutActionLinkKind.license => Icons.gavel_outlined,
                        AboutActionLinkKind.changelog =>
                          Icons.history_edu_outlined,
                      },
                      enabled: payload.canOpenExternalLinks && !busy,
                      onTap: () => _runAction(switch (link.kind) {
                        AboutActionLinkKind.issues =>
                          controller.openIssueTracker,
                        AboutActionLinkKind.license => controller.openLicense,
                        AboutActionLinkKind.changelog =>
                          controller.openChangelog,
                      }),
                    ),
                  );
                })
                .toList(growable: false),
          );
        },
      ),
    );
  }

  Widget _buildLegalFooter(BuildContext context, AboutPagePayload payload) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      key: const ValueKey<String>('about_legal_footer'),
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SelectableText(
            context.l10n.aboutCopyrightNoticeBody(
              payload.copyrightYearRange,
              payload.authorName,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            context.l10n.aboutLicenseNoticeBody('GPL-3.0-only'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required Key key,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, IconData icon, String text) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  Widget _resourceTile(
    BuildContext context, {
    required Key key,
    required String title,
    required String supportingText,
    required IconData icon,
    required bool enabled,
    required Future<void> Function() onTap,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Material(
      key: key,
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      supportingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_outward_rounded,
                size: 18,
                color: enabled
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runAction(Future<AboutActionResult> Function() action) async {
    final AboutActionResult result = await action();
    if (!mounted || !_shouldShowFeedback(result)) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_messageForResult(context.l10n, result)),
        ),
      );
  }

  bool _shouldShowFeedback(AboutActionResult result) {
    if (result.actionType == AboutActionType.checkForUpdates) {
      return true;
    }
    return result.type != AboutActionResultType.opened;
  }

  String _messageForResult(AppLocalizations l10n, AboutActionResult result) {
    final String label = switch (result.actionType) {
      AboutActionType.repository => l10n.aboutLinkRepositoryTitle,
      AboutActionType.issueTracker => l10n.aboutLinkIssueTrackerTitle,
      AboutActionType.license => l10n.aboutLinkLicenseTitle,
      AboutActionType.changelog => l10n.aboutLinkChangelogTitle,
      AboutActionType.checkForUpdates => l10n.aboutActionCheckUpdate,
    };
    return switch (result.type) {
      AboutActionResultType.opened =>
        result.actionType == AboutActionType.checkForUpdates
            ? l10n.aboutCheckUpdateOpenedReleaseNotes
            : l10n.aboutActionOpenedLink(label),
      AboutActionResultType.unsupported =>
        result.actionType == AboutActionType.checkForUpdates
            ? l10n.aboutCheckUpdateUnavailable
            : l10n.aboutExternalLinksUnavailable,
      AboutActionResultType.failed =>
        result.actionType == AboutActionType.checkForUpdates
            ? l10n.aboutCheckUpdateFailed
            : l10n.aboutActionOpenLinkFailed(label),
      AboutActionResultType.upToDate => l10n.aboutCheckUpdateUpToDate,
      AboutActionResultType.updateAvailable => l10n.aboutCheckUpdateAvailable(
        result.latestVersion ?? '',
      ),
    };
  }
}
