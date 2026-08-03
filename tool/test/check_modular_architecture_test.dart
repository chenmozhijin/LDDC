import 'dart:io';

import 'package:test/test.dart';

import '../check_modular_architecture.dart';

void main() {
  test('AST 门禁会拒绝每类层级、包边界、src 导入与依赖环违规', () async {
    final Directory fixture = Directory(
      'tool/test/fixtures/violations',
    ).absolute;

    final List<String> failures = await checkModularArchitecture(
      fixture,
      checkPubDependencyGraph: false,
    );
    final String report = failures.join('\n');

    expect(report, contains('platform -> infra'));
    expect(report, contains('infra -> platform'));
    expect(report, contains('必须通过 lddc_lyrics_runtime 正式 barrel'));
    expect(report, contains('lddc_lyrics_core 禁止依赖 dart:io'));
    expect(report, contains('lddc_lyrics_core 禁止依赖 lddc_lyrics_runtime'));
    expect(report, contains('lddc_lyrics_runtime 禁止依赖 package:flutter'));
    expect(report, contains('lddc_lyrics_flutter 禁止依赖 package:lddc/'));
    expect(
      report,
      contains('lddc_desktop_lyrics 禁止依赖 package:lddc_lyrics_runtime'),
    );
    expect(report, contains('依赖了 LDDC 应用代码'));
    expect(report, contains('源码依赖图 存在环'));
  });
}
