import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 搜索批量保存单次运行所需配置。
final class SearchBatchSaveOptions {
  const SearchBatchSaveOptions({
    required this.fileNameFormat,
    required this.skipInstrumental,
    required this.convertOptions,
  });

  final String fileNameFormat;
  final bool skipInstrumental;
  final LyricsConvertOptions convertOptions;
}

/// 批量保存单条状态。
enum SearchBatchSaveEntryStatus {
  saved,
  skippedInstrumental,
  fetchFailed,
  saveFailed,
}

/// 批量保存进度文案语义码。
enum SearchBatchSaveProgressMessageCode { empty, preparing, fetchingLyrics }

/// 批量保存进度文案参数。
///
/// 搜索工作流可能跨过 locale 切换，因此状态层只保存语义码和必要参数，
/// 最终文案由 UI 层根据当前语言渲染。
class SearchBatchSaveProgressMessage {
  const SearchBatchSaveProgressMessage({required this.code, this.songName});

  const SearchBatchSaveProgressMessage.empty()
    : code = SearchBatchSaveProgressMessageCode.empty,
      songName = null;

  final SearchBatchSaveProgressMessageCode code;
  final String? songName;
}

/// 批量保存进度事件。
class SearchBatchSaveProgress {
  const SearchBatchSaveProgress({
    required this.current,
    required this.total,
    required this.message,
  });

  final int current;
  final int total;
  final SearchBatchSaveProgressMessage message;
}

/// 批量保存单条结果。
class SearchBatchSaveEntryResult {
  const SearchBatchSaveEntryResult({
    required this.index,
    required this.song,
    required this.status,
    required this.message,
    this.savePath,
  });

  final int index;
  final SongInfo song;
  final SearchBatchSaveEntryStatus status;
  final String message;
  final String? savePath;
}

/// 批量保存汇总结果。
class SearchBatchSaveResult {
  SearchBatchSaveResult({
    required this.total,
    required this.savedCount,
    required this.skippedCount,
    required this.failedCount,
    required this.cancelled,
    required List<SearchBatchSaveEntryResult> entries,
  }) : entries = List<SearchBatchSaveEntryResult>.unmodifiable(entries);

  final int total;
  final int savedCount;
  final int skippedCount;
  final int failedCount;
  final bool cancelled;
  final List<SearchBatchSaveEntryResult> entries;
}

/// 批量保存取消令牌。
class SearchBatchSaveCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

typedef SearchBatchSaveProgressCallback =
    void Function(SearchBatchSaveProgress value);
