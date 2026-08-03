/// 桌面歌词渲染使用的 RGB 颜色值。
final class RgbColor {
  const RgbColor(this.r, this.g, this.b)
    : assert(r >= 0 && r <= 255),
      assert(g >= 0 && g <= 255),
      assert(b >= 0 && b <= 255);

  final int r;
  final int g;
  final int b;

  /// 按 `[r, g, b]` 顺序输出，供宿主配置和平台通道序列化复用。
  List<int> toTuple() => <int>[r, g, b];
}

/// 桌面浮窗在虚拟桌面逻辑坐标系中的矩形区域。
final class WindowRect {
  const WindowRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  /// 按 `[left, top, width, height]` 顺序输出，保持现有配置文件字段语义。
  List<double> toList() => <double>[left, top, width, height];
}
