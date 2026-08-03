import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../support/internal_runtime_test_api.dart';

import 'live_api_cases.dart';

// 真实云源协议测试使用独立 live profile：
// - 默认测试链必须保持离线，不访问外部 API，避免网络波动影响开发回归；
// - 设置 RUN_LIVE_API=1，可用 LIVE_API_SOURCES 选择来源；
// - 结果报告默认写入 build 目录，由独立 workflow 作为服务兼容性门禁。
final bool _runLiveApiSmoke = Platform.environment['RUN_LIVE_API'] == '1';

void main() {
  test('live 步骤只对瞬时故障执行有界重试', () async {
    int attempts = 0;
    final List<LiveApiStepResult> steps = <LiveApiStepResult>[];

    final _StepRunResult<int> result = await _runStep<int>(
      steps: steps,
      step: 'transient_retry',
      action: () async {
        attempts += 1;
        if (attempts < 3) {
          throw TimeoutException('synthetic timeout');
        }
        return 7;
      },
    );

    expect(attempts, 3);
    expect(result.value, 7);
    expect(steps, hasLength(1));
    expect(steps.single.success, isTrue);
  });

  test('live 步骤不重试确定性业务错误', () async {
    int attempts = 0;
    final List<LiveApiStepResult> steps = <LiveApiStepResult>[];

    final _StepRunResult<int> result = await _runStep<int>(
      steps: steps,
      step: 'deterministic_failure',
      action: () async {
        attempts += 1;
        throw const FormatException('synthetic parse failure');
      },
    );

    expect(attempts, 1);
    expect(result.value, isNull);
    expect(steps, hasLength(1));
    expect(steps.single.success, isFalse);
    expect(steps.single.errorMessage, contains('attempts=1'));
  });

  test(
    '云源真实请求协议兼容性',
    () async {
      final _LiveRuntimeConfig config = _LiveRuntimeConfig.fromEnvironment();

      final List<LiveApiCase> selectedCases = kDefaultLiveApiCases
          .where(
            (LiveApiCase item) => config.enabledSources.contains(item.source),
          )
          .toList(growable: false);
      if (selectedCases.isEmpty) {
        fail('LIVE_API_SOURCES 过滤后无可执行来源');
      }

      final Stopwatch allStopwatch = Stopwatch()..start();
      final List<LiveApiSourceReport> reports = <LiveApiSourceReport>[];
      for (final LiveApiCase liveCase in selectedCases) {
        final LiveApiSourceReport report = await _runSingleSourceCase(
          liveCase: liveCase,
        );
        reports.add(report);
        if (!report.success &&
            config.failurePolicy == _LiveFailurePolicy.failFast) {
          break;
        }
      }
      allStopwatch.stop();

      final List<LiveApiSourceReport> failedReports = reports
          .where((LiveApiSourceReport item) => !item.success)
          .toList(growable: false);
      final Map<String, Object?> reportPayload = <String, Object?>{
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'runConfig': <String, Object?>{
          'enabled': config.enabled,
          'sources': selectedCases
              .map<String>((LiveApiCase item) => item.source.value)
              .toList(growable: false),
          'failurePolicy': config.failurePolicy.wireName,
          'reportPath': config.reportPath,
        },
        'summary': <String, Object?>{
          'totalSources': reports.length,
          'passedSources': reports.length - failedReports.length,
          'failedSources': failedReports.length,
          'elapsedMs': allStopwatch.elapsedMilliseconds,
        },
        'sources': reports
            .map<Map<String, Object?>>(
              (LiveApiSourceReport item) => item.toMap(),
            )
            .toList(growable: false),
      };
      await _writeReport(path: config.reportPath, payload: reportPayload);

      _printSummary(
        reports: reports,
        elapsedMs: allStopwatch.elapsedMilliseconds,
        reportPath: config.reportPath,
      );

      if (failedReports.isNotEmpty &&
          config.failurePolicy != _LiveFailurePolicy.reportOnly) {
        final String failedSources = failedReports
            .map<String>((LiveApiSourceReport item) => item.source.value)
            .join(', ');
        fail('真实请求冒烟失败，来源: $failedSources；详见 ${config.reportPath}');
      }
    },
    skip: _runLiveApiSmoke ? false : '该用例只在 RUN_LIVE_API=1 的 live profile 运行。',
    tags: 'live',
    // 四个来源会串行执行搜索、分页、列表和歌词协议检查。默认 30 秒测试
    // 超时会在正常网络请求尚未完成时杀死整个用例，导致来源报告无法落盘。
    // 单步骤仍有独立 20 秒边界，因此这里放宽总预算不会允许无限等待。
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<LiveApiSourceReport> _runSingleSourceCase({
  required LiveApiCase liveCase,
}) async {
  final LyricsCloudSourceProvider provider = _createProvider(liveCase.source);
  final Stopwatch sourceStopwatch = Stopwatch()..start();
  final List<LiveApiStepResult> steps = <LiveApiStepResult>[];
  try {
    await _runSongFlow(liveCase: liveCase, provider: provider, steps: steps);
    final String? paginationSongKeyword = liveCase.paginationSongKeyword;
    if (paginationSongKeyword != null) {
      await _runSearchPaginationFlow(
        source: liveCase.source,
        keyword: paginationSongKeyword,
        provider: provider,
        steps: steps,
      );
    }
    if (liveCase.enableSonglistFlow) {
      await _runSonglistFlow(
        liveCase: liveCase,
        provider: provider,
        steps: steps,
      );
    }
    if (liveCase.enableAlbumFlow) {
      await _runAlbumFlow(liveCase: liveCase, provider: provider, steps: steps);
    }

    sourceStopwatch.stop();
    final bool sourceSuccess = steps.every(
      (LiveApiStepResult item) => item.success,
    );
    return LiveApiSourceReport(
      source: liveCase.source,
      success: sourceSuccess,
      elapsedMs: sourceStopwatch.elapsedMilliseconds,
      steps: steps,
    );
  } finally {
    if (sourceStopwatch.isRunning) {
      sourceStopwatch.stop();
    }
    // Live 流程同样必须释放连接池和持久缓存，避免验收代码本身掩盖泄漏。
    if (provider is ClosableLyricsSourceProvider) {
      await (provider as ClosableLyricsSourceProvider).close();
    }
  }
}

Future<void> _runSearchPaginationFlow({
  required Source source,
  required String keyword,
  required LyricsCloudSourceProvider provider,
  required List<LiveApiStepResult> steps,
}) async {
  await _runStep<APIResultList<SourceAware>>(
    steps: steps,
    step: 'search_song_pagination',
    action: () async {
      final APIResultList<SourceAware> page1 = await provider.search(
        keyword: keyword,
        searchType: SearchType.song,
      );
      final APIResultList<SourceAware> page2 = await provider.search(
        keyword: keyword,
        searchType: SearchType.song,
        page: 2,
      );
      final SourceRange? page1Range = page1.sourceRanges[source];
      final SourceRange? page2Range = page2.sourceRanges[source];
      if (page1.isEmpty || page2.isEmpty) {
        throw const _LiveEmptyResultException('连续分页返回空结果');
      }
      if (page1Range == null || page2Range == null) {
        throw const _LiveEmptyResultException('连续分页缺少来源范围');
      }
      if (page1Range.start != 0 || page2Range.start != 20) {
        throw _LiveEmptyResultException(
          '连续分页范围错误: ${page1Range.toList()} / ${page2Range.toList()}',
        );
      }

      final Set<String> page1Ids = _collectSongInfos(page1)
          .map(_liveSongIdentity)
          .where((String identity) => identity.isNotEmpty)
          .toSet();
      final Set<String> page2Ids = _collectSongInfos(page2)
          .map(_liveSongIdentity)
          .where((String identity) => identity.isNotEmpty)
          .toSet();
      if (page1Ids.intersection(page2Ids).isNotEmpty) {
        throw const _LiveEmptyResultException('连续分页仍包含重复歌曲');
      }
      _verifyQmSearchText(source, <SourceAware>[...page1, ...page2]);

      final APIResultList<SourceAware> merged = page1 + page2;
      if (merged.length != page1.length + page2.length) {
        throw const _LiveEmptyResultException('连续分页合并后数量不一致');
      }
      return merged;
    },
  );
}

String _liveSongIdentity(SongInfo song) {
  return song.id?.trim().isNotEmpty == true
      ? 'id:${song.id!.trim()}'
      : song.mid?.trim().isNotEmpty == true
      ? 'mid:${song.mid!.trim()}'
      : '';
}

Future<void> _runSongFlow({
  required LiveApiCase liveCase,
  required LyricsCloudSourceProvider provider,
  required List<LiveApiStepResult> steps,
}) async {
  final _StepRunResult<APIResultList<SourceAware>> searchSongResult =
      await _runStep<APIResultList<SourceAware>>(
        steps: steps,
        step: 'search_song',
        action: () async {
          final APIResultList<SourceAware> result = await provider.search(
            keyword: liveCase.songKeyword,
            searchType: SearchType.song,
          );
          final List<SongInfo> songs = _collectSongInfos(result);
          if (songs.isEmpty) {
            throw const _LiveEmptyResultException('search(song) 返回空结果');
          }
          if (!_hasTitle(songs.first)) {
            throw const _LiveEmptyResultException('search(song) 结果缺少 title');
          }
          _verifyQmSearchText(liveCase.source, result);
          return result;
        },
      );
  if (searchSongResult.value == null) {
    _appendSkipped(
      steps: steps,
      step: 'search_song_id',
      reason: 'search_song 失败',
      enabled: liveCase.enableSongIdFlow,
    );
    _appendSkipped(
      steps: steps,
      step: 'get_lyrics_song',
      reason: 'search_song 失败',
    );
    return;
  }

  final List<SongInfo> songs = _collectSongInfos(searchSongResult.value!);
  final int pickIndex = liveCase.preferSecondSong && songs.length > 1 ? 1 : 0;
  SongInfo selectedSong = songs[pickIndex];

  if (liveCase.enableSongIdFlow) {
    final _StepRunResult<APIResultList<SourceAware>> songIdSearchResult =
        await _runStep<APIResultList<SourceAware>>(
          steps: steps,
          step: 'search_song_id',
          action: () async {
            final String songId = selectedSong.id?.trim() ?? '';
            if (songId.isEmpty) {
              throw const _LiveEmptyResultException(
                'search(song) 返回结果缺少 id，无法执行 songId 流程',
              );
            }
            final APIResultList<SourceAware> result = await provider.search(
              keyword: songId,
              searchType: SearchType.songId,
            );
            final List<SongInfo> songIdSongs = _collectSongInfos(result);
            if (songIdSongs.isEmpty) {
              throw const _LiveEmptyResultException('search(songId) 返回空结果');
            }
            if (!_hasTitle(songIdSongs.first)) {
              throw const _LiveEmptyResultException(
                'search(songId) 结果缺少 title',
              );
            }
            _verifyQmSearchText(liveCase.source, result);
            return result;
          },
        );
    if (songIdSearchResult.value != null) {
      selectedSong = _collectSongInfos(songIdSearchResult.value!).first;
    } else {
      _appendSkipped(
        steps: steps,
        step: 'get_lyrics_song',
        reason: 'search_song_id 失败',
      );
      return;
    }
  }

  await _runStep<Lyrics>(
    steps: steps,
    step: 'get_lyrics_song',
    action: () async {
      final Lyrics lyrics = await provider.getLyrics(selectedSong);
      // 对齐Python版：只要求成功返回 Lyrics 对象。
      return lyrics;
    },
  );
}

Future<void> _runSonglistFlow({
  required LiveApiCase liveCase,
  required LyricsCloudSourceProvider provider,
  required List<LiveApiStepResult> steps,
}) async {
  final String keyword = liveCase.songlistKeyword ?? '';
  final _StepRunResult<APIResultList<SourceAware>> searchSonglistResult =
      await _runStep<APIResultList<SourceAware>>(
        steps: steps,
        step: 'search_songlist',
        action: () async {
          final APIResultList<SourceAware> result = await provider.search(
            keyword: keyword,
            searchType: SearchType.songlist,
          );
          final List<SongListInfo> songlists = _collectSongLists(result);
          if (songlists.isEmpty) {
            throw const _LiveEmptyResultException('search(songlist) 返回空结果');
          }
          if (!_hasSongListTitle(songlists.first)) {
            throw const _LiveEmptyResultException(
              'search(songlist) 结果缺少 title',
            );
          }
          _verifyQmSearchText(liveCase.source, result);
          return result;
        },
      );
  if (searchSonglistResult.value == null) {
    _appendSkipped(
      steps: steps,
      step: 'get_songlist_from_songlist',
      reason: 'search_songlist 失败',
    );
    _appendSkipped(
      steps: steps,
      step: 'get_lyrics_songlist_first',
      reason: 'search_songlist 失败',
    );
    return;
  }

  final SongListInfo firstSonglist = _collectSongLists(
    searchSonglistResult.value!,
  ).first;
  if (liveCase.source == Source.ne) {
    await _runStep<void>(
      steps: steps,
      step: 'verify_songlist_cover_cdn',
      action: () => _verifyNeCoverCdn(firstSonglist.imgUrl),
    );
  }
  final _StepRunResult<APIResultList<SongInfo>> songlistSongsResult =
      await _runStep<APIResultList<SongInfo>>(
        steps: steps,
        step: 'get_songlist_from_songlist',
        action: () async {
          final APIResultList<SongInfo> songs = await provider.getSonglist(
            firstSonglist,
          );
          if (songs.isEmpty) {
            throw const _LiveEmptyResultException(
              'getSonglist(songlist) 返回空结果',
            );
          }
          if (!_hasTitle(songs.first)) {
            throw const _LiveEmptyResultException(
              'getSonglist(songlist) 结果缺少 title',
            );
          }
          return songs;
        },
      );
  if (songlistSongsResult.value == null) {
    _appendSkipped(
      steps: steps,
      step: 'get_lyrics_songlist_first',
      reason: 'get_songlist_from_songlist 失败',
    );
    return;
  }

  await _runStep<Lyrics>(
    steps: steps,
    step: 'get_lyrics_songlist_first',
    action: () async {
      return provider.getLyrics(songlistSongsResult.value!.first);
    },
  );
}

Future<void> _verifyNeCoverCdn(String coverUrl) async {
  final Uri? sourceUri = Uri.tryParse(coverUrl);
  if (sourceUri == null ||
      sourceUri.scheme != 'https' ||
      !sourceUri.host.toLowerCase().endsWith('.music.126.net')) {
    throw _LiveEmptyResultException(
      'NE歌单封面不是 HTTPS music.126.net URL: $coverUrl',
    );
  }
  final HttpTransport transport = createDefaultHttpTransport();
  try {
    final Uri p1Uri = sourceUri.replace(host: 'p1.music.126.net');
    final HttpTransportResponse dartUaResponse = await transport.send(
      HttpTransportRequest(
        method: 'GET',
        uri: p1Uri,
        timeout: const Duration(seconds: 10),
      ),
    );
    final String dartUaContentType =
        _headerValue(dartUaResponse.headers, 'content-type') ?? '';
    // 默认 Dart UA 的 CDN 行为属于服务端可变观察项，曾从 403 text/html
    // 变为 200 image/jpg，不能作为生产策略正确性的反向门禁。
    debugPrint(
      'NE cover default-UA observation: '
      '${dartUaResponse.statusCode} $dartUaContentType bytes=${dartUaResponse.body.length}',
    );

    final List<Uri> candidates = NeCoverRequestPolicy.requestCandidates(
      url: sourceUri.toString(),
      decodeSize: 100,
    );
    for (final Uri candidate in candidates) {
      final HttpTransportResponse response = await transport.send(
        HttpTransportRequest(
          method: 'GET',
          uri: candidate,
          timeout: const Duration(seconds: 10),
          headers: NeCoverRequestPolicy.headers,
        ),
      );
      final String contentType =
          _headerValue(response.headers, 'content-type') ?? '';
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          !contentType.toLowerCase().startsWith('image/') ||
          response.body.isEmpty) {
        throw StateError(
          '${candidate.host} 标准 UA 图片请求失败: '
          '${response.statusCode} $contentType',
        );
      }
      // HTTP 200 只证明 CDN 返回了字节；继续走 Flutter codec 才能覆盖用户
      // 实际看到的图片解码链路，并确保服务端没有返回伪装成图片的错误内容。
      final ui.Codec codec = await ui.instantiateImageCodec(
        response.body,
        targetWidth: 100,
        targetHeight: 100,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      frame.image.dispose();
      codec.dispose();
    }
  } finally {
    await transport.close();
  }
}

String? _headerValue(Map<String, String> headers, String name) {
  final String normalizedName = name.toLowerCase();
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.toLowerCase() == normalizedName) {
      return entry.value;
    }
  }
  return null;
}

