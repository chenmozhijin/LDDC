import 'local_match_usecase.dart';

/// Android SAF 歌词保存目标：写到哪棵树 + 树内哪一级目录。
///
/// 三种保存模式的差异全部收敛为这两个字段，因此用纯函数表达，便于单测穷举组合。
class AndroidSafSaveTarget {
  const AndroidSafSaveTarget({
    required this.treeUri,
    required this.directorySegments,
    required this.treeLabel,
  });

  /// 目标授权树 URI。
  final String treeUri;

  /// 相对授权树的目录层级，空列表表示树根。
  final List<String> directorySegments;

  /// 目标树显示名，仅用于预览文案。
  final String treeLabel;

  /// 目标目录的展示标签，例如 `根目录 / Album / Disc 1`。
  String get directoryLabel => <String>[
    if (treeLabel.trim().isNotEmpty) treeLabel.trim(),
    ...directorySegments,
  ].join(' / ');
}

/// 保存目标推导失败原因。
///
/// 预览与保存都必须据此给出可解释的结果，不能静默回退到树根。
enum AndroidSafSaveTargetFailure {
  /// 歌曲 URI 不是可解析的 SAF 文档（例如本地文件路径）。
  unknownSongPath,

  /// 歌曲不在所选授权树内，无法推导相对目录。
  songOutsideTree,

  /// mirror / specify 尚未选择保存根树。
  missingSaveTree,
}

/// 推导结果：`target` 与 `failure` 互斥。
typedef AndroidSafSaveTargetResult = ({
  AndroidSafSaveTarget? target,
  AndroidSafSaveTargetFailure? failure,
});

/// 从 SAF 树形 URI 中取出文档 id。
///
/// `content://<authority>/tree/<treeDocId>/document/<docId>` 取第 4 段，
/// 与平台 `DocumentsContract.getDocumentId()` 的 `paths.get(3)` 分支一致；
/// 裸树 URI 取第 2 段（树根文档 id）。`Uri.pathSegments` 已解码，
/// 所以含 `/` 的文档 id（如 `primary:Music/Album/a.mp3`）仍是完整一段。
String? safDocumentIdOf(String? uri) {
  final String text = uri?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final List<String> segments = Uri.parse(text).pathSegments;
  if (segments.length >= 4 &&
      segments[0] == 'tree' &&
      segments[2] == 'document') {
    return segments[3].isEmpty ? null : segments[3];
  }
  if (segments.length >= 2 && segments[0] == 'tree') {
    return segments[1].isEmpty ? null : segments[1];
  }
  return null;
}

/// 由授权树 URI + 树内文档 id 构造文档 URI。
///
/// 用于把"树内相对目录"换算成可枚举的目录 URI（存在性查询用），避免为此新增一次
/// 原生往返。编码方式与平台 `buildDocumentUriUsingTree` 一致（每段独立转义）。
String? safDocumentUri({required String treeUri, required String documentId}) {
  final Uri tree = Uri.tryParse(treeUri) ?? Uri();
  final String? treeDocumentId = safDocumentIdOf(treeUri);
  if (tree.scheme != 'content' ||
      tree.host.isEmpty ||
      treeDocumentId == null ||
      documentId.trim().isEmpty) {
    return null;
  }
  return Uri(
    scheme: tree.scheme,
    host: tree.host,
    pathSegments: <String>['tree', treeDocumentId, 'document', documentId],
  ).toString();
}

/// 把"树内相对目录层级"换算成目录 URI；空层级返回树根 URI。
String? safDirectoryUri({
  required String treeUri,
  required List<String> directorySegments,
}) {
  final String? treeDocumentId = safDocumentIdOf(treeUri);
  if (treeDocumentId == null) {
    return null;
  }
  if (directorySegments.isEmpty) {
    return treeUri;
  }
  return safDocumentUri(
    treeUri: treeUri,
    documentId: <String>[treeDocumentId, ...directorySegments].join('/'),
  );
}

