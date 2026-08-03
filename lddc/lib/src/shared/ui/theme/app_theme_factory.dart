import 'package:flutter/material.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../core/config/config.dart';
import 'lyrics_theme_extension.dart';

/// 应用主题工厂：集中管理 ThemeData 与 ThemeExtension 的注入。
abstract final class AppThemeFactory {
  static const Color _seedColor = Color(0xFF1F6F4A);

  static ThemeData build({
    required AppConfig config,
    required Brightness brightness,
  }) {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    final List<Color> playedGradient = _safeGradient(
      config.desktop.playedColors,
      const <Color>[Color(0xFF00FFFF), Color(0xFF0080FF)],
    );
    final List<Color> unplayedGradient = _safeGradient(
      config.desktop.unplayedColors,
      const <Color>[Color(0xFFFFFFFF), Color(0xFFE0E0E0)],
    );

    // _safeGradient 对空配置始终提供两种回退颜色，因此这里可以直接取首色。
    // 保留不可达的空列表分支会掩盖 helper 的真实契约，也增加后续维护成本。
    final Color strokeFallback = unplayedGradient.first.withAlpha(200);

    final LyricsThemeExtension lyricsTheme = LyricsThemeExtension(
      playedGradientColors: playedGradient,
      unplayedGradientColors: unplayedGradient,
      desktopStrokeColor: strokeFallback,
      desktopStrokeWidth: 1.4,
      desktopFontScale: _safeScale(config.desktop.fontSize, 30.0),
      panelFontScale: _safeScale(config.desktop.panelFontSize, 12.0),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[lyricsTheme],
    );
  }

  static Color _colorFromRgb(RgbColor color) {
    return Color.fromARGB(255, color.r, color.g, color.b);
  }

  static List<Color> _safeGradient(
    List<RgbColor> colors,
    List<Color> fallback,
  ) {
    final List<Color> parsed = colors
        .map(_colorFromRgb)
        .toList(growable: false);
    return parsed.isEmpty ? fallback : parsed;
  }

  static double _safeScale(double value, double baseline) {
    return (value / baseline).clamp(0.4, 3.0);
  }
}
