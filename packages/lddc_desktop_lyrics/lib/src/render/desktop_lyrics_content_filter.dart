/// 桌面歌词内容过滤，语义对齐Python版 `has_content()`。
///
/// 说明：
/// - 仅去掉“实际不应显示”的文本，不改动调用方的时间轴；
/// - 用于过滤空白、注释占位、纯时间标签和歌手标签行。
final RegExp _desktopLyricsMetadataPattern = RegExp(
  r'\[\d+:\d+\.\d+\]|\[\d+,\d+\]|<\d+:\d+\.\d+>',
);

/// 浮窗静态文本保留原始行序与空白分隔，对齐Python版 `set_display_text()`。
List<String> desktopLyricsRetainStaticDisplayLines(Iterable<String> lines) {
  return List<String>.unmodifiable(lines);
}

/// panel 静态文本只保留真正可显示的行，对齐Python版 `_create_static_panel_data()`。
List<String> desktopLyricsVisibleStaticDisplayLines(Iterable<String> lines) {
  return List<String>.unmodifiable(
    lines.where(desktopLyricsHasRenderableContent),
  );
}

bool desktopLyricsHasRenderableContent(String line) {
  final String content = line
      .replaceAll(_desktopLyricsMetadataPattern, '')
      .trim();
  if (content.isEmpty || content == '//') {
    return false;
  }
  return !(content.length == 2 &&
      content.codeUnitAt(0) >= 0x41 &&
      content.codeUnitAt(0) <= 0x5A &&
      content[1] == '：');
}

String desktopLyricsFilterDisplayText(String line) {
  return desktopLyricsHasRenderableContent(line) ? line : '';
}
