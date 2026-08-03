import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  const TextSimilarity textSimilarity = TextSimilarity();
  const LyricsLineMatcher lineMatcher = LyricsLineMatcher();
  final bool fullProfile =
      Platform.environment['LDDC_ALGORITHM_BENCHMARK'] == '1';

  test('算法组件 benchmark smoke 防止灾难性退化', () {
    final Stopwatch stopwatch = Stopwatch()..start();
    for (int i = 0; i < 120; i += 1) {
      textSimilarity.textDifference('願いの歌 第$i話', '愿望之歌 $i');
    }
    final List<LyricsLine> left = <LyricsLine>[
      for (int index = 0; index < 600; index += 1)
        _line(index * 1000, index * 1000 + 500, 'l$index'),
    ];
    final List<LyricsLine> right = <LyricsLine>[
      for (int index = 0; index < 600; index += 1)
        _line(index * 1000 + 20, index * 1000 + 520, 'r$index'),
    ];
    expect(lineMatcher.findClosestMatch(left, right).length, 600);
    stopwatch.stop();
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });

  test(
    '算法组件 full benchmark 输出结构化 JSON',
    () {
      final List<({String name, void Function() body})> cases =
          _buildBenchmarkCases();
      final Map<String, Object?> output = <String, Object?>{
        'dart': Platform.version,
        'os': Platform.operatingSystem,
        'cases': <Map<String, Object?>>[],
      };
      for (final ({void Function() body, String name}) item in cases) {
        final List<int> samples = <int>[];
        for (int run = 0; run < 5; run += 1) {
          final Stopwatch stopwatch = Stopwatch()..start();
          item.body();
          stopwatch.stop();
          samples.add(stopwatch.elapsedMicroseconds);
        }
        samples.sort();
        (output['cases']! as List<Map<String, Object?>>).add(<String, Object?>{
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
      print(jsonEncode(output));
    },
    skip: fullProfile
        ? false
        : '设置 LDDC_ALGORITHM_BENCHMARK=1 后输出 full profile。',
    tags: 'full-benchmark',
  );
}

List<({String name, void Function() body})> _buildBenchmarkCases() {
  return <({String name, void Function() body})>[
    (
      name: 'textDifference short',
      body: () {
        for (int i = 0; i < 1000; i += 1) {
          const TextSimilarity().textDifference('Song Title $i', 'Song $i');
        }
      },
    ),
    (
      name: 'textDifference multilingual',
      body: () {
        for (int i = 0; i < 1000; i += 1) {
          const TextSimilarity().textDifference('願いの歌 第$i話', '愿望之歌 $i');
        }
      },
    ),
    (
      name: 'findClosestMatch 1200 lines',
      body: () {
        final List<LyricsLine> left = <LyricsLine>[
          for (int index = 0; index < 1200; index += 1)
            _line(index * 1000, index * 1000 + 500, 'l$index'),
        ];
        final List<LyricsLine> right = <LyricsLine>[
          for (int index = 0; index < 1200; index += 1)
            _line(index * 1000 + 12, index * 1000 + 512, 'r$index'),
        ];
        const LyricsLineMatcher().findClosestMatch(left, right);
      },
    ),
  ];
}

LyricsLine _line(int startMs, int endMs, String text) {
  return LyricsLine(
    startMs: startMs,
    endMs: endMs,
    words: <LyricsWord>[LyricsWord(startMs: startMs, endMs: endMs, text: text)],
  );
}
