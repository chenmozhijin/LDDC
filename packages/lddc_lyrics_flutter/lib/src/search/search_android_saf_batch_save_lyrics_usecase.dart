import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'search_batch_save_executor.dart';
import 'search_batch_save_lyrics_usecase.dart';

/// 搜索页 Android SAF 批量保存用例。
///
/// 语义约束：
/// - 仅负责“已选树目录 -> 逐首拉取歌词 -> 直接写入树目录”。
/// - 文件名仍复用搜索页既有占位符和非法字符转义规则。
class SearchAndroidSafBatchSaveLyricsUseCase {
  const SearchAndroidSafBatchSaveLyricsUseCase({
    required this._lyricsApi,
    required this._persistenceFactory,
  });

  final LyricsClient _lyricsApi;
  final SearchLyricsSavePersistenceFactory _persistenceFactory;

  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String treeUri,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) async {
    return SearchBatchSaveExecutor(
      lyricsApi: _lyricsApi,
      persistencePort: _persistenceFactory(treeUri),
    ).execute(
      songs: songs,
      langs: langs,
      lyricsFormat: lyricsFormat,
      options: options,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }
}
