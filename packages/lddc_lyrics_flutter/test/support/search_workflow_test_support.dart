import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

SearchWorkflowController createIdleSearchWorkflowController({
  LyricsClient? lyricsClient,
  AppFilePicker? filePicker,
  AutoFetchUseCase? autoFetchUseCase,
  List<Source> searchSources = const <Source>[Source.qm],
}) {
  final LyricsClient effectiveLyricsClient =
      lyricsClient ?? _UnusedLyricsClient();
  LyricsSavePersistencePort persistenceFactory(String _) =>
      _UnusedLyricsSavePersistence();
  return SearchWorkflowController(
    dependencies: SearchWorkflowDependencies(
      optionsResolver: () => SearchWorkflowOptions(
        defaultSaveDirectory: '',
        fileNameFormat: '%<artist> - %<title>',
        id3Version: Id3Version.v23,
        autoSelect: true,
        translationSource: TranslateSource.bing,
        searchSources: searchSources,
        convertOptions: LyricsConvertOptions(),
        skipInstrumental: true,
      ),
      capabilities: const SearchWorkflowCapabilities(
        multiWindow: false,
        androidSafTreeAccess: false,
        audioTagWrite: false,
      ),
      lyricsApi: effectiveLyricsClient,
      translateApi: _UnusedTranslationClient(),
      mediaGateway: _UnusedMediaGateway(),
      filePicker: filePicker ?? _UnusedFilePicker(),
      dragDropPort: const UnsupportedDragDropPort(),
      androidSafTreePort: _UnusedAndroidSafTreePort(),
      batchSaveUseCase: SearchBatchSaveLyricsUseCase(
        lyricsApi: effectiveLyricsClient,
        persistenceFactory: persistenceFactory,
      ),
      androidSafBatchSaveUseCase: SearchAndroidSafBatchSaveLyricsUseCase(
        lyricsApi: effectiveLyricsClient,
        persistenceFactory: persistenceFactory,
      ),
      fileSavePersistenceFactory: persistenceFactory,
      autoFetchUseCase:
          autoFetchUseCase ??
          AutoFetchUseCase(gateway: _UnusedAutoFetchLyricsGateway()),
    ),
  );
}

final class _UnusedLyricsClient extends Fake implements LyricsClient {}

final class _UnusedTranslationClient extends Fake
    implements TranslationClient {}

final class _UnusedMediaGateway extends Fake
    implements LocalMatchMediaGateway {}

final class _UnusedFilePicker extends Fake implements AppFilePicker {}

final class _UnusedAndroidSafTreePort extends Fake
    implements AndroidSafTreePort {}

final class _UnusedLyricsSavePersistence extends Fake
    implements LyricsSavePersistencePort {}

final class _UnusedAutoFetchLyricsGateway extends Fake
    implements AutoFetchLyricsGateway {}
