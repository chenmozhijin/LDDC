import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide AsyncError, AsyncLoading;

import '../../../core/i18n/i18n.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import '../../../shared/ui/components/components.dart';
import '../application/settings_page_controller.dart';
import '../application/settings_page_models.dart';
import 'settings_notice_text.dart';
import 'widgets/settings_page_chrome.dart';
import 'widgets/settings_data_helpers.dart';
import 'widgets/settings_page_state_helpers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends ConsumerState<SettingsPage> {
  static const double compactBreakpoint = 600;
  static const double _anchorLayoutBreakpoint = 900;
  static const double anchorBarExtent = 64;

  final ScrollController settingsScrollController = ScrollController();
  final Map<SettingsSection, GlobalKey> sectionKeys =
      <SettingsSection, GlobalKey>{
        for (final SettingsSection section in SettingsSection.values)
          section: GlobalKey(debugLabel: 'settings_section_${section.name}'),
      };

  bool syncQueued = false;
  bool _compactTransitionQueued = false;
  bool compactLayoutActive = false;
  SettingsSection? compactSection;

  @override
  void initState() {
    super.initState();
    settingsScrollController.addListener(handleScroll);
  }

  @override
  void dispose() {
    settingsScrollController.removeListener(handleScroll);
    settingsScrollController.dispose();
    super.dispose();
  }

  void setCompactSection(SettingsSection? section) {
    // State.setState 是 Flutter 状态对象自己的生命周期入口。
    // 拆到 part extension 的方法不能直接调用受保护成员，所以统一回到这里修改紧凑布局的当前分区。
    setState(() {
      compactSection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PageViewState<SettingsPagePayload>>(
      settingsPageControllerProvider,
      (
        PageViewState<SettingsPagePayload>? previous,
        PageViewState<SettingsPagePayload> next,
      ) {
        final String? message = next.action.message;
        if (message == null ||
            message == previous?.action.message ||
            !mounted) {
          return;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(settingsNoticeText(context, message)),
            ),
          );
      },
    );

    // 页面主体只依赖 view；一次性 Snackbar 由上面的 ref.listen 处理。
    // 这样保存设置后只更新 action.message 时，不会把整棵设置页重新布局。
    final AsyncViewState<SettingsPagePayload> view = ref.watch(
      settingsPageControllerProvider.select(
        (PageViewState<SettingsPagePayload> state) => state.view,
      ),
    );
    final SettingsPageController controller = ref.read(
      settingsPageControllerProvider.notifier,
    );

    if (view is AsyncLoading<SettingsPagePayload>) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ProgressPanel(
          title: context.l10n.uiLoading,
          currentValue: 1,
          maxValue: 1,
          statusText: view.message ?? context.l10n.uiLoadingStepFetching,
        ),
      );
    }
    if (view is AsyncError<SettingsPagePayload>) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorState(
          message: view.message,
          retryLabel: context.l10n.actionRetry,
          onRetry: controller.clearMessage,
        ),
      );
    }
    if (view is AsyncEmpty<SettingsPagePayload>) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(message: view.message ?? context.l10n.uiEmpty),
      );
    }

    final SettingsPagePayload payload = payloadOf(view);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < compactBreakpoint;
        // ScrollController 会在帧开始阶段通知监听器，此时新的布局约束可能
        // 已经把 RenderObject 标记为 dirty，但 LayoutBuilder 尚未重新布局。
        // 保存最近一次已计算的模式，滚动回调便无需读取 context.size。
        compactLayoutActive = compact;
        final bool anchorLayout =
            constraints.maxWidth >= compactBreakpoint &&
            constraints.maxWidth < _anchorLayoutBreakpoint;
        final EdgeInsets pagePadding = EdgeInsets.fromLTRB(
          compact ? 12 : (anchorLayout ? 16 : 20),
          16,
          compact ? 12 : (anchorLayout ? 16 : 20),
          20,
        );
        final List<SettingsSection> sections = visibleSections(payload);
        if (!compact && compactSection != null && !_compactTransitionQueued) {
          _compactTransitionQueued = true;
          final SettingsSection targetSection = compactSection!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _compactTransitionQueued = false;
            if (!mounted) {
              return;
            }
            setCompactSection(null);
            scrollToSection(targetSection);
          });
        }
        if (!compact) {
          scheduleActiveSectionSync(payload);
        }

        if (compact) {
          return buildCompactLayout(
            context: context,
            payload: payload,
            controller: controller,
            sections: sections,
            pagePadding: pagePadding,
          );
        }

        return CustomScrollView(
          key: const ValueKey<String>('settings_single_page_scroll'),
          controller: settingsScrollController,
          slivers: <Widget>[
            SliverPersistentHeader(
              pinned: true,
              delegate: SettingsPinnedHeaderDelegate(
                extent: anchorBarExtent,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      pagePadding.left,
                      8,
                      pagePadding.right,
                      8,
                    ),
                    child: SettingsPageBounds(
                      child: SettingsAnchorBar(
                        key: const ValueKey<String>('settings_anchor_bar'),
                        sections: sections,
                        activeSection: payload.activeSection,
                        onSelected: scrollToSection,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: pagePadding.copyWith(top: 12),
              sliver: SliverToBoxAdapter(
                child: SettingsPageBounds(
                  child: Column(
                    children: <Widget>[
                      for (int index = 0; index < sections.length; index += 1)
                        Padding(
                          key: sectionKeys[sections[index]],
                          padding: EdgeInsets.only(
                            bottom: index == sections.length - 1 ? 0 : 20,
                          ),
                          child: buildSection(
                            context: context,
                            payload: payload,
                            section: sections[index],
                            controller: controller,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