/// 推导歌词写入目标。
///
/// - `song`：写到歌曲所在目录（歌曲树 + 歌曲相对树根的目录层级）
/// - `mirror`：写到保存根树 + 歌曲相对歌曲树的目录层级（保存根就是歌曲树时与 song 等价）
/// - `specify`：写到保存根树的根目录（扁平）
AndroidSafSaveTargetResult resolveAndroidSafSaveTarget({
  required LocalMatchSaveMode saveMode,
  required String? songPath,
  required String songTreeUri,
  required String? saveTreeUri,
  String? songTreeLabel,
  String? saveTreeLabel,
}) {
  final List<String>? songSegments = _songRelativeDirectorySegments(
    songPath: songPath,
    songTreeUri: songTreeUri,
  );
  switch (saveMode) {
    case LocalMatchSaveMode.song:
      if (songSegments == null) {
        return (
          target: null,
          failure: _songTreeFailure(
            songPath: songPath,
            songTreeUri: songTreeUri,
          ),
        );
      }
      return (
        target: AndroidSafSaveTarget(
          treeUri: songTreeUri,
          directorySegments: songSegments,
          treeLabel: songTreeLabel ?? '',
        ),
        failure: null,
      );
    case LocalMatchSaveMode.mirror:
      final String? saveTree = _nonBlank(saveTreeUri);
      if (saveTree == null) {
        return (
          target: null,
          failure: AndroidSafSaveTargetFailure.missingSaveTree,
        );
      }
      if (songSegments == null) {
        return (
          target: null,
          failure: _songTreeFailure(
            songPath: songPath,
            songTreeUri: songTreeUri,
          ),
        );
      }
      return (
        target: AndroidSafSaveTarget(
          treeUri: saveTree,
          directorySegments: songSegments,
          treeLabel: saveTreeLabel ?? '',
        ),
        failure: null,
      );
    case LocalMatchSaveMode.specify:
      final String? saveTree = _nonBlank(saveTreeUri);
      if (saveTree == null) {
        return (
          target: null,
          failure: AndroidSafSaveTargetFailure.missingSaveTree,
        );
      }
      return (
        target: AndroidSafSaveTarget(
          treeUri: saveTree,
          directorySegments: const <String>[],
          treeLabel: saveTreeLabel ?? '',
        ),
        failure: null,
      );
  }
}

AndroidSafSaveTargetFailure _songTreeFailure({
  required String? songPath,
  required String songTreeUri,
}) {
  // 歌曲本身可解析但不在该树内 → 树外；否则是路径形态不认识（例如本地路径）。
  if (safDocumentIdOf(songPath) == null) {
    return AndroidSafSaveTargetFailure.unknownSongPath;
  }
  if (safDocumentIdOf(songTreeUri) == null) {
    return AndroidSafSaveTargetFailure.unknownSongPath;
  }
  return AndroidSafSaveTargetFailure.songOutsideTree;
}

List<String>? _songRelativeDirectorySegments({
  required String? songPath,
  required String songTreeUri,
}) {
  final String? songId = safDocumentIdOf(songPath);
  final String? treeId = safDocumentIdOf(songTreeUri);
  if (songId == null || treeId == null) {
    return null;
  }
  if (songId == treeId) {
    // 文档 id 与树根相同：只可能出现在异常 provider 返回上，视为不可推导。
    return null;
  }
  final int lastSlash = songId.lastIndexOf('/');
  if (lastSlash < 0) {
    // 文件直接位于树根之下。
    return const <String>[];
  }
  final String songDirectory = songId.substring(0, lastSlash);
  if (songDirectory == treeId) {
    return const <String>[];
  }
  final String prefix = '$treeId/';
  if (!songDirectory.startsWith(prefix)) {
    return null;
  }
  return songDirectory
      .substring(prefix.length)
      .split('/')
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
}

String? _nonBlank(String? value) {
  final String text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
