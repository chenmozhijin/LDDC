import 'package:flutter/material.dart';

import '../../core/i18n/l10n/app_localizations.dart';
import '../../core/accessibility/app_action_semantics.dart';

/// 壳层路由枚举，顺序与Python版主侧栏语义保持一致。
enum AppShellRoute {
  search,
  localMatch,
  openLyrics,
  associationManager,
  batchConvert,
  settings,
  about,
}

extension AppShellRouteX on AppShellRoute {
  /// 返回主导航中应该高亮的路由。
  ///
  /// 关联管理器是设置页打开的子页面，不单独占用导航项；进入该页面时仍应保持
  /// “设置”高亮，避免移动端底部导航错误地回退到第一个“搜索”项。
  AppShellRoute get navigationRoute => switch (this) {
    AppShellRoute.associationManager => AppShellRoute.settings,
    _ => this,
  };

  IconData get icon => switch (this) {
    AppShellRoute.search => Icons.search,
    AppShellRoute.localMatch => Icons.library_music_outlined,
    AppShellRoute.openLyrics => Icons.file_open_outlined,
    AppShellRoute.associationManager => Icons.link_outlined,
    AppShellRoute.batchConvert => Icons.auto_fix_high_outlined,
    AppShellRoute.settings => Icons.settings_outlined,
    AppShellRoute.about => Icons.info_outline,
  };

  /// 只有原生平台场景需要操作的导航项才暴露稳定 identifier。
  String? get platformSemanticsIdentifier => switch (this) {
    AppShellRoute.localMatch => AppSemanticsIdentifiers.navLocalMatch,
    AppShellRoute.openLyrics => AppSemanticsIdentifiers.navOpenLyrics,
    AppShellRoute.batchConvert => AppSemanticsIdentifiers.navBatchConvert,
    AppShellRoute.settings => AppSemanticsIdentifiers.navSettings,
    _ => null,
  };

  String title(AppLocalizations l10n) => switch (this) {
    AppShellRoute.search => l10n.navSearch,
    AppShellRoute.localMatch => l10n.navLocalMatch,
    AppShellRoute.openLyrics => l10n.navOpenLyrics,
    AppShellRoute.associationManager => l10n.libraryLinkManagerTitle,
    AppShellRoute.batchConvert => l10n.navBatchConvert,
    AppShellRoute.settings => l10n.navSettings,
    AppShellRoute.about => l10n.navAbout,
  };
}
