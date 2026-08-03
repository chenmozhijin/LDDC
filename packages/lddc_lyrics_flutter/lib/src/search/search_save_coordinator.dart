import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import 'search_android_saf_batch_save_lyrics_usecase.dart';
import 'search_batch_save_lyrics_usecase.dart';

/// 保存与批处理协调器，只持有注入端口，不复制页面的忙碌态或取消代际。
final class SearchSaveCoordinator {
  const SearchSaveCoordinator({
    required this._filePicker,
    required this._mediaGateway,
    required this._fileSaveFactory,
    required this._batchSaveUseCase,
    required this._androidBatchSaveUseCase,
  });

  final AppFilePicker _filePicker;
  final LocalMatchMediaGateway _mediaGateway;
  final SearchLyricsSavePersistenceFactory _fileSaveFactory;
  final SearchBatchSaveLyricsUseCase _batchSaveUseCase;
  final SearchAndroidSafBatchSaveLyricsUseCase _androidBatchSaveUseCase;

  LyricsSavePlan buildPreviewPlan({
    required String folder,
    required String fileNameFormat,
    required Lyrics lyrics,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
  }) {
    return LyricsSavePlanner.planSearch(
      folder: folder,
      fileNameFormat: fileNameFormat,
      songInfo: lyrics.songInfo,
      lyricLangs: langs,
      lyricsFormat: lyricsFormat,
    );
  }

  Future<String> savePreviewToDirectory({
    required String folder,
    required String fileNameFormat,
    required Lyrics lyrics,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String text,
  }) {
    final LyricsSavePlan plan = buildPreviewPlan(
      folder: folder,
      fileNameFormat: fileNameFormat,
      lyrics: lyrics,
      langs: langs,
      lyricsFormat: lyricsFormat,
    );
    return _fileSaveFactory(
      folder,
    ).saveText(request: plan.request!, text: text);
  }

  Future<SavedTextFileResult?> savePreviewToFile({
    required String fileName,
    required String text,
    required String? initialDirectory,
    required List<String>? allowedExtensions,
  }) {
    return _filePicker.saveTextFile(
      fileName: fileName,
      text: text,
      initialDirectory: initialDirectory,
      allowedExtensions: allowedExtensions,
    );
  }

  Future<void> writeLyricsTag({
    required PickedAudioFileHandle file,
    required String songPath,
    required String text,
    required Lyrics lyrics,
    required Id3Version id3Version,
  }) {
    return _mediaGateway.writeLyricsTag(
      songPath: songPath,
      lyricsText: text,
      lyrics: lyrics,
      id3Version: id3Version,
      fileDescriptor: file.fileDescriptor,
      fileDescriptorNameHint: file.fileDescriptorNameHint,
    );
  }

  Future<SearchBatchSaveResult> saveBatch({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String saveFolder,
    required SearchBatchSaveOptions options,
    required SearchBatchSaveCancellationToken cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) {
    return _batchSaveUseCase.execute(
      songs: songs,
      langs: langs,
      lyricsFormat: lyricsFormat,
      saveFolder: saveFolder,
      options: options,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }

  Future<SearchBatchSaveResult> saveAndroidBatch({
    required List<SongInfo> songs,
    required List<String> langs,
    required LyricsFormat lyricsFormat,
    required String treeUri,
    required SearchBatchSaveOptions options,
    required SearchBatchSaveCancellationToken cancellationToken,
    SearchBatchSaveProgressCallback? onProgress,
  }) {
    return _androidBatchSaveUseCase.execute(
      songs: songs,
      langs: langs,
      lyricsFormat: lyricsFormat,
      treeUri: treeUri,
      options: options,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }
}