Future<void> _runAlbumFlow({
  required LiveApiCase liveCase,
  required LyricsCloudSourceProvider provider,
  required List<LiveApiStepResult> steps,
}) async {
  final String keyword = liveCase.albumKeyword ?? '';
  final _StepRunResult<APIResultList<SourceAware>> searchAlbumResult =
      await _runStep<APIResultList<SourceAware>>(
        steps: steps,
        step: 'search_album',
        action: () async {
          final APIResultList<SourceAware> result = await provider.search(
            keyword: keyword,
            searchType: SearchType.album,
          );
          final List<SongListInfo> albums = _collectSongLists(result);
          if (albums.isEmpty) {
            throw const _LiveEmptyResultException('search(album) 返回空结果');
          }
          if (!_hasSongListTitle(albums.first)) {
            throw const _LiveEmptyResultException('search(album) 结果缺少 title');
          }
          _verifyQmSearchText(liveCase.source, result);
          return result;
        },
      );
  if (searchAlbumResult.value == null) {
    _appendSkipped(
      steps: steps,
      step: 'get_songlist_from_album',
      reason: 'search_album 失败',
    );
    _appendSkipped(
      steps: steps,
      step: 'get_lyrics_album_first',
      reason: 'search_album 失败',
    );
    return;
  }

  final SongListInfo firstAlbum = _collectSongLists(
    searchAlbumResult.value!,
  ).first;
  final _StepRunResult<APIResultList<SongInfo>> albumSongsResult =
      await _runStep<APIResultList<SongInfo>>(
        steps: steps,
        step: 'get_songlist_from_album',
        action: () async {
          final APIResultList<SongInfo> songs = await provider.getSonglist(
            firstAlbum,
          );
          if (songs.isEmpty) {
            throw const _LiveEmptyResultException('getSonglist(album) 返回空结果');
          }
          if (!_hasTitle(songs.first)) {
            throw const _LiveEmptyResultException(
              'getSonglist(album) 结果缺少 title',
            );
          }
          return songs;
        },
      );
  if (albumSongsResult.value == null) {
    _appendSkipped(
      steps: steps,
      step: 'get_lyrics_album_first',
      reason: 'get_songlist_from_album 失败',
    );
    return;
  }

  await _runStep<Lyrics>(
    steps: steps,
    step: 'get_lyrics_album_first',
    action: () async {
      return provider.getLyrics(albumSongsResult.value!.first);
    },
  );
}

