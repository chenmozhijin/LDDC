import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 通用歌词组件需要的固定文案键。
///
/// 共享包只声明展示语义，不读取宿主的 `AppLocalizations`。宿主可以把任意本地化
/// 方案映射到这些键，独立消费者也可以直接使用包内置的简体中文实现。
enum LyricsUiTextKey {
  formatLabel,
  offsetLabel,
  languageTypeSummary,
  cancelTranslation,
  translating,
  translationProgress,
  openAiTranslationProgress,
}

/// 带数量参数的歌词组件文案上下文。
final class LyricsUiTextArguments {
  const LyricsUiTextArguments({
    this.completed = 0,
    this.total = 0,
    this.language = '',
    this.type = '',
  });

  final int completed;
  final int total;
  final String language;
  final String type;
}

typedef LyricsUiTextResolver =
    String Function(LyricsUiTextKey key, LyricsUiTextArguments arguments);
typedef LyricsFormatLabelResolver = String Function(LyricsFormat format);
typedef LyricsLanguageLabelResolver = String Function(String language);
typedef LyricsTypeLabelResolver = String Function(LyricsType type);

/// 通用歌词控件的宿主可注入文案集合。
final class LyricsUiStrings {
  const LyricsUiStrings({
    required this.textResolver,
    required this.formatLabelResolver,
    required this.languageLabelResolver,
    required this.typeLabelResolver,
  });

  factory LyricsUiStrings.zhHans() {
    return const LyricsUiStrings(
      textResolver: _zhHansLyricsText,
      formatLabelResolver: _zhHansLyricsFormatLabel,
      languageLabelResolver: _zhHansLyricsLanguageLabel,
      typeLabelResolver: _zhHansLyricsTypeLabel,
    );
  }

  final LyricsUiTextResolver textResolver;
  final LyricsFormatLabelResolver formatLabelResolver;
  final LyricsLanguageLabelResolver languageLabelResolver;
  final LyricsTypeLabelResolver typeLabelResolver;

  String text(
    LyricsUiTextKey key, {
    LyricsUiTextArguments arguments = const LyricsUiTextArguments(),
  }) {
    return textResolver(key, arguments);
  }

  String formatLabel(LyricsFormat format) => formatLabelResolver(format);

  String languageLabel(String language) => languageLabelResolver(
    LyricsLanguageRegistry.normalizeKey(language) ?? language,
  );

  String typeLabel(LyricsType type) => typeLabelResolver(type);
}

String _zhHansLyricsText(LyricsUiTextKey key, LyricsUiTextArguments arguments) {
  return switch (key) {
    LyricsUiTextKey.formatLabel => '歌词格式',
    LyricsUiTextKey.offsetLabel => '偏移',
    LyricsUiTextKey.languageTypeSummary =>
      '${arguments.language}（${arguments.type}）',
    LyricsUiTextKey.cancelTranslation => '取消翻译',
    LyricsUiTextKey.translating => '翻译中...',
    LyricsUiTextKey.translationProgress =>
      '翻译中 ${arguments.completed}/${arguments.total}',
    LyricsUiTextKey.openAiTranslationProgress =>
      'OpenAI 翻译进度 ${arguments.completed}/${arguments.total}',
  };
}

String _zhHansLyricsFormatLabel(LyricsFormat format) {
  return switch (format) {
    LyricsFormat.verbatimLrc => '逐字 LRC',
    LyricsFormat.lineByLineLrc => '逐行 LRC',
    LyricsFormat.enhancedLrc => '增强 LRC',
    LyricsFormat.srt => 'SRT',
    LyricsFormat.ass => 'ASS',
    _ => format.name.toUpperCase(),
  };
}

String _zhHansLyricsLanguageLabel(String language) {
  return switch (language) {
    LyricsLanguageRegistry.original => '原文',
    LyricsLanguageRegistry.translation => '译文',
    LyricsLanguageRegistry.romanized => '罗马音',
    _ => language,
  };
}

String _zhHansLyricsTypeLabel(LyricsType type) {
  return switch (type) {
    LyricsType.verbatim => '逐字',
    LyricsType.lineByLine => '逐行',
    LyricsType.plainText => '纯文本',
  };
}
