import 'package:flutter/material.dart';

/// 原生 UI 自动化与读屏共同使用的稳定控件标识。
///
/// 这里只收录需要跨越 Flutter/系统界面边界的关键操作。普通 Widget 测试继续
/// 使用 ValueKey，避免把整棵界面树变成维护成本很高的自动化协议。
abstract final class AppSemanticsIdentifiers {
  static const String navLocalMatch = 'lddc.nav.local_match';
  static const String navOpenLyrics = 'lddc.nav.open_lyrics';
  static const String navBatchConvert = 'lddc.nav.batch_convert';
  static const String navSettings = 'lddc.nav.settings';

  static const String openLyricsFile = 'lddc.open_lyrics.open_lyrics_file';
  static const String openSongFile = 'lddc.open_lyrics.open_song_file';
  static const String convertOpenLyrics = 'lddc.open_lyrics.convert';
  static const String saveLyricsFile = 'lddc.open_lyrics.save_file';
  static const String saveLyricsTag = 'lddc.open_lyrics.save_tag';
  static const String translateLyrics = 'lddc.open_lyrics.translate';
  static const String openLyricsSaveTagSucceeded =
      'lddc.open_lyrics.notice.saveTagSucceeded';
  static const String openLyricsSaveTagFailed =
      'lddc.open_lyrics.notice.saveTagFailed';
  static const String openLyricsConvertFailed =
      'lddc.open_lyrics.notice.convertFailed';

  static const String localMatchPickFiles = 'lddc.local_match.pick_files';
  static const String localMatchPickDirectories =
      'lddc.local_match.pick_directories';
  static const String localMatchPickTree = 'lddc.local_match.pick_tree';
  static const String localMatchSaveRoot = 'lddc.local_match.select_save_root';
  static const String localMatchStart = 'lddc.local_match.start_or_cancel';

  static const String batchPickFiles = 'lddc.batch_convert.pick_files';
  static const String batchPickDirectories =
      'lddc.batch_convert.pick_directories';
  static const String batchSaveRoot = 'lddc.batch_convert.select_save_root';
  static const String batchStart = 'lddc.batch_convert.start_or_cancel';

  static const String settingsOpenLogDirectory =
      'lddc.settings.open_log_directory';

  static const String searchDropRegion = 'lddc.search.drop_region';
  static const String openLyricsDropRegion = 'lddc.open_lyrics.drop_region';
  static const String localMatchDropRegion = 'lddc.local_match.drop_region';
  static const String batchConvertDropRegion = 'lddc.batch_convert.drop_region';

  static const List<String> all = <String>[
    navLocalMatch,
    navOpenLyrics,
    navBatchConvert,
    navSettings,
    openLyricsFile,
    openSongFile,
    convertOpenLyrics,
    saveLyricsFile,
    saveLyricsTag,
    translateLyrics,
    openLyricsSaveTagSucceeded,
    openLyricsSaveTagFailed,
    openLyricsConvertFailed,
    localMatchPickFiles,
    localMatchPickDirectories,
    localMatchPickTree,
    localMatchSaveRoot,
    localMatchStart,
    batchPickFiles,
    batchPickDirectories,
    batchSaveRoot,
    batchStart,
    settingsOpenLogDirectory,
    searchDropRegion,
    openLyricsDropRegion,
    localMatchDropRegion,
    batchConvertDropRegion,
  ];
}

/// 给关键命令增加稳定 identifier，同时保留完整的按钮读屏语义。
///
/// `excludeSemantics` 会移除子按钮重复生成的语义节点，再由当前节点提供同一份
/// label、enabled 和 tap 动作。这样 UI Automator/XCUITest 只看到一个可点击节点，
/// 读屏也不会把同一个按钮朗读两次；视觉树与按钮自身的鼠标/触摸处理保持不变。
class AppActionSemantics extends StatelessWidget {
  const AppActionSemantics({
    required this.identifier,
    required this.label,
    required this.onTap,
    required this.child,
    this.actionKey,
    super.key,
  });

  final String identifier;
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // 交互测试和业务代码应定位真正参与 hit test 的语义节点，不能把 key
      // 放在被 excludeSemantics 包裹的子按钮上，否则 Flutter 会正确报告漏点。
      key: actionKey,
      identifier: identifier,
      label: label,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: child,
    );
  }
}
