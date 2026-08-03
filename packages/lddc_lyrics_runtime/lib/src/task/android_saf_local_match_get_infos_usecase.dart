import 'dart:collection';

import 'package:path/path.dart' as p;

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../audio_tag/audio_file_extensions.dart';
import '../parser/cue_parser.dart';
import 'android_saf_ports.dart';
import 'local_match_usecase.dart';

/// Android SAF 扫描阶段。
///
/// 扫描分两遍进行：第一遍只处理外部 CUE 并统计音频，第二遍才
/// 逐个解析音频。这样可以保留“CUE 优先且覆盖的音频不重复入队”
/// 的业务语义，同时不需要把整棵目录的文件列表留在内存中。
enum AndroidSafScanStage { cueParsing, audioParsing }

/// Android SAF 待扫描目录页。
class AndroidSafQueuedDirectory {
  const AndroidSafQueuedDirectory({
    required this.uri,
    required this.relativeDirectoryPath,
    this.offset = 0,
  });

  final String uri;
  final String relativeDirectoryPath;
  final int offset;

  AndroidSafQueuedDirectory nextPage(int nextOffset) {
    return AndroidSafQueuedDirectory(
      uri: uri,
      relativeDirectoryPath: relativeDirectoryPath,
      offset: nextOffset,
    );
  }
}

/// Android SAF 扫描出的待处理文件。
class AndroidSafDiscoveredFile {
  const AndroidSafDiscoveredFile({
    required this.uri,
    required this.relativePath,
    required this.displayName,
  });

  final String uri;
  final String relativePath;
  final String displayName;
}

/// Android SAF 扫描恢复检查点。
///
/// 检查点只保留尚未处理的目录页和当前页文件。已经输出的
/// `LocalMatchSongEntry` 由上层批处理检查点保管，不会在扫描检查点内
/// 再复制一份。已访问 URI 集合用于防止目录环和重复文档。
class AndroidSafScanCheckpoint {
  AndroidSafScanCheckpoint({
    required this.rootTreeUri,
    required this.stage,
    required List<AndroidSafQueuedDirectory> pendingDirectories,
    required List<AndroidSafDiscoveredFile> pendingFiles,
    required List<String> visitedDirectoryUris,
    required List<String> seenFileUris,
    required List<String> excludedAudioUris,
    required this.discoveredCueFileCount,
    required this.discoveredAudioFileCount,
    required this.processedCueFileCount,
    required this.processedAudioFileCount,
  }) : pendingDirectories = List<AndroidSafQueuedDirectory>.unmodifiable(
         pendingDirectories,
       ),
       pendingFiles = List<AndroidSafDiscoveredFile>.unmodifiable(pendingFiles),
       visitedDirectoryUris = List<String>.unmodifiable(visitedDirectoryUris),
       seenFileUris = List<String>.unmodifiable(seenFileUris),
       excludedAudioUris = List<String>.unmodifiable(excludedAudioUris);

  final String rootTreeUri;
  final AndroidSafScanStage stage;
  final List<AndroidSafQueuedDirectory> pendingDirectories;
  final List<AndroidSafDiscoveredFile> pendingFiles;
  final List<String> visitedDirectoryUris;
  final List<String> seenFileUris;
  final List<String> excludedAudioUris;
  final int discoveredCueFileCount;
  final int discoveredAudioFileCount;
  final int processedCueFileCount;
  final int processedAudioFileCount;
}

/// Android SAF 的 `GetInfos` 结果。
class AndroidSafLocalMatchGetInfosResult {
  AndroidSafLocalMatchGetInfosResult({
    required List<LocalMatchSongEntry> entries,
    required List<String> errors,
    required this.cancelled,
    required this.checkpoint,
  }) : entries = List<LocalMatchSongEntry>.unmodifiable(entries),
       errors = List<String>.unmodifiable(errors);

  final List<LocalMatchSongEntry> entries;
  final List<String> errors;
  final bool cancelled;
  final AndroidSafScanCheckpoint? checkpoint;
}

