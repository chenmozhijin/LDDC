import 'dart:convert';
import 'dart:typed_data';

import 'lyrics_parser_dispatcher.dart';
import 'lyrics_parser_engine.dart';
import 'lyrics_parser_port.dart';

/// 面向包消费者的歌词解析入口。
///
/// 该门面只冻结输入并委托现有 dispatcher/engine，不保留第二套格式探测或解析逻辑。
final class LyricsParser {
  LyricsParser({LyricsParserPort parser = const LyricsParserEngine()})
    : _dispatcher = LyricsParserDispatcher(parser);

  final LyricsParserDispatcher _dispatcher;

  ParsedLyricsPayload parseBytes(Uint8List data, {String? path}) {
    return _dispatcher.parse(LyricsParserRequest(data: data, path: path));
  }

  ParsedLyricsPayload parseText(String text, {String? path}) {
    return parseBytes(Uint8List.fromList(utf8.encode(text)), path: path);
  }
}
