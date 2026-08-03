import 'package:flutter/material.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../lyrics_ui_strings.dart';

/// 歌词预览框内的 OpenAI 流式翻译进度条。
///
/// 进度条覆盖在预览内容顶部，不参与布局高度计算，因此开始/结束翻译时不会
/// 推挤歌词正文。这里只接收已经由 controller 判定好的状态，避免展示组件读取
/// 业务配置，方便搜索页和打开歌词页共用。
final class LyricsTranslationProgressOverlay extends StatelessWidget {
  const LyricsTranslationProgressOverlay({
    super.key,
    required this.progress,
    required this.strings,
    required this.child,
  });

  final OpenAiTranslationProgress? progress;
  final LyricsUiStrings strings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final OpenAiTranslationProgress? current = progress;
    if (current == null) {
      return child;
    }
    final String tooltip = strings.text(
      LyricsUiTextKey.openAiTranslationProgress,
      arguments: LyricsUiTextArguments(
        completed: current.completedLines,
        total: current.totalLines,
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 3,
          child: Tooltip(
            message: tooltip,
            child: Semantics(
              label: tooltip,
              child: LinearProgressIndicator(
                key: const ValueKey<String>('lyrics_translation_progress_bar'),
                minHeight: 3,
                value: current.value,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
