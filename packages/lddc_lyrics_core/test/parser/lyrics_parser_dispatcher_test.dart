import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('LyricsParserDispatcher 分派规则', () {
    test('命中 QRC 魔数时优先路由到 qrc 解析器', () {
      final _FakeLyricsParser parser = _FakeLyricsParser(
        handlers: <LyricsParserFormat, ParsedLyricsPayload Function()>{
          LyricsParserFormat.qrc: () => _buildSuccessResult('QRC'),
        },
      );
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(parser);
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList(<int>[...qrcMagicHeader, 0x00]),
        path: 'demo.lrc',
      );

      dispatcher.parse(request);
      expect(parser.calledFormats, <LyricsParserFormat>[
        LyricsParserFormat.qrc,
      ]);
    });

    test('命中 KRC 魔数时优先路由到 krc 解析器', () {
      final _FakeLyricsParser parser = _FakeLyricsParser(
        handlers: <LyricsParserFormat, ParsedLyricsPayload Function()>{
          LyricsParserFormat.krc: () => _buildSuccessResult('KRC'),
        },
      );
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(parser);
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList(<int>[...krcMagicHeader, 0x01]),
        path: 'demo.srt',
      );

      dispatcher.parse(request);
      expect(parser.calledFormats, <LyricsParserFormat>[
        LyricsParserFormat.krc,
      ]);
    });

    test('无扩展名时走 LRC/ASS/SRT 回退链路', () {
      final _FakeLyricsParser parser = _FakeLyricsParser(
        handlers: <LyricsParserFormat, ParsedLyricsPayload Function()>{
          LyricsParserFormat.lrc: () =>
              throw const LddcLyricsFormatException('不是 LRC'),
          LyricsParserFormat.ass: () =>
              throw const LddcLyricsFormatException('不是 ASS'),
          LyricsParserFormat.srt: () => _buildSuccessResult('SRT'),
        },
      );
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(parser);
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList('not-json'.codeUnits),
      );

      dispatcher.parse(request);
      expect(parser.calledFormats, <LyricsParserFormat>[
        LyricsParserFormat.lrc,
        LyricsParserFormat.ass,
        LyricsParserFormat.srt,
      ]);
    });
  });

  group('LyricsParserDispatcher 解析回退', () {
    test('前序候选格式不匹配时继续尝试后续候选', () {
      final _FakeLyricsParser parser = _FakeLyricsParser(
        handlers: <LyricsParserFormat, ParsedLyricsPayload Function()>{
          LyricsParserFormat.jsonLrc: () =>
              throw const LddcLyricsFormatException('json 结构不合法'),
          LyricsParserFormat.lrc: () => _buildSuccessResult('LRC'),
        },
      );
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(parser);
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList('{"version":1}'.codeUnits),
        path: 'demo.lrc',
      );

      final ParsedLyricsPayload result = dispatcher.parse(request);
      expect(parser.calledFormats, <LyricsParserFormat>[
        LyricsParserFormat.jsonLrc,
        LyricsParserFormat.lrc,
      ]);
      expect(result.lyricsData['orig']!.single.text, 'LRC');
    });

    test('未知文本扩展名且非 JSON 数据时走统一文本回退链路', () {
      final _FakeLyricsParser parser = _FakeLyricsParser(
        handlers: <LyricsParserFormat, ParsedLyricsPayload Function()>{
          LyricsParserFormat.lrc: () => _buildSuccessResult('LRC'),
        },
      );
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(parser);
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList('plain text'.codeUnits),
        path: 'lyrics.txt',
      );

      dispatcher.parse(request);
      expect(parser.calledFormats, <LyricsParserFormat>[
        LyricsParserFormat.lrc,
      ]);
    });

    test('候选格式未注册实现时，错误信息包含候选链路', () {
      final LyricsParserDispatcher dispatcher = LyricsParserDispatcher(
        _FakeLyricsParser(),
      );
      final LyricsParserRequest request = LyricsParserRequest(
        data: Uint8List.fromList('hello'.codeUnits),
      );

      expect(
        () => dispatcher.parse(request),
        throwsA(
          isA<LddcLyricsFormatException>().having(
            (LddcLyricsFormatException e) => e.message,
            'message',
            allOf(contains('候选=lrc -> ass -> srt'), contains('未注册实现')),
          ),
        ),
      );
    });
  });
}

ParsedLyricsPayload _buildSuccessResult(String text) {
  return ParsedLyricsPayload(
    lyricsData: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: <LyricsWord>[LyricsWord(startMs: 0, endMs: 1000, text: text)],
        ),
      ],
    },
  );
}

class _FakeLyricsParser implements LyricsParserPort {
  _FakeLyricsParser({
    Map<LyricsParserFormat, ParsedLyricsPayload Function()> handlers =
        const <LyricsParserFormat, ParsedLyricsPayload Function()>{},
  }) : _handlers = Map<LyricsParserFormat, ParsedLyricsPayload Function()>.from(
         handlers,
       );

  final Map<LyricsParserFormat, ParsedLyricsPayload Function()> _handlers;
  final List<LyricsParserFormat> calledFormats = <LyricsParserFormat>[];

  @override
  Set<LyricsParserFormat> get supportedFormats => _handlers.keys.toSet();

  @override
  ParsedLyricsPayload parse({
    required LyricsParserFormat format,
    required LyricsParserRequest request,
  }) {
    calledFormats.add(format);
    final ParsedLyricsPayload Function()? handler = _handlers[format];
    if (handler == null) {
      throw const LddcLyricsFormatException('未注册实现');
    }
    return handler();
  }
}
