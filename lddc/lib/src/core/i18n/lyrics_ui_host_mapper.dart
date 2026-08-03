import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import 'i18n.dart';
import 'l10n/app_localizations.dart';

/// 将 LDDC 本地化对象映射为通用歌词控件文案，供多个宿主页面复用同一实现。
extension LyricsUiAppLocalizationsMapper on AppLocalizations {
  LyricsUiStrings toLyricsUiStrings() {
    return LyricsUiStrings(
      textResolver: _resolveLyricsUiText,
      formatLabelResolver: lyricsFormatLabel,
      languageLabelResolver: _lyricsLanguageLabel,
      typeLabelResolver: lyricsTypeLabel,
    );
  }

  String _resolveLyricsUiText(
    LyricsUiTextKey key,
    LyricsUiTextArguments arguments,
  ) {
    return switch (key) {
      LyricsUiTextKey.formatLabel => searchFormatLabel,
      LyricsUiTextKey.offsetLabel => commonOffset,
      LyricsUiTextKey.languageTypeSummary => commonLyricsLanguageTypeSummary(
        arguments.language,
        arguments.type,
      ),
      LyricsUiTextKey.cancelTranslation => commonCancelTranslation,
      LyricsUiTextKey.translating => commonTranslating,
      LyricsUiTextKey.translationProgress => commonTranslationProgress(
        arguments.completed,
        arguments.total,
      ),
      LyricsUiTextKey.openAiTranslationProgress =>
        commonOpenAiTranslationProgress(arguments.completed, arguments.total),
    };
  }

  String _lyricsLanguageLabel(String language) {
    return switch (LyricsLanguageRegistry.normalizeKey(language)) {
      LyricsLanguageRegistry.original => lyricOriginal,
      LyricsLanguageRegistry.translation => lyricTranslation,
      LyricsLanguageRegistry.romanized => lyricRomanized,
      _ => language,
    };
  }
}
