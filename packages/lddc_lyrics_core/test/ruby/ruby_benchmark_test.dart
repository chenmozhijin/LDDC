import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../support/ruby/ruby_vector_harness.dart';

void main() {
  final bool fullProfile = Platform.environment['LDDC_RUBY_BENCHMARK'] == '1';

  test('Ruby 生成 benchmark smoke 防止灾难性退化', () {
    final List<(LyricsLine, LyricsLine)> cases = _benchmarkLines();
    final Stopwatch stopwatch = Stopwatch()..start();
    int generatedSpans = 0;
    for (int run = 0; run < 80; run += 1) {
      for (final (LyricsLine orig, LyricsLine roma) in cases) {
        generatedSpans += generateRuby(orig, roma).length;
      }
    }
    stopwatch.stop();

    expect(generatedSpans, greaterThan(0));
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });

  test(
    'Ruby 生成 full benchmark 输出结构化 JSON',
    () {
      final List<({String name, void Function() body})> cases =
          _buildBenchmarkCases();
      final List<Map<String, Object?>> results = <Map<String, Object?>>[];
      for (final ({String name, void Function() body}) item in cases) {
        final List<int> samples = <int>[];
        for (int run = 0; run < 5; run += 1) {
          final Stopwatch stopwatch = Stopwatch()..start();
          item.body();
          stopwatch.stop();
          samples.add(stopwatch.elapsedMicroseconds);
        }
        samples.sort();
        results.add(<String, Object?>{
          'name': item.name,
          'samples': samples,
          'medianUs': samples[samples.length ~/ 2],
          'p95Us':
              samples[(samples.length * 0.95).floor().clamp(
                0,
                samples.length - 1,
              )],
        });
      }

      // ignore: avoid_print
      print(
        jsonEncode(<String, Object?>{
          'dart': Platform.version,
          'os': Platform.operatingSystem,
          'cases': results,
        }),
      );
    },
    skip: fullProfile ? false : '设置 LDDC_RUBY_BENCHMARK=1 后输出 full profile。',
    tags: 'full-benchmark',
  );
}

List<({String name, void Function() body})> _buildBenchmarkCases() {
  final List<(LyricsLine, LyricsLine)> lines = _benchmarkLines();
  return <({String name, void Function() body})>[
    (
      name: 'generateRuby dictionary phrases x100',
      body: () {
        for (int run = 0; run < 100; run += 1) {
          generateRuby(lines[0].$1, lines[0].$2);
        }
      },
    ),
    (
      name: 'generateRuby mixed graphemes x100',
      body: () {
        for (int run = 0; run < 100; run += 1) {
          generateRuby(lines[1].$1, lines[1].$2);
        }
      },
    ),
    (
      name: 'romaToHiragana x5000',
      body: () {
        for (int run = 0; run < 5000; run += 1) {
          romaToHiragana("shin'ichi no ko-hi-");
        }
      },
    ),
  ];
}

List<(LyricsLine, LyricsLine)> _benchmarkLines() {
  return <(LyricsLine, LyricsLine)>[
    (
      buildRubyTestLine('未来永劫 東京の夜'),
      buildRubyTestLine('mirai eigou  toukyou no yoru'),
    ),
    (
      buildRubyTestLine('🙂 東京で一番星を描く'),
      buildRubyTestLine('toukyou de ichibanboshi wo egaku'),
    ),
  ];
}
