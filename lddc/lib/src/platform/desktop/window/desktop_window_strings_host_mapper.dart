import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/l10n/app_localizations.dart';

/// 将 LDDC 当前 locale 的文案裁剪为桌面歌词包所需的最小集合。
extension DesktopWindowStringsHostMapper on AppLocalizations {
  DesktopLyricsWindowStrings toDesktopLyricsWindowStrings() {
    return DesktopLyricsWindowStrings(
      appTitle: appTitle,
      controlConnectionLost: desktopWindowControlConnectionLost,
      selectLyrics: desktopWindowActionSelectLyrics,
      markInstrumental: desktopWindowActionMarkInstrumental,
      disableAutoSearch: desktopWindowActionDisableAutoSearch,
      unlinkLyrics: desktopWindowActionUnlinkLyrics,
      openAssociationManager: desktopWindowActionAssociationManager,
      toggleFloating: desktopWindowActionToggleFloating,
      showMainWindow: desktopWindowActionShowMainWindow,
      clickThrough: desktopWindowActionClickThrough,
      instrumental: desktopWindowInfoInstrumental,
      previous: desktopWindowActionPrevious,
      pause: desktopWindowActionPause,
      play: desktopWindowActionPlay,
      next: desktopWindowActionNext,
      hide: desktopWindowActionHide,
      sourceLabelBuilder: sourceLabel,
      lyricsTypeLabelBuilder: lyricsTypeLabel,
    );
  }
}
