import 'dart:math';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  const TextSimilarity textSimilarity = TextSimilarity();
  const ArtistParser artistParser = ArtistParser();
  const TitleScorer titleScorer = TitleScorer();
  const LyricsLineMatcher lineMatcher = LyricsLineMatcher();
  const LyricsTrackAssigner trackAssigner = LyricsTrackAssigner();

  group('文本相似度与歌手解析', () {
    test('统一全角符号与空白，但不改变歌词文字本身', () {
      const Map<String, String> cases = <String, String>{
        ' （A）\tB\n': '(A) B',
        '｛测试｝': '{测试}',
        'A　B': 'A B',
        'Hello／World': 'Hello/World',
        'Mix＆Match': 'Mix&Match',
        '＄price％': r'$price%',
      };

      for (final MapEntry<String, String> item in cases.entries) {
        expect(
          textSimilarity.unifiedSymbol(item.key),
          item.value,
          reason: item.key,
        );
      }
    });

    test('复杂角色与歌手署名会保留分组和对应关系', () {
      final ArtistParseResult parsed = artistParser.parse(
        'Project(角色甲・角色乙CV:歌手甲・歌手乙)',
      );

      expect(parsed.groups, <String>['Project']);
      expect(parsed.artists, <List<String>>[
        <String>['歌手甲', '角色甲'],
        <String>['歌手乙', '角色乙'],
      ]);
    });

    test('分组和分段 CV 语法保持角色与歌手一一对应', () {
      final ArtistParseResult grouped = artistParser.parse(
        'Project(角色甲・角色乙)/CV:歌手甲・歌手乙',
      );
      final ArtistParseResult segmented = artistParser.parse(
        'GroupA(角色甲・角色乙CV:歌手甲・歌手乙)/'
        'GroupB(角色丙・角色丁CV:歌手丙・歌手丁)',
      );

      expect(grouped.groups, <String>['Project']);
      expect(grouped.artists, hasLength(2));
      expect(grouped.artists[0].toSet(), <String>{'角色甲', '歌手甲'});
      expect(grouped.artists[1].toSet(), <String>{'角色乙', '歌手乙'});
      expect(segmented.groups, <String>['GroupA', 'GroupB']);
      expect(segmented.artists, hasLength(4));
      expect(segmented.artists[2].toSet(), <String>{'角色丙', '歌手丙'});
    });

    test('组合成员、feat 角色、别名和常见分隔符解析为稳定结构', () {
      final ArtistParseResult groupMembers = artistParser.parse(
        'Project(歌手甲・歌手乙)',
      );
      final ArtistParseResult featured = artistParser.parse(
        'Singer One feat.Character(Singer Two)',
      );
      final ArtistParseResult aliases = artistParser.parse(
        'Singer(CV:Alias)/Same(Same)&Third',
      );

      expect(groupMembers.groups, <String>['Project']);
      expect(groupMembers.artists, <List<String>>[
        <String>['歌手甲'],
        <String>['歌手乙'],
      ]);
      expect(featured.artists.first, <String>['Singer One']);
      expect(featured.artists.last.toSet(), <String>{
        'Character',
        'Singer Two',
      });
      expect(aliases.artists, hasLength(3));
      expect(aliases.artists[0].toSet(), <String>{'Singer', 'Alias'});
      expect(aliases.artists[1], <String>['Same']);
      expect(aliases.artists[2], <String>['Third']);
    });

    test('全角符号、逐字空格、组合前缀和 ). 分段被规范化', () {
      expect(artistParser.parse('Ａ Ｂ Ｃ').artists.single, <String>['ＡＢＣ']);

      final ArtistParseResult prefixed = artistParser.parse('Project 歌手甲、歌手乙');
      expect(prefixed.groups, <String>['Project']);
      expect(prefixed.artists, <List<String>>[
        <String>['歌手甲'],
        <String>['歌手乙'],
      ]);

      final ArtistParseResult dotted = artistParser.parse(
        'Singer(Alias).Other',
      );
      expect(dotted.artists, hasLength(2));
      expect(dotted.artists.first.toSet(), <String>{'Singer', 'Alias'});
      expect(dotted.artists.last, <String>['Other']);
    });

    test('listMaxDifference 保持有向 SequenceMatcher 语义', () {
      final double forward = textSimilarity.textDifference('tide', 'diet');
      final double backward = textSimilarity.textDifference('diet', 'tide');
      expect(
        textSimilarity.listMaxDifference(
          <Object>[
            <String>['tide'],
          ],
          <Object>[
            <String>['diet'],
          ],
        ),
        forward,
      );
      expect(
        textSimilarity.listMaxDifference(
          <Object>[
            <String>['diet'],
          ],
          <Object>[
            <String>['tide'],
          ],
        ),
        backward,
      );
    });

    test('评分入口拒绝非字符串别名', () {
      expect(
        () => textSimilarity.listMaxDifference(
          <Object>[
            <Object>['A', 1],
          ],
          <Object>['A'],
        ),
        throwsArgumentError,
      );
      expect(
        () => artistParser.calculateScore(<Object>['A', 1], 'A'),
        throwsArgumentError,
      );
      expect(() => artistParser.calculateScore(1, 'A'), throwsArgumentError);
    });

    test('歌手评分覆盖字符串、集合和解析结构路径并保持基本排序', () {
      final double exactText = artistParser.calculateScore(
        'Project(角色CV:歌手)',
        'Project(角色CV:歌手)',
      );
      final double exactLists = artistParser.calculateScore(
        <String>['Singer A', 'Singer B'],
        <String>['Singer A', 'Singer B'],
      );
      final double listVsParsed = artistParser.calculateScore(<String>[
        '歌手',
        '角色',
      ], 'Project(角色CV:歌手)');
      final double unrelated = artistParser.calculateScore(<String>[
        'Singer A',
      ], 'Completely Different');
      final double reversed = artistParser.calculateScore(
        'Project(角色CV:歌手)',
        <String>['歌手', '角色'],
      );

      expect(exactText, 100);
      expect(exactLists, 100);
      expect(listVsParsed, greaterThan(unrelated));
      expect(reversed, listVsParsed);
      expect(artistParser.calculateScore('', ''), greaterThanOrEqualTo(0));
    });

    test('解析结果冻结两层集合', () {
      final ArtistParseResult parsed = artistParser.parse('A(CV:B)');
      expect(() => parsed.groups.add('C'), throwsUnsupportedError);
      expect(() => parsed.artists.add(<String>['C']), throwsUnsupportedError);
      expect(() => parsed.artists.first.add('C'), throwsUnsupportedError);
    });
  });

  group('标题与歌手评分', () {
    test('calculateTitleScore 按字面量处理 tag 中的正则元字符', () {
      final double same = titleScorer.calculateScore(
        'Song inst.',
        'Song inst.',
      );
      final double dotLiteral = titleScorer.calculateScore(
        'Song inst.',
        'Song insta',
      );
      final double cppLiteral = titleScorer.calculateScore(
        'Song C++ ver.',
        'Song C-- ver.',
      );

      expect(same, 100);
      expect(dotLiteral, lessThan(same));
      expect(cppLiteral, lessThan(100));
    });
  });

  group('TitleScorer 版本分类', () {
    test('识别 title 与 subtitle 中的纯音乐版本词', () {
      for (final String marker in <String>[
        'Inst.',
        'Instrumental',
        'off vocal',
        'off-vocal',
        'off_vocal version',
        '伴奏',
        '纯音乐',
      ]) {
        expect(
          titleScorer.analyzeVariant('Last Desire ($marker)').isInstrumental,
          isTrue,
          reason: marker,
        );
      }
    });

    test('普通版与纯音乐版关系使用参数化规则判断', () {
      const List<({String local, String remote, SongVariantRelation expected})>
      cases = <({String local, String remote, SongVariantRelation expected})>[
        (
          local: 'Signal',
          remote: 'Signal (Inst.)',
          expected: SongVariantRelation.conflict,
        ),
        (
          local: 'Signal',
          remote: 'Signal Inst.',
          expected: SongVariantRelation.conflict,
        ),
        (
          local: 'Signal (Inst.)',
          remote: 'Signal',
          expected: SongVariantRelation.unknown,
        ),
        (
          local: 'Signal (Inst.)',
          remote: 'Signal Instrumental',
          expected: SongVariantRelation.compatible,
        ),
        (
          local: 'Signal',
          remote: 'Signal',
          expected: SongVariantRelation.compatible,
        ),
        (local: '', remote: 'Signal', expected: SongVariantRelation.unknown),
        (local: 'Signal', remote: '', expected: SongVariantRelation.unknown),
      ];

      for (final item in cases) {
        expect(
          titleScorer.classifyVariant(item.local, item.remote),
          item.expected,
          reason: '${item.local} -> ${item.remote}',
        );
      }
    });

    test('标题评分保持完全匹配优先，并将无关标题排在最后', () {
      final double exact = titleScorer.calculateScore(
        'Signal (Live)',
        'Signal (Live)',
      );
      final double related = titleScorer.calculateScore(
        'Signal',
        'Signal (Live)',
      );
      final double unrelated = titleScorer.calculateScore(
        'Signal',
        'Different Work',
      );

      expect(exact, 100);
      expect(related, lessThan(exact));
      expect(related, greaterThan(unrelated));
    });

    test('标题标签归一覆盖 mix/edit/solo/TV size 和非 BMP 前缀', () {
      const List<({String left, String right})> relatedPairs =
          <({String left, String right})>[
            (left: 'Signal mixed version', right: 'Signal mix'),
            (left: 'Signal edited ver.', right: 'Signal edit'),
            (left: 'Signal TV size ver.', right: 'Signal TVサイズ'),
            (left: '😀Signal solo ver.', right: '😀Signal solo'),
          ];

      for (final pair in relatedPairs) {
        final double related = titleScorer.calculateScore(
          pair.left,
          pair.right,
        );
        final double unrelated = titleScorer.calculateScore(
          pair.left,
          'Different Work',
        );
        expect(related, greaterThan(unrelated), reason: pair.toString());
      }

      expect(
        titleScorer.calculateScore('Signal solo ver.', 'Signal edit ver.'),
        inInclusiveRange(0, 100),
      );
      expect(
        titleScorer.calculateScore('No shared prefix', 'Different'),
        inInclusiveRange(0, 100),
      );
    });
  });
  group('歌词行匹配', () {
    test('括号注释与空白差异不会破坏同一行判断', () {
      expect(
        lineMatcher.isSameLine(
          _line(0, 1000, 'same line （注释）'),
          _line(0, 1000, 'same line'),
        ),
        isTrue,
      );
      expect(
        lineMatcher.isSameLine(
          _line(0, 1000, 'same    line'),
          _line(0, 1000, 'sameline'),
        ),
        isTrue,
      );
      expect(
        lineMatcher.isSameLine(
          _line(0, 1000, 'first'),
          _line(0, 1000, 'second'),
        ),
        isFalse,
      );
    });

    test('QM 过滤空行后保留原始索引', () {
      final List<LyricsLine> qmWithEmptyOrig = <LyricsLine>[
        _emptyLine(0),
        _line(1000, 2000, 'a'),
        _line(2000, 3000, 'b'),
      ];
      final List<LyricsLine> qmWithoutEmptyTrans = <LyricsLine>[
        _line(1000, 2000, 'ta'),
        _line(2000, 3000, 'tb'),
      ];
      expect(
        lineMatcher.findClosestMatch(
          qmWithEmptyOrig,
          qmWithoutEmptyTrans,
          source: Source.qm,
        ),
        <int, int>{1: 0, 2: 1},
      );
    });

    test('findClosestMatch 大量行时保持线性候选内存', () {
      final List<LyricsLine> left = <LyricsLine>[
        for (int index = 0; index < 1200; index += 1)
          _line(index * 1000, index * 1000 + 500, 'l$index'),
      ];
      final List<LyricsLine> right = <LyricsLine>[
        for (int index = 0; index < 1200; index += 1)
          _line(index * 1000 + 12, index * 1000 + 512, 'r$index'),
      ];
      final Map<int, int> result = lineMatcher.findClosestMatch(left, right);
      expect(result.length, 1200);
      expect(result[0], 0);
      expect(result[1199], 1199);
    });

    test('findClosestMatch 惰性堆与全量稳定贪心等价', () {
      final Random random = Random(20260715);
      for (int iteration = 0; iteration < 300; iteration += 1) {
        final List<LyricsLine> left = <LyricsLine>[
          for (int index = 0; index < random.nextInt(8) + 1; index += 1)
            _line(random.nextInt(7) * 100, 1000, 'left-$index'),
        ];
        final List<LyricsLine> right = <LyricsLine>[
          for (int index = 0; index < random.nextInt(8) + 1; index += 1)
            _line(random.nextInt(7) * 100, 1000, 'right-$index'),
        ];
        expect(
          lineMatcher.findClosestMatch(left, right),
          _findClosestMatchExhaustive(left, right),
          reason: 'iteration=$iteration',
        );
      }
    });
  });

  group('桌面歌词轨道分配', () {
    test('空时间轴不创建轨道', () {
      expect(trackAssigner.assignPositions(const <LyricsLine>[]), isEmpty);
    });

    test('随机重叠时间轴不丢行、不重复且同轨不重叠', () {
      final Random random = Random(20260731);
      for (int iteration = 0; iteration < 200; iteration += 1) {
        final List<LyricsLine> lines = <LyricsLine>[
          for (int index = 0; index < random.nextInt(24) + 1; index += 1)
            _line(random.nextInt(12000), 0, 'line-$index'),
        ];
        for (int index = 0; index < lines.length; index += 1) {
          final int startMs = lines[index].startMs!;
          lines[index] = _line(
            startMs,
            startMs + random.nextInt(2500) + 1,
            'line-$index',
          );
        }

        final Map<(Direction, int), List<(int, LyricsLine)>> assigned =
            trackAssigner.assignPositions(lines);
        final List<(int, LyricsLine)> flattened = assigned.values
            .expand((List<(int, LyricsLine)> slot) => slot)
            .toList(growable: false);
        final List<int> indices = flattened
            .map(((int, LyricsLine) item) => item.$1)
            .toList(growable: false);

        expect(flattened, hasLength(lines.length), reason: '$iteration');
        expect(indices.toSet(), <int>{
          for (int index = 0; index < lines.length; index += 1) index,
        }, reason: '$iteration');
        for (final (int index, LyricsLine line) in flattened) {
          expect(identical(line, lines[index]), isTrue, reason: '$iteration');
        }
        for (final List<(int, LyricsLine)> slot in assigned.values) {
          for (int index = 1; index < slot.length; index += 1) {
            expect(
              slot[index - 1].$2.endMs,
              lessThanOrEqualTo(slot[index].$2.startMs!),
              reason: 'iteration=$iteration slot=$slot',
            );
          }
        }
      }
    });
  });
}

