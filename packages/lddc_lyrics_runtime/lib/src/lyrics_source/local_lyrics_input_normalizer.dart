import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../files/file_ports.dart' show normalizePickedLocalFilePath;
import 'lyrics_source_provider.dart';

typedef LocalLyricsFileReader = Future<Uint8List> Function(String path);

/// 本地歌词入口统一允许选择的扩展名。
///
/// Parser dispatcher 负责按扩展名或文本回退链路决定真正的解析格式；这里仅声明
/// “本地输入入口可以接收哪些歌词文件”。打开歌词页、批量转换和本地 provider
/// 都应复用这份能力，避免某个入口能解析、另一个入口却不能选择。
const List<String> localLyricsInputSupportedExtensions = <String>[
  'qrc',
  'krc',
  'yrc',
  'json',
  'lrc',
  'ass',
  'ssa',
  'srt',
  'txt',
];

/// 本地歌词输入规范化结果。
class ResolvedLocalLyricsInput {
  ResolvedLocalLyricsInput({
    required this.path,
    required Uint8List data,
    required this.info,
  }) : data = Uint8List.fromList(data);

  final String? path;
  final Uint8List data;
  final LyricInfo? info;
}

/// 本地歌词字节入口的共享规范化器。
///
/// 打开歌词页、本地歌词 provider、批量转换都会遇到同一类输入：路径可能为空、
/// 数据可能来自文件或内存，QRC/KRC 文件还是加密字节。把这部分收在一个类里，
/// 可以避免不同入口各自判断 magic header 后出现行为漂移。
class LocalLyricsInputNormalizer {
  LocalLyricsInputNormalizer({
    LyricsDecryptor? decryptor,
    LocalLyricsFileReader? fileReader,
  }) : _decryptor = decryptor ?? LyricsDecryptor(),
       _fileReader = fileReader ?? _unsupportedFileReader;

  final LyricsDecryptor _decryptor;
  final LocalLyricsFileReader _fileReader;

  Future<ResolvedLocalLyricsInput> resolve(LocalLyricsRequest request) async {
    final LyricInfo? info = request.info;
    final String? normalizedPath = normalizePath(request.path ?? info?.path);

    Uint8List? data = request.data;
    data ??= info?.data;

    if (normalizedPath == null && data == null) {
      throw const LddcApiParamsException('没有任何文件路径和数据');
    }

    data ??= await _fileReader(normalizedPath!);

    if (data.isEmpty) {
      throw const LddcApiParamsException('没有任何文件数据');
    }

    return ResolvedLocalLyricsInput(
      path: normalizedPath,
      data: data,
      info: info,
    );
  }

  ParsedLyricsPayload parsePayload({
    required Uint8List data,
    required String? path,
    required LyricsParserPort parser,
    required LyricsParserDispatcher dispatcher,
  }) {
    if (isQrc(data)) {
      return parseDecryptedQrc(data: data, path: path, parser: parser);
    }
    if (isKrc(data)) {
      final String decrypted = _decryptor.decryptKrc(data);
      return parser.parse(
        format: LyricsParserFormat.krc,
        request: LyricsParserRequest(
          data: Uint8List.fromList(utf8.encode(decrypted)),
          path: path,
        ),
      );
    }
    return dispatcher.parse(LyricsParserRequest(data: data, path: path));
  }

  ParsedLyricsPayload parseDecryptedQrc({
    required Uint8List data,
    required String? path,
    required LyricsParserPort parser,
  }) {
    final String decrypted = _decryptor.decryptQrc(
      data,
      type: QrcDecryptType.local,
    );
    return parser.parse(
      format: LyricsParserFormat.qrc,
      request: LyricsParserRequest(
        data: Uint8List.fromList(utf8.encode(decrypted)),
        path: path,
      ),
    );
  }

  String decodeDisplayText({required Uint8List data, String? path}) {
    final String normalizedPath = (path ?? '').trim().toLowerCase();
    if (isQrc(data)) {
      return _decryptor.decryptQrc(data, type: QrcDecryptType.local);
    }
    if (isKrc(data)) {
      return _decryptor.decryptKrc(data);
    }
    if (normalizedPath.endsWith('.lrc')) {
      return decodeUnknownEncoding(
        data,
        signWords: const <String>['[', ']', ':'],
      );
    }
    // 加密 QRC/KRC 已在上方通过 magic header 解密；这里继续接收同扩展名的
    // 明文内容。parser dispatcher 本来就支持这两种明文语法，若展示阶段先按
    // 扩展名拒绝，打开歌词页会在真正解析前失败，形成“批量转换能读、页面不能读”
    // 的入口断层。使用通用编码探测即可，不重复实现 QRC/KRC 解析器。
    if (normalizedPath.endsWith('.qrc') ||
        normalizedPath.endsWith('.krc') ||
        normalizedPath.endsWith('.ass') ||
        normalizedPath.endsWith('.ssa') ||
        normalizedPath.endsWith('.srt') ||
        normalizedPath.endsWith('.yrc') ||
        normalizedPath.endsWith('.json') ||
        normalizedPath.endsWith('.txt')) {
      return decodeUnknownEncoding(data);
    }
    throw UnsupportedError('不支持的文件格式');
  }

  bool isQrc(List<int> data) => hasBytePrefix(data, qrcMagicHeader);

  bool isKrc(List<int> data) => hasBytePrefix(data, krcMagicHeader);

  static String? normalizePath(String? rawPath) {
    return normalizePickedLocalFilePath(rawPath);
  }

  static Future<Uint8List> _unsupportedFileReader(String path) {
    throw const LddcApiParamsException('当前入口没有提供本地文件读取器');
  }
}
