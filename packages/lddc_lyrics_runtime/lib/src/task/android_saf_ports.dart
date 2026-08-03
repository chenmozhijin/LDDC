import 'dart:typed_data';

/// Android SAF 目录授权令牌。
///
/// SAF 是 Android 的 Storage Access Framework。用户选择目录后，系统会给应用
/// 一个可持久化的 URI，而不是传统文件路径；后续扫描、创建文件都要围绕这个 URI
/// 调用平台能力。
class AndroidSafTreeToken {
  const AndroidSafTreeToken({required this.uri, this.displayName});

  final String uri;
  final String? displayName;
}

/// Android SAF 持久化目录授权信息。
class AndroidSafPersistedTree {
  const AndroidSafPersistedTree({
    required this.uri,
    this.displayName,
    required this.persistedTimeMs,
    required this.readable,
    required this.writable,
  });

  final String uri;
  final String? displayName;
  final int persistedTimeMs;
  final bool readable;
  final bool writable;
}

/// Android SAF 目录子项。
class AndroidSafTreeEntry {
  const AndroidSafTreeEntry({
    required this.uri,
    required this.displayName,
    required this.mimeType,
    required this.isDirectory,
    required this.isFile,
    this.sizeBytes,
    this.lastModifiedMs,
  });

  final String uri;
  final String displayName;
  final String? mimeType;
  final bool isDirectory;
  final bool isFile;
  final int? sizeBytes;
  final int? lastModifiedMs;
}

/// Android SAF 目录分页结果。
///
/// MethodChannel 传输大列表时会在 Kotlin、平台编解码层和 Dart 各保留
/// 一份数据。分页后每次只传输固定数量的直接子项，避免超大单目录
/// 瞬时占用过多内存。
class AndroidSafTreePage {
  AndroidSafTreePage({
    required List<AndroidSafTreeEntry> entries,
    required this.nextOffset,
  }) : entries = List<AndroidSafTreeEntry>.unmodifiable(entries);

  final List<AndroidSafTreeEntry> entries;
  final int? nextOffset;
}

/// Android SAF 文档写入结果。
class AndroidSafWriteDocumentResult {
  const AndroidSafWriteDocumentResult({
    required this.uri,
    required this.displayName,
  });

  final String uri;
  final String displayName;
}

/// Android SAF 目录能力端口。
///
/// core 层只关心“选择目录、列目录、创建文件”的语义，不直接知道 MethodChannel。
/// 真正调用 Android API 的实现放在 platform 层，测试可以用内存 fake 替换。
abstract interface class AndroidSafTreePort {
  Future<AndroidSafTreeToken> pickTree({String? initialUri});

  Future<void> persistTreePermission(String uri);

  Future<List<AndroidSafPersistedTree>> listPersistedTrees();

  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  });

  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  });
}

/// Android SAF 打开的读写文件描述符。
///
/// Android 的 `content://` URI 不能直接交给大多数 native 库读取，所以平台层会先
/// 打开 fd，再由 infra 层把 fd 交给 taglib。fd 必须在使用后关闭，避免系统句柄泄漏。
class AndroidSafOpenedFileDescriptor {
  const AndroidSafOpenedFileDescriptor({
    required this.fileDescriptor,
    this.nameHint,
  });

  final int fileDescriptor;
  final String? nameHint;
}

/// Android SAF 文件描述符能力端口。
abstract interface class AndroidSafFdPort {
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri);

  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri);

  Future<void> closeFd(int fileDescriptor);
}

/// Android SAF 文档内容读写能力端口。
///
/// 该端口只负责已经拿到 URI 的文档内容流；目录授权、枚举和创建目标文件仍由
/// `AndroidSafTreePort` 承担，避免一个平台适配器同时承担树语义和整文件 IO。
abstract interface class AndroidSafContentPort {
  Future<Uint8List> readBytes(String uri, {int? maxBytes});
}

/// Android SAF 音频元数据。
///
/// 这是 core 层需要的最小字段集合。taglib 的会话、属性表、fd 打开关闭等细节
/// 全部留在 infra/platform 实现里，避免领域用例依赖第三方库对象。
class AndroidSafAudioMetadata {
  const AndroidSafAudioMetadata({
    required this.nameHint,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.trackNumber,
    required this.cuesheet,
  });

  final String nameHint;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? trackNumber;
  final String? cuesheet;
}

/// Android SAF 音频元数据读取端口。
///
/// 实现者负责处理 fd/session 的生命周期；调用方只拿到纯数据对象，不需要也不能关闭
/// native 资源。
abstract interface class AndroidSafAudioMetadataPort {
  Future<AndroidSafAudioMetadata> readMetadata({
    required String uri,
    required String? nameHint,
  });
}