Future<_StepRunResult<T>> _runStep<T>({
  required List<LiveApiStepResult> steps,
  required String step,
  required Future<T> Function() action,
}) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  const int maxAttempts = 3;
  for (int attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      final T value = await action().timeout(const Duration(seconds: 20));
      stopwatch.stop();
      steps.add(
        LiveApiStepResult(
          step: step,
          success: true,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ),
      );
      return _StepRunResult<T>(value: value);
    } catch (error) {
      final bool retry =
          attempt < maxAttempts && _isTransientLiveFailure(error);
      if (retry) {
        // 只重试超时、连接故障、限流和常见网关错误。参数或解析错误再次
        // 请求不会变好，立即保留原始失败可避免掩盖确定性协议回归。
        await Future<void>.delayed(Duration(milliseconds: attempt * 500));
        continue;
      }
      stopwatch.stop();
      steps.add(
        LiveApiStepResult(
          step: step,
          success: false,
          elapsedMs: stopwatch.elapsedMilliseconds,
          errorCategory: _classifyError(error),
          errorMessage: '${error.toString()} (attempts=$attempt)',
        ),
      );
      return _StepRunResult<T>(value: null);
    }
  }
  throw StateError('live step retry loop exited unexpectedly');
}

void _appendSkipped({
  required List<LiveApiStepResult> steps,
  required String step,
  required String reason,
  bool enabled = true,
}) {
  if (!enabled) {
    return;
  }
  steps.add(
    LiveApiStepResult(
      step: step,
      success: false,
      elapsedMs: 0,
      errorCategory: 'data',
      errorMessage: '跳过: $reason',
    ),
  );
}