LyricsLine _emptyLine(int startMs) {
  return LyricsLine(
    startMs: startMs,
    endMs: startMs,
    words: const <LyricsWord>[],
  );
}

LyricsLine _line(int startMs, int endMs, String text) {
  return LyricsLine(
    startMs: startMs,
    endMs: endMs,
    words: <LyricsWord>[LyricsWord(startMs: startMs, endMs: endMs, text: text)],
  );
}

Map<int, int> _findClosestMatchExhaustive(
  List<LyricsLine> left,
  List<LyricsLine> right,
) {
  final List<({int diffMs, int leftIndex, int rightIndex})> candidates =
      <({int diffMs, int leftIndex, int rightIndex})>[
        for (int leftIndex = 0; leftIndex < left.length; leftIndex += 1)
          for (int rightIndex = 0; rightIndex < right.length; rightIndex += 1)
            (
              diffMs: (left[leftIndex].startMs! - right[rightIndex].startMs!)
                  .abs(),
              leftIndex: leftIndex,
              rightIndex: rightIndex,
            ),
      ]..sort((left, right) {
        final int differenceOrder = left.diffMs.compareTo(right.diffMs);
        if (differenceOrder != 0) {
          return differenceOrder;
        }
        final int leftOrder = left.leftIndex.compareTo(right.leftIndex);
        return leftOrder != 0
            ? leftOrder
            : left.rightIndex.compareTo(right.rightIndex);
      });
  final Map<int, int> matched = <int, int>{};
  final Set<int> usedLeft = <int>{};
  final Set<int> usedRight = <int>{};
  for (final candidate in candidates) {
    if (usedLeft.contains(candidate.leftIndex) ||
        usedRight.contains(candidate.rightIndex)) {
      continue;
    }
    usedLeft.add(candidate.leftIndex);
    usedRight.add(candidate.rightIndex);
    matched[candidate.leftIndex] = candidate.rightIndex;
  }
  return matched;
}
