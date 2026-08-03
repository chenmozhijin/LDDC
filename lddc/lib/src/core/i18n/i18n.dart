import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'l10n/app_localizations.dart';

/// 应用语言配置对应的显式 Flutter locale。
///
/// `auto` 返回 null，交给 MaterialApp 跟随系统；需要立即取得具体翻译对象的调用方
/// 可以在 null 时再按自己的平台上下文选择回退 locale。
extension AppLanguageLocaleX on AppLanguage {
  Locale? get explicitLocale => switch (this) {
    AppLanguage.auto => null,
    AppLanguage.zhHans => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
    AppLanguage.zhHant => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    AppLanguage.en => const Locale('en'),
    AppLanguage.ru => const Locale('ru'),
    AppLanguage.ja => const Locale('ja'),
    AppLanguage.ko => const Locale('ko'),
  };
}

/// 将系统 Locale 解析为 LDDC 明确支持的界面 Locale。
///
/// Flutter 的通用语言匹配在只有 `zh`、`zh_Hans` 和 `zh_Hant` 时，可能先把
/// `zh_TW` 匹配到无脚本的技术 fallback。这里同时检查 scriptCode 和常见繁体
/// 地区，确保自动语言与用户显式选择的语义一致；未知语言统一回退英文。
Locale resolveSupportedAppLocale(Locale locale) {
  final String languageCode = locale.languageCode.toLowerCase();
  if (languageCode == 'zh') {
    final String scriptCode = locale.scriptCode?.toLowerCase() ?? '';
    final String countryCode = locale.countryCode?.toUpperCase() ?? '';
    final bool useTraditional =
        scriptCode == 'hant' ||
        (scriptCode.isEmpty &&
            <String>{'TW', 'HK', 'MO'}.contains(countryCode));
    return Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: useTraditional ? 'Hant' : 'Hans',
    );
  }
  if (<String>{'en', 'ru', 'ja', 'ko'}.contains(languageCode)) {
    return Locale(languageCode);
  }
  return const Locale('en');
}

/// `BuildContext` 的本地化快捷访问扩展。
extension BuildContextL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// 将稳定的歌词格式枚举转换为当前界面语言下的展示名称。
///
/// 转换器只负责声明支持的格式，不能携带中文或英文界面文案；把映射集中在本地化
/// 边界后，搜索、打开歌词和批量转换页面会使用同一套翻译，也不会各自维护重复列表。
extension LyricsFormatL10nX on AppLocalizations {
  String lyricsFormatLabel(LyricsFormat format) {
    return switch (format) {
      LyricsFormat.verbatimLrc => lyricsFormatVerbatimLrc,
      LyricsFormat.lineByLineLrc => lyricsFormatLineByLineLrc,
      LyricsFormat.enhancedLrc => lyricsFormatEnhancedLrc,
      LyricsFormat.srt => lyricsFormatSrt,
      LyricsFormat.ass => lyricsFormatAss,
      _ => format.name.toUpperCase(),
    };
  }
}

/// 将歌词来源转换为当前界面语言下的展示名称。
///
/// `Source` 是业务层的稳定语义，不能提前转换成中文或英文后再传给页面；否则桌面
/// 子窗口收到的只是一段已经失去语义的文本，运行时切换语言也无法重新本地化。
/// 所有需要展示来源的页面都通过这个入口转换，避免各模块重复维护同一组 switch。
extension SourceL10nX on AppLocalizations {
  String sourceLabel(Source source) {
    return switch (source) {
      Source.multi => sourceAggregate,
      Source.qm => sourceQQMusic,
      Source.kg => sourceKugou,
      Source.ne => sourceNetease,
      Source.lrclib => sourceLrclib,
      Source.local => sourceLocal,
    };
  }
}

/// 将搜索类型转换为当前界面语言下的展示名称。
///
/// `SearchType` 同时被搜索状态、结果标签页和集成测试使用。业务状态只保存枚举，
/// 页面在真正绘制文字时才调用此方法，既能支持运行时切换语言，也避免不同页面各自
/// 维护一份容易漂移的中英文映射。
extension SearchTypeL10nX on AppLocalizations {
  String searchTypeLabel(SearchType type) {
    return switch (type) {
      SearchType.song => searchSong,
      SearchType.album => searchAlbum,
      SearchType.songlist => searchSongList,
      SearchType.artist => searchArtist,
      SearchType.lyrics => searchLyrics,
      SearchType.songId => searchSongId,
    };
  }
}

/// 将歌词时间轴类型转换为当前界面语言下的展示名称。
extension LyricsTypeL10nX on AppLocalizations {
  String lyricsTypeLabel(LyricsType type) {
    return switch (type) {
      LyricsType.verbatim => lyricsTypeVerbatim,
      LyricsType.lineByLine => lyricsTypeLineByLine,
      LyricsType.plainText => lyricsTypePlainText,
    };
  }
}
