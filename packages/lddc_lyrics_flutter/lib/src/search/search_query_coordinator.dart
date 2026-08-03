import 'dart:async';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import 'search_workflow_state.dart';

enum SearchSourceQueryStatus { success, error, timeout, cancelled }

/// 单个歌词源查询的不可变结果。
final class SearchSourceQueryResult {
  const SearchSourceQueryResult({
    required this.source,
    required this.result,
    required this.error,
    this.status = SearchSourceQueryStatus.success,
    this.failure,
  });

  final Source source;
  final APIResultList<SourceAware>? result;
  final String? error;
  final SearchSourceQueryStatus status;
  final SearchSourceFailure? failure;
}

typedef SearchSourceQueryCallback =
    void Function(SearchSourceQueryResult result);

/// 搜索与分页协调器，只调用歌词客户端并返回结果，不持有页面状态或订阅。
final class SearchQueryCoordinator {
  const SearchQueryCoordinator({
    required this._lyricsClient,
    this.sourceDeadline = const Duration(seconds: 15),
  });

  static const int pageSize = 20;

  final LyricsClient _lyricsClient;
  final Duration sourceDeadline;

  List<Source> resolveSources({
    required Source selectedSource,
    required SearchType searchType,
    required List<Source> configuredSources,
  }) {
    final List<Source> candidates = selectedSource == Source.multi
        ? configuredSources
        : <Source>[selectedSource];
    final List<Source> resolved = <Source>[];
    for (final Source source in candidates) {
      if (source == Source.multi || source == Source.local) {
        continue;
      }
      if (!source.supportedSearchTypes.contains(searchType)) {
        continue;
      }
      if (!resolved.contains(source)) {
        resolved.add(source);
      }
    }
    return List<Source>.unmodifiable(resolved);
  }

  Future<List<SearchSourceQueryResult>> searchFirstPage({
    required List<Source> sources,
    required String keyword,
    required SearchType searchType,
    RequestCancellationToken? cancellationToken,
    SearchSourceQueryCallback? onResult,
  }) {
    return _runBatch(
      sources.map(
        (Source source) =>
            () => searchSource(
              source: source,
              keyword: keyword,
              searchType: searchType,
              page: 1,
              cancellationToken: cancellationToken,
            ),
      ),
      cancellationToken: cancellationToken,
      onResult: onResult,
    );
  }

  Future<List<SearchSourceQueryResult>> loadMore(
    APIResultList<SourceAware> current, {
    Iterable<Source>? sources,
    RequestCancellationToken? cancellationToken,
    SearchSourceQueryCallback? onResult,
  }) {
    final SearchInfo info = current.info! as SearchInfo;
    final Iterable<Source> requestedSources = sources ?? current.more;
    return _runBatch(
      requestedSources.map((Source source) {
        final SourceRange? range = current.sourceRanges[source];
        final int currentCount = range?.length ?? 0;
        // 不足整页但远端仍声明有更多时也向上取整，保证下一次请求不会重复当前页。
        final int page = ((currentCount + pageSize - 1) ~/ pageSize) + 1;
        return () => searchSource(
          source: source,
          keyword: info.keyword,
          searchType: info.searchType,
          page: page,
          cancellationToken: cancellationToken,
        );
      }),
      cancellationToken: cancellationToken,
      onResult: onResult,
    );
  }

  Future<SearchSourceQueryResult> searchSource({
    required Source source,
    required String keyword,
    required SearchType searchType,
    required int page,
    RequestCancellationToken? cancellationToken,
  }) async {
    final RequestCancellationToken sourceToken =
        cancellationToken?.child() ?? RequestCancellationToken();
    bool deadlineReached = false;
    final Timer deadlineTimer = Timer(sourceDeadline, () {
      deadlineReached = true;
      sourceToken.cancel();
    });
    try {
      final Future<APIResultList<SourceAware>> request = _lyricsClient.search(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
        cancellationToken: sourceToken,
      );
      final APIResultList<SourceAware> result =
          await Future.any<APIResultList<SourceAware>>(
            <Future<APIResultList<SourceAware>>>[
              request,
              sourceToken.whenCancelled.then<APIResultList<SourceAware>>((_) {
                if (deadlineReached) {
                  throw RequestTimeoutException(sourceDeadline);
                }
                throw const RequestCancelledException();
              }),
            ],
          );
      return SearchSourceQueryResult(
        source: source,
        result: result,
        error: null,
        status: SearchSourceQueryStatus.success,
      );
    } on RequestCancelledException {
      return SearchSourceQueryResult(
        source: source,
        result: null,
        error: null,
        status: SearchSourceQueryStatus.cancelled,
      );
    } on TimeoutException catch (error) {
      return SearchSourceQueryResult(
        source: source,
        result: null,
        error: '${source.value}: $error',
        status: SearchSourceQueryStatus.timeout,
        failure: SearchSourceFailure.bounded(
          source: source,
          kind: SearchSourceFailureKind.timeout,
          detail: error.toString(),
        ),
      );
    } on LddcApiParamsException catch (error) {
      return _failureResult(
        source: source,
        error: error,
        kind: SearchSourceFailureKind.parameters,
      );
    } on LddcApiNotSupportedException catch (error) {
      return _failureResult(
        source: source,
        error: error,
        kind: SearchSourceFailureKind.unsupported,
      );
    } on LddcApiRequestException catch (error) {
      return _failureResult(
        source: source,
        error: error,
        kind: SearchSourceFailureKind.request,
      );
    } on Exception catch (error) {
      return _failureResult(
        source: source,
        error: error,
        kind: SearchSourceFailureKind.unknown,
      );
    } finally {
      deadlineTimer.cancel();
      sourceToken.dispose();
    }
  }

  SearchSourceQueryResult _failureResult({
    required Source source,
    required Object error,
    required SearchSourceFailureKind kind,
  }) {
    return SearchSourceQueryResult(
      source: source,
      result: null,
      error: '${source.value}: $error',
      status: SearchSourceQueryStatus.error,
      failure: SearchSourceFailure.bounded(
        source: source,
        kind: kind,
        detail: error.toString(),
      ),
    );
  }

  Future<List<SearchSourceQueryResult>> _runBatch(
    Iterable<Future<SearchSourceQueryResult> Function()> requests, {
    required RequestCancellationToken? cancellationToken,
    required SearchSourceQueryCallback? onResult,
  }) {
    return Future.wait<SearchSourceQueryResult>(
      requests.map((Future<SearchSourceQueryResult> Function() request) async {
        final SearchSourceQueryResult result = await request();
        if (!(cancellationToken?.isCancelled ?? false) &&
            result.status != SearchSourceQueryStatus.cancelled) {
          onResult?.call(result);
        }
        return result;
      }),
    );
  }
}
