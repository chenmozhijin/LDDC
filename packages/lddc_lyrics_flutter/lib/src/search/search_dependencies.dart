import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import '../drag_drop/drag_drop.dart';
import 'search_android_saf_batch_save_lyrics_usecase.dart';
import 'search_batch_save_lyrics_usecase.dart';

/// 搜索工作流需要的平台能力，不暴露宿主的完整能力矩阵。
final class SearchWorkflowCapabilities {
  const SearchWorkflowCapabilities({
    required this.multiWindow,
    required this.androidSafTreeAccess,
    required this.audioTagWrite,
  });

  final bool multiWindow;
  final bool androidSafTreeAccess;
  final bool audioTagWrite;
}

/// 搜索工作流按调用能力读取的配置快照。
final class SearchWorkflowOptions {
  SearchWorkflowOptions({
    required this.defaultSaveDirectory,
    required this.fileNameFormat,
    required this.id3Version,
    required this.autoSelect,
    required this.translationSource,
    required List<Source> searchSources,
    required this.convertOptions,
    required this.skipInstrumental,
  }) : searchSources = List<Source>.unmodifiable(searchSources);

  final String defaultSaveDirectory;
  final String fileNameFormat;
  final Id3Version id3Version;
  final bool autoSelect;
  final TranslateSource translationSource;
  final List<Source> searchSources;
  final LyricsConvertOptions convertOptions;
  final bool skipInstrumental;

  SearchBatchSaveOptions toBatchSaveOptions() {
    return SearchBatchSaveOptions(
      fileNameFormat: fileNameFormat,
      skipInstrumental: skipInstrumental,
      convertOptions: convertOptions,
    );
  }
}

typedef SearchWorkflowOptionsResolver = SearchWorkflowOptions Function();

class SearchWorkflowDependencies {
  const SearchWorkflowDependencies({
    required this.optionsResolver,
    required this.capabilities,
    required this.lyricsApi,
    required this.translateApi,
    required this.mediaGateway,
    required this.filePicker,
    required this.dragDropPort,
    required this.androidSafTreePort,
    required this.batchSaveUseCase,
    required this.androidSafBatchSaveUseCase,
    required this.fileSavePersistenceFactory,
    required this.autoFetchUseCase,
  });

  final SearchWorkflowOptionsResolver optionsResolver;
  final SearchWorkflowCapabilities capabilities;
  final LyricsClient lyricsApi;
  final TranslationClient translateApi;
  final LocalMatchMediaGateway mediaGateway;
  final AppFilePicker filePicker;
  final DragDropPort dragDropPort;
  final AndroidSafTreePort androidSafTreePort;
  final SearchBatchSaveLyricsUseCase batchSaveUseCase;
  final SearchAndroidSafBatchSaveLyricsUseCase androidSafBatchSaveUseCase;
  final SearchLyricsSavePersistenceFactory fileSavePersistenceFactory;
  final AutoFetchUseCase autoFetchUseCase;
}
