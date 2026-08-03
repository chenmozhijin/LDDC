import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 桌面歌词窗口所需的最小文案契约。
///
/// 共享组件不读取宿主的本地化系统；宿主可按当前 locale 创建此对象并传入。
class DesktopLyricsWindowStrings {
  const DesktopLyricsWindowStrings({
    required this.appTitle,
    required this.controlConnectionLost,
    required this.selectLyrics,
    required this.markInstrumental,
    required this.disableAutoSearch,
    required this.unlinkLyrics,
    required this.openAssociationManager,
    required this.toggleFloating,
    required this.showMainWindow,
    required this.clickThrough,
    required this.instrumental,
    required this.previous,
    required this.pause,
    required this.play,
    required this.next,
    required this.hide,
    this.sourceLabelBuilder,
    this.lyricsTypeLabelBuilder,
  });

  const DesktopLyricsWindowStrings.zhHans()
    : appTitle = 'LDDC',
      controlConnectionLost = '播放器控制连接已断开',
      selectLyrics = '选择歌词',
      markInstrumental = '标记为纯音乐',
      disableAutoSearch = '禁用自动搜索',
      unlinkLyrics = '解除歌词关联',
      openAssociationManager = '歌词关联管理',
      toggleFloating = '显示或隐藏桌面歌词',
      showMainWindow = '显示主窗口',
      clickThrough = '鼠标穿透',
      instrumental = '纯音乐',
      previous = '上一首',
      pause = '暂停',
      play = '播放',
      next = '下一首',
      hide = '隐藏',
      sourceLabelBuilder = null,
      lyricsTypeLabelBuilder = null;

  final String appTitle;
  final String controlConnectionLost;
  final String selectLyrics;
  final String markInstrumental;
  final String disableAutoSearch;
  final String unlinkLyrics;
  final String openAssociationManager;
  final String toggleFloating;
  final String showMainWindow;
  final String clickThrough;
  final String instrumental;
  final String previous;
  final String pause;
  final String play;
  final String next;
  final String hide;
  final String Function(Source source)? sourceLabelBuilder;
  final String Function(LyricsType type)? lyricsTypeLabelBuilder;

  String sourceLabel(Source source) {
    return sourceLabelBuilder?.call(source) ?? source.name.toUpperCase();
  }

  String lyricsTypeLabel(LyricsType type) {
    return lyricsTypeLabelBuilder?.call(type) ??
        switch (type) {
          LyricsType.lineByLine => '逐行',
          LyricsType.verbatim => '逐字',
          LyricsType.plainText => '纯文本',
        };
  }
}
