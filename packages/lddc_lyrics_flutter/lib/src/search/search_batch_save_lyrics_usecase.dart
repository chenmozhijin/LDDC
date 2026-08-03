export 'search_batch_save_models.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'search_batch_save_executor.dart';
import 'search_batch_save_models.dart';

typedef SearchLyricsSavePersistenceFactory =
    LyricsSavePersistencePort Function(String target);

/// 搜索页专辑/歌单批量保存用例。
class SearchBatchSaveLyricsUseCase {
  const SearchBatchSaveLyricsUseCase({
    required this._lyricsApi,
    required this._persistenceFactory,
  });

  final LyricsClient _lyricsApi;
  final SearchLyricsSavePersistenceFactory _persistenceFactory;

  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String saveFolder,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) async {
    return SearchBatchSaveExecutor(
      lyricsApi: _lyricsApi,
      persistencePort: _persistenceFactory(saveFolder),
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
