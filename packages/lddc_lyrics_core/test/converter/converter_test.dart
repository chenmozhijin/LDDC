import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:test/test.dart';

void main() {
  final List<Map<String, dynamic>> sanitizedCases =
      ((jsonDecode(
                    File(
                      'test/resources/converter/sanitized_converter_cases.json',
                    ).readAsStringSync(),
                  )
                  as Map<String, dynamic>)['cases']
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  group('Converter 脱敏真实结构', () {
    for (final Map<String, dynamic> item in sanitizedCases) {
      test(item['originClass'].toString(), () {
        final Lyrics lyrics = _parseFixtureDocument(
          item['document'] as Map<String, dynamic>,
        );
        final List<String> expectedLangs = (item['expectedLangs'] as List)
            .map((Object? value) => value.toString())
            .toList(growable: false);
        final Map<String, dynamic> expectedTypes =
            item['expectedTypes'] as Map<String, dynamic>;

        expect(lyrics.data.keys, orderedEquals(expectedLangs));
        for (final MapEntry<String, dynamic> expected
            in expectedTypes.entries) {
          expect(
            lyrics.types[expected.key],
            LyricsType.fromValue(expected.value),
            reason: '${item['originClass']}:${expected.key}',
          );
        }

        final String jsonOutput = convert2(
          lyrics: lyrics,
          lyricsFormat: LyricsFormat.json,
        );
        final Lyrics roundTrip = _parseFixtureDocument(
          jsonDecode(jsonOutput) as Map<String, dynamic>,
        );
        expect(_lyricsShape(roundTrip), _lyricsShape(lyrics));
      });
    }

    test('word-timed 样本可导出并由各格式解析器回读', () {
      final Map<String, dynamic> item = sanitizedCases.singleWhere(
        (Map<String, dynamic> value) =>
            value['originClass'] == 'sanitized-auto-save-v1-three-langs',
      );
      final Lyrics lyrics = _parseFixtureDocument(
        item['document'] as Map<String, dynamic>,
      );
      final Map<LyricsFormat, LyricsParserFormat> formats =
          <LyricsFormat, LyricsParserFormat>{
            LyricsFormat.verbatimLrc: LyricsParserFormat.lrc,
            LyricsFormat.lineByLineLrc: LyricsParserFormat.lrc,
            LyricsFormat.enhancedLrc: LyricsParserFormat.lrc,
            LyricsFormat.srt: LyricsParserFormat.srt,
            LyricsFormat.ass: LyricsParserFormat.ass,
          };

      for (final MapEntry<LyricsFormat, LyricsParserFormat> format
          in formats.entries) {
        final String output = convert2(
          lyrics: lyrics,
          langs: const <String>['orig', 'ts', 'roma'],
          lyricsFormat: format.key,
          options: LyricsConvertOptions(generatorVersion: 'fixture'),
        );
        final ParsedLyricsPayload parsed = const LyricsParserEngine().parse(
          format: format.value,
          request: LyricsParserRequest(
            data: Uint8List.fromList(utf8.encode(output)),
          ),
        );

        expect(output, isNotEmpty, reason: format.key.value);
        expect(parsed.lyricsData['orig'], isNotEmpty, reason: format.key.value);
      }
    });

    test('LDDC_ts 作为 ts 导出，空语言不会生成伪内容', () {
      final Map<String, dynamic> item = sanitizedCases.singleWhere(
        (Map<String, dynamic> value) =>
            value['originClass'] == 'sanitized-auto-save-v1-lddc-ts-empty-lang',
      );
      final Lyrics lyrics = _parseFixtureDocument(
        item['document'] as Map<String, dynamic>,
      );
      final String output = convert2(
        lyrics: lyrics,
        langs: const <String>['ts', 'roma'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
      );

      expect(output, contains('local translation'));
      expect(output, isNot(contains('source line')));
    });

    test('零字节与损坏 JSON 明确失败', () {
      for (final Uint8List input in <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('{')),
      ]) {
        expect(
          () => const LyricsParserEngine().parse(
            format: LyricsParserFormat.jsonLrc,
            request: LyricsParserRequest(data: input),
          ),
          throwsA(isA<LddcLyricsFormatException>()),
        );
      }
    });
  });

  group('convert2 JSON 边界', () {
    final Lyrics lyrics = Lyrics(
      songInfo: const SongInfo(source: Source.local, title: '测试歌曲'),
      source: Source.local,
      types: const <String, LyricsType>{
        'orig': LyricsType.verbatim,
        'ts': LyricsType.lineByLine,
      },
      data: <String, LyricsData>{
        'orig': <LyricsLine>[
          LyricsLine(
            startMs: 1000,
            endMs: 2000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 1000, endMs: 1500, text: '你'),
              LyricsWord(startMs: 1500, endMs: 2000, text: '好'),
            ],
          ),
        ],
        'ts': <LyricsLine>[
          LyricsLine(
            startMs: 1000,
            endMs: 2000,
            words: const <LyricsWord>[
              LyricsWord(startMs: 1000, endMs: 2000, text: 'Hello'),
            ],
          ),
        ],
      },
    );

    test('JSON 作为完整结构快照，不支持按语言筛选', () {
      expect(
        () => convert2(
          lyrics: lyrics,
          langs: const <String>['ts'],
          lyricsFormat: LyricsFormat.json,
        ),
        throwsA(
          isA<LddcLyricsFormatException>().having(
            (LddcLyricsFormatException error) => error.message,
            'message',
            'JSON 格式不支持按语言筛选导出',
          ),
        ),
      );
    });

    test('JSON 作为完整结构快照，不支持时间偏移', () {
      expect(
        () => convert2(
          lyrics: lyrics,
          lyricsFormat: LyricsFormat.json,
          offsetMs: 250,
        ),
        throwsA(
          isA<LddcLyricsFormatException>().having(
            (LddcLyricsFormatException error) => error.message,
            'message',
            'JSON 格式不支持时间偏移导出',
          ),
        ),
      );
    });
  });

  group('convert2 格式能力边界', () {
    test('导出格式快照复用且不可修改', () {
      final List<LyricsFormat> formats =
          LyricsFormatCapabilities.exportableFormats;

      expect(
        identical(formats, LyricsFormatCapabilities.exportableFormats),
        isTrue,
      );
      expect(() => formats.clear(), throwsUnsupportedError);
    });

    test('QRC/KRC/YRC 即使未选择语言也明确拒绝导出', () {
      final Lyrics lyrics = _buildSingleLineLyrics(
        type: LyricsType.lineByLine,
        startMs: 0,
        endMs: 1000,
      );

      for (final LyricsFormat format in const <LyricsFormat>[
        LyricsFormat.qrc,
        LyricsFormat.krc,
        LyricsFormat.yrc,
      ]) {
        expect(
          () => convert2(lyrics: lyrics, lyricsFormat: format),
          throwsA(isA<LddcLyricsFormatException>()),
        );
      }
    });

    test('纯文本只允许导出 LRC，不会生成扩展名与内容不符的 SRT/ASS', () {
      final Lyrics lyrics = _buildSingleLineLyrics(
        type: LyricsType.plainText,
        startMs: null,
        endMs: null,
      );

      for (final LyricsFormat format in const <LyricsFormat>[
        LyricsFormat.srt,
        LyricsFormat.ass,
      ]) {
        expect(
          () => convert2(
            lyrics: lyrics,
            langs: const <String>['orig'],
            lyricsFormat: format,
          ),
          throwsA(isA<LddcLyricsFormatException>()),
        );
      }
      expect(
        convert2(
          lyrics: lyrics,
          langs: const <String>['orig'],
          lyricsFormat: LyricsFormat.verbatimLrc,
        ),
        contains('单行歌词'),
      );
    });

    test('缺少 orig 时间轴时抛格式错误而不是 StateError', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local),
        source: Source.local,
        types: const <String, LyricsType>{'ts': LyricsType.lineByLine},
        data: <String, LyricsData>{
          'ts': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 0, endMs: 1000, text: 'translation'),
              ],
            ),
          ],
        },
      );

      expect(
        () => convert2(
          lyrics: lyrics,
          langs: const <String>['ts'],
          lyricsFormat: LyricsFormat.srt,
        ),
        throwsA(isA<LddcLyricsFormatException>()),
      );
    });
  });

  group('convert2 导出投影与时间边界', () {
    test('ASS 在前序语言为空时仍按真实语言写入 Dialogue Style', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local, title: '样式测试'),
        source: Source.local,
        durationMs: 3000,
        types: const <String, LyricsType>{
          'orig': LyricsType.lineByLine,
          'roma': LyricsType.lineByLine,
          'ts': LyricsType.lineByLine,
        },
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: '你好'),
              ],
            ),
          ],
          'roma': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: ''),
              ],
            ),
          ],
          'ts': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: 'Hello'),
              ],
            ),
          ],
        },
      );

      final String output = convert2(
        lyrics: lyrics,
        langs: const <String>['roma', 'orig', 'ts'],
        lyricsFormat: LyricsFormat.ass,
        options: LyricsConvertOptions(
          languageOrder: const <String>['roma', 'orig', 'ts'],
        ),
      );

      expect(output, contains('Dialogue: 0,00:00:01.00,00:00:02.00,orig'));
      expect(output, contains('Dialogue: 0,00:00:01.00,00:00:02.00,ts'));
      expect(
        output,
        isNot(contains('Dialogue: 0,00:00:01.00,00:00:02.00,roma')),
      );
      expect(output, isNot(contains(',orig,,0,0,0,,Hello')));
    });

    test('非 JSON 导出先应用 offset，再按 langs 裁剪输出语言', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local),
        source: Source.local,
        types: const <String, LyricsType>{
          'orig': LyricsType.lineByLine,
          'LDDC_ts': LyricsType.lineByLine,
          'roma': LyricsType.lineByLine,
        },
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: '原文'),
              ],
            ),
          ],
          'LDDC_ts': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: 'Translated'),
              ],
            ),
          ],
          'roma': <LyricsLine>[
            LyricsLine(
              startMs: 1000,
              endMs: 2000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 1000, endMs: 2000, text: 'roma'),
              ],
            ),
          ],
        },
      );

      final String output = convert2(
        lyrics: lyrics,
        langs: const <String>['ts'],
        lyricsFormat: LyricsFormat.lineByLineLrc,
        offsetMs: -1500,
        options: LyricsConvertOptions(
          languageOrder: const <String>['orig', 'roma', 'ts'],
        ),
      );

      expect(output, contains('[00:00.000]Translated'));
      expect(output, isNot(contains('原文')));
      expect(output, isNot(contains('roma')));
    });

    test('时间格式化不会在边界输出非法秒数或缺位数字', () {
      expect(msToAssTimestamp(59999), '00:01:00.00');
      expect(msToAssTimestamp(-1), '00:00:00.00');
      expect(
        msToFormatTime(const Duration(hours: 1).inMilliseconds),
        '60:00.000',
      );
      expect(formatTimeSub1('00:03.000'), '00:02.999');
      expect(formatTimeSub1('01:00.00'), '00:59.99');
    });

    test('起点为 0 的无结束时间单行可回退为五秒 SRT/ASS', () {
      final Lyrics lyrics = _buildSingleLineLyrics(
        type: LyricsType.lineByLine,
        startMs: 0,
        endMs: null,
      );

      final String srt = convert2(
        lyrics: lyrics,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.srt,
      );
      final String ass = convert2(
        lyrics: lyrics,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.ass,
      );

      expect(srt, contains('00:00:00,000 --> 00:00:05,000'));
      expect(ass, contains('Dialogue: 0,00:00:00.00,00:00:05.00,orig'));
    });

    test('SRT/ASS 跳过结束时间早于开始时间的损坏行', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local, title: '时间测试'),
        source: Source.local,
        durationMs: 4000,
        types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 2000,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 2000, endMs: 1000, text: '损坏行'),
              ],
            ),
            LyricsLine(
              startMs: 2000,
              endMs: 2500,
              words: const <LyricsWord>[
                LyricsWord(startMs: 2000, endMs: 2500, text: ''),
              ],
            ),
            LyricsLine(
              startMs: 3000,
              endMs: 4000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 3000, endMs: 4000, text: '有效行'),
              ],
            ),
          ],
        },
      );

      final String srt = convert2(
        lyrics: lyrics,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.srt,
      );
      final String ass = convert2(
        lyrics: lyrics,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.ass,
      );

      expect(srt, startsWith('1\n00:00:03,000 --> 00:00:04,000'));
      expect(srt, isNot(contains('损坏行')));
      expect(srt, isNot(contains('00:00:02,000 --> 00:00:02,500')));
      expect(ass, contains('Dialogue: 0,00:00:03.00,00:00:04.00,orig'));
      expect(ass, isNot(contains('损坏行')));
    });

    test('ASS 转义标题换行和歌词控制语法', () {
      final Lyrics lyrics = Lyrics(
        songInfo: const SongInfo(source: Source.local, title: '标题\n[Events]'),
        source: Source.local,
        durationMs: 1000,
        types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(
                  startMs: 0,
                  endMs: 1000,
                  text: '前缀\\N{\\pos(0,0)}后缀\n下一行',
                ),
              ],
            ),
          ],
        },
      );

      final String ass = convert2(
        lyrics: lyrics,
        langs: const <String>['orig'],
        lyricsFormat: LyricsFormat.ass,
      );

      expect(ass, contains('Title: 标题 [Events]\n'));
      expect(ass, isNot(contains('Title: 标题\n[Events]\n')));
      expect(ass, contains(r'前缀\\N\{\\pos(0,0)\}后缀\N下一行'));

      final ParsedLyricsPayload parsed = parseAssToMultiResult(ass);
      expect(parsed.tags['title'], '标题 [Events]');
      expect(
        parsed.lyricsData['orig']!.single.text,
        '前缀\\N{\\pos(0,0)}后缀\n下一行',
      );
    });
  });
}

