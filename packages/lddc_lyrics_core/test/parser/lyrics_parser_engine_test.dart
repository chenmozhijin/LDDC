import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('ParserUtils', () {
    test('judgeLyricsType 可区分 plain/line/verbatim', () {
      final LyricsData plain = <LyricsLine>[
        LyricsLine(
          startMs: null,
          endMs: null,
          words: <LyricsWord>[
            LyricsWord(startMs: null, endMs: null, text: '纯文本'),
          ],
        ),
      ];
      final LyricsData lineByLine = <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2000,
          words: <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 2000, text: '逐行'),
          ],
        ),
      ];
      final LyricsData verbatim = <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2000,
          words: <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 1500, text: '逐'),
            LyricsWord(startMs: 1500, endMs: 2000, text: '字'),
          ],
        ),
      ];

      expect(judgeLyricsType(plain), LyricsType.plainText);
      expect(judgeLyricsType(lineByLine), LyricsType.lineByLine);
      expect(judgeLyricsType(verbatim), LyricsType.verbatim);
    });
  });

  group('LyricsParserEngine', () {
    const LyricsParserEngine engine = LyricsParserEngine();

    test('支持格式集合包含 parser-03 扩展格式', () {
      final Set<LyricsParserFormat> firstSnapshot = engine.supportedFormats;
      expect(
        firstSnapshot,
        containsAll(<LyricsParserFormat>[
          LyricsParserFormat.lrc,
          LyricsParserFormat.qrc,
          LyricsParserFormat.krc,
          LyricsParserFormat.yrc,
          LyricsParserFormat.jsonLrc,
          LyricsParserFormat.ass,
          LyricsParserFormat.srt,
        ]),
      );
      expect(identical(firstSnapshot, engine.supportedFormats), isTrue);
      expect(() => firstSnapshot.clear(), throwsUnsupportedError);
    });

    test('lrc 解析：可提取标签与逐字时间', () {
      const String lrc = '[ar:测试]\n[00:01.34]你[00:01.50]好[00:02.00]';
      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.lrc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(lrc)),
        ),
      );

      expect(result.tags['ar'], '测试');
      final LyricsData orig = result.lyricsData['orig']!;
      expect(orig.length, 1);
      expect(orig.first.startMs, 1340);
      expect(orig.first.endMs, 2000);
      expect(orig.first.words.length, 2);
      expect(orig.first.words.first.text, '你');
      expect(orig.first.words.last.text, '好');
    });

    test('LyricsParserRequest 只复制一次并以只读视图保护输入', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode('[00:01.00]原始'));
      final LyricsParserRequest request = LyricsParserRequest(data: bytes);
      bytes.fillRange(0, bytes.length, 0x20);
      final Uint8List exposed = request.data;
      expect(identical(exposed, request.data), isTrue);
      expect(
        () => exposed.fillRange(0, exposed.length, 0x20),
        throwsUnsupportedError,
      );

      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.lrc,
        request: request,
      );

      expect(result.lyricsData['orig']!.single.text, '原始');
    });

    test('lrc 解析：NE多时间戳行可展开', () {
      const String lrc = '[00:01.00][00:02.00]同一句';
      final ParsedLyricsPayload result = parseLrcToMultiResult(
        lrc,
        source: Source.ne,
      );
      final LyricsData orig = result.lyricsData['orig']!;
      expect(orig.length, 2);
      expect(orig[0].startMs, 1000);
      expect(orig[1].startMs, 2000);
    });

    test('lrc 单语言合并按第一语言时间轴插入同时间戳内容', () {
      const String lrc = '''
[00:01.00]原文一
[00:02.00]原文二
[00:01.00]翻译一
[00:02.00]翻译二
''';

      final ({Map<String, String> tags, LyricsData lyricsData}) parsed =
          parseLrcToData(lrc);

      expect(parsed.lyricsData.map((LyricsLine line) => line.text), <String>[
        '原文一',
        '翻译一',
        '原文二',
        '翻译二',
      ]);
    });

    test('qrc 解析：可解析行与词时间', () {
      const String qrc =
          '<Lyric_1 LyricType="1" LyricContent="[ar:测试]\n[1000,500]你(1000,200)好(1200,300)\n"/>';
      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.qrc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(qrc)),
        ),
      );

      expect(result.tags['ar'], '测试');
      final LyricsData orig = result.lyricsData['orig']!;
      expect(orig.single.startMs, 1000);
      expect(orig.single.endMs, 1500);
      expect(orig.single.words.map((LyricsWord w) => w.text).toList(), <String>[
        '你',
        '好',
      ]);
    });

    test('krc 解析：可解析语言扩展（roma/ts）', () {
      final String languageTag = base64Encode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'content': <Object?>[
              <String, Object?>{
                'type': 0,
                'lyricContent': <Object?>[
                  <Object?>['ni', 'hao'],
                ],
              },
              <String, Object?>{
                'type': 1,
                'lyricContent': <Object?>[
                  <Object?>['你好'],
                ],
              },
            ],
          }),
        ),
      );
      final String krc =
          '[language:$languageTag]\n[1000,500]<0,200,0>你<200,300,0>好';

      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.krc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(krc)),
        ),
      );

      expect(
        result.lyricsData.keys,
        containsAll(<String>['orig', 'roma', 'ts']),
      );
      expect(
        result.lyricsData['orig']!.single.words.map((LyricsWord w) => w.text),
        <String>['你', '好'],
      );
      expect(
        result.lyricsData['roma']!.single.words.map((LyricsWord w) => w.text),
        <String>['ni', 'hao'],
      );
      expect(result.lyricsData['ts']!.single.words.single.text, '你好');
    });

    test('krc 解析：损坏 language 标签统一抛歌词格式异常', () {
      final String invalidStructure = base64Encode(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 0, 'lyricContent': 'not-a-list'},
            ],
          }),
        ),
      );

      for (final String languageTag in <String>[
        'not-base64',
        invalidStructure,
      ]) {
        expect(
          () => parseKrcToMultiResult(
            '[language:$languageTag]\n[1000,500]<0,500,0>歌词',
          ),
          throwsA(isA<LddcLyricsFormatException>()),
        );
      }
    });

    test('yrc 解析：可解析逐字结构', () {
      const String yrc = '[1000,500](1000,200,0)你(1200,300,0)好';
      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.yrc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(yrc)),
        ),
      );

      expect(result.lyricsData['orig']!.single.words.length, 2);
      expect(result.lyricsData['orig']!.single.words.first.startMs, 1000);
      expect(result.lyricsData['orig']!.single.words.last.endMs, 1500);
    });

    test('json_lrc 解析：可读取 tags + lyrics', () {
      final String jsonText = jsonEncode(<String, Object?>{
        'version': 1,
        'info': <String, Object?>{
          'source': 'QM',
          'title': 'title',
          'artist': <String>['artist'],
          'duration': 1234,
          'id': 1,
        },
        'tags': <String, String>{'ar': 'artist'},
        'lyrics': <String, Object?>{
          'orig': <Object?>[
            <Object?>[
              0,
              1000,
              <Object?>[
                <Object?>[0, 1000, 'hello'],
              ],
            ],
          ],
        },
      });

      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.jsonLrc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(jsonText)),
        ),
      );

      expect(result.tags['ar'], 'artist');
      expect(result.lyricsData['orig']!.single.words.single.text, 'hello');
      expect(result.embeddedInfo, isNotNull);
      expect(result.embeddedInfo!.songInfo, isNotNull);
      expect(result.embeddedInfo!.songInfo!.source, Source.qm);
      expect(result.embeddedInfo!.id, '1');
      expect(result.embeddedInfo!.durationMs, 1234);
    });

    test('json_lrc 自家导出再解析时保留 songinfo 与歌词级 metadata', () {
      final Lyrics lyrics = Lyrics(
        songInfo: SongInfo(
          source: Source.qm,
          title: '标题',
          artist: SongArtist(<String>['歌手']),
          album: '专辑',
          durationMs: 4321,
          id: 'song-info-id',
          path: r'D:\music\a.flac',
          language: Language.chinese,
        ),
        source: Source.qm,
        id: 'lyrics-id',
        accessKey: 'access',
        durationMs: 4321,
        creator: 'creator',
        score: 99,
        tags: const <String, String>{'ti': '标题'},
        types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 0, endMs: 1000, text: '歌词'),
              ],
            ),
          ],
        },
      );

      final String jsonText = convert2(
        lyrics: lyrics,
        lyricsFormat: LyricsFormat.json,
      );
      final ParsedLyricsPayload payload = engine.parse(
        format: LyricsParserFormat.jsonLrc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(jsonText)),
        ),
      );
      final Lyrics assembled = const LyricsAssembler().assemble(payload);

      expect(assembled.songInfo.title, '标题');
      expect(assembled.songInfo.artist!.join(), '歌手');
      expect(assembled.songInfo.album, '专辑');
      expect(assembled.songInfo.path, r'D:\music\a.flac');
      expect(assembled.songInfo.language, Language.chinese);
      expect(assembled.id, 'lyrics-id');
      expect(assembled.accessKey, 'access');
      expect(assembled.durationMs, 4321);
      expect(assembled.creator, 'creator');
      expect(assembled.score, 99);
      expect(assembled.data['orig']!.single.text, '歌词');
    });

    test('json_lrc 解析：非法 source 抛出格式错误', () {
      final Map<String, Object?> payload = <String, Object?>{
        'version': 1,
        'info': <String, Object?>{'source': 'UNKNOWN'},
        'tags': <String, Object?>{},
        'lyrics': <String, Object?>{},
      };

      expect(
        () => parseJsonLrcToMultiResult(payload),
        throwsA(
          isA<LddcLyricsFormatException>().having(
            (LddcLyricsFormatException e) => e.message,
            'message',
            contains('不正确的值'),
          ),
        ),
      );
    });

    test('srt 解析：支持三语行拆分并跳过非法时间块', () {
      const String srt = '''
1
00:00:01,000 --> 00:00:03,000
ni hao
你好
Hello

2
bad timestamp
ignored

3
00:00:04.000 --> 00:00:05.000
单语行
''';
      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.srt,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(srt)),
        ),
      );

      expect(
        result.lyricsData.keys,
        containsAll(<String>['orig', 'roma', 'ts']),
      );
      expect(result.lyricsData['roma']!.single.words.single.text, 'ni hao');
      expect(result.lyricsData['orig']![0].words.single.text, '你好');
      expect(result.lyricsData['orig']![1].words.single.text, '单语行');
      expect(result.lyricsData['ts']!.single.words.single.text, 'Hello');
    });

    test('ass 解析：支持 LDDC 样式多语映射与 karaoke 分词', () {
      const String ass = '''
[Script Info]
Title: Demo Title
Script generated by LDDC

[Events]
Format: Layer, Start, End, Style, Text
Dialogue: 0,0:00:01.00,0:00:03.00,orig,{\\k100}你{\\k100}好
Dialogue: 0,0:00:01.00,0:00:03.00,ts,Hello
''';
      final ParsedLyricsPayload result = engine.parse(
        format: LyricsParserFormat.ass,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(ass)),
        ),
      );

      expect(result.tags['title'], 'Demo Title');
      expect(result.lyricsData.keys, containsAll(<String>['orig', 'ts']));
      final LyricsLine orig = result.lyricsData['orig']!.single;
      expect(orig.words.length, 2);
      expect(orig.words[0].text, '你');
      expect(orig.words[0].startMs, 1000);
      expect(orig.words[0].endMs, 2000);
      expect(orig.words[1].text, '好');
      expect(orig.words[1].startMs, 2000);
      expect(orig.words[1].endMs, 3000);
      final LyricsLine ts = result.lyricsData['ts']!.single;
      expect(ts.words.single.text, 'Hello');
      expect(ts.words.single.startMs, 1000);
      expect(ts.words.single.endMs, 3000);
    });

    test('ass 解析：缺字段和反向时间行不会造成越界或非法结果', () {
      const String ass = '''
[Events]
Format: Start, End, Text, Style
Dialogue: 0:00:01.00,0:00:02.00,missing-style
Dialogue: 0:00:03.00,0:00:02.00,reversed,orig
''';

      final ParsedLyricsPayload result = parseAssToMultiResult(ass);

      expect(result.lyricsData, isEmpty);
    });
  });
}
