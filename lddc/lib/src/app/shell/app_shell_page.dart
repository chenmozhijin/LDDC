import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/i18n/l10n/app_localizations.dart';
import '../app_feature_scopes.dart'
    if (dart.library.html) '../app_feature_scopes_web.dart';
import 'app_shell_providers.dart';
import 'app_shell_route.dart';

class AppShellPage extends ConsumerStatefulWidget {
  const AppShellPage({super.key});

  @override
  ConsumerState<AppShellPage> createState() => _AppShellPageState();
}

class _AppShellPageState extends ConsumerState<AppShellPage> {
  static const List<AppShellRoute> _routeOrder = <AppShellRoute>[
    AppShellRoute.search,
    AppShellRoute.localMatch,
    AppShellRoute.openLyrics,
    AppShellRoute.batchConvert,
    AppShellRoute.settings,
    AppShellRoute.about,
  ];

  static const double _sidebarBreakpoint = 980;

  late final ValueNotifier<AppShellRoute> _routeListenable;
  late final List<Widget?> _pageSlots;

  @override
  void initState() {
    super.initState();
    _routeListenable = ref.read(appShellRouteListenableProvider);
    _routeListenable.addListener(_handleRouteChanged);
    _pageSlots = List<Widget?>.filled(AppShellRoute.values.length, null);
    _ensurePageSlot(_routeListenable.value);
  }

  @override
  void dispose() {
    _routeListenable.removeListener(_handleRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final AppShellRoute currentRoute = _routeListenable.value;
    _ensurePageSlot(currentRoute);
    final int selectedIndex = _routeOrder.indexOf(currentRoute.navigationRoute);
    final int pageIndex = AppShellRoute.values.indexOf(currentRoute);
    // 长任务页面在切换导航时不能被销毁，否则队列控制器和局部交互状态会被重置。
    // 同时不能一次性构建所有页面：资料库等未访问页面可能在测试或启动时提前打开数据库。
    final Widget pageSlot = IndexedStack(
      index: pageIndex,
      children: <Widget>[
        for (final Widget? page in _pageSlots) page ?? const SizedBox.shrink(),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool useSidebar = constraints.maxWidth >= _sidebarBreakpoint;
        final Widget navigationSlot = useSidebar
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: _onDestinationSelected,
                    labelType: NavigationRailLabelType.all,
                    destinations: _routeOrder
                        .map(
                          (AppShellRoute route) => NavigationRailDestination(
                            icon: _navigationIcon(route, l10n),
                            label: Text(route.title(l10n)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const VerticalDivider(width: 1),
                ],
              )
            : const SizedBox.shrink();
        return Scaffold(
          appBar: AppBar(title: Text(currentRoute.title(l10n))),
          body: Row(
            children: <Widget>[
              navigationSlot,
              Expanded(child: pageSlot),
            ],
          ),
          bottomNavigationBar: useSidebar
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _onDestinationSelected,
                  destinations: _routeOrder
                      .map(
                        (AppShellRoute route) => NavigationDestination(
                          icon: _navigationIcon(route, l10n),
                          label: route.title(l10n),
                        ),
                      )
                      .toList(growable: false),
                ),
        );
      },
    );
  }

  void _onDestinationSelected(int value) {
    _routeListenable.value = _routeOrder[value];
  }

  Widget _navigationIcon(AppShellRoute route, AppLocalizations l10n) {
    final Widget icon = Icon(route.icon);
    final String? identifier = route.platformSemanticsIdentifier;
    if (identifier == null) {
      return icon;
    }
    // NavigationRail/NavigationBar 自己负责点击和选中状态；这里只给图标节点
    // 增加原生可发现标识，不重复注册 onTap，避免一次辅助功能动作触发两次导航。
    return Semantics(
      identifier: identifier,
      label: route.title(l10n),
      child: ExcludeSemantics(child: icon),
    );
  }

  void _handleRouteChanged() {
    if (mounted) {
      _ensurePageSlot(_routeListenable.value);
      setState(() {});
    }
  }

  void _ensurePageSlot(AppShellRoute route) {
    final int pageIndex = AppShellRoute.values.indexOf(route);
    _pageSlots[pageIndex] ??= KeyedSubtree(
      key: ValueKey<AppShellRoute>(route),
      child: _buildPage(route),
    );
  }

  Widget _buildPage(AppShellRoute route) {
    return switch (route) {
      AppShellRoute.search => const AppSearchPageScope(),
      AppShellRoute.localMatch => const AppLocalMatchPageScope(),
      AppShellRoute.openLyrics => const AppOpenLyricsPageScope(),
      AppShellRoute.associationManager =>
        const AppLibraryLinkManagerPageScope(),
      AppShellRoute.batchConvert => const AppBatchConvertPageScope(),
      AppShellRoute.settings => const AppSettingsPageScope(),
      AppShellRoute.about => const AppAboutPageScope(),
    };
  }
}
