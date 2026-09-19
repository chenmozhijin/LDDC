import 'dart:convert';
import 'dart:typed_data';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 歌词保存请求。
class LyricsSaveRequest {
  LyricsSaveRequest({
    required this.songInfo,
    required List<String> lyricLangs,
    required this.lyricsFormat,
    required this.fileNameFormat,
  }) : lyricLangs = List<String>.unmodifiable(lyricLangs);

  final SongInfo songInfo;
  final List<String> lyricLangs;
  final LyricsFormat lyricsFormat;
  final String fileNameFormat;

  /// 实际写入时使用的文件名模板，包含歌词格式扩展名。
  String get resolvedFileNameFormat => '$fileNameFormat${lyricsFormat.ext}';
}

/// 歌词写入结果。
///
/// [path] 是真实写入位置（安卓端为 SAF `content://` URI），供读写、去重与打开文件使用；
/// [displayPath] 是可直接展示给用户的文本，安卓端由授权树显示名与已知相对层级拼出，
/// 不含任何编码 URI；桌面端两者相同。
class LyricsSaveOutcome {
  const LyricsSaveOutcome({required this.path, required this.displayPath});

  final String path;
  final String displayPath;
}

/// 歌词写入端口。
///
/// 由上层只传入“写什么”，由不同实现决定“写到哪里”。
abstract class LyricsSavePersistencePort {
  Future<String> saveBytes({
    required LyricsSaveRequest request,
    required Uint8List bytes,
  });

  /// [path] 对应的可展示文本。
  ///
  /// 默认与 [path] 相同（桌面端本地路径本身就是可读文本）；安卓端由实现覆盖为
  /// “授权树显示名 / 相对目录 / 文件名”，因为此时 [path] 是用户看不懂的
  /// `content://…%2F…`，而展示层不允许再解析 URI。
  String displayPathFor(LyricsSaveRequest request, String path) => path;

  Future<LyricsSaveOutcome> saveText({
    required LyricsSaveRequest request,
    required String text,
  }) async {
    final String path = await saveBytes(
      request: request,
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    return LyricsSaveOutcome(
      path: path,
      displayPath: displayPathFor(request, path),
    );
  }
}

/// 可选的“目标是否已存在”查询端口。
///
/// 仅在上层需要复用统一保存策略做“跳过已存在歌词”判定时使用。
abstract interface class LyricsSaveExistencePort {
  Future<bool> exists({required LyricsSaveRequest request});
}
