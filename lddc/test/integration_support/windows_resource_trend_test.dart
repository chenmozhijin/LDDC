import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/windows_resource_trend.dart';

void main() {
  test('周期性分配与回落不会被误判为持续私有内存增长', () {
    final List<int> samples = List<int>.generate(100, (int index) {
      // 每 20 次操作模拟一次 GC 回落；周期内每次约增长 1 MiB，但长期基线不涨。
      return 320 * 1024 * 1024 + (index % 20) * 1024 * 1024;
    });

    expect(
      estimatePrivateBytesGrowthPerOperation(samples),
      lessThan(256 * 1024),
    );
  });

  test('周期性波动上的真实线性增长仍会超过硬门槛', () {
    final List<int> samples = List<int>.generate(100, (int index) {
      final int allocatorSawtooth = (index % 20) * 1024 * 1024;
      final int sustainedGrowth = index * 512 * 1024;
      return 320 * 1024 * 1024 + allocatorSawtooth + sustainedGrowth;
    });

    expect(
      estimatePrivateBytesGrowthPerOperation(samples),
      greaterThan(256 * 1024),
    );
  });

  test('样本不足时不伪造趋势证据', () {
    expect(estimatePrivateBytesGrowthPerOperation(<int>[1, 2, 3]), 0);
  });

  test('hosted 回落后的高局部斜率不构成持续增长', () {
    expect(
      hasSustainedPrivateBytesGrowth(
        baselinePrivateBytes: 355266560,
        settledPrivateBytes: 353599488,
        estimatedGrowthPerOperation: 275501,
        growthPerOperationLimit: 256 * 1024,
        residentPrivateBytesSlack: 24 * 1024 * 1024,
      ),
      isFalse,
    );
  });

  test('趋势和 settle 后驻留同时超标才构成持续增长', () {
    expect(
      hasSustainedPrivateBytesGrowth(
        baselinePrivateBytes: 320 * 1024 * 1024,
        settledPrivateBytes: 350 * 1024 * 1024,
        estimatedGrowthPerOperation: 512 * 1024,
        growthPerOperationLimit: 256 * 1024,
        residentPrivateBytesSlack: 24 * 1024 * 1024,
      ),
      isTrue,
    );
  });

  test('只有驻留超标时不伪造操作期持续趋势', () {
    expect(
      hasSustainedPrivateBytesGrowth(
        baselinePrivateBytes: 320 * 1024 * 1024,
        settledPrivateBytes: 350 * 1024 * 1024,
        estimatedGrowthPerOperation: 128 * 1024,
        growthPerOperationLimit: 256 * 1024,
        residentPrivateBytesSlack: 24 * 1024 * 1024,
      ),
      isFalse,
    );
  });
}
