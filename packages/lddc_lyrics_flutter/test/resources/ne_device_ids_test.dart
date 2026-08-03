import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NeDeviceIdPool 从压缩资产懒加载完整样本池', () async {
    final NeDeviceIdPool pool = createBundledNeDeviceIdPool();

    final List<String> ids = await pool.load();
    final String picked = await pool.pick(Random(1));

    expect(ids, hasLength(24641));
    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids.every((String value) => RegExp(r'^[0-9A-F]+$').hasMatch(value)),
      isTrue,
    );
    expect(ids, contains(picked));
  });
}