/// Android SAF 本地匹配阶段一（目录扫描 + CUE/音频解析）。
///
/// 实现采用“分页目录 + 两遍遍历 + 条目批次回调”：
/// 1. 单次 MethodChannel 最多返回 128 个直接子项。
/// 2. 当前页的 CUE/音频处理完后才请求下一页。
/// 3. 生成的歌曲条目最多以 64 条为一批交给上层。
/// 4. 取消时检查点保留当前未处理部分，恢复后不重复也不跳过。
class AndroidSafLocalMatchGetInfosUseCase {
  AndroidSafLocalMatchGetInfosUseCase({
    required this._treePort,
    required this._contentPort,
    required this._audioMetadataPort,
  });

  final AndroidSafTreePort _treePort;
  final AndroidSafContentPort _contentPort;
  final AndroidSafAudioMetadataPort _audioMetadataPort;

  static const int _maxCueBytes = 1024 * 1024;
  static const int _directoryPageSize = 128;
  static const int _entryBatchSize = 64;

  Future<AndroidSafLocalMatchGetInfosResult> run({
    required AndroidSafTreeToken rootTree,
    AndroidSafScanCheckpoint? checkpoint,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    final LocalMatchCancellationToken token =
        cancellationToken ?? LocalMatchCancellationToken();
    final _AndroidSafScanMutableState state = _createInitialState(
      rootTree: rootTree,
      checkpoint: checkpoint,
    );
    final List<String> errors = <String>[];
    final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[];
    final List<LocalMatchSongEntry> pendingEntries = <LocalMatchSongEntry>[];
    final _AndroidSafRunCache cache = _AndroidSafRunCache();

    Future<void> flushEntries() async {
      if (pendingEntries.isEmpty) {
        return;
      }
      final List<LocalMatchSongEntry> batch =
          List<LocalMatchSongEntry>.unmodifiable(pendingEntries);
      pendingEntries.clear();
      await onEntries?.call(batch);
    }

    Future<void> publishEntries(Iterable<LocalMatchSongEntry> values) async {
      for (final LocalMatchSongEntry entry in values) {
        if (collectEntries) {
          entries.add(entry);
        }
        if (onEntries != null) {
          pendingEntries.add(entry);
          if (pendingEntries.length >= _entryBatchSize) {
            await flushEntries();
          }
        }
      }
    }

    Future<AndroidSafLocalMatchGetInfosResult> finish({
      required bool cancelled,
      required AndroidSafScanCheckpoint? resultCheckpoint,
    }) async {
      await flushEntries();
      onProgress?.call(
        const LocalMatchGetInfosProgress(text: '', value: 0, maxValue: 0),
      );
      return AndroidSafLocalMatchGetInfosResult(
        entries: entries,
        errors: errors,
        cancelled: cancelled,
        checkpoint: resultCheckpoint,
      );
    }

    onProgress?.call(
      const LocalMatchGetInfosProgress(text: '遍历文件...', value: 0, maxValue: 0),
    );

    try {
      while (true) {
        if (token.isCancelled) {
          // finish 会异步冲刷最后一批条目；必须等待完成后再进入 finally 清理
          // 扫描缓存，保证取消结果不会遗漏已经解析但尚未发布的歌曲。
          return await finish(
            cancelled: true,
            resultCheckpoint: _toCheckpoint(state),
          );
        }

        if (state.pendingFiles.isNotEmpty) {
          final AndroidSafDiscoveredFile file = state.pendingFiles.first;
          final bool isCueStage = state.stage == AndroidSafScanStage.cueParsing;
          final int completedBefore = isCueStage
              ? state.processedCueFileCount
              : state.discoveredCueFileCount + state.processedAudioFileCount;
          final int progressTotal =
              state.discoveredCueFileCount + state.discoveredAudioFileCount;
          onProgress?.call(
            LocalMatchGetInfosProgress(
              text: isCueStage
                  ? '解析cue${file.displayName}...'
                  : '解析歌曲文件${file.displayName}...',
              value: completedBefore,
              maxValue: progressTotal,
            ),
          );

          bool completed = false;
          try {
            final List<LocalMatchSongEntry> produced = isCueStage
                ? await _processExternalCue(
                    file: file,
                    rootTree: rootTree,
                    state: state,
                    cache: cache,
                    token: token,
                    errors: errors,
                  )
                : await _processAudio(
                    file: file,
                    rootTree: rootTree,
                    state: state,
                    cache: cache,
                    token: token,
                    errors: errors,
                  );
            await publishEntries(produced);
            completed = true;
          } on _AndroidSafScanCancelled {
            // 解析过程中收到取消信号时也要先等待尾批发布完成，随后由外层
            // finally 清理短生命周期缓存，避免返回结果与进度回调发生竞态。
            return await finish(
              cancelled: true,
              resultCheckpoint: _toCheckpoint(state),
            );
          } on Exception catch (error) {
            errors.add('${error.runtimeType}: $error');
            completed = true;
          } finally {
            cache.clear();
          }

          if (completed) {
            state.pendingFiles.removeFirst();
            if (isCueStage) {
              state.processedCueFileCount += 1;
            } else {
              state.processedAudioFileCount += 1;
            }
            onProgress?.call(
              LocalMatchGetInfosProgress(
                text: isCueStage
                    ? '解析cue${file.displayName}...'
                    : '解析歌曲文件${file.displayName}...',
                value: completedBefore + 1,
                maxValue: progressTotal,
              ),
            );
          }
          continue;
        }

        if (state.pendingDirectories.isNotEmpty) {
          await _loadNextDirectoryPage(state: state, errors: errors);
          continue;
        }

        if (state.stage == AndroidSafScanStage.cueParsing) {
          state.startAudioPhase();
          continue;
        }

        // 正常结束同样等待尾批和结束进度完成，再释放本轮扫描缓存。
        return await finish(cancelled: false, resultCheckpoint: null);
      }
    } finally {
      cache.clear();
    }
  }

  Future<List<LocalMatchSongEntry>> _processExternalCue({
    required AndroidSafDiscoveredFile file,
    required AndroidSafTreeToken rootTree,
    required _AndroidSafScanMutableState state,
    required _AndroidSafRunCache cache,
    required LocalMatchCancellationToken token,
    required List<String> errors,
  }) async {
    _throwIfCancelled(token);
    final String cueText = readUnknownEncoding(
      data: await _contentPort.readBytes(file.uri, maxBytes: _maxCueBytes),
    );
    _throwIfCancelled(token);
    final CueData cue = parseCue(cuePath: file.uri, data: cueText);
    final _AndroidSafResolvedCueFiles resolved = await _resolveCueFiles(
      cue: cue,
      cueFileRelativePath: file.relativePath,
      rootTreeUri: rootTree.uri,
      token: token,
    );
    await _warmupDurationCache(
      resolved.referencedAudioUris,
      cache,
      token: token,
      errors: errors,
    );
    _throwIfCancelled(token);
    state.excludedAudioUris.addAll(resolved.referencedAudioUris);
    return cue
        .toSongInfos(
          durationResolver: (String uri) => cache.durations[uri],
          audioPathResolver: resolved.resolve,
          audioExistsChecker: resolved.containsUri,
        )
        .map(
          (SongInfo song) =>
              LocalMatchSongEntry(songInfo: song, rootPath: rootTree.uri),
        )
        .toList(growable: false);
  }

  Future<List<LocalMatchSongEntry>> _processAudio({
    required AndroidSafDiscoveredFile file,
    required AndroidSafTreeToken rootTree,
    required _AndroidSafScanMutableState state,
    required _AndroidSafRunCache cache,
    required LocalMatchCancellationToken token,
    required List<String> errors,
  }) async {
    if (state.excludedAudioUris.contains(file.uri)) {
      return const <LocalMatchSongEntry>[];
    }
    _throwIfCancelled(token);
    final AndroidSafAudioMetadata metadata = await _readAudioMetadata(
      uri: file.uri,
      nameHint: file.displayName,
      cache: cache,
    );
    _throwIfCancelled(token);
    cache.durations[file.uri] = metadata.durationMs;

    final String? embeddedCue = metadata.cuesheet;
    if (embeddedCue != null && embeddedCue.trim().isNotEmpty) {
      final CueData cue = parseCue(cuePath: file.uri, data: embeddedCue);
      final _AndroidSafResolvedCueFiles resolved = await _resolveCueFiles(
        cue: cue,
        cueFileRelativePath: file.relativePath,
        rootTreeUri: rootTree.uri,
        token: token,
      );
      await _warmupDurationCache(
        resolved.referencedAudioUris,
        cache,
        token: token,
        errors: errors,
      );
      _throwIfCancelled(token);
      return cue
          .toSongInfos(
            durationResolver: (String uri) => cache.durations[uri],
            audioPathResolver: resolved.resolve,
            audioExistsChecker: resolved.containsUri,
          )
          .map(
            (SongInfo song) =>
                LocalMatchSongEntry(songInfo: song, rootPath: rootTree.uri),
          )
          .toList(growable: false);
    }

    return <LocalMatchSongEntry>[
      LocalMatchSongEntry(
        songInfo: SongInfo(
          source: Source.local,
          path: file.uri,
          title: metadata.title,
          artist: _splitArtist(metadata.artist),
          album: metadata.album,
          durationMs: metadata.durationMs,
          id: metadata.trackNumber?.toString(),
        ),
        rootPath: rootTree.uri,
      ),
    ];
  }

  Future<_AndroidSafResolvedCueFiles> _resolveCueFiles({
    required CueData cue,
    required String cueFileRelativePath,
    required String rootTreeUri,
    required LocalMatchCancellationToken token,
  }) async {
    final _AndroidSafAudioResolver resolver = _AndroidSafAudioResolver(
      treePort: _treePort,
      rootTreeUri: rootTreeUri,
      pageSize: _directoryPageSize,
    );
    final Map<CueAudioFile, String?> uriByFile = <CueAudioFile, String?>{};
    for (final CueAudioFile audioFile in cue.files) {
      _throwIfCancelled(token);
      uriByFile[audioFile] = await resolver.resolve(
        cueFileRelativePath: cueFileRelativePath,
        cueFileReference: audioFile.filename,
      );
    }
    _throwIfCancelled(token);
    return _AndroidSafResolvedCueFiles(uriByFile);
  }

  Future<void> _loadNextDirectoryPage({
    required _AndroidSafScanMutableState state,
    required List<String> errors,
  }) async {
    final AndroidSafQueuedDirectory directory = state.pendingDirectories
        .removeFirst();
    if (directory.offset == 0) {
      state.queuedDirectoryUris.remove(directory.uri);
      if (!state.visitedDirectoryUris.add(directory.uri)) {
        return;
      }
    }

    try {
      final AndroidSafTreePage page = await _treePort.listChildrenPage(
        uri: directory.uri,
        offset: directory.offset,
        limit: _directoryPageSize,
      );
      final List<AndroidSafTreeEntry>
      children = <AndroidSafTreeEntry>[...page.entries]
        ..sort((AndroidSafTreeEntry left, AndroidSafTreeEntry right) {
          final int nameCompare = left.displayName.compareTo(right.displayName);
          return nameCompare != 0 ? nameCompare : left.uri.compareTo(right.uri);
        });

      final int? nextOffset = page.nextOffset;
      if (nextOffset != null) {
        state.pendingDirectories.addFirst(directory.nextPage(nextOffset));
      }

      for (final AndroidSafTreeEntry child in children) {
        final String relativePath = _joinRelativePath(
          directory.relativeDirectoryPath,
          child.displayName,
        );
        if (child.isDirectory) {
          if (!state.visitedDirectoryUris.contains(child.uri) &&
              state.queuedDirectoryUris.add(child.uri)) {
            state.pendingDirectories.addLast(
              AndroidSafQueuedDirectory(
                uri: child.uri,
                relativeDirectoryPath: relativePath,
              ),
            );
          }
          continue;
        }
        if (!child.isFile || !state.seenFileUris.add(child.uri)) {
          continue;
        }

        final String extension = p.extension(child.displayName).toLowerCase();
        final bool isCue = extension == '.cue';
        final bool isAudio = _isSupportedAudioName(child.displayName);
        if (state.stage == AndroidSafScanStage.cueParsing) {
          if (isCue) {
            state.discoveredCueFileCount += 1;
            state.pendingFiles.addLast(
              AndroidSafDiscoveredFile(
                uri: child.uri,
                relativePath: relativePath,
                displayName: child.displayName,
              ),
            );
          } else if (isAudio) {
            state.discoveredAudioFileCount += 1;
          }
          continue;
        }
        if (isAudio) {
          state.pendingFiles.addLast(
            AndroidSafDiscoveredFile(
              uri: child.uri,
              relativePath: relativePath,
              displayName: child.displayName,
            ),
          );
        }
      }
    } on Exception catch (error) {
      errors.add('${error.runtimeType}: $error');
    }
  }

  _AndroidSafScanMutableState _createInitialState({
    required AndroidSafTreeToken rootTree,
    required AndroidSafScanCheckpoint? checkpoint,
  }) {
    if (checkpoint == null) {
      return _AndroidSafScanMutableState.initial(rootTree.uri);
    }
    if (checkpoint.rootTreeUri != rootTree.uri) {
      throw ArgumentError.value(
        checkpoint.rootTreeUri,
        'checkpoint.rootTreeUri',
        'checkpoint 与当前 rootTree 不匹配',
      );
    }
    return _AndroidSafScanMutableState.fromCheckpoint(checkpoint);
  }

  AndroidSafScanCheckpoint _toCheckpoint(_AndroidSafScanMutableState state) {
    return AndroidSafScanCheckpoint(
      rootTreeUri: state.rootTreeUri,
      stage: state.stage,
      pendingDirectories: state.pendingDirectories.toList(growable: false),
      pendingFiles: state.pendingFiles.toList(growable: false),
      visitedDirectoryUris: state.visitedDirectoryUris.toList(growable: false),
      seenFileUris: state.seenFileUris.toList(growable: false),
      excludedAudioUris: state.excludedAudioUris.toList(growable: false),
      discoveredCueFileCount: state.discoveredCueFileCount,
      discoveredAudioFileCount: state.discoveredAudioFileCount,
      processedCueFileCount: state.processedCueFileCount,
      processedAudioFileCount: state.processedAudioFileCount,
    );
  }

  Future<void> _warmupDurationCache(
    Iterable<String> audioUris,
    _AndroidSafRunCache cache, {
    required LocalMatchCancellationToken token,
    required List<String> errors,
  }) async {
    for (final String uri in audioUris) {
      if (cache.durations.containsKey(uri)) {
        continue;
      }
      _throwIfCancelled(token);
      try {
        final AndroidSafAudioMetadata metadata = await _readAudioMetadata(
          uri: uri,
          nameHint: cache.metadata[uri]?.nameHint,
          cache: cache,
        );
        cache.durations[uri] = metadata.durationMs;
      } on Exception catch (error) {
        cache.durations[uri] = null;
        errors.add('读取 CUE 关联音频时长失败 $uri: ${error.runtimeType}: $error');
      }
    }
  }

  Future<AndroidSafAudioMetadata> _readAudioMetadata({
    required String uri,
    required String? nameHint,
    required _AndroidSafRunCache cache,
  }) async {
    final AndroidSafAudioMetadata? cached = cache.metadata[uri];
    if (cached != null) {
      return cached;
    }
    final AndroidSafAudioMetadata metadata = await _audioMetadataPort
        .readMetadata(uri: uri, nameHint: nameHint);
    cache.metadata[uri] = metadata;
    return metadata;
  }

  SongArtist? _splitArtist(String? artistText) {
    if (artistText == null || artistText.trim().isEmpty) {
      return null;
    }
    final List<String> values = artistText
        .split('/')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? null : SongArtist(values);
  }
}

final class _AndroidSafScanMutableState {
  _AndroidSafScanMutableState({
    required this.rootTreeUri,
    required this.stage,
    required this.pendingDirectories,
    required this.pendingFiles,
    required this.visitedDirectoryUris,
    required this.seenFileUris,
    required this.excludedAudioUris,
    required this.discoveredCueFileCount,
    required this.discoveredAudioFileCount,
    required this.processedCueFileCount,
    required this.processedAudioFileCount,
  }) : queuedDirectoryUris = pendingDirectories
           .where((AndroidSafQueuedDirectory item) => item.offset == 0)
           .map((AndroidSafQueuedDirectory item) => item.uri)
           .toSet();

