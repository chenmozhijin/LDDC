import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../lyrics_ui_strings.dart';

/// 翻译按钮文案生成器。
///
/// UI 文案集中后，搜索页和打开歌词页不会因为各自复制判断而出现显示漂移。
String translationProgressButtonLabel({
  required LyricsUiStrings strings,
  required bool hasTranslation,
  required bool isTranslating,
  required OpenAiTranslationProgress? progress,
  required String idleLabel,
}) {
  if (hasTranslation) {
    return strings.text(LyricsUiTextKey.cancelTranslation);
  }
  if (progress != null &&
      progress.completedLines > 0 &&
      progress.totalLines > 0) {
    return strings.text(
      LyricsUiTextKey.translationProgress,
      arguments: LyricsUiTextArguments(
        completed: progress.completedLines,
        total: progress.totalLines,
      ),
    );
  }
  return isTranslating || progress != null
      ? strings.text(LyricsUiTextKey.translating)
      : idleLabel;
}