LyricsCloudSourceProvider _createProvider(Source source) {
  return switch (source) {
    Source.qm => _createLiveQmProvider(),
    Source.ne => _createLiveNeProvider(),
    Source.kg => KgLyricsProvider(),
    Source.lrclib => LrclibLyricsProvider(),
    _ => throw ArgumentError('不支持的来源: ${source.value}'),
  };
}

NeLyricsProvider _createLiveNeProvider() {
  final NeRequestExecutorImpl executor = NeRequestExecutorImpl(
    // 手动 live smoke 必须保留真实 dart:io HttpClient。若初始化 flutter_test
    // binding 来读取 rootBundle，测试框架会把所有 HTTP 请求固定为 400；因此
    // 这里只从工作区内同一份正式 gzip asset 构造测试专用池。
    deviceIdPool: NeDeviceIdPool(
      compressedBytesLoader: () {
        final File asset = File(
          '${Directory.current.parent.path}'
          '${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}lddc_lyrics_flutter'
          '${Platform.pathSeparator}assets'
          '${Platform.pathSeparator}ne_device_ids.txt.gz',
        );
        return asset.readAsBytes();
      },
    ),
  );
  return NeLyricsProvider(
    requestExecutor: executor.execute,
    close: executor.close,
  );
}

QmLyricsProvider _createLiveQmProvider() {
  // Live 测试是独立进程，不经过应用 bootstrap 注册路径端口；使用独立内存库
  // 仍可完整验证身份仓储和原子状态机，同时不会污染用户真实缓存。
  final CacheFacade cache = CacheFacade(
    store: PersistentCacheStore(executor: NativeDatabase.memory()),
  );
  final QmApiClientImpl delegate = QmApiClientImpl(
    identityRepository: QmDeviceIdentityRepository(cache: cache),
  );
  return QmLyricsProvider(client: _OwnedLiveQmClient(delegate, cache));
}