  factory _AndroidSafScanMutableState.initial(String rootTreeUri) {
    return _AndroidSafScanMutableState(
      rootTreeUri: rootTreeUri,
      stage: AndroidSafScanStage.cueParsing,
      pendingDirectories: Queue<AndroidSafQueuedDirectory>.from(
        <AndroidSafQueuedDirectory>[
          AndroidSafQueuedDirectory(
            uri: rootTreeUri,
            relativeDirectoryPath: '',
          ),
        ],
      ),
      pendingFiles: Queue<AndroidSafDiscoveredFile>(),
      visitedDirectoryUris: <String>{},
      seenFileUris: <String>{},
      excludedAudioUris: <String>{},
      discoveredCueFileCount: 0,
      discoveredAudioFileCount: 0,
      processedCueFileCount: 0,
      processedAudioFileCount: 0,
    );
  }

  factory _AndroidSafScanMutableState.fromCheckpoint(
    AndroidSafScanCheckpoint checkpoint,
  ) {
    return _AndroidSafScanMutableState(
      rootTreeUri: checkpoint.rootTreeUri,
      stage: checkpoint.stage,
      pendingDirectories: Queue<AndroidSafQueuedDirectory>.from(
        checkpoint.pendingDirectories,
      ),
      pendingFiles: Queue<AndroidSafDiscoveredFile>.from(
        checkpoint.pendingFiles,
      ),
      visitedDirectoryUris: Set<String>.from(checkpoint.visitedDirectoryUris),
      seenFileUris: <String>{
        ...checkpoint.seenFileUris,
        ...checkpoint.pendingFiles.map(
          (AndroidSafDiscoveredFile file) => file.uri,
        ),
      },
      excludedAudioUris: Set<String>.from(checkpoint.excludedAudioUris),
      discoveredCueFileCount: checkpoint.discoveredCueFileCount,
      discoveredAudioFileCount: checkpoint.discoveredAudioFileCount,
      processedCueFileCount: checkpoint.processedCueFileCount.clamp(
        0,
        checkpoint.discoveredCueFileCount,
      ),
      processedAudioFileCount: checkpoint.processedAudioFileCount.clamp(
        0,
        checkpoint.discoveredAudioFileCount,
      ),
    );
  }

