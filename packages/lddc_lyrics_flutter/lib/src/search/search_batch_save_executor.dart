import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'search_batch_save_models.dart';

/// 搜索页批量保存主循环执行器。
///
/// 将“获取歌词 -> 转换 -> 逐条保存 -> 统计结果”收口为单一实现，
/// 避免文件系统与 Android SAF 再维护两套平行流程。
final class SearchBatchSaveExecutor {
  const SearchBatchSaveExecutor({
    required this._lyricsApi,
    required this._persistencePort,
  });

  final LyricsClient _lyricsApi;
  final LyricsSavePersistencePort _persistencePort;

  Future<SearchBatchSaveResult> execute({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required SearchBatchSaveOptions options,
    SearchBatchSaveCancellationToken? cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) async {
    if (langs.isEmpty) {
      throw const LddcApiParamsException('select_at_least_one_lyrics_language');
    }

    final SearchBatchSaveCancellationToken token =
        cancellationToken ?? SearchBatchSaveCancellationToken();
    final List<SearchBatchSaveEntryResult> entries =
        <SearchBatchSaveEntryResult>[];
    int savedCount = 0;
    int skippedCount = 0;
    int failedCount = 0;

    for (int index = 0; index < songs.length; index += 1) {
      if (token.isCancelled) {
        break;
      }
      final SongInfo song = songs[index];
      onProgress?.call(
        SearchBatchSaveProgress(
          current: index,
          total: songs.length,
          message: SearchBatchSaveProgressMessage(
            code: SearchBatchSaveProgressMessageCode.fetchingLyrics,
            songName: song.artistTitle(replaceMissing: true),
          ),
        ),
      );
      if (token.isCancelled) {
        break;
      }

      try {
        final Lyrics lyrics = await _lyricsApi.getLyrics(info: song);
        if (token.isCancelled) {
          break;
        }
        if (options.skipInstrumental && lyrics.isInstrumental()) {
          skippedCount += 1;
          entries.add(
            SearchBatchSaveEntryResult(
              index: index,
              song: song,
              status: SearchBatchSaveEntryStatus.skippedInstrumental,
              message: SearchBatchSaveEntryStatus.skippedInstrumental.name,
            ),
          );
          continue;
        }
        if (token.isCancelled) {
          break;
        }

        final String text = convert2(
          lyrics: lyrics,
          langs: langs,
          lyricsFormat: lyricsFormat,
          options: options.convertOptions,
        );
        if (token.isCancelled) {
          break;
        }
        final String savePath = await _persistencePort.saveText(
          request: LyricsSaveRequest(
            songInfo: song,
            lyricLangs: langs,
            lyricsFormat: lyricsFormat,
            fileNameFormat: options.fileNameFormat,
          ),
          text: text,
        );
        // 保存端口一旦进入写入阶段可能已经持有文件句柄或 SAF fd，不能在
        // controller 层强行打断。若取消发生在写入期间，记录已完成条目，
        // 随后循环头会停止启动下一首，避免落下半条结果。
        savedCount += 1;
        entries.add(
          SearchBatchSaveEntryResult(
            index: index,
            song: song,
            status: SearchBatchSaveEntryStatus.saved,
            message: SearchBatchSaveEntryStatus.saved.name,
            savePath: savePath,
          ),
        );
      } on LddcLyricsNotFoundException catch (error) {
        failedCount += 1;
        entries.add(
          SearchBatchSaveEntryResult(
            index: index,
            song: song,
            status: SearchBatchSaveEntryStatus.fetchFailed,
            message: error.toString(),
          ),
        );
      } on Exception catch (error) {
        failedCount += 1;
        entries.add(
          SearchBatchSaveEntryResult(
            index: index,
            song: song,
            status: SearchBatchSaveEntryStatus.saveFailed,
            message: error.toString(),
          ),
        );
      }
    }

    onProgress?.call(
      const SearchBatchSaveProgress(
        current: 0,
        total: 0,
        message: SearchBatchSaveProgressMessage.empty(),
      ),
    );
    return SearchBatchSaveResult(
      total: songs.length,
      savedCount: savedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      cancelled: token.isCancelled && entries.length < songs.length,
      entries: entries,
    );
  }
}