final class _OwnedLiveQmClient implements QmApiClient {
  _OwnedLiveQmClient(this._delegate, this._cache);

  final QmApiClient _delegate;
  final CacheFacade _cache;

  @override
  String get sessionUid => _delegate.sessionUid;

  @override
  Future<void> init({bool refresh = false}) => _delegate.init(refresh: refresh);

  @override
  Future<Map<String, Object?>> request({
    required String method,
    required String module,
    required Map<String, Object?> param,
  }) => _delegate.request(method: method, module: module, param: param);

  @override
  Future<void> close() async {
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _delegate.close();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    await _cache.dispose();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}

List<SongInfo> _collectSongInfos(APIResultList<SourceAware> result) {
  return result.whereType<SongInfo>().toList(growable: false);
}

List<SongListInfo> _collectSongLists(APIResultList<SourceAware> result) {
  return result.whereType<SongListInfo>().toList(growable: false);
}

bool _hasTitle(SongInfo song) {
  return (song.title ?? '').trim().isNotEmpty;
}

bool _hasSongListTitle(SongListInfo songlist) {
  return songlist.title.trim().isNotEmpty;
}

void _verifyQmSearchText(Source source, Iterable<SourceAware> rows) {
  if (source != Source.qm) {
    return;
  }
  final RegExp highlightTag = RegExp(r'</?em>', caseSensitive: false);
  for (final SourceAware row in rows) {
    final Iterable<String> fields = switch (row) {
      SongInfo song => <String>[
        song.title ?? '',
        song.subtitle ?? '',
        ...?song.artist?.values,
        song.album ?? '',
      ],
      SongListInfo songList => <String>[songList.title, songList.author],
      _ => const <String>[],
    };
    for (final String value in fields) {
      if (highlightTag.hasMatch(value)) {
        throw _LiveEmptyResultException('QM 搜索字段仍包含高亮标签: $value');
      }
    }
  }
}

String _classifyError(Object error) {
  if (error is _LiveEmptyResultException) {
    return 'data';
  }
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return 'network';
  }
  if (error is FormatException) {
    return 'parse';
  }
  if (error is LddcApiRequestException) {
    final String message = error.message.toLowerCase();
    if (message.contains('解析')) {
      return 'parse';
    }
    if (message.contains('error') ||
        message.contains('错误') ||
        message.contains('code') ||
        message.contains('状态码')) {
      return 'business';
    }
    return 'network';
  }
  if (error is LddcApiParamsException ||
      error is LddcApiNotSupportedException) {
    return 'data';
  }
  return 'business';
}

