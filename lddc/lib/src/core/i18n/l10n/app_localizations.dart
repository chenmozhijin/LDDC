import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('ru'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'LDDC'**
  String get appTitle;

  /// No description provided for @commonWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get commonWarning;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get commonSuccess;

  /// No description provided for @commonFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed;

  /// No description provided for @commonSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get commonSkipped;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonRestoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore Default'**
  String get commonRestoreDefault;

  /// No description provided for @commonEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get commonEnabled;

  /// No description provided for @commonDisabledByDefault.
  ///
  /// In en, this message translates to:
  /// **'Disabled by default'**
  String get commonDisabledByDefault;

  /// No description provided for @commonFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get commonFormat;

  /// No description provided for @commonOffset.
  ///
  /// In en, this message translates to:
  /// **'Offset'**
  String get commonOffset;

  /// No description provided for @commonSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get commonSaving;

  /// No description provided for @commonAddFiles.
  ///
  /// In en, this message translates to:
  /// **'Add Files'**
  String get commonAddFiles;

  /// No description provided for @commonClearQueue.
  ///
  /// In en, this message translates to:
  /// **'Clear Queue'**
  String get commonClearQueue;

  /// No description provided for @commonUnsupportedOperation.
  ///
  /// In en, this message translates to:
  /// **'This operation is not supported on this platform'**
  String get commonUnsupportedOperation;

  /// No description provided for @commonLyricsFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This entry has no lyrics file to open yet'**
  String get commonLyricsFileUnavailable;

  /// No description provided for @commonAudioTagRequiresLrc.
  ///
  /// In en, this message translates to:
  /// **'Song-tag lyrics must use LRC format'**
  String get commonAudioTagRequiresLrc;

  /// No description provided for @commonLyricsLanguageTypeSummary.
  ///
  /// In en, this message translates to:
  /// **'{language} ({type})'**
  String commonLyricsLanguageTypeSummary(String language, String type);

  /// No description provided for @commonTranslationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Translation removed'**
  String get commonTranslationCancelled;

  /// No description provided for @commonCancelTranslation.
  ///
  /// In en, this message translates to:
  /// **'Remove Translation'**
  String get commonCancelTranslation;

  /// No description provided for @commonTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating...'**
  String get commonTranslating;

  /// No description provided for @commonTranslationProgress.
  ///
  /// In en, this message translates to:
  /// **'Translating {completed}/{total}'**
  String commonTranslationProgress(int completed, int total);

  /// No description provided for @commonOpenAiTranslationProgress.
  ///
  /// In en, this message translates to:
  /// **'OpenAI streaming translation: {completed} / {total} lines'**
  String commonOpenAiTranslationProgress(int completed, int total);

  /// No description provided for @commonTranslationCompleted.
  ///
  /// In en, this message translates to:
  /// **'Translation completed'**
  String get commonTranslationCompleted;

  /// No description provided for @commonLyricsSaved.
  ///
  /// In en, this message translates to:
  /// **'Lyrics saved'**
  String get commonLyricsSaved;

  /// No description provided for @commonDropFailed.
  ///
  /// In en, this message translates to:
  /// **'Drop failed: {detail}'**
  String commonDropFailed(String detail);

  /// No description provided for @commonSelectSaveDirectoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select save directory: {detail}'**
  String commonSelectSaveDirectoryFailed(String detail);

  /// No description provided for @commonOpenSaveDirectoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open save directory: {detail}'**
  String commonOpenSaveDirectoryFailed(String detail);

  /// No description provided for @commonTranslationFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed: {detail}'**
  String commonTranslationFailed(String detail);

  /// No description provided for @commonLyricsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save lyrics: {detail}'**
  String commonLyricsSaveFailed(String detail);

  /// No description provided for @appErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred.'**
  String get appErrorUnknown;

  /// No description provided for @appErrorOperationTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation timed out. Please try again later.'**
  String get appErrorOperationTimeout;

  /// No description provided for @appErrorNetworkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Network is unavailable. Please check your connection.'**
  String get appErrorNetworkUnavailable;

  /// No description provided for @appErrorInvalidPayload.
  ///
  /// In en, this message translates to:
  /// **'The data format is invalid.'**
  String get appErrorInvalidPayload;

  /// No description provided for @appErrorUnsupportedOperation.
  ///
  /// In en, this message translates to:
  /// **'This operation is not supported.'**
  String get appErrorUnsupportedOperation;

  /// No description provided for @appErrorPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this operation.'**
  String get appErrorPermissionDenied;

  /// No description provided for @appErrorIoFailure.
  ///
  /// In en, this message translates to:
  /// **'File read or write failed.'**
  String get appErrorIoFailure;

  /// No description provided for @appErrorLyricsRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to request lyrics.'**
  String get appErrorLyricsRequestFailed;

  /// No description provided for @appErrorLyricsNotFound.
  ///
  /// In en, this message translates to:
  /// **'No lyrics found.'**
  String get appErrorLyricsNotFound;

  /// No description provided for @appErrorLyricsProcessing.
  ///
  /// In en, this message translates to:
  /// **'Failed to process lyrics.'**
  String get appErrorLyricsProcessing;

  /// No description provided for @appErrorLyricsDecrypt.
  ///
  /// In en, this message translates to:
  /// **'Failed to decrypt lyrics.'**
  String get appErrorLyricsDecrypt;

  /// No description provided for @appErrorLyricsFormatUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported lyrics format.'**
  String get appErrorLyricsFormatUnsupported;

  /// No description provided for @appErrorDecoding.
  ///
  /// In en, this message translates to:
  /// **'Decoding failed.'**
  String get appErrorDecoding;

  /// No description provided for @appErrorSongInfoRead.
  ///
  /// In en, this message translates to:
  /// **'Failed to read song info.'**
  String get appErrorSongInfoRead;

  /// No description provided for @appErrorUnsupportedFileType.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file format.'**
  String get appErrorUnsupportedFileType;

  /// No description provided for @appErrorDragDropInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid drag-and-drop data.'**
  String get appErrorDragDropInvalid;

  /// No description provided for @appErrorTranslateFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed.'**
  String get appErrorTranslateFailed;

  /// No description provided for @appErrorApiParamsInvalid.
  ///
  /// In en, this message translates to:
  /// **'The request parameters are invalid.'**
  String get appErrorApiParamsInvalid;

  /// No description provided for @appErrorApiRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'API request failed.'**
  String get appErrorApiRequestFailed;

  /// No description provided for @appErrorAutoFetchUnknown.
  ///
  /// In en, this message translates to:
  /// **'Automatic matching failed with an unknown error.'**
  String get appErrorAutoFetchUnknown;

  /// No description provided for @appErrorNotEnoughInfo.
  ///
  /// In en, this message translates to:
  /// **'Not enough information to search.'**
  String get appErrorNotEnoughInfo;

  /// No description provided for @appErrorIpcInvalidLength.
  ///
  /// In en, this message translates to:
  /// **'The IPC message length is invalid.'**
  String get appErrorIpcInvalidLength;

  /// No description provided for @appErrorIpcUnsupportedTask.
  ///
  /// In en, this message translates to:
  /// **'The IPC task is not supported.'**
  String get appErrorIpcUnsupportedTask;

  /// No description provided for @appErrorIpcInstanceNotFound.
  ///
  /// In en, this message translates to:
  /// **'The IPC instance does not exist.'**
  String get appErrorIpcInstanceNotFound;

  /// No description provided for @appErrorIpcPanelNotFound.
  ///
  /// In en, this message translates to:
  /// **'The IPC panel does not exist.'**
  String get appErrorIpcPanelNotFound;

  /// No description provided for @appErrorIpcInvalidWindowId.
  ///
  /// In en, this message translates to:
  /// **'The window handle is invalid.'**
  String get appErrorIpcInvalidWindowId;

  /// No description provided for @appErrorIpcEmbedUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Embedded mode is not supported on this platform.'**
  String get appErrorIpcEmbedUnsupported;

  /// No description provided for @appErrorActionRetryNetwork.
  ///
  /// In en, this message translates to:
  /// **'Please check the network and try again.'**
  String get appErrorActionRetryNetwork;

  /// No description provided for @appErrorActionCheckPayload.
  ///
  /// In en, this message translates to:
  /// **'Please check the input data format.'**
  String get appErrorActionCheckPayload;

  /// No description provided for @appErrorActionChangeFormat.
  ///
  /// In en, this message translates to:
  /// **'Please use a supported file or format.'**
  String get appErrorActionChangeFormat;

  /// No description provided for @appErrorActionDetachedMode.
  ///
  /// In en, this message translates to:
  /// **'Please fall back to detached mode.'**
  String get appErrorActionDetachedMode;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get actionViewDetails;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @sourceAggregate.
  ///
  /// In en, this message translates to:
  /// **'Aggregate'**
  String get sourceAggregate;

  /// No description provided for @sourceQQMusic.
  ///
  /// In en, this message translates to:
  /// **'QQ Music'**
  String get sourceQQMusic;

  /// No description provided for @sourceKugou.
  ///
  /// In en, this message translates to:
  /// **'Kugou Music'**
  String get sourceKugou;

  /// No description provided for @sourceNetease.
  ///
  /// In en, this message translates to:
  /// **'Netease Music'**
  String get sourceNetease;

  /// No description provided for @sourceLrclib.
  ///
  /// In en, this message translates to:
  /// **'Lrclib'**
  String get sourceLrclib;

  /// No description provided for @sourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get sourceLocal;

  /// No description provided for @lyricOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get lyricOriginal;

  /// No description provided for @lyricTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get lyricTranslation;

  /// No description provided for @lyricRomanized.
  ///
  /// In en, this message translates to:
  /// **'Romanized'**
  String get lyricRomanized;

  /// No description provided for @lyricsFormatVerbatimLrc.
  ///
  /// In en, this message translates to:
  /// **'Word-timed LRC'**
  String get lyricsFormatVerbatimLrc;

  /// No description provided for @lyricsFormatLineByLineLrc.
  ///
  /// In en, this message translates to:
  /// **'Line-timed LRC'**
  String get lyricsFormatLineByLineLrc;

  /// No description provided for @lyricsFormatEnhancedLrc.
  ///
  /// In en, this message translates to:
  /// **'Enhanced LRC (ESLyric)'**
  String get lyricsFormatEnhancedLrc;

  /// No description provided for @lyricsFormatSrt.
  ///
  /// In en, this message translates to:
  /// **'SRT'**
  String get lyricsFormatSrt;

  /// No description provided for @lyricsFormatAss.
  ///
  /// In en, this message translates to:
  /// **'ASS'**
  String get lyricsFormatAss;

  /// No description provided for @lyricsTypeVerbatim.
  ///
  /// In en, this message translates to:
  /// **'Word-timed'**
  String get lyricsTypeVerbatim;

  /// No description provided for @lyricsTypeLineByLine.
  ///
  /// In en, this message translates to:
  /// **'Line-timed'**
  String get lyricsTypeLineByLine;

  /// No description provided for @lyricsTypePlainText.
  ///
  /// In en, this message translates to:
  /// **'Plain text'**
  String get lyricsTypePlainText;

  /// No description provided for @searchSong.
  ///
  /// In en, this message translates to:
  /// **'Song'**
  String get searchSong;

  /// No description provided for @searchAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get searchAlbum;

  /// No description provided for @searchSongList.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get searchSongList;

  /// No description provided for @searchArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get searchArtist;

  /// No description provided for @searchLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get searchLyrics;

  /// No description provided for @searchSongId.
  ///
  /// In en, this message translates to:
  /// **'Song ID'**
  String get searchSongId;

  /// No description provided for @localMatchIteratingFiles.
  ///
  /// In en, this message translates to:
  /// **'Scanning files...'**
  String get localMatchIteratingFiles;

  /// No description provided for @localMatchProgressImportCompleted.
  ///
  /// In en, this message translates to:
  /// **'Import completed'**
  String get localMatchProgressImportCompleted;

  /// No description provided for @localMatchProgressScanCompleted.
  ///
  /// In en, this message translates to:
  /// **'Scan completed'**
  String get localMatchProgressScanCompleted;

  /// No description provided for @localMatchProgressScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed'**
  String get localMatchProgressScanFailed;

  /// No description provided for @localMatchProgressMatchCompleted.
  ///
  /// In en, this message translates to:
  /// **'Match completed'**
  String get localMatchProgressMatchCompleted;

  /// No description provided for @localMatchProgressMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Match failed'**
  String get localMatchProgressMatchFailed;

  /// No description provided for @localMatchProgressPreparingMatch.
  ///
  /// In en, this message translates to:
  /// **'Preparing to match...'**
  String get localMatchProgressPreparingMatch;

  /// No description provided for @localMatchPreviewTagOnly.
  ///
  /// In en, this message translates to:
  /// **'Write tags only'**
  String get localMatchPreviewTagOnly;

  /// No description provided for @localMatchPreviewWriteTag.
  ///
  /// In en, this message translates to:
  /// **'Write to tags'**
  String get localMatchPreviewWriteTag;

  /// No description provided for @localMatchPreviewNoOutput.
  ///
  /// In en, this message translates to:
  /// **'No output configured'**
  String get localMatchPreviewNoOutput;

  /// No description provided for @localMatchPreviewSongTagOnly.
  ///
  /// In en, this message translates to:
  /// **'Song tags only'**
  String get localMatchPreviewSongTagOnly;

  /// No description provided for @localMatchPendingLyricsFileName.
  ///
  /// In en, this message translates to:
  /// **'Waiting for matched lyrics info to determine the file name'**
  String get localMatchPendingLyricsFileName;

  /// No description provided for @localMatchPendingLyricsFileNameAt.
  ///
  /// In en, this message translates to:
  /// **'{root} / waiting for matched lyrics info to determine the file name'**
  String localMatchPendingLyricsFileNameAt(String root);

  /// No description provided for @localMatchCalcSavePathFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to calculate save path'**
  String get localMatchCalcSavePathFailed;

  /// No description provided for @localMatchNoticeBusyImportFiles.
  ///
  /// In en, this message translates to:
  /// **'A task is running, so files cannot be imported now'**
  String get localMatchNoticeBusyImportFiles;

  /// No description provided for @localMatchNoticeSelectedFilesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected files are unavailable'**
  String get localMatchNoticeSelectedFilesUnavailable;

  /// No description provided for @localMatchNoticeImportFilesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import files: {detail}'**
  String localMatchNoticeImportFilesFailed(String detail);

  /// No description provided for @localMatchNoticeBusyImportDirectories.
  ///
  /// In en, this message translates to:
  /// **'A task is running, so directories cannot be imported now'**
  String get localMatchNoticeBusyImportDirectories;

  /// No description provided for @localMatchNoticeImportDirectoriesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import directories: {detail}'**
  String localMatchNoticeImportDirectoriesFailed(String detail);

  /// No description provided for @localMatchNoticeDroppedNoAccessibleFiles.
  ///
  /// In en, this message translates to:
  /// **'The dropped data contains no accessible files'**
  String get localMatchNoticeDroppedNoAccessibleFiles;

  /// No description provided for @localMatchNoticeDroppedSongResolveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve dropped song: {detail}'**
  String localMatchNoticeDroppedSongResolveFailed(String detail);

  /// No description provided for @localMatchNoticeImportCompletedWithErrors.
  ///
  /// In en, this message translates to:
  /// **'Import completed, but some entries could not be parsed'**
  String get localMatchNoticeImportCompletedWithErrors;

  /// No description provided for @localMatchNoticeSafTreeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Directory tree access is not supported on this platform'**
  String get localMatchNoticeSafTreeUnsupported;

  /// No description provided for @localMatchNoticeBusySwitchTree.
  ///
  /// In en, this message translates to:
  /// **'A task is running, so the directory tree cannot be changed now'**
  String get localMatchNoticeBusySwitchTree;

  /// No description provided for @localMatchNoticeSelectTreeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select directory tree: {detail}'**
  String localMatchNoticeSelectTreeFailed(String detail);

  /// No description provided for @localMatchNoticeBusyClearQueue.
  ///
  /// In en, this message translates to:
  /// **'A task is running, so the queue cannot be cleared now'**
  String get localMatchNoticeBusyClearQueue;

  /// No description provided for @localMatchNoticeSelectItemsToDelete.
  ///
  /// In en, this message translates to:
  /// **'Select entries to delete first'**
  String get localMatchNoticeSelectItemsToDelete;

  /// No description provided for @localMatchNoticeSelectItemsToSetRoot.
  ///
  /// In en, this message translates to:
  /// **'Select entries before setting a root directory'**
  String get localMatchNoticeSelectItemsToSetRoot;

  /// No description provided for @localMatchNoticeSelectedRootSkippedSongs.
  ///
  /// In en, this message translates to:
  /// **'These songs are outside the selected root and were skipped: {detail}'**
  String localMatchNoticeSelectedRootSkippedSongs(String detail);

  /// No description provided for @localMatchNoticeSetRootFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to set root directory: {detail}'**
  String localMatchNoticeSetRootFailed(String detail);

  /// No description provided for @localMatchNoticeSelectItemsToRestore.
  ///
  /// In en, this message translates to:
  /// **'Select entries to restore first'**
  String get localMatchNoticeSelectItemsToRestore;

  /// No description provided for @localMatchNoticeCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling current task...'**
  String get localMatchNoticeCancelling;

  /// No description provided for @localMatchNoticeValidationFailed.
  ///
  /// In en, this message translates to:
  /// **'Resolve the local match requirements first'**
  String get localMatchNoticeValidationFailed;

  /// No description provided for @localMatchNoticeSongDirectoryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This entry cannot open a song directory'**
  String get localMatchNoticeSongDirectoryUnavailable;

  /// No description provided for @localMatchNoticeOpenSongDirectoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open song directory: {detail}'**
  String localMatchNoticeOpenSongDirectoryFailed(String detail);

  /// No description provided for @localMatchNoticeSaveDirectoryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This entry has no save directory to open yet'**
  String get localMatchNoticeSaveDirectoryUnavailable;

  /// No description provided for @localMatchNoticeOpenLyricsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open lyrics: {detail}'**
  String localMatchNoticeOpenLyricsFailed(String detail);

  /// No description provided for @localMatchNoticeScanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Scan cancelled'**
  String get localMatchNoticeScanCancelled;

  /// No description provided for @localMatchNoticeScanCompletedWithErrors.
  ///
  /// In en, this message translates to:
  /// **'Scan completed, but some files could not be parsed'**
  String get localMatchNoticeScanCompletedWithErrors;

  /// No description provided for @localMatchNoticeScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {detail}'**
  String localMatchNoticeScanFailed(String detail);

  /// No description provided for @localMatchNoticeTreeScanFailed.
  ///
  /// In en, this message translates to:
  /// **'Directory tree scan failed: {detail}'**
  String localMatchNoticeTreeScanFailed(String detail);

  /// No description provided for @localMatchNoticeMatchCancelled.
  ///
  /// In en, this message translates to:
  /// **'Match cancelled'**
  String get localMatchNoticeMatchCancelled;

  /// No description provided for @localMatchNoticeMatchCompleted.
  ///
  /// In en, this message translates to:
  /// **'{total} songs total, {success} matched, {failed} failed, {skipped} skipped.'**
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  );

  /// No description provided for @localMatchNoticeMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Local match failed: {detail}'**
  String localMatchNoticeMatchFailed(String detail);

  /// No description provided for @localMatchNoticeAndroidMatchCancelledResume.
  ///
  /// In en, this message translates to:
  /// **'Match cancelled. Start again to resume from the checkpoint'**
  String get localMatchNoticeAndroidMatchCancelledResume;

  /// No description provided for @localMatchNoticeAndroidMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Android SAF local match failed: {detail}'**
  String localMatchNoticeAndroidMatchFailed(String detail);

  /// No description provided for @localMatchValidationEmptyLangs.
  ///
  /// In en, this message translates to:
  /// **'Select lyrics languages to match'**
  String get localMatchValidationEmptyLangs;

  /// No description provided for @localMatchValidationEmptySources.
  ///
  /// In en, this message translates to:
  /// **'Select at least one source'**
  String get localMatchValidationEmptySources;

  /// No description provided for @localMatchValidationEmptyQueue.
  ///
  /// In en, this message translates to:
  /// **'Import songs to match first'**
  String get localMatchValidationEmptyQueue;

  /// No description provided for @localMatchValidationSkipExistingFileNameConflict.
  ///
  /// In en, this message translates to:
  /// **'When skipping existing lyrics while also saving files, the file name mode cannot use matched lyrics info'**
  String get localMatchValidationSkipExistingFileNameConflict;

  /// No description provided for @localMatchValidationMissingAndroidTree.
  ///
  /// In en, this message translates to:
  /// **'Select a directory tree first'**
  String get localMatchValidationMissingAndroidTree;

  /// No description provided for @localMatchValidationNeedsSaveRoot.
  ///
  /// In en, this message translates to:
  /// **'A save path is required'**
  String get localMatchValidationNeedsSaveRoot;

  /// No description provided for @localMatchValidationNeedsSongRoot.
  ///
  /// In en, this message translates to:
  /// **'A song root directory is required'**
  String get localMatchValidationNeedsSongRoot;

  /// No description provided for @localMatchValidationUnknownSavePath.
  ///
  /// In en, this message translates to:
  /// **'Unknown save path error'**
  String get localMatchValidationUnknownSavePath;

  /// No description provided for @localMatchIntro.
  ///
  /// In en, this message translates to:
  /// **'Import local songs or folders, preview the output, then run batch matching.'**
  String get localMatchIntro;

  /// No description provided for @localMatchDropUnsupportedItem.
  ///
  /// In en, this message translates to:
  /// **'Local match accepts song files, folders, or parseable player items'**
  String get localMatchDropUnsupportedItem;

  /// No description provided for @localMatchReadyToStart.
  ///
  /// In en, this message translates to:
  /// **'Ready to start local matching'**
  String get localMatchReadyToStart;

  /// No description provided for @localMatchQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Task Queue'**
  String get localMatchQueueTitle;

  /// No description provided for @localMatchQueueEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Import files or folders to build the task queue'**
  String get localMatchQueueEmptyHint;

  /// No description provided for @localMatchQueueDesktopHint.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks. Right-click a row for more actions'**
  String localMatchQueueDesktopHint(int count);

  /// No description provided for @localMatchQueueMobileHint.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks. Long-press or tap more to open actions'**
  String localMatchQueueMobileHint(int count);

  /// No description provided for @localMatchImportAndRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Import And Run'**
  String get localMatchImportAndRunTitle;

  /// No description provided for @localMatchActionStart.
  ///
  /// In en, this message translates to:
  /// **'Start Matching'**
  String get localMatchActionStart;

  /// No description provided for @localMatchActionAddFolders.
  ///
  /// In en, this message translates to:
  /// **'Add Folders'**
  String get localMatchActionAddFolders;

  /// No description provided for @localMatchActionSelectSaveRoot.
  ///
  /// In en, this message translates to:
  /// **'Select Save Root'**
  String get localMatchActionSelectSaveRoot;

  /// No description provided for @localMatchActionSelectTree.
  ///
  /// In en, this message translates to:
  /// **'Select Tree'**
  String get localMatchActionSelectTree;

  /// No description provided for @localMatchActionReselectTree.
  ///
  /// In en, this message translates to:
  /// **'Reselect Tree'**
  String get localMatchActionReselectTree;

  /// No description provided for @localMatchActionBulkSelect.
  ///
  /// In en, this message translates to:
  /// **'Bulk Select'**
  String get localMatchActionBulkSelect;

  /// No description provided for @localMatchActionExitSelection.
  ///
  /// In en, this message translates to:
  /// **'Exit bulk selection'**
  String get localMatchActionExitSelection;

  /// No description provided for @localMatchActionSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get localMatchActionSelectAll;

  /// No description provided for @localMatchActionDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get localMatchActionDeselectAll;

  /// No description provided for @localMatchActionSetRoot.
  ///
  /// In en, this message translates to:
  /// **'Set Root'**
  String get localMatchActionSetRoot;

  /// No description provided for @localMatchSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String localMatchSelectedCount(int count);

  /// No description provided for @localMatchBulkActionHint.
  ///
  /// In en, this message translates to:
  /// **'Bulk actions apply directly to the selected tasks'**
  String get localMatchBulkActionHint;

  /// No description provided for @localMatchPhaseIdle.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get localMatchPhaseIdle;

  /// No description provided for @localMatchPhaseScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get localMatchPhaseScanning;

  /// No description provided for @localMatchPhaseMatching.
  ///
  /// In en, this message translates to:
  /// **'Matching'**
  String get localMatchPhaseMatching;

  /// No description provided for @localMatchPhaseWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing'**
  String get localMatchPhaseWriting;

  /// No description provided for @localMatchPhaseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get localMatchPhaseCompleted;

  /// No description provided for @localMatchPhaseHintIdle.
  ///
  /// In en, this message translates to:
  /// **'Import songs to start matching'**
  String get localMatchPhaseHintIdle;

  /// No description provided for @localMatchPhaseHintScanning.
  ///
  /// In en, this message translates to:
  /// **'Building the task queue and estimating output'**
  String get localMatchPhaseHintScanning;

  /// No description provided for @localMatchPhaseHintMatching.
  ///
  /// In en, this message translates to:
  /// **'Querying sources and calculating the best match'**
  String get localMatchPhaseHintMatching;

  /// No description provided for @localMatchPhaseHintWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing lyrics files or song tags'**
  String get localMatchPhaseHintWriting;

  /// No description provided for @localMatchPhaseHintCompleted.
  ///
  /// In en, this message translates to:
  /// **'This run is complete. Adjust and run again if needed'**
  String get localMatchPhaseHintCompleted;

  /// No description provided for @localMatchPipelineIdle.
  ///
  /// In en, this message translates to:
  /// **'Scan -> Match -> Write'**
  String get localMatchPipelineIdle;

  /// No description provided for @localMatchPipelineScanning.
  ///
  /// In en, this message translates to:
  /// **'Current stage: scan'**
  String get localMatchPipelineScanning;

  /// No description provided for @localMatchPipelineMatching.
  ///
  /// In en, this message translates to:
  /// **'Current stage: match'**
  String get localMatchPipelineMatching;

  /// No description provided for @localMatchPipelineWriting.
  ///
  /// In en, this message translates to:
  /// **'Current stage: write'**
  String get localMatchPipelineWriting;

  /// No description provided for @localMatchPipelineCompleted.
  ///
  /// In en, this message translates to:
  /// **'Scan, match, and write completed'**
  String get localMatchPipelineCompleted;

  /// No description provided for @localMatchUnknownSong.
  ///
  /// In en, this message translates to:
  /// **'Unknown Song'**
  String get localMatchUnknownSong;

  /// No description provided for @localMatchUnknownDuration.
  ///
  /// In en, this message translates to:
  /// **'Unknown Duration'**
  String get localMatchUnknownDuration;

  /// No description provided for @localMatchStatusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not Started'**
  String get localMatchStatusNotStarted;

  /// No description provided for @localMatchSongPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Song Path'**
  String get localMatchSongPathLabel;

  /// No description provided for @localMatchLyricsPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Save Path'**
  String get localMatchLyricsPathLabel;

  /// No description provided for @localMatchExpandDetails.
  ///
  /// In en, this message translates to:
  /// **'Expand details'**
  String get localMatchExpandDetails;

  /// No description provided for @localMatchCollapseDetails.
  ///
  /// In en, this message translates to:
  /// **'Collapse details'**
  String get localMatchCollapseDetails;

  /// No description provided for @localMatchRowActionOpenInSearch.
  ///
  /// In en, this message translates to:
  /// **'Open In Search'**
  String get localMatchRowActionOpenInSearch;

  /// No description provided for @localMatchRowActionEnterSelection.
  ///
  /// In en, this message translates to:
  /// **'Enter Bulk Selection'**
  String get localMatchRowActionEnterSelection;

  /// No description provided for @localMatchRowActionOpenSongDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Song Folder'**
  String get localMatchRowActionOpenSongDirectory;

  /// No description provided for @localMatchRowActionOpenSaveDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Save Folder'**
  String get localMatchRowActionOpenSaveDirectory;

  /// No description provided for @localMatchRowActionOpenLyrics.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics'**
  String get localMatchRowActionOpenLyrics;

  /// No description provided for @localMatchFieldLyricsType.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Type'**
  String get localMatchFieldLyricsType;

  /// No description provided for @localMatchFieldOutputStrategy.
  ///
  /// In en, this message translates to:
  /// **'Output Strategy'**
  String get localMatchFieldOutputStrategy;

  /// No description provided for @localMatchFieldSaveMode.
  ///
  /// In en, this message translates to:
  /// **'Save Mode'**
  String get localMatchFieldSaveMode;

  /// No description provided for @localMatchFieldFileNameMode.
  ///
  /// In en, this message translates to:
  /// **'File Name Mode'**
  String get localMatchFieldFileNameMode;

  /// No description provided for @localMatchFieldLyricsFormat.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Format'**
  String get localMatchFieldLyricsFormat;

  /// No description provided for @localMatchFieldThreshold.
  ///
  /// In en, this message translates to:
  /// **'Match Threshold'**
  String get localMatchFieldThreshold;

  /// No description provided for @localMatchFieldSaveRoot.
  ///
  /// In en, this message translates to:
  /// **'Save Root'**
  String get localMatchFieldSaveRoot;

  /// No description provided for @localMatchMoreSettings.
  ///
  /// In en, this message translates to:
  /// **'More Settings'**
  String get localMatchMoreSettings;

  /// No description provided for @localMatchRulesTitle.
  ///
  /// In en, this message translates to:
  /// **'Match Rules'**
  String get localMatchRulesTitle;

  /// No description provided for @localMatchRulesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sources, languages, output strategy, and threshold'**
  String get localMatchRulesSubtitle;

  /// No description provided for @localMatchMinScore.
  ///
  /// In en, this message translates to:
  /// **'Minimum Score'**
  String get localMatchMinScore;

  /// No description provided for @localMatchSkipExisting.
  ///
  /// In en, this message translates to:
  /// **'Skip Existing Lyrics'**
  String get localMatchSkipExisting;

  /// No description provided for @localMatchSkipExistingConflictHint.
  ///
  /// In en, this message translates to:
  /// **'The current output strategy and file-name mode cannot skip existing lyrics. If files still need to be saved, avoid naming by matched lyrics info.'**
  String get localMatchSkipExistingConflictHint;

  /// No description provided for @localMatchSaveToSongDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'Saving to the song folder does not need an extra save root.'**
  String get localMatchSaveToSongDirectoryHint;

  /// No description provided for @localMatchAndroidTreeSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Android directory tree saves are written directly into the authorized tree.'**
  String get localMatchAndroidTreeSaveHint;

  /// No description provided for @localMatchFileNameTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'The file name template uses lyrics_file_name_fmt from Settings.'**
  String get localMatchFileNameTemplateHint;

  /// No description provided for @localMatchSaveRootPath.
  ///
  /// In en, this message translates to:
  /// **'Save root: {path}'**
  String localMatchSaveRootPath(String path);

  /// No description provided for @localMatchSaveRootRequired.
  ///
  /// In en, this message translates to:
  /// **'This save mode needs a save root. Select one first.'**
  String get localMatchSaveRootRequired;

  /// No description provided for @localMatchTreeNotSelected.
  ///
  /// In en, this message translates to:
  /// **'No directory tree selected'**
  String get localMatchTreeNotSelected;

  /// No description provided for @localMatchSaveModeSong.
  ///
  /// In en, this message translates to:
  /// **'Save To Song Folder'**
  String get localMatchSaveModeSong;

  /// No description provided for @localMatchSaveModeMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror Folders'**
  String get localMatchSaveModeMirror;

  /// No description provided for @localMatchSaveModeSpecify.
  ///
  /// In en, this message translates to:
  /// **'Specific Folder'**
  String get localMatchSaveModeSpecify;

  /// No description provided for @localMatchFileNameModeSong.
  ///
  /// In en, this message translates to:
  /// **'Use Song File Name'**
  String get localMatchFileNameModeSong;

  /// No description provided for @localMatchFileNameModeFormatBySong.
  ///
  /// In en, this message translates to:
  /// **'Name By Song Info'**
  String get localMatchFileNameModeFormatBySong;

  /// No description provided for @localMatchFileNameModeFormatByLyrics.
  ///
  /// In en, this message translates to:
  /// **'Name By Lyrics Info'**
  String get localMatchFileNameModeFormatByLyrics;

  /// No description provided for @localMatchFileNameHintSong.
  ///
  /// In en, this message translates to:
  /// **'Reuse the audio file name and only replace the lyrics extension.'**
  String get localMatchFileNameHintSong;

  /// No description provided for @localMatchFileNameHintFormatBySong.
  ///
  /// In en, this message translates to:
  /// **'Generate the file name from song metadata such as title, artist, and album.'**
  String get localMatchFileNameHintFormatBySong;

  /// No description provided for @localMatchFileNameHintFormatByLyrics.
  ///
  /// In en, this message translates to:
  /// **'Generate the file name from the matched lyrics song info; it may be unknown before matching.'**
  String get localMatchFileNameHintFormatByLyrics;

  /// No description provided for @localMatchSaveToTagOnlyFile.
  ///
  /// In en, this message translates to:
  /// **'File Only'**
  String get localMatchSaveToTagOnlyFile;

  /// No description provided for @localMatchSaveToTagOnlyTag.
  ///
  /// In en, this message translates to:
  /// **'Tag Only'**
  String get localMatchSaveToTagOnlyTag;

  /// No description provided for @localMatchSaveToTagBoth.
  ///
  /// In en, this message translates to:
  /// **'File + Tag'**
  String get localMatchSaveToTagBoth;

  /// No description provided for @localMatchValidationTitle.
  ///
  /// In en, this message translates to:
  /// **'Issues to fix before starting'**
  String get localMatchValidationTitle;

  /// No description provided for @localMatchValidationMoreIssues.
  ///
  /// In en, this message translates to:
  /// **'{count} more issues need to be fixed'**
  String localMatchValidationMoreIssues(int count);

  /// No description provided for @batchConvertNoticeSelectedFilesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The selected files are not directly accessible'**
  String get batchConvertNoticeSelectedFilesUnavailable;

  /// No description provided for @batchConvertNoticeImportFilesCompleted.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} lyrics files'**
  String batchConvertNoticeImportFilesCompleted(int count);

  /// No description provided for @batchConvertNoticeDroppedNoAccessibleFiles.
  ///
  /// In en, this message translates to:
  /// **'The dropped data contains no accessible lyrics files'**
  String get batchConvertNoticeDroppedNoAccessibleFiles;

  /// No description provided for @batchConvertNoticeEmptyQueue.
  ///
  /// In en, this message translates to:
  /// **'Add lyrics files to convert first'**
  String get batchConvertNoticeEmptyQueue;

  /// No description provided for @batchConvertNoticeOverwriteCancelled.
  ///
  /// In en, this message translates to:
  /// **'Batch conversion cancelled'**
  String get batchConvertNoticeOverwriteCancelled;

  /// No description provided for @batchConvertNoticeConversionCancelledCompleted.
  ///
  /// In en, this message translates to:
  /// **'Batch conversion cancelled, {count} items completed'**
  String batchConvertNoticeConversionCancelledCompleted(int count);

  /// No description provided for @batchConvertNoticeConversionCompletedWithFailures.
  ///
  /// In en, this message translates to:
  /// **'Batch conversion completed: {success} succeeded, {failure} failed'**
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  );

  /// No description provided for @batchConvertNoticeConversionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Batch conversion completed: {count} items'**
  String batchConvertNoticeConversionCompleted(int count);

  /// No description provided for @batchConvertNoticeConversionFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch conversion failed: {detail}'**
  String batchConvertNoticeConversionFailed(String detail);

  /// No description provided for @batchConvertNoticeOpenSourceDirectoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open source directory: {detail}'**
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail);

  /// No description provided for @batchConvertNoticeOpenOutputFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open lyrics file: {detail}'**
  String batchConvertNoticeOpenOutputFileFailed(String detail);

  /// No description provided for @batchConvertNoticeScanNoSupportedFiles.
  ///
  /// In en, this message translates to:
  /// **'No supported lyrics files were found in the selected folder'**
  String get batchConvertNoticeScanNoSupportedFiles;

  /// No description provided for @batchConvertNoticeScanImportedFromDirectory.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} lyrics files from folder'**
  String batchConvertNoticeScanImportedFromDirectory(int count);

  /// No description provided for @batchConvertNoticeDuplicateItems.
  ///
  /// In en, this message translates to:
  /// **'All selected entries are already in the queue'**
  String get batchConvertNoticeDuplicateItems;

  /// No description provided for @batchConvertControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import & Settings'**
  String get batchConvertControlsTitle;

  /// No description provided for @batchConvertCompactControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import & Output Settings'**
  String get batchConvertCompactControlsTitle;

  /// No description provided for @batchConvertCompactControlsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Format: {format}'**
  String batchConvertCompactControlsSubtitle(String format);

  /// No description provided for @batchConvertImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get batchConvertImportTitle;

  /// No description provided for @batchConvertAddFolders.
  ///
  /// In en, this message translates to:
  /// **'Add Folder'**
  String get batchConvertAddFolders;

  /// No description provided for @batchConvertOutputSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Output Settings'**
  String get batchConvertOutputSettingsTitle;

  /// No description provided for @batchConvertTargetFormat.
  ///
  /// In en, this message translates to:
  /// **'Target Format'**
  String get batchConvertTargetFormat;

  /// No description provided for @batchConvertSaveDirectoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Folder'**
  String get batchConvertSaveDirectoryTitle;

  /// No description provided for @batchConvertSaveDirectoryDefault.
  ///
  /// In en, this message translates to:
  /// **'When unset, output goes next to the source lyrics file'**
  String get batchConvertSaveDirectoryDefault;

  /// No description provided for @batchConvertSelectSaveDirectory.
  ///
  /// In en, this message translates to:
  /// **'Choose Save Folder'**
  String get batchConvertSelectSaveDirectory;

  /// No description provided for @batchConvertRestoreOriginalDirectory.
  ///
  /// In en, this message translates to:
  /// **'Use Source Folder'**
  String get batchConvertRestoreOriginalDirectory;

  /// No description provided for @batchConvertRecursiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan Subfolders'**
  String get batchConvertRecursiveTitle;

  /// No description provided for @batchConvertRecursiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When importing a folder, continue scanning lyrics files in subfolders'**
  String get batchConvertRecursiveSubtitle;

  /// No description provided for @batchConvertStart.
  ///
  /// In en, this message translates to:
  /// **'Start Conversion'**
  String get batchConvertStart;

  /// No description provided for @batchConvertCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel Conversion'**
  String get batchConvertCancel;

  /// No description provided for @batchConvertQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversion Queue'**
  String get batchConvertQueueTitle;

  /// No description provided for @batchConvertQueueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} items, output format {format}'**
  String batchConvertQueueSubtitle(int count, String format);

  /// No description provided for @batchConvertPageErrorFallback.
  ///
  /// In en, this message translates to:
  /// **'The batch conversion page encountered an error'**
  String get batchConvertPageErrorFallback;

  /// No description provided for @batchConvertRetryImport.
  ///
  /// In en, this message translates to:
  /// **'Import Again'**
  String get batchConvertRetryImport;

  /// No description provided for @batchConvertEmptyQueue.
  ///
  /// In en, this message translates to:
  /// **'Add lyrics files or folders and the batch conversion queue will appear here.'**
  String get batchConvertEmptyQueue;

  /// No description provided for @batchConvertOutputPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Output Path'**
  String get batchConvertOutputPathLabel;

  /// No description provided for @batchConvertQueueStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get batchConvertQueueStatusWaiting;

  /// No description provided for @batchConvertQueueStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Converting'**
  String get batchConvertQueueStatusRunning;

  /// No description provided for @batchConvertQueueStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get batchConvertQueueStatusSuccess;

  /// No description provided for @batchConvertQueueStatusFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get batchConvertQueueStatusFailure;

  /// No description provided for @batchConvertMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get batchConvertMoreActions;

  /// No description provided for @batchConvertActionOpenSourceDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Source Folder'**
  String get batchConvertActionOpenSourceDirectory;

  /// No description provided for @batchConvertActionOpenSaveDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Save Folder'**
  String get batchConvertActionOpenSaveDirectory;

  /// No description provided for @batchConvertActionOpenOutputFile.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics File'**
  String get batchConvertActionOpenOutputFile;

  /// No description provided for @batchConvertActionOpenInOpenLyrics.
  ///
  /// In en, this message translates to:
  /// **'Open in Open Lyrics'**
  String get batchConvertActionOpenInOpenLyrics;

  /// No description provided for @batchConvertPhaseIdle.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get batchConvertPhaseIdle;

  /// No description provided for @batchConvertPhaseScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get batchConvertPhaseScanning;

  /// No description provided for @batchConvertPhaseRunning.
  ///
  /// In en, this message translates to:
  /// **'Converting'**
  String get batchConvertPhaseRunning;

  /// No description provided for @batchConvertPhaseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get batchConvertPhaseCompleted;

  /// No description provided for @batchConvertPipelineIdle.
  ///
  /// In en, this message translates to:
  /// **'Import -> Scan -> Convert -> Finish'**
  String get batchConvertPipelineIdle;

  /// No description provided for @batchConvertPipelineScanning.
  ///
  /// In en, this message translates to:
  /// **'Scan folders -> Build queue'**
  String get batchConvertPipelineScanning;

  /// No description provided for @batchConvertPipelineRunning.
  ///
  /// In en, this message translates to:
  /// **'Convert each item -> Update status'**
  String get batchConvertPipelineRunning;

  /// No description provided for @batchConvertPipelineCompleted.
  ///
  /// In en, this message translates to:
  /// **'Adjust format or import again'**
  String get batchConvertPipelineCompleted;

  /// No description provided for @batchConvertHintCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled, {success} succeeded, {failure} failed'**
  String batchConvertHintCancelled(int success, int failure);

  /// No description provided for @batchConvertHintCompleted.
  ///
  /// In en, this message translates to:
  /// **'{success} succeeded, {failure} failed'**
  String batchConvertHintCompleted(int success, int failure);

  /// No description provided for @batchConvertHintNoQueue.
  ///
  /// In en, this message translates to:
  /// **'Add files or folders to start converting'**
  String get batchConvertHintNoQueue;

  /// No description provided for @batchConvertHintReady.
  ///
  /// In en, this message translates to:
  /// **'The queue is ready'**
  String get batchConvertHintReady;

  /// No description provided for @batchConvertMetricWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get batchConvertMetricWaiting;

  /// No description provided for @batchConvertDropUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The batch conversion page accepts only lyrics files or folders'**
  String get batchConvertDropUnsupported;

  /// No description provided for @batchConvertDropFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to process drop: {detail}'**
  String batchConvertDropFailed(String detail);

  /// No description provided for @batchConvertProgressConvertingFile.
  ///
  /// In en, this message translates to:
  /// **'Converting {fileName}'**
  String batchConvertProgressConvertingFile(String fileName);

  /// No description provided for @batchConvertProgressItemSuccess.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get batchConvertProgressItemSuccess;

  /// No description provided for @batchConvertProgressItemFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get batchConvertProgressItemFailure;

  /// No description provided for @batchConvertProgressPreparingConversion.
  ///
  /// In en, this message translates to:
  /// **'Preparing conversion...'**
  String get batchConvertProgressPreparingConversion;

  /// No description provided for @batchConvertProgressCancellingConversion.
  ///
  /// In en, this message translates to:
  /// **'Cancelling conversion...'**
  String get batchConvertProgressCancellingConversion;

  /// No description provided for @batchConvertProgressConversionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Conversion cancelled'**
  String get batchConvertProgressConversionCancelled;

  /// No description provided for @batchConvertProgressConversionCompleted.
  ///
  /// In en, this message translates to:
  /// **'Conversion completed: {success} succeeded, {failure} failed'**
  String batchConvertProgressConversionCompleted(int success, int failure);

  /// No description provided for @batchConvertProgressConversionFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversion failed: {detail}'**
  String batchConvertProgressConversionFailed(String detail);

  /// No description provided for @batchConvertProgressScanningFolders.
  ///
  /// In en, this message translates to:
  /// **'Scanning folders...'**
  String get batchConvertProgressScanningFolders;

  /// No description provided for @batchConvertProgressScanningDirectory.
  ///
  /// In en, this message translates to:
  /// **'Scanning {directoryName}'**
  String batchConvertProgressScanningDirectory(String directoryName);

  /// No description provided for @batchConvertProgressScannedLyricsFiles.
  ///
  /// In en, this message translates to:
  /// **'Found {count} lyrics files'**
  String batchConvertProgressScannedLyricsFiles(int count);

  /// No description provided for @batchConvertProgressScanCancelled.
  ///
  /// In en, this message translates to:
  /// **'Scan cancelled'**
  String get batchConvertProgressScanCancelled;

  /// No description provided for @batchConvertProgressScanNoSupportedFiles.
  ///
  /// In en, this message translates to:
  /// **'No supported lyrics files found'**
  String get batchConvertProgressScanNoSupportedFiles;

  /// No description provided for @batchConvertProgressScanCompleted.
  ///
  /// In en, this message translates to:
  /// **'Scan completed'**
  String get batchConvertProgressScanCompleted;

  /// No description provided for @navSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// No description provided for @navLocalMatch.
  ///
  /// In en, this message translates to:
  /// **'Local Match'**
  String get navLocalMatch;

  /// No description provided for @navOpenLyrics.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics'**
  String get navOpenLyrics;

  /// No description provided for @navBatchConvert.
  ///
  /// In en, this message translates to:
  /// **'Batch Convert'**
  String get navBatchConvert;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get navAbout;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get commonSource;

  /// No description provided for @searchKeywordHint.
  ///
  /// In en, this message translates to:
  /// **'Input keyword'**
  String get searchKeywordHint;

  /// No description provided for @uiLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get uiLoading;

  /// No description provided for @uiLoadingStepFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching list and preview...'**
  String get uiLoadingStepFetching;

  /// No description provided for @uiEmpty.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get uiEmpty;

  /// No description provided for @uiNoMoreResult.
  ///
  /// In en, this message translates to:
  /// **'No more results'**
  String get uiNoMoreResult;

  /// No description provided for @searchInitialResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter keywords to start searching'**
  String get searchInitialResultTitle;

  /// No description provided for @searchInitialResultDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose a source above and run a search'**
  String get searchInitialResultDescription;

  /// No description provided for @searchResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Results'**
  String get searchResultTitle;

  /// No description provided for @searchResultReturn.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get searchResultReturn;

  /// No description provided for @searchPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Preview'**
  String get searchPreviewTitle;

  /// No description provided for @searchPreviewLangsLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get searchPreviewLangsLabel;

  /// No description provided for @searchPreviewSongIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Song ID'**
  String get searchPreviewSongIdLabel;

  /// No description provided for @searchPreviewPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select a song or lyric item first'**
  String get searchPreviewPlaceholder;

  /// No description provided for @searchPreviewNoLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select at least one lyric language'**
  String get searchPreviewNoLanguage;

  /// No description provided for @searchPreviewNoContent.
  ///
  /// In en, this message translates to:
  /// **'No previewable content is available'**
  String get searchPreviewNoContent;

  /// No description provided for @searchPreviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics...'**
  String get searchPreviewLoading;

  /// No description provided for @searchFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Format'**
  String get searchFormatLabel;

  /// No description provided for @searchTranslateLyrics.
  ///
  /// In en, this message translates to:
  /// **'Translate Lyrics'**
  String get searchTranslateLyrics;

  /// No description provided for @searchResizeWorkspacePanes.
  ///
  /// In en, this message translates to:
  /// **'Resize search results and lyrics preview'**
  String get searchResizeWorkspacePanes;

  /// No description provided for @searchSavePreviewToDirectory.
  ///
  /// In en, this message translates to:
  /// **'Save to Folder'**
  String get searchSavePreviewToDirectory;

  /// No description provided for @searchSavePreviewToFile.
  ///
  /// In en, this message translates to:
  /// **'Save to File'**
  String get searchSavePreviewToFile;

  /// No description provided for @searchSavePreviewToTag.
  ///
  /// In en, this message translates to:
  /// **'Save Preview to Tag'**
  String get searchSavePreviewToTag;

  /// No description provided for @searchSaveListLyrics.
  ///
  /// In en, this message translates to:
  /// **'Save Album/Playlist Lyrics'**
  String get searchSaveListLyrics;

  /// No description provided for @searchSaveListLyricsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel Batch Save'**
  String get searchSaveListLyricsCancel;

  /// No description provided for @searchSelectSavePath.
  ///
  /// In en, this message translates to:
  /// **'Choose Save Folder'**
  String get searchSelectSavePath;

  /// No description provided for @searchBatchSaveProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Batch Save Progress'**
  String get searchBatchSaveProgressTitle;

  /// No description provided for @searchBatchSaveProgressPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing batch save...'**
  String get searchBatchSaveProgressPreparing;

  /// No description provided for @searchBatchSaveProgressFetchingLyrics.
  ///
  /// In en, this message translates to:
  /// **'Fetching lyrics for {songName}...'**
  String searchBatchSaveProgressFetchingLyrics(String songName);

  /// No description provided for @searchTableSongCountValue.
  ///
  /// In en, this message translates to:
  /// **'{count} songs'**
  String searchTableSongCountValue(int count);

  /// No description provided for @searchTableStatusAutoFetching.
  ///
  /// In en, this message translates to:
  /// **'Auto fetching...'**
  String get searchTableStatusAutoFetching;

  /// No description provided for @searchTableStatusSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searchTableStatusSearching;

  /// No description provided for @searchTableStatusFetchingSongList.
  ///
  /// In en, this message translates to:
  /// **'Fetching song list...'**
  String get searchTableStatusFetchingSongList;

  /// No description provided for @searchTableStatusNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results found'**
  String get searchTableStatusNoResults;

  /// No description provided for @searchTableStatusEmptyList.
  ///
  /// In en, this message translates to:
  /// **'The list is empty'**
  String get searchTableStatusEmptyList;

  /// No description provided for @searchTableStatusUnsupportedSearchType.
  ///
  /// In en, this message translates to:
  /// **'The selected source does not support this search type'**
  String get searchTableStatusUnsupportedSearchType;

  /// No description provided for @searchTableStatusSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed'**
  String get searchTableStatusSearchFailed;

  /// No description provided for @searchTableStatusSearchFailedWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {detail}'**
  String searchTableStatusSearchFailedWithDetail(String detail);

  /// No description provided for @searchTableStatusAutoFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto fetch failed: {detail}'**
  String searchTableStatusAutoFetchFailed(String detail);

  /// No description provided for @searchTableStatusSongListFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch song list: {detail}'**
  String searchTableStatusSongListFailed(String detail);

  /// No description provided for @searchTableStatusPartialSourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some sources are unavailable. Showing available results'**
  String get searchTableStatusPartialSourceUnavailable;

  /// No description provided for @searchTableStatusLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Some sources failed to load more results'**
  String get searchTableStatusLoadMoreFailed;

  /// No description provided for @searchSourceFailureDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Search error details'**
  String get searchSourceFailureDetailsTitle;

  /// No description provided for @searchSourceFailureRequest.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get searchSourceFailureRequest;

  /// No description provided for @searchSourceFailureTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timed out'**
  String get searchSourceFailureTimeout;

  /// No description provided for @searchSourceFailureParameters.
  ///
  /// In en, this message translates to:
  /// **'Invalid parameters'**
  String get searchSourceFailureParameters;

  /// No description provided for @searchSourceFailureUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported operation'**
  String get searchSourceFailureUnsupported;

  /// No description provided for @searchSourceFailureUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get searchSourceFailureUnknown;

  /// No description provided for @searchResultLoadingMore.
  ///
  /// In en, this message translates to:
  /// **'Loading more results...'**
  String get searchResultLoadingMore;

  /// No description provided for @searchResultLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto load failed. Retry to continue loading remaining results'**
  String get searchResultLoadMoreFailed;

  /// No description provided for @searchResultScrollForMore.
  ///
  /// In en, this message translates to:
  /// **'Scroll down to automatically load more results'**
  String get searchResultScrollForMore;

  /// No description provided for @tableSavePath.
  ///
  /// In en, this message translates to:
  /// **'Save Path'**
  String get tableSavePath;

  /// No description provided for @settingsSectionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSectionSave;

  /// No description provided for @settingsSectionLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get settingsSectionLyrics;

  /// No description provided for @settingsSectionDesktopLyrics.
  ///
  /// In en, this message translates to:
  /// **'Desktop Lyrics'**
  String get settingsSectionDesktopLyrics;

  /// No description provided for @settingsSectionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get settingsSectionTranslate;

  /// No description provided for @settingsSectionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get settingsSectionSearch;

  /// No description provided for @settingsSectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsSectionApp;

  /// No description provided for @settingsSectionTools.
  ///
  /// In en, this message translates to:
  /// **'Tools And Data'**
  String get settingsSectionTools;

  /// No description provided for @settingsSectionSaveSummary.
  ///
  /// In en, this message translates to:
  /// **'Save paths, file name template, and ID3 version'**
  String get settingsSectionSaveSummary;

  /// No description provided for @settingsSectionSearchSummary.
  ///
  /// In en, this message translates to:
  /// **'Choose the default lyric sources for Aggregate search and local matching.'**
  String get settingsSectionSearchSummary;

  /// No description provided for @settingsSectionDesktopLyricsSummary.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics auto-fetch, display languages, appearance, and refresh rate.'**
  String get settingsSectionDesktopLyricsSummary;

  /// No description provided for @settingsSectionLyricsSummary.
  ///
  /// In en, this message translates to:
  /// **'Local matching behavior and lyrics file export format.'**
  String get settingsSectionLyricsSummary;

  /// No description provided for @settingsSectionTranslateSummary.
  ///
  /// In en, this message translates to:
  /// **'Translation source, target language, and conditional fields'**
  String get settingsSectionTranslateSummary;

  /// No description provided for @settingsSectionAppSummary.
  ///
  /// In en, this message translates to:
  /// **'Language, theme, logs, and update policy'**
  String get settingsSectionAppSummary;

  /// No description provided for @settingsSectionToolsSummary.
  ///
  /// In en, this message translates to:
  /// **'Desktop tools, log folder, and cache cleanup'**
  String get settingsSectionToolsSummary;

  /// No description provided for @settingsTranslateSourceBing.
  ///
  /// In en, this message translates to:
  /// **'Bing Translate'**
  String get settingsTranslateSourceBing;

  /// No description provided for @settingsTranslateSourceGoogle.
  ///
  /// In en, this message translates to:
  /// **'Google Translate'**
  String get settingsTranslateSourceGoogle;

  /// No description provided for @settingsTranslateSourceOpenAi.
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible API'**
  String get settingsTranslateSourceOpenAi;

  /// No description provided for @settingsLangSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get settingsLangSimplifiedChinese;

  /// No description provided for @settingsLangTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get settingsLangTraditionalChinese;

  /// No description provided for @settingsLangEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLangEnglish;

  /// No description provided for @settingsLangJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get settingsLangJapanese;

  /// No description provided for @settingsLangKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get settingsLangKorean;

  /// No description provided for @settingsLangSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settingsLangSpanish;

  /// No description provided for @settingsLangFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get settingsLangFrench;

  /// No description provided for @settingsLangPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get settingsLangPortuguese;

  /// No description provided for @settingsLangGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settingsLangGerman;

  /// No description provided for @settingsLangRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get settingsLangRussian;

  /// No description provided for @settingsAppLanguageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsAppLanguageAuto;

  /// No description provided for @settingsColorSchemeAuto.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get settingsColorSchemeAuto;

  /// No description provided for @settingsColorSchemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsColorSchemeLight;

  /// No description provided for @settingsColorSchemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsColorSchemeDark;

  /// No description provided for @settingsDesktopGradientColors.
  ///
  /// In en, this message translates to:
  /// **'Gradient Colors'**
  String get settingsDesktopGradientColors;

  /// No description provided for @settingsDesktopPlayedColors.
  ///
  /// In en, this message translates to:
  /// **'Played Colors'**
  String get settingsDesktopPlayedColors;

  /// No description provided for @settingsDesktopUnplayedColors.
  ///
  /// In en, this message translates to:
  /// **'Unplayed Colors'**
  String get settingsDesktopUnplayedColors;

  /// No description provided for @settingsAddColor.
  ///
  /// In en, this message translates to:
  /// **'Add Color'**
  String get settingsAddColor;

  /// No description provided for @settingsEditColor.
  ///
  /// In en, this message translates to:
  /// **'Edit Color'**
  String get settingsEditColor;

  /// No description provided for @settingsDeleteColor.
  ///
  /// In en, this message translates to:
  /// **'Delete Color'**
  String get settingsDeleteColor;

  /// No description provided for @settingsBackToSections.
  ///
  /// In en, this message translates to:
  /// **'Back To Setting Sections'**
  String get settingsBackToSections;

  /// No description provided for @settingsAvailablePlaceholders.
  ///
  /// In en, this message translates to:
  /// **'Available Placeholders'**
  String get settingsAvailablePlaceholders;

  /// No description provided for @settingsPlaceholderTitleArtist.
  ///
  /// In en, this message translates to:
  /// **'Title: %<title>    Artist: %<artist>'**
  String get settingsPlaceholderTitleArtist;

  /// No description provided for @settingsPlaceholderAlbumId.
  ///
  /// In en, this message translates to:
  /// **'Album: %<album>    Song/Lyrics id: %<id>'**
  String get settingsPlaceholderAlbumId;

  /// No description provided for @settingsPlaceholderLangs.
  ///
  /// In en, this message translates to:
  /// **'Language types: %<langs>'**
  String get settingsPlaceholderLangs;

  /// No description provided for @settingsCurrentTemplate.
  ///
  /// In en, this message translates to:
  /// **'Current template: {template}'**
  String settingsCurrentTemplate(String template);

  /// No description provided for @settingsTranslateSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Translation Source'**
  String get settingsTranslateSourceLabel;

  /// No description provided for @settingsTranslateTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Language'**
  String get settingsTranslateTargetLabel;

  /// No description provided for @settingsOpenAiProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get settingsOpenAiProfileLabel;

  /// No description provided for @settingsOpenAiProfileHelper.
  ///
  /// In en, this message translates to:
  /// **'Built-in providers fill the Base URL automatically. You still need to configure the API Key and model.'**
  String get settingsOpenAiProfileHelper;

  /// No description provided for @settingsAppLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Interface Language'**
  String get settingsAppLanguageLabel;

  /// No description provided for @settingsColorSchemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsColorSchemeLabel;

  /// No description provided for @settingsLogLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Log Level'**
  String get settingsLogLevelLabel;

  /// No description provided for @settingsLogLevelHelper.
  ///
  /// In en, this message translates to:
  /// **'Keep INFO for normal use. TRACE and DEBUG record more detail and create larger logs.'**
  String get settingsLogLevelHelper;

  /// No description provided for @settingsAutoCheckUpdateLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto Check Updates'**
  String get settingsAutoCheckUpdateLabel;

  /// No description provided for @settingsRestoreDefaultsWarning.
  ///
  /// In en, this message translates to:
  /// **'Restoring defaults writes the config immediately. Please confirm before continuing.'**
  String get settingsRestoreDefaultsWarning;

  /// No description provided for @settingsRestoreAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Default Settings'**
  String get settingsRestoreAllTitle;

  /// No description provided for @settingsRestoreAllContent.
  ///
  /// In en, this message translates to:
  /// **'This restores all settings and writes them to the config immediately.'**
  String get settingsRestoreAllContent;

  /// No description provided for @settingsRestoreAllAction.
  ///
  /// In en, this message translates to:
  /// **'Restore Default Settings'**
  String get settingsRestoreAllAction;

  /// No description provided for @settingsOpenAssociationManager.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics Association Manager'**
  String get settingsOpenAssociationManager;

  /// No description provided for @settingsOpenAssociationManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the next settings page to manage song and lyrics associations.'**
  String get settingsOpenAssociationManagerSubtitle;

  /// No description provided for @settingsOpenLogDirectory.
  ///
  /// In en, this message translates to:
  /// **'Open Log Directory'**
  String get settingsOpenLogDirectory;

  /// No description provided for @settingsOpenLogDirectorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'View runtime logs and troubleshooting files.'**
  String get settingsOpenLogDirectorySubtitle;

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get settingsClearCache;

  /// No description provided for @settingsClearCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clear search and translation cache without changing config files.'**
  String get settingsClearCacheSubtitle;

  /// No description provided for @settingsClearCacheContent.
  ///
  /// In en, this message translates to:
  /// **'After clearing cache, later searches and translations may request data again.'**
  String get settingsClearCacheContent;

  /// No description provided for @settingsRestoreSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore This Section'**
  String get settingsRestoreSectionTitle;

  /// No description provided for @settingsRestoreSectionContent.
  ///
  /// In en, this message translates to:
  /// **'Only settings in the “{sectionTitle}” section will be restored. Other sections will not change.'**
  String settingsRestoreSectionContent(String sectionTitle);

  /// No description provided for @settingsRestoreSectionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Restore defaults for {sectionTitle}'**
  String settingsRestoreSectionTooltip(String sectionTitle);

  /// No description provided for @settingsDefaultSavePathHelper.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the platform default Music directory.'**
  String get settingsDefaultSavePathHelper;

  /// No description provided for @settingsChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose Folder'**
  String get settingsChooseFolder;

  /// No description provided for @settingsLyricsFileNameFormat.
  ///
  /// In en, this message translates to:
  /// **'Lyrics File Name Template'**
  String get settingsLyricsFileNameFormat;

  /// No description provided for @settingsLyricsFileNameFormatHelper.
  ///
  /// In en, this message translates to:
  /// **'Use the placeholders below to compose saved file names.'**
  String get settingsLyricsFileNameFormatHelper;

  /// No description provided for @settingsId3Version.
  ///
  /// In en, this message translates to:
  /// **'ID3 Version'**
  String get settingsId3Version;

  /// No description provided for @settingsId3VersionHelper.
  ///
  /// In en, this message translates to:
  /// **'Only affects lyrics written to audio tags. Keep v2.3 if you are unsure.'**
  String get settingsId3VersionHelper;

  /// No description provided for @settingsSearchSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Aggregate Search Sources'**
  String get settingsSearchSourcesTitle;

  /// No description provided for @settingsSearchSourcesDescription.
  ///
  /// In en, this message translates to:
  /// **'Checked sources are queried when Search uses Aggregate. Sources higher in the list rank first for result grouping and automatic matching. Local Match uses this list by default.'**
  String get settingsSearchSourcesDescription;

  /// No description provided for @settingsReorderPriorityHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to change priority'**
  String get settingsReorderPriorityHint;

  /// No description provided for @settingsReorderOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to change order'**
  String get settingsReorderOrderHint;

  /// No description provided for @settingsDefaultLanguage.
  ///
  /// In en, this message translates to:
  /// **'Default Display Languages'**
  String get settingsDefaultLanguage;

  /// No description provided for @settingsDefaultLanguageDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the languages shown by default in desktop lyrics, then drag to change their display order.'**
  String get settingsDefaultLanguageDescription;

  /// No description provided for @settingsDesktopAutoFetchSources.
  ///
  /// In en, this message translates to:
  /// **'Auto-fetch Sources'**
  String get settingsDesktopAutoFetchSources;

  /// No description provided for @settingsDesktopAutoFetchSourcesDescription.
  ///
  /// In en, this message translates to:
  /// **'When desktop lyrics has no linked lyrics, sources are tried from top to bottom.'**
  String get settingsDesktopAutoFetchSourcesDescription;

  /// No description provided for @settingsFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get settingsFont;

  /// No description provided for @settingsFollowSystemFont.
  ///
  /// In en, this message translates to:
  /// **'Follow System Font'**
  String get settingsFollowSystemFont;

  /// No description provided for @settingsFontSizeByResize.
  ///
  /// In en, this message translates to:
  /// **'Resize the desktop lyrics window to adjust its main font size.'**
  String get settingsFontSizeByResize;

  /// No description provided for @settingsPanelFontSize.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Panel Font Size'**
  String get settingsPanelFontSize;

  /// No description provided for @settingsAdaptiveRefreshRate.
  ///
  /// In en, this message translates to:
  /// **'Adaptive Refresh Rate'**
  String get settingsAdaptiveRefreshRate;

  /// No description provided for @settingsAdaptiveRefreshRateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically choose the refresh cadence based on lyrics animation state.'**
  String get settingsAdaptiveRefreshRateSubtitle;

  /// No description provided for @settingsFixedRefreshRate.
  ///
  /// In en, this message translates to:
  /// **'Fixed Refresh Rate'**
  String get settingsFixedRefreshRate;

  /// No description provided for @settingsShowFurigana.
  ///
  /// In en, this message translates to:
  /// **'Show Furigana'**
  String get settingsShowFurigana;

  /// No description provided for @settingsLyricsMatchBehavior.
  ///
  /// In en, this message translates to:
  /// **'Matching Behavior'**
  String get settingsLyricsMatchBehavior;

  /// No description provided for @settingsLyricsMatchBehaviorDescription.
  ///
  /// In en, this message translates to:
  /// **'Set the default handling for local matching and Kugou lyric candidates.'**
  String get settingsLyricsMatchBehaviorDescription;

  /// No description provided for @settingsLyricsExport.
  ///
  /// In en, this message translates to:
  /// **'LRC Export'**
  String get settingsLyricsExport;

  /// No description provided for @settingsLyricsExportDescription.
  ///
  /// In en, this message translates to:
  /// **'Set the language order and LRC timestamp format used when saving lyrics files.'**
  String get settingsLyricsExportDescription;

  /// No description provided for @settingsDisplayOrder.
  ///
  /// In en, this message translates to:
  /// **'Export Language Order'**
  String get settingsDisplayOrder;

  /// No description provided for @settingsDisplayOrderDescription.
  ///
  /// In en, this message translates to:
  /// **'Drag to arrange original, translated, and romanized lyrics in exported files.'**
  String get settingsDisplayOrderDescription;

  /// No description provided for @settingsSkipInstrumental.
  ///
  /// In en, this message translates to:
  /// **'Skip Instrumental Tracks'**
  String get settingsSkipInstrumental;

  /// No description provided for @settingsSkipInstrumentalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Do not save lyrics when Local Match identifies an instrumental track.'**
  String get settingsSkipInstrumentalSubtitle;

  /// No description provided for @settingsAutoSelectKugou.
  ///
  /// In en, this message translates to:
  /// **'Auto Select Kugou Candidate'**
  String get settingsAutoSelectKugou;

  /// No description provided for @settingsAutoSelectKugouSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically choose the best lyric candidate when opening a Kugou song in Search.'**
  String get settingsAutoSelectKugouSubtitle;

  /// No description provided for @settingsAddLrcEndTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Add End Timestamp When Exporting LRC'**
  String get settingsAddLrcEndTimestamp;

  /// No description provided for @settingsAddLrcEndTimestampSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only affects line-by-line LRC and writes line end timestamps when needed.'**
  String get settingsAddLrcEndTimestampSubtitle;

  /// No description provided for @settingsMillisecondsDigits.
  ///
  /// In en, this message translates to:
  /// **'Millisecond Digits'**
  String get settingsMillisecondsDigits;

  /// No description provided for @settingsMillisecondsDigitsHelper.
  ///
  /// In en, this message translates to:
  /// **'Use two digits for centiseconds or three digits to keep full milliseconds.'**
  String get settingsMillisecondsDigitsHelper;

  /// No description provided for @settingsDigitsValue.
  ///
  /// In en, this message translates to:
  /// **'{value} digits'**
  String settingsDigitsValue(int value);

  /// No description provided for @settingsLastRefStyle.
  ///
  /// In en, this message translates to:
  /// **'Last Language Line Timestamp'**
  String get settingsLastRefStyle;

  /// No description provided for @settingsLastRefStyleHelper.
  ///
  /// In en, this message translates to:
  /// **'For multi-language line-by-line LRC, use the current line time or one millisecond before the next line for the last language line.'**
  String get settingsLastRefStyleHelper;

  /// No description provided for @settingsLastRefCurrentLine.
  ///
  /// In en, this message translates to:
  /// **'Use Current Line Time'**
  String get settingsLastRefCurrentLine;

  /// No description provided for @settingsLastRefNextLine.
  ///
  /// In en, this message translates to:
  /// **'Use One Millisecond Before Next Line'**
  String get settingsLastRefNextLine;

  /// No description provided for @settingsTagInfoSource.
  ///
  /// In en, this message translates to:
  /// **'Tag Info Source'**
  String get settingsTagInfoSource;

  /// No description provided for @settingsTagInfoLyricsSource.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Source'**
  String get settingsTagInfoLyricsSource;

  /// No description provided for @settingsTagInfoSongInfo.
  ///
  /// In en, this message translates to:
  /// **'Song Info'**
  String get settingsTagInfoSongInfo;

  /// No description provided for @settingsNoticeDefaultSavePathUpdated.
  ///
  /// In en, this message translates to:
  /// **'Default save path updated'**
  String get settingsNoticeDefaultSavePathUpdated;

  /// No description provided for @settingsNoticeDefaultSavePathRestored.
  ///
  /// In en, this message translates to:
  /// **'Default save path restored'**
  String get settingsNoticeDefaultSavePathRestored;

  /// No description provided for @settingsNoticeLyricsFileNameFormatUpdated.
  ///
  /// In en, this message translates to:
  /// **'Lyrics file name template updated'**
  String get settingsNoticeLyricsFileNameFormatUpdated;

  /// No description provided for @settingsNoticeId3VersionUpdated.
  ///
  /// In en, this message translates to:
  /// **'ID3 version updated'**
  String get settingsNoticeId3VersionUpdated;

  /// No description provided for @settingsNoticeLyricsLangOrderEmpty.
  ///
  /// In en, this message translates to:
  /// **'Lyrics language order cannot be empty'**
  String get settingsNoticeLyricsLangOrderEmpty;

  /// No description provided for @settingsNoticeLyricsLangOrderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Lyrics language order updated'**
  String get settingsNoticeLyricsLangOrderUpdated;

  /// No description provided for @settingsNoticeSkipInstUpdated.
  ///
  /// In en, this message translates to:
  /// **'Instrumental skip policy updated'**
  String get settingsNoticeSkipInstUpdated;

  /// No description provided for @settingsNoticeAutoSelectUpdated.
  ///
  /// In en, this message translates to:
  /// **'Auto select policy updated'**
  String get settingsNoticeAutoSelectUpdated;

  /// No description provided for @settingsNoticeAddEndTimestampUpdated.
  ///
  /// In en, this message translates to:
  /// **'End timestamp policy updated'**
  String get settingsNoticeAddEndTimestampUpdated;

  /// No description provided for @settingsNoticeMsDigitsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Millisecond digits updated'**
  String get settingsNoticeMsDigitsUpdated;

  /// No description provided for @settingsNoticeLastRefStyleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last line time style updated'**
  String get settingsNoticeLastRefStyleUpdated;

  /// No description provided for @settingsNoticeTagInfoSourceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Tag info source updated'**
  String get settingsNoticeTagInfoSourceUpdated;

  /// No description provided for @settingsNoticeDesktopSourcesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics sources cannot be empty'**
  String get settingsNoticeDesktopSourcesEmpty;

  /// No description provided for @settingsNoticeDesktopSourcesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics sources updated'**
  String get settingsNoticeDesktopSourcesUpdated;

  /// No description provided for @settingsNoticeDesktopDefaultLangsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Desktop default languages cannot be empty'**
  String get settingsNoticeDesktopDefaultLangsEmpty;

  /// No description provided for @settingsNoticeDesktopLangsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics language settings updated'**
  String get settingsNoticeDesktopLangsUpdated;

  /// No description provided for @settingsNoticeDesktopFontFamilyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics font updated'**
  String get settingsNoticeDesktopFontFamilyUpdated;

  /// No description provided for @settingsNoticeDesktopRefreshRateUpdated.
  ///
  /// In en, this message translates to:
  /// **'Refresh rate updated'**
  String get settingsNoticeDesktopRefreshRateUpdated;

  /// No description provided for @settingsNoticeDesktopPlayedColorsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Played colors updated'**
  String get settingsNoticeDesktopPlayedColorsUpdated;

  /// No description provided for @settingsNoticeDesktopUnplayedColorsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Unplayed colors updated'**
  String get settingsNoticeDesktopUnplayedColorsUpdated;

  /// No description provided for @settingsNoticeDesktopFontSizeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Desktop lyrics font size updated'**
  String get settingsNoticeDesktopFontSizeUpdated;

  /// No description provided for @settingsNoticeDesktopPanelFontSizeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Desktop panel font size updated'**
  String get settingsNoticeDesktopPanelFontSizeUpdated;

  /// No description provided for @settingsNoticeDesktopShowFuriganaUpdated.
  ///
  /// In en, this message translates to:
  /// **'Furigana display policy updated'**
  String get settingsNoticeDesktopShowFuriganaUpdated;

  /// No description provided for @settingsNoticeTranslateSourceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Translation source updated'**
  String get settingsNoticeTranslateSourceUpdated;

  /// No description provided for @settingsNoticeTranslateTargetLangUpdated.
  ///
  /// In en, this message translates to:
  /// **'Translation target language updated'**
  String get settingsNoticeTranslateTargetLangUpdated;

  /// No description provided for @settingsNoticeOpenAiProfileUpdated.
  ///
  /// In en, this message translates to:
  /// **'OpenAI preset updated'**
  String get settingsNoticeOpenAiProfileUpdated;

  /// No description provided for @settingsNoticeOpenAiBaseUrlUpdated.
  ///
  /// In en, this message translates to:
  /// **'OpenAI Base URL updated'**
  String get settingsNoticeOpenAiBaseUrlUpdated;

  /// No description provided for @settingsNoticeOpenAiApiKeyUpdated.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API Key updated'**
  String get settingsNoticeOpenAiApiKeyUpdated;

  /// No description provided for @settingsNoticeOpenAiModelUpdated.
  ///
  /// In en, this message translates to:
  /// **'OpenAI model updated'**
  String get settingsNoticeOpenAiModelUpdated;

  /// No description provided for @settingsNoticeSearchSourcesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Aggregate search sources cannot be empty'**
  String get settingsNoticeSearchSourcesEmpty;

  /// No description provided for @settingsNoticeSearchSourcesUpdated.
  ///
  /// In en, this message translates to:
  /// **'Aggregate search sources updated'**
  String get settingsNoticeSearchSourcesUpdated;

  /// No description provided for @settingsNoticeAppLanguageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Interface language updated'**
  String get settingsNoticeAppLanguageUpdated;

  /// No description provided for @settingsNoticeAppColorSchemeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Theme mode updated'**
  String get settingsNoticeAppColorSchemeUpdated;

  /// No description provided for @settingsNoticeAppLogLevelUpdated.
  ///
  /// In en, this message translates to:
  /// **'Log level updated'**
  String get settingsNoticeAppLogLevelUpdated;

  /// No description provided for @settingsNoticeAutoCheckUpdateUpdated.
  ///
  /// In en, this message translates to:
  /// **'Auto check updates setting updated'**
  String get settingsNoticeAutoCheckUpdateUpdated;

  /// No description provided for @settingsNoticeSectionNoRestorableConfig.
  ///
  /// In en, this message translates to:
  /// **'This section has no restorable config items'**
  String get settingsNoticeSectionNoRestorableConfig;

  /// No description provided for @settingsNoticeSectionDefaultsRestored.
  ///
  /// In en, this message translates to:
  /// **'Current section defaults restored'**
  String get settingsNoticeSectionDefaultsRestored;

  /// No description provided for @settingsNoticeAllDefaultsRestored.
  ///
  /// In en, this message translates to:
  /// **'Application settings restored to defaults'**
  String get settingsNoticeAllDefaultsRestored;

  /// No description provided for @settingsNoticeAssociationManagerOpened.
  ///
  /// In en, this message translates to:
  /// **'Lyrics association manager opened'**
  String get settingsNoticeAssociationManagerOpened;

  /// No description provided for @settingsNoticeLogDirectoryOpened.
  ///
  /// In en, this message translates to:
  /// **'Log directory opened'**
  String get settingsNoticeLogDirectoryOpened;

  /// No description provided for @settingsNoticeLogDirectoryOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open log directory'**
  String get settingsNoticeLogDirectoryOpenFailed;

  /// No description provided for @settingsNoticeCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Cache cleared'**
  String get settingsNoticeCacheCleared;

  /// No description provided for @settingsNoticeCacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear cache'**
  String get settingsNoticeCacheClearFailed;

  /// No description provided for @settingsNoticeConfigWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to write settings'**
  String get settingsNoticeConfigWriteFailed;

  /// No description provided for @settingsCurrentSavePathLabel.
  ///
  /// In en, this message translates to:
  /// **'Default Save Path'**
  String get settingsCurrentSavePathLabel;

  /// No description provided for @aboutLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load about metadata.'**
  String get aboutLoadFailed;

  /// No description provided for @aboutActionOpenRepository.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repo'**
  String get aboutActionOpenRepository;

  /// No description provided for @aboutActionCheckUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check Update'**
  String get aboutActionCheckUpdate;

  /// No description provided for @aboutHeroHeadline.
  ///
  /// In en, this message translates to:
  /// **'Built for precise lyrics'**
  String get aboutHeroHeadline;

  /// No description provided for @aboutHeroDescription.
  ///
  /// In en, this message translates to:
  /// **'LDDC brings search, conversion, desktop lyrics, and batch workflows into one efficient surface so finding, organizing, and using lyrics stays fast and focused.'**
  String get aboutHeroDescription;

  /// No description provided for @aboutLinksSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Links'**
  String get aboutLinksSectionTitle;

  /// No description provided for @aboutLinksSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Use these links when you want feedback channels, release notes, or license details.'**
  String get aboutLinksSectionDescription;

  /// No description provided for @aboutCopyrightNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Copyright (C) {years} {author}'**
  String aboutCopyrightNoticeBody(String years, String author);

  /// No description provided for @aboutLicenseNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Licensed under {license}.'**
  String aboutLicenseNoticeBody(String license);

  /// No description provided for @aboutLinkRepositoryTitle.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get aboutLinkRepositoryTitle;

  /// No description provided for @aboutLinkIssueTrackerTitle.
  ///
  /// In en, this message translates to:
  /// **'Issue Tracker'**
  String get aboutLinkIssueTrackerTitle;

  /// No description provided for @aboutLinkIssueTrackerDescription.
  ///
  /// In en, this message translates to:
  /// **'Report bugs, UX gaps, and feature requests.'**
  String get aboutLinkIssueTrackerDescription;

  /// No description provided for @aboutLinkLicenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLinkLicenseTitle;

  /// No description provided for @aboutLinkLicenseDescription.
  ///
  /// In en, this message translates to:
  /// **'Review the current open source license:'**
  String get aboutLinkLicenseDescription;

  /// No description provided for @aboutLinkChangelogTitle.
  ///
  /// In en, this message translates to:
  /// **'Release Notes'**
  String get aboutLinkChangelogTitle;

  /// No description provided for @aboutLinkChangelogDescription.
  ///
  /// In en, this message translates to:
  /// **'See published versions and their change summaries.'**
  String get aboutLinkChangelogDescription;

  /// No description provided for @aboutExternalLinksUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Opening external links is not supported on this platform.'**
  String get aboutExternalLinksUnavailable;

  /// No description provided for @aboutCheckUpdateUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates is not supported on this platform.'**
  String get aboutCheckUpdateUnavailable;

  /// No description provided for @aboutCheckUpdateOpenedReleaseNotes.
  ///
  /// In en, this message translates to:
  /// **'Opened the release notes page.'**
  String get aboutCheckUpdateOpenedReleaseNotes;

  /// No description provided for @aboutCheckUpdateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are already on the latest version.'**
  String get aboutCheckUpdateUpToDate;

  /// No description provided for @aboutCheckUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version found: {version}. Open the release notes page for details.'**
  String aboutCheckUpdateAvailable(Object version);

  /// No description provided for @aboutCheckUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates. Please try again later.'**
  String get aboutCheckUpdateFailed;

  /// No description provided for @aboutActionOpenedLink.
  ///
  /// In en, this message translates to:
  /// **'Opened {title}'**
  String aboutActionOpenedLink(String title);

  /// No description provided for @aboutActionOpenLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open {title}'**
  String aboutActionOpenLinkFailed(String title);

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @libraryLinkManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Association Manager'**
  String get libraryLinkManagerTitle;

  /// No description provided for @libraryLinkManagerReturnToSettings.
  ///
  /// In en, this message translates to:
  /// **'Back to Settings'**
  String get libraryLinkManagerReturnToSettings;

  /// No description provided for @libraryLinkManagerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get libraryLinkManagerRefresh;

  /// No description provided for @libraryLinkManagerDeleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected ({count})'**
  String libraryLinkManagerDeleteSelected(int count);

  /// No description provided for @libraryLinkManagerDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get libraryLinkManagerDeleteAll;

  /// No description provided for @libraryLinkManagerClearInvalid.
  ///
  /// In en, this message translates to:
  /// **'Clear Invalid Data'**
  String get libraryLinkManagerClearInvalid;

  /// No description provided for @libraryLinkManagerChangeDirectory.
  ///
  /// In en, this message translates to:
  /// **'Batch Change Directory'**
  String get libraryLinkManagerChangeDirectory;

  /// No description provided for @libraryLinkManagerBackupToJson.
  ///
  /// In en, this message translates to:
  /// **'Backup to JSON'**
  String get libraryLinkManagerBackupToJson;

  /// No description provided for @libraryLinkManagerRestoreFromJson.
  ///
  /// In en, this message translates to:
  /// **'Restore from JSON'**
  String get libraryLinkManagerRestoreFromJson;

  /// No description provided for @libraryLinkManagerRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get libraryLinkManagerRestoreAction;

  /// No description provided for @libraryLinkManagerExportLyrics.
  ///
  /// In en, this message translates to:
  /// **'Export Lyrics'**
  String get libraryLinkManagerExportLyrics;

  /// No description provided for @libraryLinkManagerSummary.
  ///
  /// In en, this message translates to:
  /// **'{totalCount} records · {selectedCount} selected'**
  String libraryLinkManagerSummary(int totalCount, int selectedCount);

  /// No description provided for @libraryLinkManagerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search songs, artists, albums, or paths'**
  String get libraryLinkManagerSearchHint;

  /// No description provided for @libraryLinkManagerClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get libraryLinkManagerClearSearch;

  /// No description provided for @libraryLinkManagerSearchSummary.
  ///
  /// In en, this message translates to:
  /// **'{totalCount} matches · {selectedCount} selected'**
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount);

  /// No description provided for @libraryLinkManagerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No lyrics link records'**
  String get libraryLinkManagerEmpty;

  /// No description provided for @libraryLinkManagerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load lyrics link records: {error}'**
  String libraryLinkManagerLoadFailed(String error);

  /// No description provided for @libraryLinkManagerDeleteSelectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted selected lyrics links'**
  String get libraryLinkManagerDeleteSelectedSuccess;

  /// No description provided for @libraryLinkManagerDeleteAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all lyrics link records?'**
  String get libraryLinkManagerDeleteAllConfirm;

  /// No description provided for @libraryLinkManagerDeleteAllSuccess.
  ///
  /// In en, this message translates to:
  /// **'Deleted all lyrics link records'**
  String get libraryLinkManagerDeleteAllSuccess;

  /// No description provided for @libraryLinkManagerClearInvalidSuccess.
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} invalid records'**
  String libraryLinkManagerClearInvalidSuccess(int count);

  /// No description provided for @libraryLinkManagerChangeDirectorySuccess.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} records after directory rewrite'**
  String libraryLinkManagerChangeDirectorySuccess(int count);

  /// No description provided for @libraryLinkManagerBackupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Lyrics link data backed up to {path}'**
  String libraryLinkManagerBackupSuccess(String path);

  /// No description provided for @libraryLinkManagerRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restoring will overwrite all current lyrics link records. Continue?'**
  String get libraryLinkManagerRestoreConfirm;

  /// No description provided for @libraryLinkManagerRestoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Lyrics link data restored'**
  String get libraryLinkManagerRestoreSuccess;

  /// No description provided for @libraryLinkManagerInvalidBackupFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid backup file format'**
  String get libraryLinkManagerInvalidBackupFormat;

  /// No description provided for @libraryLinkManagerExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} lyric files'**
  String libraryLinkManagerExportSuccess(int count);

  /// No description provided for @libraryLinkManagerOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String libraryLinkManagerOperationFailed(String error);

  /// No description provided for @libraryLinkManagerUnnamedSong.
  ///
  /// In en, this message translates to:
  /// **'Untitled Song'**
  String get libraryLinkManagerUnnamedSong;

  /// No description provided for @libraryLinkManagerUnknownArtist.
  ///
  /// In en, this message translates to:
  /// **'Unknown Artist'**
  String get libraryLinkManagerUnknownArtist;

  /// No description provided for @libraryLinkManagerUnknownAlbum.
  ///
  /// In en, this message translates to:
  /// **'Unknown Album'**
  String get libraryLinkManagerUnknownAlbum;

  /// No description provided for @libraryLinkManagerSongPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Song Path'**
  String get libraryLinkManagerSongPathLabel;

  /// No description provided for @libraryLinkManagerSongPathEmpty.
  ///
  /// In en, this message translates to:
  /// **'No song path recorded'**
  String get libraryLinkManagerSongPathEmpty;

  /// No description provided for @libraryLinkManagerLyricsPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Lyrics Path'**
  String get libraryLinkManagerLyricsPathLabel;

  /// No description provided for @libraryLinkManagerLyricsPathEmpty.
  ///
  /// In en, this message translates to:
  /// **'No lyrics linked'**
  String get libraryLinkManagerLyricsPathEmpty;

  /// No description provided for @libraryLinkManagerTrackLabel.
  ///
  /// In en, this message translates to:
  /// **'Track {track}'**
  String libraryLinkManagerTrackLabel(String track);

  /// No description provided for @libraryLinkManagerTrackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Track number: {track}'**
  String libraryLinkManagerTrackTooltip(String track);

  /// No description provided for @libraryLinkManagerTrackEmpty.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get libraryLinkManagerTrackEmpty;

  /// No description provided for @libraryLinkManagerOffsetLabel.
  ///
  /// In en, this message translates to:
  /// **'Offset {offset}'**
  String libraryLinkManagerOffsetLabel(String offset);

  /// No description provided for @libraryLinkManagerOffsetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Lyric offset: {offset}'**
  String libraryLinkManagerOffsetTooltip(String offset);

  /// No description provided for @libraryLinkManagerLanguagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages {langs}'**
  String libraryLinkManagerLanguagesLabel(String langs);

  /// No description provided for @libraryLinkManagerLanguagesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Lyrics languages: {langs}'**
  String libraryLinkManagerLanguagesTooltip(String langs);

  /// No description provided for @libraryLinkManagerInstrumental.
  ///
  /// In en, this message translates to:
  /// **'Instrumental'**
  String get libraryLinkManagerInstrumental;

  /// No description provided for @libraryLinkManagerInstrumentalTooltip.
  ///
  /// In en, this message translates to:
  /// **'This song is marked as instrumental'**
  String get libraryLinkManagerInstrumentalTooltip;

  /// No description provided for @libraryLinkManagerDisableAutoSearch.
  ///
  /// In en, this message translates to:
  /// **'Disable Auto Search'**
  String get libraryLinkManagerDisableAutoSearch;

  /// No description provided for @libraryLinkManagerDisableAutoSearchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Auto search is disabled for this song'**
  String get libraryLinkManagerDisableAutoSearchTooltip;

  /// No description provided for @libraryLinkManagerOtherConfig.
  ///
  /// In en, this message translates to:
  /// **'Other Config {count}'**
  String libraryLinkManagerOtherConfig(int count);

  /// No description provided for @libraryLinkManagerDefaultConfig.
  ///
  /// In en, this message translates to:
  /// **'Default Config'**
  String get libraryLinkManagerDefaultConfig;

  /// No description provided for @libraryLinkManagerDefaultConfigTooltip.
  ///
  /// In en, this message translates to:
  /// **'No song-level override config is saved for this record'**
  String get libraryLinkManagerDefaultConfigTooltip;

  /// No description provided for @openLyricsNoticeOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Open failed: {detail}'**
  String openLyricsNoticeOpenFailed(String detail);

  /// No description provided for @openLyricsNoticeLyricsFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The lyrics file is unavailable'**
  String get openLyricsNoticeLyricsFileUnavailable;

  /// No description provided for @openLyricsNoticeSongFileUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The song file is unavailable'**
  String get openLyricsNoticeSongFileUnavailable;

  /// No description provided for @openLyricsNoticeNoEmbeddedLyrics.
  ///
  /// In en, this message translates to:
  /// **'No readable embedded lyrics were found in this song'**
  String get openLyricsNoticeNoEmbeddedLyrics;

  /// No description provided for @openLyricsNoticeAlreadyConverted.
  ///
  /// In en, this message translates to:
  /// **'These lyrics have already been converted'**
  String get openLyricsNoticeAlreadyConverted;

  /// No description provided for @openLyricsNoticeEmptyLyrics.
  ///
  /// In en, this message translates to:
  /// **'Lyrics content cannot be empty'**
  String get openLyricsNoticeEmptyLyrics;

  /// No description provided for @openLyricsNoticeConvertFailed.
  ///
  /// In en, this message translates to:
  /// **'Conversion failed: {detail}'**
  String openLyricsNoticeConvertFailed(String detail);

  /// No description provided for @openLyricsNoticeConvertFirst.
  ///
  /// In en, this message translates to:
  /// **'Convert the lyrics first'**
  String get openLyricsNoticeConvertFirst;

  /// No description provided for @openLyricsNoticeNoLyricsToSave.
  ///
  /// In en, this message translates to:
  /// **'There are no lyrics to save'**
  String get openLyricsNoticeNoLyricsToSave;

  /// No description provided for @openLyricsNoticeSaveFileSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Lyrics saved: {detail}'**
  String openLyricsNoticeSaveFileSucceeded(String detail);

  /// No description provided for @openLyricsNoticeSaveFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {detail}'**
  String openLyricsNoticeSaveFileFailed(String detail);

  /// No description provided for @openLyricsNoticeOpenSongFirst.
  ///
  /// In en, this message translates to:
  /// **'Open a song file first'**
  String get openLyricsNoticeOpenSongFirst;

  /// No description provided for @openLyricsNoticeAudioTagUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This platform cannot write song tags'**
  String get openLyricsNoticeAudioTagUnsupported;

  /// No description provided for @openLyricsDropUnsupportedItem.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics accepts lyrics files or audio files'**
  String get openLyricsDropUnsupportedItem;

  /// No description provided for @openLyricsPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get openLyricsPreviewTitle;

  /// No description provided for @openLyricsPreviewRawText.
  ///
  /// In en, this message translates to:
  /// **'Raw Text'**
  String get openLyricsPreviewRawText;

  /// No description provided for @openLyricsPreviewLanguages.
  ///
  /// In en, this message translates to:
  /// **'Lyrics languages · {langs}'**
  String openLyricsPreviewLanguages(String langs);

  /// No description provided for @openLyricsPreviewStateIdle.
  ///
  /// In en, this message translates to:
  /// **'Not Loaded'**
  String get openLyricsPreviewStateIdle;

  /// No description provided for @openLyricsPreviewStateRawLoaded.
  ///
  /// In en, this message translates to:
  /// **'Ready To Convert'**
  String get openLyricsPreviewStateRawLoaded;

  /// No description provided for @openLyricsPreviewStateConverted.
  ///
  /// In en, this message translates to:
  /// **'Converted'**
  String get openLyricsPreviewStateConverted;

  /// No description provided for @openLyricsPreviewEmptyNoInput.
  ///
  /// In en, this message translates to:
  /// **'Open a lyrics file or song file first'**
  String get openLyricsPreviewEmptyNoInput;

  /// No description provided for @openLyricsActionOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening...'**
  String get openLyricsActionOpening;

  /// No description provided for @openLyricsActionOpenLyricsFile.
  ///
  /// In en, this message translates to:
  /// **'Open Lyrics File'**
  String get openLyricsActionOpenLyricsFile;

  /// No description provided for @openLyricsActionOpenSongFile.
  ///
  /// In en, this message translates to:
  /// **'Open Song File'**
  String get openLyricsActionOpenSongFile;

  /// No description provided for @openLyricsActionConvertFormat.
  ///
  /// In en, this message translates to:
  /// **'Convert Format'**
  String get openLyricsActionConvertFormat;

  /// No description provided for @openLyricsActionSaveLyrics.
  ///
  /// In en, this message translates to:
  /// **'Save Lyrics'**
  String get openLyricsActionSaveLyrics;

  /// No description provided for @openLyricsActionSaveToTag.
  ///
  /// In en, this message translates to:
  /// **'Save To Song Tag'**
  String get openLyricsActionSaveToTag;

  /// No description provided for @openLyricsActionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate Lyrics'**
  String get openLyricsActionTranslate;

  /// No description provided for @openLyricsExportFormatCanWriteTag.
  ///
  /// In en, this message translates to:
  /// **'Current export format: {format} · can write tags'**
  String openLyricsExportFormatCanWriteTag(String format);

  /// No description provided for @openLyricsExportFormatFileOnly.
  ///
  /// In en, this message translates to:
  /// **'Current export format: {format} · file export only'**
  String openLyricsExportFormatFileOnly(String format);

  /// No description provided for @searchLyricsSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Lyrics'**
  String get searchLyricsSelectorTitle;

  /// No description provided for @searchLyricsSelectorOpenLocal.
  ///
  /// In en, this message translates to:
  /// **'Open Local Lyrics'**
  String get searchLyricsSelectorOpenLocal;

  /// No description provided for @searchLyricsSelectorSelect.
  ///
  /// In en, this message translates to:
  /// **'Select Lyrics'**
  String get searchLyricsSelectorSelect;

  /// No description provided for @searchLyricsSelectorDescription.
  ///
  /// In en, this message translates to:
  /// **'Select online or local lyrics for desktop lyrics'**
  String get searchLyricsSelectorDescription;

  /// No description provided for @searchLyricsSelectorOpenLocalFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open local lyrics: {detail}'**
  String searchLyricsSelectorOpenLocalFailed(String detail);

  /// No description provided for @searchLyricsSelectorSelectLyricsFirst.
  ///
  /// In en, this message translates to:
  /// **'Select lyrics first'**
  String get searchLyricsSelectorSelectLyricsFirst;

  /// No description provided for @searchLyricsSelectorSelectFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select lyrics. Try again later'**
  String get searchLyricsSelectorSelectFailed;

  /// No description provided for @searchDropUnsupportedItem.
  ///
  /// In en, this message translates to:
  /// **'Search accepts parseable song items or audio files'**
  String get searchDropUnsupportedItem;

  /// No description provided for @searchNoticePartialSourcesFailed.
  ///
  /// In en, this message translates to:
  /// **'Some sources failed. Results from other sources are shown'**
  String get searchNoticePartialSourcesFailed;

  /// No description provided for @searchNoticeAllSourcesFailed.
  ///
  /// In en, this message translates to:
  /// **'All search sources failed'**
  String get searchNoticeAllSourcesFailed;

  /// No description provided for @searchNoticeLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Some sources failed to load more results'**
  String get searchNoticeLoadMoreFailed;

  /// No description provided for @searchNoticeDirectoryPickerUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Directory selection is not supported on this platform'**
  String get searchNoticeDirectoryPickerUnsupported;

  /// No description provided for @searchNoticeAutoFetchSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Fetched lyrics for {detail}'**
  String searchNoticeAutoFetchSucceeded(String detail);

  /// No description provided for @searchNoticeAutoFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto fetch failed: {detail}'**
  String searchNoticeAutoFetchFailed(String detail);

  /// No description provided for @searchNoticeSelectedSongUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No available song file was selected'**
  String get searchNoticeSelectedSongUnavailable;

  /// No description provided for @searchNoticeFilePickerUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Song file selection is not supported on this platform'**
  String get searchNoticeFilePickerUnsupported;

  /// No description provided for @searchNoticeOpenSongFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open song: {detail}'**
  String searchNoticeOpenSongFailed(String detail);

  /// No description provided for @searchNoticeDroppedSongUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The dropped song file is unavailable'**
  String get searchNoticeDroppedSongUnavailable;

  /// No description provided for @searchNoticeDroppedSongResolveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve dropped song: {detail}'**
  String searchNoticeDroppedSongResolveFailed(String detail);

  /// No description provided for @searchNoticeEmptyKeyword.
  ///
  /// In en, this message translates to:
  /// **'Enter a search keyword'**
  String get searchNoticeEmptyKeyword;

  /// No description provided for @searchNoticeGetLyricsFirst.
  ///
  /// In en, this message translates to:
  /// **'Get lyrics first'**
  String get searchNoticeGetLyricsFirst;

  /// No description provided for @searchNoticeLyricsSaveSucceededWithPath.
  ///
  /// In en, this message translates to:
  /// **'Lyrics saved: {detail}'**
  String searchNoticeLyricsSaveSucceededWithPath(String detail);

  /// No description provided for @searchNoticeSaveFileUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Saving files is not supported on this platform'**
  String get searchNoticeSaveFileUnsupported;

  /// No description provided for @searchNoticeFilePickerForTagUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Selecting a song tag file is not supported on this platform'**
  String get searchNoticeFilePickerForTagUnsupported;

  /// No description provided for @searchNoticeFilePickerFailed.
  ///
  /// In en, this message translates to:
  /// **'File selection failed: {detail}'**
  String searchNoticeFilePickerFailed(String detail);

  /// No description provided for @searchNoticeBatchCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling batch save...'**
  String get searchNoticeBatchCancelling;

  /// No description provided for @searchNoticeSelectAlbumOrPlaylistFirst.
  ///
  /// In en, this message translates to:
  /// **'Select an album or playlist first'**
  String get searchNoticeSelectAlbumOrPlaylistFirst;

  /// No description provided for @searchNoticeSelectAtLeastOneLyricsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select at least one lyrics language'**
  String get searchNoticeSelectAtLeastOneLyricsLanguage;

  /// No description provided for @searchNoticeNoSongsToSave.
  ///
  /// In en, this message translates to:
  /// **'There are no songs to save'**
  String get searchNoticeNoSongsToSave;

  /// No description provided for @searchNoticeBatchSaveCancelled.
  ///
  /// In en, this message translates to:
  /// **'Batch save cancelled: {saved} saved, {failed} failed, {skipped} skipped'**
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped);

  /// No description provided for @searchNoticeBatchSaveCompleted.
  ///
  /// In en, this message translates to:
  /// **'Batch save completed: {saved} saved, {failed} failed, {skipped} skipped'**
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped);

  /// No description provided for @searchNoticeBatchSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch save failed: {detail}'**
  String searchNoticeBatchSaveFailed(String detail);

  /// No description provided for @searchNoticeMultipleLyricsCandidates.
  ///
  /// In en, this message translates to:
  /// **'Multiple lyric candidates were found. Select one to continue'**
  String get searchNoticeMultipleLyricsCandidates;

  /// No description provided for @searchNoticeGetLyricsFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to get lyrics: {detail}'**
  String searchNoticeGetLyricsFailed(String detail);

  /// No description provided for @searchNoticeSelectSavePathFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a save path first'**
  String get searchNoticeSelectSavePathFirst;

  /// No description provided for @searchNoticeDirectoryPickFailed.
  ///
  /// In en, this message translates to:
  /// **'Directory selection failed: {detail}'**
  String searchNoticeDirectoryPickFailed(String detail);

  /// No description provided for @searchNoticePreviewLoading.
  ///
  /// In en, this message translates to:
  /// **'Lyrics are still loading'**
  String get searchNoticePreviewLoading;

  /// No description provided for @searchNoticePreviewNoLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select at least one lyrics language'**
  String get searchNoticePreviewNoLanguage;

  /// No description provided for @searchNoticePreviewNoContent.
  ///
  /// In en, this message translates to:
  /// **'The current lyrics have no previewable content'**
  String get searchNoticePreviewNoContent;

  /// No description provided for @searchNoticePreviewNoSelection.
  ///
  /// In en, this message translates to:
  /// **'Download and preview lyrics first'**
  String get searchNoticePreviewNoSelection;

  /// No description provided for @desktopWindowActionSelectLyrics.
  ///
  /// In en, this message translates to:
  /// **'Select lyrics'**
  String get desktopWindowActionSelectLyrics;

  /// No description provided for @desktopWindowActionMarkInstrumental.
  ///
  /// In en, this message translates to:
  /// **'Mark as instrumental'**
  String get desktopWindowActionMarkInstrumental;

  /// No description provided for @desktopWindowActionDisableAutoSearch.
  ///
  /// In en, this message translates to:
  /// **'Disable auto search for this song'**
  String get desktopWindowActionDisableAutoSearch;

  /// No description provided for @desktopWindowActionUnlinkLyrics.
  ///
  /// In en, this message translates to:
  /// **'Unlink lyrics'**
  String get desktopWindowActionUnlinkLyrics;

  /// No description provided for @desktopWindowActionAssociationManager.
  ///
  /// In en, this message translates to:
  /// **'Lyrics association manager'**
  String get desktopWindowActionAssociationManager;

  /// No description provided for @desktopWindowActionToggleFloating.
  ///
  /// In en, this message translates to:
  /// **'Show or hide desktop lyrics'**
  String get desktopWindowActionToggleFloating;

  /// No description provided for @desktopWindowActionShowMainWindow.
  ///
  /// In en, this message translates to:
  /// **'Show main window'**
  String get desktopWindowActionShowMainWindow;

  /// No description provided for @desktopWindowActionClickThrough.
  ///
  /// In en, this message translates to:
  /// **'Click-through'**
  String get desktopWindowActionClickThrough;

  /// No description provided for @desktopWindowActionPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get desktopWindowActionPrevious;

  /// No description provided for @desktopWindowActionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get desktopWindowActionPlay;

  /// No description provided for @desktopWindowActionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get desktopWindowActionPause;

  /// No description provided for @desktopWindowActionNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get desktopWindowActionNext;

  /// No description provided for @desktopWindowActionHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get desktopWindowActionHide;

  /// No description provided for @desktopTrayCurrentTarget.
  ///
  /// In en, this message translates to:
  /// **'Current target: '**
  String get desktopTrayCurrentTarget;

  /// No description provided for @desktopTrayNoSelection.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get desktopTrayNoSelection;

  /// No description provided for @desktopTrayTargetInstance.
  ///
  /// In en, this message translates to:
  /// **'Target instance'**
  String get desktopTrayTargetInstance;

  /// No description provided for @desktopTrayInstance.
  ///
  /// In en, this message translates to:
  /// **'Instance'**
  String get desktopTrayInstance;

  /// No description provided for @desktopTrayExit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get desktopTrayExit;

  /// No description provided for @desktopWindowInfoInstrumental.
  ///
  /// In en, this message translates to:
  /// **'Instrumental'**
  String get desktopWindowInfoInstrumental;

  /// No description provided for @desktopWindowControlConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'The player connection was lost. The action was not performed.'**
  String get desktopWindowControlConnectionLost;

  /// No description provided for @desktopWindowClientDisconnected.
  ///
  /// In en, this message translates to:
  /// **'The player connection was lost. Desktop lyrics were closed.'**
  String get desktopWindowClientDisconnected;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