  final String rootTreeUri;
  AndroidSafScanStage stage;
  final Queue<AndroidSafQueuedDirectory> pendingDirectories;
  final Queue<AndroidSafDiscoveredFile> pendingFiles;
  final Set<String> visitedDirectoryUris;
  final Set<String> queuedDirectoryUris;
  final Set<String> seenFileUris;
  final Set<String> excludedAudioUris;
  int discoveredCueFileCount;
  int discoveredAudioFileCount;
  int processedCueFileCount;
  int processedAudioFileCount;

  void startAudioPhase() {
    stage = AndroidSafScanStage.audioParsing;
    pendingDirectories
      ..clear()
      ..add(
        AndroidSafQueuedDirectory(uri: rootTreeUri, relativeDirectoryPath: ''),
      );
    pendingFiles.clear();
    visitedDirectoryUris.clear();
    queuedDirectoryUris
      ..clear()
      ..add(rootTreeUri);
    seenFileUris.clear();
    processedAudioFileCount = 0;
  }
}

final class _AndroidSafRunCache {
  final Map<String, AndroidSafAudioMetadata> metadata =
      <String, AndroidSafAudioMetadata>{};
  final Map<String, int?> durations = <String, int?>{};
  void clear() {
    metadata.clear();
    durations.clear();
  }
}

final class _AndroidSafResolvedCueFiles {
  _AndroidSafResolvedCueFiles(this._uriByFile)
    : referencedAudioUris = _uriByFile.values.whereType<String>().toSet();