bool _isTransientLiveFailure(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is HandshakeException ||
      error is HttpException) {
    return true;
  }
  if (error is LddcApiRequestException) {
    return RegExp(r'(^|\D)(429|502|503|504)(\D|$)').hasMatch(error.message);
  }
  return false;
}

Future<void> _writeReport({
  required String path,
  required Map<String, Object?> payload,
}) async {
  final File file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
}

void _printSummary({
  required List<LiveApiSourceReport> reports,
  required int elapsedMs,
  required String reportPath,
}) {
  final int passedCount = reports.where((LiveApiSourceReport item) {
    return item.success;
  }).length;
  final int failedCount = reports.length - passedCount;

  debugPrint('--- live api smoke summary ---');
  for (final LiveApiSourceReport report in reports) {
    debugPrint(
      '${report.source.value}: ${report.success ? 'PASS' : 'FAIL'} '
      '(${report.elapsedMs}ms)',
    );
    for (final LiveApiStepResult step in report.steps) {
      if (step.success) {
        continue;
      }
      debugPrint(
        '  - ${step.step}: ${step.errorCategory ?? 'unknown'} '
        '${step.errorMessage ?? ''}',
      );
    }
  }
  debugPrint(
    'sources=${reports.length}, passed=$passedCount, failed=$failedCount, '
    'elapsed=${elapsedMs}ms',
  );
  debugPrint('report=$reportPath');
}

