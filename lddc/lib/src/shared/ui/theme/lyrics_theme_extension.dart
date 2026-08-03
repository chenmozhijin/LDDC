import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 歌词域主题扩展。
///
/// 仅承载视觉语义，不包含业务状态。
@immutable
final class LyricsThemeExtension extends ThemeExtension<LyricsThemeExtension> {
  LyricsThemeExtension({
    required List<Color> playedGradientColors,
    required List<Color> unplayedGradientColors,
    required Color desktopStrokeColor,
    required double desktopStrokeWidth,
    required double desktopFontScale,
    required double panelFontScale,
  }) : this._(
         playedGradientColors: List<Color>.unmodifiable(playedGradientColors),
         unplayedGradientColors: List<Color>.unmodifiable(
           unplayedGradientColors,
         ),
         desktopStrokeColor: desktopStrokeColor,
         desktopStrokeWidth: desktopStrokeWidth,
         desktopFontScale: desktopFontScale,
         panelFontScale: panelFontScale,
       );

  const LyricsThemeExtension._({
    required this.playedGradientColors,
    required this.unplayedGradientColors,
    required this.desktopStrokeColor,
    required this.desktopStrokeWidth,
    required this.desktopFontScale,
    required this.panelFontScale,
  });

  /// 已播放歌词渐变色。
  final List<Color> playedGradientColors;

  /// 未播放歌词渐变色。
  final List<Color> unplayedGradientColors;

  /// 桌面歌词描边颜色。
  final Color desktopStrokeColor;

  /// 桌面歌词描边宽度。
  final double desktopStrokeWidth;

  /// 桌面歌词字号比例。
  final double desktopFontScale;

  /// 面板歌词字号比例。
  final double panelFontScale;

  @override
  LyricsThemeExtension copyWith({
    List<Color>? playedGradientColors,
    List<Color>? unplayedGradientColors,
    Color? desktopStrokeColor,
    double? desktopStrokeWidth,
    double? desktopFontScale,
    double? panelFontScale,
  }) {
    // 未替换的渐变已经不可变，可以安全共享；只冻结调用方真正传入的新列表。
    // 这样仅修改描边或字号时不会复制两份颜色数组。
    return LyricsThemeExtension._(
      playedGradientColors: _freezeReplacement(
        playedGradientColors,
        this.playedGradientColors,
      ),
      unplayedGradientColors: _freezeReplacement(
        unplayedGradientColors,
        this.unplayedGradientColors,
      ),
      desktopStrokeColor: desktopStrokeColor ?? this.desktopStrokeColor,
      desktopStrokeWidth: desktopStrokeWidth ?? this.desktopStrokeWidth,
      desktopFontScale: desktopFontScale ?? this.desktopFontScale,
      panelFontScale: panelFontScale ?? this.panelFontScale,
    );
  }

  @override
  LyricsThemeExtension lerp(
    covariant ThemeExtension<LyricsThemeExtension>? other,
    double t,
  ) {
    if (other is! LyricsThemeExtension) {
      return this;
    }
    return LyricsThemeExtension(
      playedGradientColors: _lerpColorList(
        playedGradientColors,
        other.playedGradientColors,
        t,
      ),
      unplayedGradientColors: _lerpColorList(
        unplayedGradientColors,
        other.unplayedGradientColors,
        t,
      ),
      desktopStrokeColor:
          Color.lerp(desktopStrokeColor, other.desktopStrokeColor, t) ??
          desktopStrokeColor,
      desktopStrokeWidth:
          lerpDouble(desktopStrokeWidth, other.desktopStrokeWidth, t) ??
          desktopStrokeWidth,
      desktopFontScale:
          lerpDouble(desktopFontScale, other.desktopFontScale, t) ??
          desktopFontScale,
      panelFontScale:
          lerpDouble(panelFontScale, other.panelFontScale, t) ?? panelFontScale,
    );
  }

  static List<Color> _lerpColorList(List<Color> a, List<Color> b, double t) {
    // ThemeExtension 在动画端点必须精确返回对应主题。若直接按较长列表补项，
    // 空列表在 t=0 也会凭空出现目标颜色，导致主题切换首帧跳变。
    if (t <= 0) {
      return a;
    }
    if (t >= 1) {
      return b;
    }
    final int maxLength = math.max(a.length, b.length);
    if (maxLength == 0) {
      return const <Color>[];
    }
    // 一侧为空时从透明色淡入/淡出；非空但较短时延续末尾颜色，避免渐变
    // stop 数量变化时新增颜色瞬间出现。构造器会统一冻结返回列表，这里不重复复制。
    return List<Color>.generate(maxLength, (int index) {
      final Color left = _colorAt(a, index);
      final Color right = _colorAt(b, index);
      return Color.lerp(left, right, t) ?? left;
    }, growable: false);
  }

  static Color _colorAt(List<Color> colors, int index) {
    if (colors.isEmpty) {
      return Colors.transparent;
    }
    return colors[math.min(index, colors.length - 1)];
  }

  static List<Color> _freezeReplacement(
    List<Color>? replacement,
    List<Color> current,
  ) {
    if (replacement == null || identical(replacement, current)) {
      return current;
    }
    return List<Color>.unmodifiable(replacement);
  }
}
