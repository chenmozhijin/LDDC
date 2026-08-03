import 'config_keys.dart';

/// Python版 `config.json` 与 Flutter 内部配置键的映射表。
///
/// 约束：
/// - 外部桌面配置文件继续使用Python版 snake_case 键名；
/// - Flutter 内部仍使用点分键与强类型 `AppConfig`；
/// - 未知键不进入本映射，由仓储额外保留。
abstract final class LegacyConfigKeyMap {
  static const Map<String, String> legacyToCurrent = <String, String>{
    'lyrics_file_name_fmt': ConfigKey.lyricsFileNameFormat,
    'default_save_path': ConfigKey.storageDefaultSavePath,
    'ID3_version': ConfigKey.lyricsId3Version,
    'multi_search_sources': ConfigKey.searchSources,
    'langs_order': ConfigKey.lyricsLangOrder,
    'skip_inst_lyrics': ConfigKey.matchSkipInst,
    'auto_select': ConfigKey.matchAutoSelect,
    'add_end_timestamp_line': ConfigKey.lyricsAddEndTimestamp,
    'lrc_ms_digit_count': ConfigKey.lyricsMsDigits,
    'last_ref_line_time_sty': ConfigKey.lyricsLastRefStyle,
    'lrc_tag_info_src': ConfigKey.lyricsTagInfoSource,
    'translate_source': ConfigKey.translateSource,
    'translate_target_lang': ConfigKey.translateTargetLang,
    'openai_profile': ConfigKey.translateOpenAiProfile,
    'openai_base_url': ConfigKey.translateOpenAiBaseUrl,
    'openai_api_key': ConfigKey.translateOpenAiApiKey,
    'openai_model': ConfigKey.translateOpenAiModel,
    'desktop_lyrics_played_colors': ConfigKey.desktopPlayedColors,
    'desktop_lyrics_unplayed_colors': ConfigKey.desktopUnplayedColors,
    'desktop_lyrics_default_langs': ConfigKey.desktopDefaultLangs,
    'desktop_lyrics_langs_order': ConfigKey.desktopLangOrder,
    'desktop_lyrics_sources': ConfigKey.desktopSources,
    'desktop_lyrics_font_family': ConfigKey.desktopFontFamily,
    'desktop_lyrics_refresh_rate': ConfigKey.desktopRefreshRate,
    'desktop_lyrics_rect': ConfigKey.desktopWindowRect,
    'desktop_lyrics_font_size': ConfigKey.desktopFontSize,
    'desktop_lyrics_show_furigana': ConfigKey.desktopShowFurigana,
    'lyrics_panel_font_size': ConfigKey.desktopPanelFontSize,
    'language': ConfigKey.appLanguage,
    'color_scheme': ConfigKey.appColorScheme,
    'log_level': ConfigKey.appLogLevel,
    'auto_check_update': ConfigKey.appAutoCheckUpdate,
  };

  static final Map<String, String> currentToLegacy =
      Map<String, String>.unmodifiable(
        legacyToCurrent.map(
          (String legacyKey, String currentKey) =>
              MapEntry<String, String>(currentKey, legacyKey),
        ),
      );
}
