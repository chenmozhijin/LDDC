/// 歌词转换使用的能力级配置。
///
/// 共享库不读取宿主应用配置；LDDC 和其他应用分别把自己的配置映射为该对象。
final class LyricsConvertOptions {
  LyricsConvertOptions({
    List<String> languageOrder = const <String>['roma', 'orig', 'ts'],
    this.addEndTimestampLine = false,
    this.millisecondDigits = 3,
    this.lastReferenceLineStyle = 0,
    this.generatorVersion = 'LDDC',
  }) : languageOrder = List<String>.unmodifiable(languageOrder);

  final List<String> languageOrder;
  final bool addEndTimestampLine;
  final int millisecondDigits;
  final int lastReferenceLineStyle;
  final String generatorVersion;
}