  final Map<CueAudioFile, String?> _uriByFile;
  final Set<String> referencedAudioUris;

  String? resolve(CueData _, CueAudioFile file) => _uriByFile[file];

  bool containsUri(String uri) => referencedAudioUris.contains(uri);
}

final class _AndroidSafAudioResolver {
  const _AndroidSafAudioResolver({
    required this._treePort,
    required this.rootTreeUri,
    required this.pageSize,
  });

  final AndroidSafTreePort _treePort;
  final String rootTreeUri;
  final int pageSize;

  Future<String?> resolve({
    required String cueFileRelativePath,
    required String cueFileReference,
  }) async {
    final String normalizedReference = _normalizeRelativePath(cueFileReference);
    if (normalizedReference.isEmpty) {
      return null;
    }
    final String cueDirectory = _normalizeRelativePath(
      p.posix.dirname(cueFileRelativePath),
    );
    final String relativeCandidate = cueDirectory.isEmpty || cueDirectory == '.'
        ? normalizedReference
        : _normalizeRelativePath('$cueDirectory/$normalizedReference');
    if (relativeCandidate != '..' && !relativeCandidate.startsWith('../')) {
      final String? exact = await _resolveExactRelativePath(relativeCandidate);
      if (exact != null) {
        return exact;
      }
    }
    return _findByDisplayNameOrStem(normalizedReference);
  }