class _LiveRuntimeConfig {
  const _LiveRuntimeConfig({
    required this.enabled,
    required this.enabledSources,
    required this.failurePolicy,
    required this.reportPath,
  });

  final bool enabled;
  final Set<Source> enabledSources;
  final _LiveFailurePolicy failurePolicy;
  final String reportPath;

  static _LiveRuntimeConfig fromEnvironment() {
    final Map<String, String> env = Platform.environment;
    final bool enabled = env['RUN_LIVE_API'] == '1';
    final String sourceText = env['LIVE_API_SOURCES'] ?? 'qm,ne,kg,lrclib';
    final _LiveFailurePolicy failurePolicy = _LiveFailurePolicy.parse(
      env['LIVE_API_FAILURE_POLICY'] ?? 'continue',
    );
    final String reportPath =
        env['LIVE_API_REPORT_PATH'] ?? 'build/live_api_smoke_report.json';

    return _LiveRuntimeConfig(
      enabled: enabled,
      enabledSources: _parseSources(sourceText),
      failurePolicy: failurePolicy,
      reportPath: reportPath,
    );
  }

  static Set<Source> _parseSources(String text) {
    final Set<Source> parsed = <Source>{};
    for (final String token in text.split(',')) {
      final String key = token.trim().toLowerCase();
      switch (key) {
        case 'qm':
          parsed.add(Source.qm);
          break;
        case 'ne':
          parsed.add(Source.ne);
          break;
        case 'kg':
          parsed.add(Source.kg);
          break;
        case 'lrclib':
        case 'lrc_lib':
        case 'lrc':
          parsed.add(Source.lrclib);
          break;
      }
    }
    if (parsed.isEmpty) {
      return <Source>{Source.qm, Source.ne, Source.kg, Source.lrclib};
    }
    return parsed;
  }
}

enum _LiveFailurePolicy {
  continueRun,
  failFast,
  reportOnly;

  String get wireName {
    return switch (this) {
      _LiveFailurePolicy.continueRun => 'continue',
      _LiveFailurePolicy.failFast => 'failFast',
      _LiveFailurePolicy.reportOnly => 'reportOnly',
    };
  }

  static _LiveFailurePolicy parse(String raw) {
    return switch (raw.trim()) {
      '' || 'continue' => _LiveFailurePolicy.continueRun,
      'failFast' || 'fail-fast' || 'fail_fast' => _LiveFailurePolicy.failFast,
      'reportOnly' ||
      'report-only' ||
      'report_only' => _LiveFailurePolicy.reportOnly,
      final String value => throw ArgumentError(
        'LIVE_API_FAILURE_POLICY 仅支持 continue、failFast、reportOnly，当前为 $value',
      ),
    };
  }
}

class _StepRunResult<T> {
  const _StepRunResult({required this.value});

  final T? value;
}

class _LiveEmptyResultException implements Exception {
  const _LiveEmptyResultException(this.message);

  final String message;

  @override
  String toString() => message;
}
