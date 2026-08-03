import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/shared/ui/theme/app_theme_factory.dart';
import 'package:lddc/src/shared/ui/theme/lyrics_theme_extension.dart';

void main() {
  test('LyricsThemeExtension 颜色列表不可被外部修改', () {
    final List<Color> colors = <Color>[Colors.red];
    final LyricsThemeExtension theme = LyricsThemeExtension(
      playedGradientColors: colors,
      unplayedGradientColors: const <Color>[Colors.white],
      desktopStrokeColor: Colors.black,
      desktopStrokeWidth: 1,
      desktopFontScale: 1,
      panelFontScale: 1,
    );
    colors.add(Colors.blue);

    expect(theme.playedGradientColors, <Color>[Colors.red]);
    expect(
      () => theme.playedGradientColors.add(Colors.green),
      throwsUnsupportedError,
    );
  });

  test('LyricsThemeExtension lerp 支持一侧为空列表', () {
    final LyricsThemeExtension empty = LyricsThemeExtension(
      playedGradientColors: const <Color>[],
      unplayedGradientColors: const <Color>[],
      desktopStrokeColor: Colors.black,
      desktopStrokeWidth: 1,
      desktopFontScale: 1,
      panelFontScale: 1,
    );
    final LyricsThemeExtension filled = LyricsThemeExtension(
      playedGradientColors: const <Color>[Colors.red],
      unplayedGradientColors: const <Color>[Colors.white, Colors.blue],
      desktopStrokeColor: Colors.white,
      desktopStrokeWidth: 2,
      desktopFontScale: 1.2,
      panelFontScale: 1.2,
    );

    expect(empty.lerp(filled, 0).playedGradientColors, isEmpty);
    expect(
      empty.lerp(filled, 1).unplayedGradientColors,
      filled.unplayedGradientColors,
    );

    final LyricsThemeExtension middle = empty.lerp(filled, 0.5);
    expect(middle.playedGradientColors, <Color>[
      Color.lerp(Colors.transparent, Colors.red, 0.5)!,
    ]);
    expect(middle.unplayedGradientColors, hasLength(2));
  });

  test('LyricsThemeExtension copyWith 冻结替换列表并保留其他字段', () {
    final LyricsThemeExtension original = LyricsThemeExtension(
      playedGradientColors: const <Color>[Colors.red],
      unplayedGradientColors: const <Color>[Colors.white],
      desktopStrokeColor: Colors.black,
      desktopStrokeWidth: 1,
      desktopFontScale: 1,
      panelFontScale: 1,
    );
    final List<Color> replacement = <Color>[Colors.blue];

    final LyricsThemeExtension copied = original.copyWith(
      playedGradientColors: replacement,
    );
    replacement.add(Colors.green);

    expect(copied.playedGradientColors, <Color>[Colors.blue]);
    expect(
      copied.unplayedGradientColors,
      same(original.unplayedGradientColors),
    );
    expect(
      () => copied.playedGradientColors.add(Colors.orange),
      throwsUnsupportedError,
    );
  });

  test('AppThemeFactory 对空渐变和异常字号使用有界回退', () {
    final AppConfig base = ConfigDefaults.current;
    final DesktopConfig desktop = DesktopConfig(
      playedColors: const <RgbColor>[],
      unplayedColors: const <RgbColor>[],
      defaultLangs: base.desktop.defaultLangs,
      langOrder: base.desktop.langOrder,
      sources: base.desktop.sources,
      fontFamily: base.desktop.fontFamily,
      refreshRate: base.desktop.refreshRate,
      windowRect: base.desktop.windowRect,
      fontSize: -100,
      showFurigana: base.desktop.showFurigana,
      panelFontSize: 1200,
    );

    final ThemeData theme = AppThemeFactory.build(
      config: base.copyWith(desktop: desktop),
      brightness: Brightness.dark,
    );
    final LyricsThemeExtension extension = theme
        .extension<LyricsThemeExtension>()!;

    expect(theme.brightness, Brightness.dark);
    expect(extension.playedGradientColors, const <Color>[
      Color(0xFF00FFFF),
      Color(0xFF0080FF),
    ]);
    expect(extension.unplayedGradientColors, const <Color>[
      Color(0xFFFFFFFF),
      Color(0xFFE0E0E0),
    ]);
    expect(extension.desktopStrokeColor, const Color(0xC8FFFFFF));
    expect(extension.desktopFontScale, 0.4);
    expect(extension.panelFontScale, 3.0);
  });
}