  Future<String?> _resolveExactRelativePath(String relativePath) async {
    final List<String> segments = relativePath
        .split('/')
        .where((String segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }
    String directoryUri = rootTreeUri;
    for (int index = 0; index < segments.length; index += 1) {
      final bool isLast = index == segments.length - 1;
      final AndroidSafTreeEntry? child = await _findDirectChild(
        directoryUri: directoryUri,
        displayName: segments[index],
        expectDirectory: !isLast,
      );
      if (child == null) {
        return null;
      }
      if (isLast) {
        return child.isFile && _isSupportedAudioName(child.displayName)
            ? child.uri
            : null;
      }
      directoryUri = child.uri;
    }
    return null;
  }

  Future<AndroidSafTreeEntry?> _findDirectChild({
    required String directoryUri,
    required String displayName,
    required bool expectDirectory,
  }) async {
    int offset = 0;
    while (true) {
      final AndroidSafTreePage page = await _treePort.listChildrenPage(
        uri: directoryUri,
        offset: offset,
        limit: pageSize,
      );
      for (final AndroidSafTreeEntry child in page.entries) {
        if (child.displayName.toLowerCase() != displayName.toLowerCase()) {
          continue;
        }
        if (expectDirectory ? child.isDirectory : child.isFile) {
          return child;
        }
      }
      final int? nextOffset = page.nextOffset;
      if (nextOffset == null) {
        return null;
      }
      offset = nextOffset;
    }
  }

  Future<String?> _findByDisplayNameOrStem(String reference) async {
    final String targetDisplayName = p.posix.basename(reference).toLowerCase();
    final String targetStem = p.posix
        .basenameWithoutExtension(reference)
        .toLowerCase();
    final Queue<String> pendingDirectories = Queue<String>.from(<String>[
      rootTreeUri,
    ]);
    final Set<String> visitedDirectories = <String>{};
    String? bestDisplayMatch;
    String? bestStemMatch;

    while (pendingDirectories.isNotEmpty) {
      final String directoryUri = pendingDirectories.removeFirst();
      if (!visitedDirectories.add(directoryUri)) {
        continue;
      }
      int offset = 0;
      while (true) {
        final AndroidSafTreePage page = await _treePort.listChildrenPage(
          uri: directoryUri,
          offset: offset,
          limit: pageSize,
        );
        for (final AndroidSafTreeEntry child in page.entries) {
          if (child.isDirectory) {
            if (!visitedDirectories.contains(child.uri)) {
              pendingDirectories.addLast(child.uri);
            }
            continue;
          }
          if (!child.isFile || !_isSupportedAudioName(child.displayName)) {
            continue;
          }
          final String displayName = child.displayName.toLowerCase();
          if (displayName == targetDisplayName &&
              (bestDisplayMatch == null ||
                  child.uri.compareTo(bestDisplayMatch) < 0)) {
            bestDisplayMatch = child.uri;
            continue;
          }
          final String stem = p.posix
              .basenameWithoutExtension(child.displayName)
              .toLowerCase();
          if (stem == targetStem &&
              (bestStemMatch == null ||
                  child.uri.compareTo(bestStemMatch) < 0)) {
            bestStemMatch = child.uri;
          }
        }
        final int? nextOffset = page.nextOffset;
        if (nextOffset == null) {
          break;
        }
        offset = nextOffset;
      }
    }
    return bestDisplayMatch ?? bestStemMatch;
  }
}

final class _AndroidSafScanCancelled implements Exception {
  const _AndroidSafScanCancelled();
}

void _throwIfCancelled(LocalMatchCancellationToken token) {
  if (token.isCancelled) {
    throw const _AndroidSafScanCancelled();
  }
}

bool _isSupportedAudioName(String displayName) {
  final String extension = p.extension(displayName).toLowerCase();
  final String withoutDot = extension.startsWith('.')
      ? extension.substring(1)
      : extension;
  return audioFileExtensionSet.contains(withoutDot);
}

String _joinRelativePath(String parent, String child) {
  final String normalizedChild = child.replaceAll('\\', '/');
  if (parent.isEmpty) {
    return p.posix.normalize(normalizedChild);
  }
  return p.posix.normalize('$parent/$normalizedChild');
}

String _normalizeRelativePath(String value) {
  String normalized = value.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) {
    return '';
  }
  while (normalized.startsWith('./')) {
    normalized = normalized.substring(2);
  }
  if (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  return p.posix.normalize(normalized);
}
