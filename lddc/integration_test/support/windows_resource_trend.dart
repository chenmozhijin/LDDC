import 'dart:math' as math;

/// 估算 Windows 资源压力样本中每次操作的持续私有内存增长。
///
/// Dart VM 与 Windows 分配器会在连续操作中形成周期性的上升和回落。固定比较
/// 尾部两小段容易与 GC 周期同相，明明已经回落仍被误判为持续泄漏。这里使用
/// 最近最多 60 个样本的 Theil-Sen 斜率中位数：周期性尖峰只影响少量样本对，
/// 而真正的线性增长会抬高大多数样本对。计算只在场景结束时执行一次，最多
/// 生成 1770 个短生命周期 double，不进入生产应用，也不会形成常驻内存。
int estimatePrivateBytesGrowthPerOperation(List<int> privateBytes) {
  if (privateBytes.length < 4) {
    return 0;
  }
  final int sampleCount = math.min(60, privateBytes.length);
  final List<int> tail = privateBytes.sublist(
    privateBytes.length - sampleCount,
  );
  final List<double> slopes = <double>[];
  for (int start = 0; start < tail.length - 1; start += 1) {
    for (int end = start + 1; end < tail.length; end += 1) {
      slopes.add((tail[end] - tail[start]) / (end - start));
    }
  }
  slopes.sort();
  final int middle = slopes.length ~/ 2;
  final double median = slopes.length.isOdd
      ? slopes[middle]
      : (slopes[middle - 1] + slopes[middle]) / 2;
  return median.round();
}

/// 判断操作期上升是否在窗口保持常驻后仍形成真实私有内存增长。
///
/// Theil-Sen 只观察最近一段样本，Windows 分配器或 Dart GC 的局部相位可能让
/// 斜率短暂超过门槛。真实泄漏必须同时满足趋势超标和 settle 后累计驻留超标；
/// 任一证据缺失都不能把分配器波动宣称为持续泄漏。
bool hasSustainedPrivateBytesGrowth({
  required int baselinePrivateBytes,
  required int settledPrivateBytes,
  required int estimatedGrowthPerOperation,
  required int growthPerOperationLimit,
  required int residentPrivateBytesSlack,
}) {
  final bool trendExceeded =
      estimatedGrowthPerOperation > growthPerOperationLimit;
  final bool residentDeltaExceeded =
      settledPrivateBytes > baselinePrivateBytes + residentPrivateBytesSlack;
  return trendExceeded && residentDeltaExceeded;
}
