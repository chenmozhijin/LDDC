// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => 'Warning';

  @override
  String get commonError => 'Error';

  @override
  String get commonSuccess => 'Success';

  @override
  String get commonFailed => 'Failed';

  @override
  String get commonSkipped => 'Skipped';

  @override
  String get commonTotal => 'Total';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonRestoreDefault => 'Restore Default';

  @override
  String get commonEnabled => 'Enabled';

  @override
  String get commonDisabledByDefault => 'Disabled by default';

  @override
  String get commonFormat => 'Format';

  @override
  String get commonOffset => 'Offset';

  @override
  String get commonSaving => 'Saving...';

  @override
  String get commonAddFiles => 'Add Files';

  @override
  String get commonClearQueue => 'Clear Queue';

  @override
  String get commonUnsupportedOperation =>
      'This operation is not supported on this platform';

  @override
  String get commonLyricsFileUnavailable =>
      'This entry has no lyrics file to open yet';

  @override
  String get commonAudioTagRequiresLrc => 'Song-tag lyrics must use LRC format';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language ($type)';
  }

  @override
  String get commonTranslationCancelled => 'Translation removed';

  @override
  String get commonCancelTranslation => 'Remove Translation';

  @override
  String get commonTranslating => 'Translating...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return 'Translating $completed/$total';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI streaming translation: $completed / $total lines';
  }

  @override
  String get commonTranslationCompleted => 'Translation completed';

  @override
  String get commonLyricsSaved => 'Lyrics saved';

  @override
  String commonDropFailed(String detail) {
    return 'Drop failed: $detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return 'Failed to select save directory: $detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return 'Failed to open save directory: $detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return 'Translation failed: $detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return 'Failed to save lyrics: $detail';
  }

  @override
  String get appErrorUnknown => 'An unknown error occurred.';

  @override
  String get appErrorOperationTimeout =>
      'The operation timed out. Please try again later.';

  @override
  String get appErrorNetworkUnavailable =>
      'Network is unavailable. Please check your connection.';

  @override
  String get appErrorInvalidPayload => 'The data format is invalid.';

  @override
  String get appErrorUnsupportedOperation => 'This operation is not supported.';

  @override
  String get appErrorPermissionDenied =>
      'You do not have permission to perform this operation.';

  @override
  String get appErrorIoFailure => 'File read or write failed.';

  @override
  String get appErrorLyricsRequestFailed => 'Failed to request lyrics.';

  @override
  String get appErrorLyricsNotFound => 'No lyrics found.';

  @override
  String get appErrorLyricsProcessing => 'Failed to process lyrics.';

  @override
  String get appErrorLyricsDecrypt => 'Failed to decrypt lyrics.';

  @override
  String get appErrorLyricsFormatUnsupported => 'Unsupported lyrics format.';

  @override
  String get appErrorDecoding => 'Decoding failed.';

  @override
  String get appErrorSongInfoRead => 'Failed to read song info.';

  @override
  String get appErrorUnsupportedFileType => 'Unsupported file format.';

  @override
  String get appErrorDragDropInvalid => 'Invalid drag-and-drop data.';

  @override
  String get appErrorTranslateFailed => 'Translation failed.';

  @override
  String get appErrorApiParamsInvalid => 'The request parameters are invalid.';

  @override
  String get appErrorApiRequestFailed => 'API request failed.';

  @override
  String get appErrorAutoFetchUnknown =>
      'Automatic matching failed with an unknown error.';

  @override
  String get appErrorNotEnoughInfo => 'Not enough information to search.';

  @override
  String get appErrorIpcInvalidLength => 'The IPC message length is invalid.';

  @override
  String get appErrorIpcUnsupportedTask => 'The IPC task is not supported.';

  @override
  String get appErrorIpcInstanceNotFound => 'The IPC instance does not exist.';

  @override
  String get appErrorIpcPanelNotFound => 'The IPC panel does not exist.';

  @override
  String get appErrorIpcInvalidWindowId => 'The window handle is invalid.';

  @override
  String get appErrorIpcEmbedUnsupported =>
      'Embedded mode is not supported on this platform.';

  @override
  String get appErrorActionRetryNetwork =>
      'Please check the network and try again.';

  @override
  String get appErrorActionCheckPayload =>
      'Please check the input data format.';

  @override
  String get appErrorActionChangeFormat =>
      'Please use a supported file or format.';

  @override
  String get appErrorActionDetachedMode => 'Please fall back to detached mode.';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionViewDetails => 'View details';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get sourceAggregate => 'Aggregate';

  @override
  String get sourceQQMusic => 'QQ Music';

  @override
  String get sourceKugou => 'Kugou Music';

  @override
  String get sourceNetease => 'Netease Music';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => 'Local';

  @override
  String get lyricOriginal => 'Original';

  @override
  String get lyricTranslation => 'Translation';

  @override
  String get lyricRomanized => 'Romanized';

  @override
  String get lyricsFormatVerbatimLrc => 'Word-timed LRC';

  @override
  String get lyricsFormatLineByLineLrc => 'Line-timed LRC';

  @override
  String get lyricsFormatEnhancedLrc => 'Enhanced LRC (ESLyric)';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => 'ASS';

  @override
  String get lyricsTypeVerbatim => 'Word-timed';

  @override
  String get lyricsTypeLineByLine => 'Line-timed';

  @override
  String get lyricsTypePlainText => 'Plain text';

  @override
  String get searchSong => 'Song';

  @override
  String get searchAlbum => 'Album';

  @override
  String get searchSongList => 'Playlist';

  @override
  String get searchArtist => 'Artist';

  @override
  String get searchLyrics => 'Lyrics';

  @override
  String get searchSongId => 'Song ID';

  @override
  String get localMatchIteratingFiles => 'Scanning files...';

  @override
  String get localMatchProgressImportCompleted => 'Import completed';

  @override
  String get localMatchProgressScanCompleted => 'Scan completed';

  @override
  String get localMatchProgressScanFailed => 'Scan failed';

  @override
  String get localMatchProgressMatchCompleted => 'Match completed';

  @override
  String get localMatchProgressMatchFailed => 'Match failed';

  @override
  String get localMatchProgressPreparingMatch => 'Preparing to match...';

  @override
  String get localMatchPreviewTagOnly => 'Write tags only';

  @override
  String get localMatchPreviewWriteTag => 'Write to tags';

  @override
  String get localMatchPreviewNoOutput => 'No output configured';

  @override
  String get localMatchPreviewSongTagOnly => 'Song tags only';

  @override
  String get localMatchPendingLyricsFileName =>
      'Waiting for matched lyrics info to determine the file name';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / waiting for matched lyrics info to determine the file name';
  }

  @override
  String get localMatchCalcSavePathFailed => 'Failed to calculate save path';

  @override
  String get localMatchNoticeBusyImportFiles =>
      'A task is running, so files cannot be imported now';

  @override
  String get localMatchNoticeSelectedFilesUnavailable =>
      'The selected files are unavailable';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return 'Failed to import files: $detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories =>
      'A task is running, so directories cannot be imported now';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return 'Failed to import directories: $detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles =>
      'The dropped data contains no accessible files';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return 'Failed to resolve dropped song: $detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors =>
      'Import completed, but some entries could not be parsed';

  @override
  String get localMatchNoticeSafTreeUnsupported =>
      'Directory tree access is not supported on this platform';

  @override
  String get localMatchNoticeBusySwitchTree =>
      'A task is running, so the directory tree cannot be changed now';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return 'Failed to select directory tree: $detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue =>
      'A task is running, so the queue cannot be cleared now';

  @override
  String get localMatchNoticeSelectItemsToDelete =>
      'Select entries to delete first';

  @override
  String get localMatchNoticeSelectItemsToSetRoot =>
      'Select entries before setting a root directory';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return 'These songs are outside the selected root and were skipped: $detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return 'Failed to set root directory: $detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore =>
      'Select entries to restore first';

  @override
  String get localMatchNoticeCancelling => 'Cancelling current task...';

  @override
  String get localMatchNoticeValidationFailed =>
      'Resolve the local match requirements first';

  @override
  String get localMatchNoticeSongDirectoryUnavailable =>
      'This entry cannot open a song directory';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return 'Failed to open song directory: $detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable =>
      'This entry has no save directory to open yet';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return 'Failed to open lyrics: $detail';
  }

  @override
  String get localMatchNoticeScanCancelled => 'Scan cancelled';

  @override
  String get localMatchNoticeScanCompletedWithErrors =>
      'Scan completed, but some files could not be parsed';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return 'Scan failed: $detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return 'Directory tree scan failed: $detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => 'Match cancelled';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '$total songs total, $success matched, $failed failed, $skipped skipped.';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return 'Local match failed: $detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume =>
      'Match cancelled. Start again to resume from the checkpoint';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF local match failed: $detail';
  }

  @override
  String get localMatchValidationEmptyLangs =>
      'Select lyrics languages to match';

  @override
  String get localMatchValidationEmptySources => 'Select at least one source';

  @override
  String get localMatchValidationEmptyQueue => 'Import songs to match first';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      'When skipping existing lyrics while also saving files, the file name mode cannot use matched lyrics info';

  @override
  String get localMatchValidationMissingAndroidTree =>
      'Select a directory tree first';

  @override
  String get localMatchValidationNeedsSaveRoot => 'A save path is required';

  @override
  String get localMatchValidationNeedsSongRoot =>
      'A song root directory is required';

  @override
  String get localMatchValidationUnknownSavePath => 'Unknown save path error';

  @override
  String get localMatchIntro =>
      'Import local songs or folders, preview the output, then run batch matching.';

  @override
  String get localMatchDropUnsupportedItem =>
      'Local match accepts song files, folders, or parseable player items';

  @override
  String get localMatchReadyToStart => 'Ready to start local matching';

  @override
  String get localMatchQueueTitle => 'Task Queue';

  @override
  String get localMatchQueueEmptyHint =>
      'Import files or folders to build the task queue';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '$count tasks. Right-click a row for more actions';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '$count tasks. Long-press or tap more to open actions';
  }

  @override
  String get localMatchImportAndRunTitle => 'Import And Run';

  @override
  String get localMatchActionStart => 'Start Matching';

  @override
  String get localMatchActionAddFolders => 'Add Folders';

  @override
  String get localMatchActionSelectSaveRoot => 'Select Save Root';

  @override
  String get localMatchActionSelectTree => 'Select Tree';

  @override
  String get localMatchActionReselectTree => 'Reselect Tree';

  @override
  String get localMatchActionBulkSelect => 'Bulk Select';

  @override
  String get localMatchActionExitSelection => 'Exit bulk selection';

  @override
  String get localMatchActionSelectAll => 'Select All';

  @override
  String get localMatchActionDeselectAll => 'Deselect All';

  @override
  String get localMatchActionSetRoot => 'Set Root';

  @override
  String localMatchSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get localMatchBulkActionHint =>
      'Bulk actions apply directly to the selected tasks';

  @override
  String get localMatchPhaseIdle => 'Waiting';

  @override
  String get localMatchPhaseScanning => 'Scanning';

  @override
  String get localMatchPhaseMatching => 'Matching';

  @override
  String get localMatchPhaseWriting => 'Writing';

  @override
  String get localMatchPhaseCompleted => 'Completed';

  @override
  String get localMatchPhaseHintIdle => 'Import songs to start matching';

  @override
  String get localMatchPhaseHintScanning =>
      'Building the task queue and estimating output';

  @override
  String get localMatchPhaseHintMatching =>
      'Querying sources and calculating the best match';

  @override
  String get localMatchPhaseHintWriting => 'Writing lyrics files or song tags';

  @override
  String get localMatchPhaseHintCompleted =>
      'This run is complete. Adjust and run again if needed';

  @override
  String get localMatchPipelineIdle => 'Scan -> Match -> Write';

  @override
  String get localMatchPipelineScanning => 'Current stage: scan';

  @override
  String get localMatchPipelineMatching => 'Current stage: match';

  @override
  String get localMatchPipelineWriting => 'Current stage: write';

  @override
  String get localMatchPipelineCompleted => 'Scan, match, and write completed';

  @override
  String get localMatchUnknownSong => 'Unknown Song';

  @override
  String get localMatchUnknownDuration => 'Unknown Duration';

  @override
  String get localMatchStatusNotStarted => 'Not Started';

  @override
  String get localMatchSongPathLabel => 'Song Path';

  @override
  String get localMatchLyricsPathLabel => 'Lyrics Save Path';

  @override
  String get localMatchExpandDetails => 'Expand details';

  @override
  String get localMatchCollapseDetails => 'Collapse details';

  @override
  String get localMatchRowActionOpenInSearch => 'Open In Search';

  @override
  String get localMatchRowActionEnterSelection => 'Enter Bulk Selection';

  @override
  String get localMatchRowActionOpenSongDirectory => 'Open Song Folder';

  @override
  String get localMatchRowActionOpenSaveDirectory => 'Open Save Folder';

  @override
  String get localMatchRowActionOpenLyrics => 'Open Lyrics';

  @override
  String get localMatchFieldLyricsType => 'Lyrics Type';

  @override
  String get localMatchFieldOutputStrategy => 'Output Strategy';

  @override
  String get localMatchFieldSaveMode => 'Save Mode';

  @override
  String get localMatchFieldFileNameMode => 'File Name Mode';

  @override
  String get localMatchFieldLyricsFormat => 'Lyrics Format';

  @override
  String get localMatchFieldThreshold => 'Match Threshold';

  @override
  String get localMatchFieldSaveRoot => 'Save Root';

  @override
  String get localMatchMoreSettings => 'More Settings';

  @override
  String get localMatchRulesTitle => 'Match Rules';

  @override
  String get localMatchRulesSubtitle =>
      'Sources, languages, output strategy, and threshold';

  @override
  String get localMatchMinScore => 'Minimum Score';

  @override
  String get localMatchSkipExisting => 'Skip Existing Lyrics';

  @override
  String get localMatchSkipExistingConflictHint =>
      'The current output strategy and file-name mode cannot skip existing lyrics. If files still need to be saved, avoid naming by matched lyrics info.';

  @override
  String get localMatchSaveToSongDirectoryHint =>
      'Saving to the song folder does not need an extra save root.';

  @override
  String get localMatchAndroidTreeSaveHint =>
      'Android directory tree saves are written directly into the authorized tree.';

  @override
  String get localMatchFileNameTemplateHint =>
      'The file name template uses lyrics_file_name_fmt from Settings.';

  @override
  String localMatchSaveRootPath(String path) {
    return 'Save root: $path';
  }

  @override
  String get localMatchSaveRootRequired =>
      'This save mode needs a save root. Select one first.';

  @override
  String get localMatchTreeNotSelected => 'No directory tree selected';

  @override
  String get localMatchSaveModeSong => 'Save To Song Folder';

  @override
  String get localMatchSaveModeMirror => 'Mirror Folders';

  @override
  String get localMatchSaveModeSpecify => 'Specific Folder';

  @override
  String get localMatchFileNameModeSong => 'Use Song File Name';

  @override
  String get localMatchFileNameModeFormatBySong => 'Name By Song Info';

  @override
  String get localMatchFileNameModeFormatByLyrics => 'Name By Lyrics Info';

  @override
  String get localMatchFileNameHintSong =>
      'Reuse the audio file name and only replace the lyrics extension.';

  @override
  String get localMatchFileNameHintFormatBySong =>
      'Generate the file name from song metadata such as title, artist, and album.';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      'Generate the file name from the matched lyrics song info; it may be unknown before matching.';

  @override
  String get localMatchSaveToTagOnlyFile => 'File Only';

  @override
  String get localMatchSaveToTagOnlyTag => 'Tag Only';

  @override
  String get localMatchSaveToTagBoth => 'File + Tag';

  @override
  String get localMatchValidationTitle => 'Issues to fix before starting';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '$count more issues need to be fixed';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable =>
      'The selected files are not directly accessible';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return 'Imported $count lyrics files';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles =>
      'The dropped data contains no accessible lyrics files';

  @override
  String get batchConvertNoticeEmptyQueue =>
      'Add lyrics files to convert first';

  @override
  String get batchConvertNoticeOverwriteCancelled =>
      'Batch conversion cancelled';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return 'Batch conversion cancelled, $count items completed';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return 'Batch conversion completed: $success succeeded, $failure failed';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return 'Batch conversion completed: $count items';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return 'Batch conversion failed: $detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return 'Failed to open source directory: $detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return 'Failed to open lyrics file: $detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles =>
      'No supported lyrics files were found in the selected folder';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return 'Imported $count lyrics files from folder';
  }

  @override
  String get batchConvertNoticeDuplicateItems =>
      'All selected entries are already in the queue';

  @override
  String get batchConvertControlsTitle => 'Import & Settings';

  @override
  String get batchConvertCompactControlsTitle => 'Import & Output Settings';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return 'Format: $format';
  }

  @override
  String get batchConvertImportTitle => 'Import';

  @override
  String get batchConvertAddFolders => 'Add Folder';

  @override
  String get batchConvertOutputSettingsTitle => 'Output Settings';

  @override
  String get batchConvertTargetFormat => 'Target Format';

  @override
  String get batchConvertSaveDirectoryTitle => 'Save Folder';

  @override
  String get batchConvertSaveDirectoryDefault =>
      'When unset, output goes next to the source lyrics file';

  @override
  String get batchConvertSelectSaveDirectory => 'Choose Save Folder';

  @override
  String get batchConvertRestoreOriginalDirectory => 'Use Source Folder';

  @override
  String get batchConvertRecursiveTitle => 'Scan Subfolders';

  @override
  String get batchConvertRecursiveSubtitle =>
      'When importing a folder, continue scanning lyrics files in subfolders';

  @override
  String get batchConvertStart => 'Start Conversion';

  @override
  String get batchConvertCancel => 'Cancel Conversion';

  @override
  String get batchConvertQueueTitle => 'Conversion Queue';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '$count items, output format $format';
  }

  @override
  String get batchConvertPageErrorFallback =>
      'The batch conversion page encountered an error';

  @override
  String get batchConvertRetryImport => 'Import Again';

  @override
  String get batchConvertEmptyQueue =>
      'Add lyrics files or folders and the batch conversion queue will appear here.';

  @override
  String get batchConvertOutputPathLabel => 'Output Path';

  @override
  String get batchConvertQueueStatusWaiting => 'Waiting';

  @override
  String get batchConvertQueueStatusRunning => 'Converting';

  @override
  String get batchConvertQueueStatusSuccess => 'Converted';

  @override
  String get batchConvertQueueStatusFailure => 'Failed';

  @override
  String get batchConvertMoreActions => 'More Actions';

  @override
  String get batchConvertActionOpenSourceDirectory => 'Open Source Folder';

  @override
  String get batchConvertActionOpenSaveDirectory => 'Open Save Folder';

  @override
  String get batchConvertActionOpenOutputFile => 'Open Lyrics File';

  @override
  String get batchConvertActionOpenInOpenLyrics => 'Open in Open Lyrics';

  @override
  String get batchConvertPhaseIdle => 'Waiting';

  @override
  String get batchConvertPhaseScanning => 'Scanning';

  @override
  String get batchConvertPhaseRunning => 'Converting';

  @override
  String get batchConvertPhaseCompleted => 'Completed';

  @override
  String get batchConvertPipelineIdle => 'Import -> Scan -> Convert -> Finish';

  @override
  String get batchConvertPipelineScanning => 'Scan folders -> Build queue';

  @override
  String get batchConvertPipelineRunning =>
      'Convert each item -> Update status';

  @override
  String get batchConvertPipelineCompleted => 'Adjust format or import again';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return 'Cancelled, $success succeeded, $failure failed';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '$success succeeded, $failure failed';
  }

  @override
  String get batchConvertHintNoQueue =>
      'Add files or folders to start converting';

  @override
  String get batchConvertHintReady => 'The queue is ready';

  @override
  String get batchConvertMetricWaiting => 'Waiting';

  @override
  String get batchConvertDropUnsupported =>
      'The batch conversion page accepts only lyrics files or folders';

  @override
  String batchConvertDropFailed(String detail) {
    return 'Failed to process drop: $detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return 'Converting $fileName';
  }

  @override
  String get batchConvertProgressItemSuccess => 'Converted';

  @override
  String get batchConvertProgressItemFailure => 'Failed';

  @override
  String get batchConvertProgressPreparingConversion =>
      'Preparing conversion...';

  @override
  String get batchConvertProgressCancellingConversion =>
      'Cancelling conversion...';

  @override
  String get batchConvertProgressConversionCancelled => 'Conversion cancelled';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return 'Conversion completed: $success succeeded, $failure failed';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return 'Conversion failed: $detail';
  }

  @override
  String get batchConvertProgressScanningFolders => 'Scanning folders...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return 'Scanning $directoryName';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return 'Found $count lyrics files';
  }

  @override
  String get batchConvertProgressScanCancelled => 'Scan cancelled';

  @override
  String get batchConvertProgressScanNoSupportedFiles =>
      'No supported lyrics files found';

  @override
  String get batchConvertProgressScanCompleted => 'Scan completed';

  @override
  String get navSearch => 'Search';

  @override
  String get navLocalMatch => 'Local Match';

  @override
  String get navOpenLyrics => 'Open Lyrics';

  @override
  String get navBatchConvert => 'Batch Convert';

  @override
  String get navSettings => 'Settings';

  @override
  String get navAbout => 'About';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSource => 'Source';

  @override
  String get searchKeywordHint => 'Input keyword';

  @override
  String get uiLoading => 'Loading...';

  @override
  String get uiLoadingStepFetching => 'Fetching list and preview...';

  @override
  String get uiEmpty => 'No data';

  @override
  String get uiNoMoreResult => 'No more results';

  @override
  String get searchInitialResultTitle => 'Enter keywords to start searching';

  @override
  String get searchInitialResultDescription =>
      'Choose a source above and run a search';

  @override
  String get searchResultTitle => 'Search Results';

  @override
  String get searchResultReturn => 'Back';

  @override
  String get searchPreviewTitle => 'Lyrics Preview';

  @override
  String get searchPreviewLangsLabel => 'Languages';

  @override
  String get searchPreviewSongIdLabel => 'Song ID';

  @override
  String get searchPreviewPlaceholder => 'Select a song or lyric item first';

  @override
  String get searchPreviewNoLanguage => 'Select at least one lyric language';

  @override
  String get searchPreviewNoContent => 'No previewable content is available';

  @override
  String get searchPreviewLoading => 'Loading lyrics...';

  @override
  String get searchFormatLabel => 'Lyrics Format';

  @override
  String get searchTranslateLyrics => 'Translate Lyrics';

  @override
  String get searchResizeWorkspacePanes =>
      'Resize search results and lyrics preview';

  @override
  String get searchSavePreviewToDirectory => 'Save to Folder';

  @override
  String get searchSavePreviewToFile => 'Save to File';

  @override
  String get searchSavePreviewToTag => 'Save Preview to Tag';

  @override
  String get searchSaveListLyrics => 'Save Album/Playlist Lyrics';

  @override
  String get searchSaveListLyricsCancel => 'Cancel Batch Save';

  @override
  String get searchSelectSavePath => 'Choose Save Folder';

  @override
  String get searchBatchSaveProgressTitle => 'Batch Save Progress';

  @override
  String get searchBatchSaveProgressPreparing => 'Preparing batch save...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return 'Fetching lyrics for $songName...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count songs';
  }

  @override
  String get searchTableStatusAutoFetching => 'Auto fetching...';

  @override
  String get searchTableStatusSearching => 'Searching...';

  @override
  String get searchTableStatusFetchingSongList => 'Fetching song list...';

  @override
  String get searchTableStatusNoResults => 'No matching results found';

  @override
  String get searchTableStatusEmptyList => 'The list is empty';

  @override
  String get searchTableStatusUnsupportedSearchType =>
      'The selected source does not support this search type';

  @override
  String get searchTableStatusSearchFailed => 'Search failed';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return 'Search failed: $detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return 'Auto fetch failed: $detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return 'Failed to fetch song list: $detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable =>
      'Some sources are unavailable. Showing available results';

  @override
  String get searchTableStatusLoadMoreFailed =>
      'Some sources failed to load more results';

  @override
  String get searchSourceFailureDetailsTitle => 'Search error details';

  @override
  String get searchSourceFailureRequest => 'Request failed';

  @override
  String get searchSourceFailureTimeout => 'Request timed out';

  @override
  String get searchSourceFailureParameters => 'Invalid parameters';

  @override
  String get searchSourceFailureUnsupported => 'Unsupported operation';

  @override
  String get searchSourceFailureUnknown => 'Unknown error';

  @override
  String get searchResultLoadingMore => 'Loading more results...';

  @override
  String get searchResultLoadMoreFailed =>
      'Auto load failed. Retry to continue loading remaining results';

  @override
  String get searchResultScrollForMore =>
      'Scroll down to automatically load more results';

  @override
  String get tableSavePath => 'Save Path';

  @override
  String get settingsSectionSave => 'Save';

  @override
  String get settingsSectionLyrics => 'Lyrics';

  @override
  String get settingsSectionDesktopLyrics => 'Desktop Lyrics';

  @override
  String get settingsSectionTranslate => 'Translate';

  @override
  String get settingsSectionSearch => 'Search';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionTools => 'Tools And Data';

  @override
  String get settingsSectionSaveSummary =>
      'Save paths, file name template, and ID3 version';

  @override
  String get settingsSectionSearchSummary =>
      'Choose the default lyric sources for Aggregate search and local matching.';

  @override
  String get settingsSectionDesktopLyricsSummary =>
      'Desktop lyrics auto-fetch, display languages, appearance, and refresh rate.';

  @override
  String get settingsSectionLyricsSummary =>
      'Local matching behavior and lyrics file export format.';

  @override
  String get settingsSectionTranslateSummary =>
      'Translation source, target language, and conditional fields';

  @override
  String get settingsSectionAppSummary =>
      'Language, theme, logs, and update policy';

  @override
  String get settingsSectionToolsSummary =>
      'Desktop tools, log folder, and cache cleanup';

  @override
  String get settingsTranslateSourceBing => 'Bing Translate';

  @override
  String get settingsTranslateSourceGoogle => 'Google Translate';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI-compatible API';

  @override
  String get settingsLangSimplifiedChinese => 'Simplified Chinese';

  @override
  String get settingsLangTraditionalChinese => 'Traditional Chinese';

  @override
  String get settingsLangEnglish => 'English';

  @override
  String get settingsLangJapanese => 'Japanese';

  @override
  String get settingsLangKorean => 'Korean';

  @override
  String get settingsLangSpanish => 'Spanish';

  @override
  String get settingsLangFrench => 'French';

  @override
  String get settingsLangPortuguese => 'Portuguese';

  @override
  String get settingsLangGerman => 'German';

  @override
  String get settingsLangRussian => 'Russian';

  @override
  String get settingsAppLanguageAuto => 'Auto';

  @override
  String get settingsColorSchemeAuto => 'Follow System';

  @override
  String get settingsColorSchemeLight => 'Light';

  @override
  String get settingsColorSchemeDark => 'Dark';

  @override
  String get settingsDesktopGradientColors => 'Gradient Colors';

  @override
  String get settingsDesktopPlayedColors => 'Played Colors';

  @override
  String get settingsDesktopUnplayedColors => 'Unplayed Colors';

  @override
  String get settingsAddColor => 'Add Color';

  @override
  String get settingsEditColor => 'Edit Color';

  @override
  String get settingsDeleteColor => 'Delete Color';

  @override
  String get settingsBackToSections => 'Back To Setting Sections';

  @override
  String get settingsAvailablePlaceholders => 'Available Placeholders';

  @override
  String get settingsPlaceholderTitleArtist =>
      'Title: %<title>    Artist: %<artist>';

  @override
  String get settingsPlaceholderAlbumId =>
      'Album: %<album>    Song/Lyrics id: %<id>';

  @override
  String get settingsPlaceholderLangs => 'Language types: %<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return 'Current template: $template';
  }

  @override
  String get settingsTranslateSourceLabel => 'Translation Source';

  @override
  String get settingsTranslateTargetLabel => 'Target Language';

  @override
  String get settingsOpenAiProfileLabel => 'Preset';

  @override
  String get settingsOpenAiProfileHelper =>
      'Built-in providers fill the Base URL automatically. You still need to configure the API Key and model.';

  @override
  String get settingsAppLanguageLabel => 'Interface Language';

  @override
  String get settingsColorSchemeLabel => 'Theme Mode';

  @override
  String get settingsLogLevelLabel => 'Log Level';

  @override
  String get settingsLogLevelHelper =>
      'Keep INFO for normal use. TRACE and DEBUG record more detail and create larger logs.';

  @override
  String get settingsAutoCheckUpdateLabel => 'Auto Check Updates';

  @override
  String get settingsRestoreDefaultsWarning =>
      'Restoring defaults writes the config immediately. Please confirm before continuing.';

  @override
  String get settingsRestoreAllTitle => 'Restore Default Settings';

  @override
  String get settingsRestoreAllContent =>
      'This restores all settings and writes them to the config immediately.';

  @override
  String get settingsRestoreAllAction => 'Restore Default Settings';

  @override
  String get settingsOpenAssociationManager =>
      'Open Lyrics Association Manager';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      'Open the next settings page to manage song and lyrics associations.';

  @override
  String get settingsOpenLogDirectory => 'Open Log Directory';

  @override
  String get settingsOpenLogDirectorySubtitle =>
      'View runtime logs and troubleshooting files.';

  @override
  String get settingsClearCache => 'Clear Cache';

  @override
  String get settingsClearCacheSubtitle =>
      'Clear search and translation cache without changing config files.';

  @override
  String get settingsClearCacheContent =>
      'After clearing cache, later searches and translations may request data again.';

  @override
  String get settingsRestoreSectionTitle => 'Restore This Section';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return 'Only settings in the “$sectionTitle” section will be restored. Other sections will not change.';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return 'Restore defaults for $sectionTitle';
  }

  @override
  String get settingsDefaultSavePathHelper =>
      'Leave empty to use the platform default Music directory.';

  @override
  String get settingsChooseFolder => 'Choose Folder';

  @override
  String get settingsLyricsFileNameFormat => 'Lyrics File Name Template';

  @override
  String get settingsLyricsFileNameFormatHelper =>
      'Use the placeholders below to compose saved file names.';

  @override
  String get settingsId3Version => 'ID3 Version';

  @override
  String get settingsId3VersionHelper =>
      'Only affects lyrics written to audio tags. Keep v2.3 if you are unsure.';

  @override
  String get settingsSearchSourcesTitle => 'Aggregate Search Sources';

  @override
  String get settingsSearchSourcesDescription =>
      'Checked sources are queried when Search uses Aggregate. Sources higher in the list rank first for result grouping and automatic matching. Local Match uses this list by default.';

  @override
  String get settingsReorderPriorityHint => 'Drag to change priority';

  @override
  String get settingsReorderOrderHint => 'Drag to change order';

  @override
  String get settingsDefaultLanguage => 'Default Display Languages';

  @override
  String get settingsDefaultLanguageDescription =>
      'Select the languages shown by default in desktop lyrics, then drag to change their display order.';

  @override
  String get settingsDesktopAutoFetchSources => 'Auto-fetch Sources';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      'When desktop lyrics has no linked lyrics, sources are tried from top to bottom.';

  @override
  String get settingsFont => 'Font';

  @override
  String get settingsFollowSystemFont => 'Follow System Font';

  @override
  String get settingsFontSizeByResize =>
      'Resize the desktop lyrics window to adjust its main font size.';

  @override
  String get settingsPanelFontSize => 'Lyrics Panel Font Size';

  @override
  String get settingsAdaptiveRefreshRate => 'Adaptive Refresh Rate';

  @override
  String get settingsAdaptiveRefreshRateSubtitle =>
      'Automatically choose the refresh cadence based on lyrics animation state.';

  @override
  String get settingsFixedRefreshRate => 'Fixed Refresh Rate';

  @override
  String get settingsShowFurigana => 'Show Furigana';

  @override
  String get settingsLyricsMatchBehavior => 'Matching Behavior';

  @override
  String get settingsLyricsMatchBehaviorDescription =>
      'Set the default handling for local matching and Kugou lyric candidates.';

  @override
  String get settingsLyricsExport => 'LRC Export';

  @override
  String get settingsLyricsExportDescription =>
      'Set the language order and LRC timestamp format used when saving lyrics files.';

  @override
  String get settingsDisplayOrder => 'Export Language Order';

  @override
  String get settingsDisplayOrderDescription =>
      'Drag to arrange original, translated, and romanized lyrics in exported files.';

  @override
  String get settingsSkipInstrumental => 'Skip Instrumental Tracks';

  @override
  String get settingsSkipInstrumentalSubtitle =>
      'Do not save lyrics when Local Match identifies an instrumental track.';

  @override
  String get settingsAutoSelectKugou => 'Auto Select Kugou Candidate';

  @override
  String get settingsAutoSelectKugouSubtitle =>
      'Automatically choose the best lyric candidate when opening a Kugou song in Search.';

  @override
  String get settingsAddLrcEndTimestamp =>
      'Add End Timestamp When Exporting LRC';

  @override
  String get settingsAddLrcEndTimestampSubtitle =>
      'Only affects line-by-line LRC and writes line end timestamps when needed.';

  @override
  String get settingsMillisecondsDigits => 'Millisecond Digits';

  @override
  String get settingsMillisecondsDigitsHelper =>
      'Use two digits for centiseconds or three digits to keep full milliseconds.';

  @override
  String settingsDigitsValue(int value) {
    return '$value digits';
  }

  @override
  String get settingsLastRefStyle => 'Last Language Line Timestamp';

  @override
  String get settingsLastRefStyleHelper =>
      'For multi-language line-by-line LRC, use the current line time or one millisecond before the next line for the last language line.';

  @override
  String get settingsLastRefCurrentLine => 'Use Current Line Time';

  @override
  String get settingsLastRefNextLine => 'Use One Millisecond Before Next Line';

  @override
  String get settingsTagInfoSource => 'Tag Info Source';

  @override
  String get settingsTagInfoLyricsSource => 'Lyrics Source';

  @override
  String get settingsTagInfoSongInfo => 'Song Info';

  @override
  String get settingsNoticeDefaultSavePathUpdated =>
      'Default save path updated';

  @override
  String get settingsNoticeDefaultSavePathRestored =>
      'Default save path restored';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated =>
      'Lyrics file name template updated';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3 version updated';

  @override
  String get settingsNoticeLyricsLangOrderEmpty =>
      'Lyrics language order cannot be empty';

  @override
  String get settingsNoticeLyricsLangOrderUpdated =>
      'Lyrics language order updated';

  @override
  String get settingsNoticeSkipInstUpdated =>
      'Instrumental skip policy updated';

  @override
  String get settingsNoticeAutoSelectUpdated => 'Auto select policy updated';

  @override
  String get settingsNoticeAddEndTimestampUpdated =>
      'End timestamp policy updated';

  @override
  String get settingsNoticeMsDigitsUpdated => 'Millisecond digits updated';

  @override
  String get settingsNoticeLastRefStyleUpdated =>
      'Last line time style updated';

  @override
  String get settingsNoticeTagInfoSourceUpdated => 'Tag info source updated';

  @override
  String get settingsNoticeDesktopSourcesEmpty =>
      'Desktop lyrics sources cannot be empty';

  @override
  String get settingsNoticeDesktopSourcesUpdated =>
      'Desktop lyrics sources updated';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty =>
      'Desktop default languages cannot be empty';

  @override
  String get settingsNoticeDesktopLangsUpdated =>
      'Desktop lyrics language settings updated';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated =>
      'Desktop lyrics font updated';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => 'Refresh rate updated';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated =>
      'Played colors updated';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated =>
      'Unplayed colors updated';

  @override
  String get settingsNoticeDesktopFontSizeUpdated =>
      'Desktop lyrics font size updated';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated =>
      'Desktop panel font size updated';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated =>
      'Furigana display policy updated';

  @override
  String get settingsNoticeTranslateSourceUpdated =>
      'Translation source updated';

  @override
  String get settingsNoticeTranslateTargetLangUpdated =>
      'Translation target language updated';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI preset updated';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI Base URL updated';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI API Key updated';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI model updated';

  @override
  String get settingsNoticeSearchSourcesEmpty =>
      'Aggregate search sources cannot be empty';

  @override
  String get settingsNoticeSearchSourcesUpdated =>
      'Aggregate search sources updated';

  @override
  String get settingsNoticeAppLanguageUpdated => 'Interface language updated';

  @override
  String get settingsNoticeAppColorSchemeUpdated => 'Theme mode updated';

  @override
  String get settingsNoticeAppLogLevelUpdated => 'Log level updated';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated =>
      'Auto check updates setting updated';

  @override
  String get settingsNoticeSectionNoRestorableConfig =>
      'This section has no restorable config items';

  @override
  String get settingsNoticeSectionDefaultsRestored =>
      'Current section defaults restored';

  @override
  String get settingsNoticeAllDefaultsRestored =>
      'Application settings restored to defaults';

  @override
  String get settingsNoticeAssociationManagerOpened =>
      'Lyrics association manager opened';

  @override
  String get settingsNoticeLogDirectoryOpened => 'Log directory opened';

  @override
  String get settingsNoticeLogDirectoryOpenFailed =>
      'Failed to open log directory';

  @override
  String get settingsNoticeCacheCleared => 'Cache cleared';

  @override
  String get settingsNoticeCacheClearFailed => 'Failed to clear cache';

  @override
  String get settingsNoticeConfigWriteFailed => 'Failed to write settings';

  @override
  String get settingsCurrentSavePathLabel => 'Default Save Path';

  @override
  String get aboutLoadFailed => 'Failed to load about metadata.';

  @override
  String get aboutActionOpenRepository => 'GitHub Repo';

  @override
  String get aboutActionCheckUpdate => 'Check Update';

  @override
  String get aboutHeroHeadline => 'Built for precise lyrics';

  @override
  String get aboutHeroDescription =>
      'LDDC brings search, conversion, desktop lyrics, and batch workflows into one efficient surface so finding, organizing, and using lyrics stays fast and focused.';

  @override
  String get aboutLinksSectionTitle => 'Quick Links';

  @override
  String get aboutLinksSectionDescription =>
      'Use these links when you want feedback channels, release notes, or license details.';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return 'Copyright (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return 'Licensed under $license.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub Repository';

  @override
  String get aboutLinkIssueTrackerTitle => 'Issue Tracker';

  @override
  String get aboutLinkIssueTrackerDescription =>
      'Report bugs, UX gaps, and feature requests.';

  @override
  String get aboutLinkLicenseTitle => 'License';

  @override
  String get aboutLinkLicenseDescription =>
      'Review the current open source license:';

  @override
  String get aboutLinkChangelogTitle => 'Release Notes';

  @override
  String get aboutLinkChangelogDescription =>
      'See published versions and their change summaries.';

  @override
  String get aboutExternalLinksUnavailable =>
      'Opening external links is not supported on this platform.';

  @override
  String get aboutCheckUpdateUnavailable =>
      'Checking for updates is not supported on this platform.';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes =>
      'Opened the release notes page.';

  @override
  String get aboutCheckUpdateUpToDate =>
      'You are already on the latest version.';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return 'New version found: $version. Open the release notes page for details.';
  }

  @override
  String get aboutCheckUpdateFailed =>
      'Failed to check for updates. Please try again later.';

  @override
  String aboutActionOpenedLink(String title) {
    return 'Opened $title';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return 'Failed to open $title';
  }

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get libraryLinkManagerTitle => 'Lyrics Association Manager';

  @override
  String get libraryLinkManagerReturnToSettings => 'Back to Settings';

  @override
  String get libraryLinkManagerRefresh => 'Refresh';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return 'Delete Selected ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => 'Delete All';

  @override
  String get libraryLinkManagerClearInvalid => 'Clear Invalid Data';

  @override
  String get libraryLinkManagerChangeDirectory => 'Batch Change Directory';

  @override
  String get libraryLinkManagerBackupToJson => 'Backup to JSON';

  @override
  String get libraryLinkManagerRestoreFromJson => 'Restore from JSON';

  @override
  String get libraryLinkManagerRestoreAction => 'Restore';

  @override
  String get libraryLinkManagerExportLyrics => 'Export Lyrics';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '$totalCount records · $selectedCount selected';
  }

  @override
  String get libraryLinkManagerSearchHint =>
      'Search songs, artists, albums, or paths';

  @override
  String get libraryLinkManagerClearSearch => 'Clear search';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '$totalCount matches · $selectedCount selected';
  }

  @override
  String get libraryLinkManagerEmpty => 'No lyrics link records';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return 'Failed to load lyrics link records: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess =>
      'Deleted selected lyrics links';

  @override
  String get libraryLinkManagerDeleteAllConfirm =>
      'Are you sure you want to delete all lyrics link records?';

  @override
  String get libraryLinkManagerDeleteAllSuccess =>
      'Deleted all lyrics link records';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return 'Cleared $count invalid records';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return 'Updated $count records after directory rewrite';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return 'Lyrics link data backed up to $path';
  }

  @override
  String get libraryLinkManagerRestoreConfirm =>
      'Restoring will overwrite all current lyrics link records. Continue?';

  @override
  String get libraryLinkManagerRestoreSuccess => 'Lyrics link data restored';

  @override
  String get libraryLinkManagerInvalidBackupFormat =>
      'Invalid backup file format';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return 'Exported $count lyric files';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => 'Untitled Song';

  @override
  String get libraryLinkManagerUnknownArtist => 'Unknown Artist';

  @override
  String get libraryLinkManagerUnknownAlbum => 'Unknown Album';

  @override
  String get libraryLinkManagerSongPathLabel => 'Song Path';

  @override
  String get libraryLinkManagerSongPathEmpty => 'No song path recorded';

  @override
  String get libraryLinkManagerLyricsPathLabel => 'Lyrics Path';

  @override
  String get libraryLinkManagerLyricsPathEmpty => 'No lyrics linked';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return 'Track $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return 'Track number: $track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => 'None';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return 'Offset $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return 'Lyric offset: $offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return 'Languages $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return 'Lyrics languages: $langs';
  }

  @override
  String get libraryLinkManagerInstrumental => 'Instrumental';

  @override
  String get libraryLinkManagerInstrumentalTooltip =>
      'This song is marked as instrumental';

  @override
  String get libraryLinkManagerDisableAutoSearch => 'Disable Auto Search';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip =>
      'Auto search is disabled for this song';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return 'Other Config $count';
  }

  @override
  String get libraryLinkManagerDefaultConfig => 'Default Config';

  @override
  String get libraryLinkManagerDefaultConfigTooltip =>
      'No song-level override config is saved for this record';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return 'Open failed: $detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable =>
      'The lyrics file is unavailable';

  @override
  String get openLyricsNoticeSongFileUnavailable =>
      'The song file is unavailable';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics =>
      'No readable embedded lyrics were found in this song';

  @override
  String get openLyricsNoticeAlreadyConverted =>
      'These lyrics have already been converted';

  @override
  String get openLyricsNoticeEmptyLyrics => 'Lyrics content cannot be empty';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return 'Conversion failed: $detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => 'Convert the lyrics first';

  @override
  String get openLyricsNoticeNoLyricsToSave => 'There are no lyrics to save';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return 'Lyrics saved: $detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return 'Save failed: $detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => 'Open a song file first';

  @override
  String get openLyricsNoticeAudioTagUnsupported =>
      'This platform cannot write song tags';

  @override
  String get openLyricsDropUnsupportedItem =>
      'Open Lyrics accepts lyrics files or audio files';

  @override
  String get openLyricsPreviewTitle => 'Preview';

  @override
  String get openLyricsPreviewRawText => 'Raw Text';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return 'Lyrics languages · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => 'Not Loaded';

  @override
  String get openLyricsPreviewStateRawLoaded => 'Ready To Convert';

  @override
  String get openLyricsPreviewStateConverted => 'Converted';

  @override
  String get openLyricsPreviewEmptyNoInput =>
      'Open a lyrics file or song file first';

  @override
  String get openLyricsActionOpening => 'Opening...';

  @override
  String get openLyricsActionOpenLyricsFile => 'Open Lyrics File';

  @override
  String get openLyricsActionOpenSongFile => 'Open Song File';

  @override
  String get openLyricsActionConvertFormat => 'Convert Format';

  @override
  String get openLyricsActionSaveLyrics => 'Save Lyrics';

  @override
  String get openLyricsActionSaveToTag => 'Save To Song Tag';

  @override
  String get openLyricsActionTranslate => 'Translate Lyrics';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return 'Current export format: $format · can write tags';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return 'Current export format: $format · file export only';
  }

  @override
  String get searchLyricsSelectorTitle => 'Select Lyrics';

  @override
  String get searchLyricsSelectorOpenLocal => 'Open Local Lyrics';

  @override
  String get searchLyricsSelectorSelect => 'Select Lyrics';

  @override
  String get searchLyricsSelectorDescription =>
      'Select online or local lyrics for desktop lyrics';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return 'Failed to open local lyrics: $detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => 'Select lyrics first';

  @override
  String get searchLyricsSelectorSelectFailed =>
      'Failed to select lyrics. Try again later';

  @override
  String get searchDropUnsupportedItem =>
      'Search accepts parseable song items or audio files';

  @override
  String get searchNoticePartialSourcesFailed =>
      'Some sources failed. Results from other sources are shown';

  @override
  String get searchNoticeAllSourcesFailed => 'All search sources failed';

  @override
  String get searchNoticeLoadMoreFailed =>
      'Some sources failed to load more results';

  @override
  String get searchNoticeDirectoryPickerUnsupported =>
      'Directory selection is not supported on this platform';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return 'Fetched lyrics for $detail';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return 'Auto fetch failed: $detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable =>
      'No available song file was selected';

  @override
  String get searchNoticeFilePickerUnsupported =>
      'Song file selection is not supported on this platform';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return 'Failed to open song: $detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable =>
      'The dropped song file is unavailable';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return 'Failed to resolve dropped song: $detail';
  }

  @override
  String get searchNoticeEmptyKeyword => 'Enter a search keyword';

  @override
  String get searchNoticeGetLyricsFirst => 'Get lyrics first';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return 'Lyrics saved: $detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported =>
      'Saving files is not supported on this platform';

  @override
  String get searchNoticeFilePickerForTagUnsupported =>
      'Selecting a song tag file is not supported on this platform';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return 'File selection failed: $detail';
  }

  @override
  String get searchNoticeBatchCancelling => 'Cancelling batch save...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst =>
      'Select an album or playlist first';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage =>
      'Select at least one lyrics language';

  @override
  String get searchNoticeNoSongsToSave => 'There are no songs to save';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return 'Batch save cancelled: $saved saved, $failed failed, $skipped skipped';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return 'Batch save completed: $saved saved, $failed failed, $skipped skipped';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return 'Batch save failed: $detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates =>
      'Multiple lyric candidates were found. Select one to continue';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return 'Failed to get lyrics: $detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => 'Select a save path first';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return 'Directory selection failed: $detail';
  }

  @override
  String get searchNoticePreviewLoading => 'Lyrics are still loading';

  @override
  String get searchNoticePreviewNoLanguage =>
      'Select at least one lyrics language';

  @override
  String get searchNoticePreviewNoContent =>
      'The current lyrics have no previewable content';

  @override
  String get searchNoticePreviewNoSelection =>
      'Download and preview lyrics first';

  @override
  String get desktopWindowActionSelectLyrics => 'Select lyrics';

  @override
  String get desktopWindowActionMarkInstrumental => 'Mark as instrumental';

  @override
  String get desktopWindowActionDisableAutoSearch =>
      'Disable auto search for this song';

  @override
  String get desktopWindowActionUnlinkLyrics => 'Unlink lyrics';

  @override
  String get desktopWindowActionAssociationManager =>
      'Lyrics association manager';

  @override
  String get desktopWindowActionToggleFloating => 'Show or hide desktop lyrics';

  @override
  String get desktopWindowActionShowMainWindow => 'Show main window';

  @override
  String get desktopWindowActionClickThrough => 'Click-through';

  @override
  String get desktopWindowActionPrevious => 'Previous';

  @override
  String get desktopWindowActionPlay => 'Play';

  @override
  String get desktopWindowActionPause => 'Pause';

  @override
  String get desktopWindowActionNext => 'Next';

  @override
  String get desktopWindowActionHide => 'Hide';

  @override
  String get desktopTrayCurrentTarget => 'Current target: ';

  @override
  String get desktopTrayNoSelection => 'None';

  @override
  String get desktopTrayTargetInstance => 'Target instance';

  @override
  String get desktopTrayInstance => 'Instance';

  @override
  String get desktopTrayExit => 'Exit';

  @override
  String get desktopWindowInfoInstrumental => 'Instrumental';

  @override
  String get desktopWindowControlConnectionLost =>
      'The player connection was lost. The action was not performed.';

  @override
  String get desktopWindowClientDisconnected =>
      'The player connection was lost. Desktop lyrics were closed.';
}