Lyrics _buildSingleLineLyrics({
  required LyricsType type,
  required int? startMs,
  required int? endMs,
}) {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: '测试'),
    source: Source.local,
    types: <String, LyricsType>{'orig': type},
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: startMs,
          endMs: endMs,
          words: <LyricsWord>[
            LyricsWord(startMs: startMs, endMs: endMs, text: '单行歌词'),
          ],
        ),
      ],
    },
  );
}

Lyrics _parseFixtureDocument(Map<String, dynamic> document) {
  final ParsedLyricsPayload payload = const LyricsParserEngine().parse(
    format: LyricsParserFormat.jsonLrc,
    request: LyricsParserRequest(
      data: Uint8List.fromList(utf8.encode(jsonEncode(document))),
    ),
  );
  return const LyricsAssembler().assemble(payload);
}

Map<String, Object?> _lyricsShape(Lyrics lyrics) {
  return <String, Object?>{
    for (final MapEntry<String, LyricsData> entry in lyrics.data.entries)
      entry.key: <Object?>[
        for (final LyricsLine line in entry.value)
          <Object?>[
            line.startMs,
            line.endMs,
            <Object?>[
              for (final LyricsWord word in line.words)
                <Object?>[word.startMs, word.endMs, word.text],
            ],
          ],
      ],
  };
}
