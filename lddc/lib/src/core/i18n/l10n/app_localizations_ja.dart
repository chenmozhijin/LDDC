// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => '警告';

  @override
  String get commonError => 'エラー';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonFailed => '失敗した';

  @override
  String get commonSkipped => 'スキップされました';

  @override
  String get commonTotal => '合計';

  @override
  String get commonDelete => '消去';

  @override
  String get commonConfirm => '確認する';

  @override
  String get commonRestoreDefault => 'デフォルトに戻す';

  @override
  String get commonEnabled => '有効';

  @override
  String get commonDisabledByDefault => 'デフォルトでは無効になっています';

  @override
  String get commonFormat => '形式';

  @override
  String get commonOffset => 'オフセット';

  @override
  String get commonSaving => '保存中...';

  @override
  String get commonAddFiles => 'ファイルの追加';

  @override
  String get commonClearQueue => 'キューをクリアする';

  @override
  String get commonUnsupportedOperation => 'この操作はこのプラットフォームではサポートされていません';

  @override
  String get commonLyricsFileUnavailable => 'このエントリには開く歌詞ファイルがまだありません';

  @override
  String get commonAudioTagRequiresLrc => 'ソングタグの歌詞には LRC 形式を使用する必要があります';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language ($type)';
  }

  @override
  String get commonTranslationCancelled => '翻訳が削除されました';

  @override
  String get commonCancelTranslation => '翻訳の削除';

  @override
  String get commonTranslating => '翻訳中...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return '$completed/$total を翻訳しています';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI ストリーミング変換: $completed / $total 行';
  }

  @override
  String get commonTranslationCompleted => '翻訳完了';

  @override
  String get commonLyricsSaved => '歌詞が保存されました';

  @override
  String commonDropFailed(String detail) {
    return 'ドロップに失敗しました: $detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return '保存ディレクトリの選択に失敗しました: $detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return '保存ディレクトリを開けませんでした: $detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return '変換に失敗しました: $detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return '歌詞の保存に失敗しました: $detail';
  }

  @override
  String get appErrorUnknown => '不明なエラーが発生しました。';

  @override
  String get appErrorOperationTimeout => '操作がタイムアウトになりました。後でもう一度試してください。';

  @override
  String get appErrorNetworkUnavailable => 'ネットワークが利用できません。接続を確認してください。';

  @override
  String get appErrorInvalidPayload => 'データ形式が無効です。';

  @override
  String get appErrorUnsupportedOperation => 'この操作はサポートされていません。';

  @override
  String get appErrorPermissionDenied => 'この操作を実行する権限がありません。';

  @override
  String get appErrorIoFailure => 'ファイルの読み取りまたは書き込みに失敗しました。';

  @override
  String get appErrorLyricsRequestFailed => '歌詞のリクエストに失敗しました。';

  @override
  String get appErrorLyricsNotFound => '歌詞が見つかりませんでした。';

  @override
  String get appErrorLyricsProcessing => '歌詞の処理に失敗しました。';

  @override
  String get appErrorLyricsDecrypt => '歌詞の解読に失敗しました。';

  @override
  String get appErrorLyricsFormatUnsupported => 'サポートされていない歌詞形式です。';

  @override
  String get appErrorDecoding => 'デコードに失敗しました。';

  @override
  String get appErrorSongInfoRead => '曲情報の読み込みに失敗しました。';

  @override
  String get appErrorUnsupportedFileType => 'サポートされていないファイル形式です。';

  @override
  String get appErrorDragDropInvalid => 'ドラッグ アンド ドロップ データが無効です。';

  @override
  String get appErrorTranslateFailed => '翻訳に失敗しました。';

  @override
  String get appErrorApiParamsInvalid => 'リクエストパラメータが無効です。';

  @override
  String get appErrorApiRequestFailed => 'API リクエストが失敗しました。';

  @override
  String get appErrorAutoFetchUnknown => '自動マッチングが不明なエラーにより失敗しました。';

  @override
  String get appErrorNotEnoughInfo => '検索するほどの情報がありません。';

  @override
  String get appErrorIpcInvalidLength => 'IPC メッセージの長さが無効です。';

  @override
  String get appErrorIpcUnsupportedTask => 'IPC タスクはサポートされていません。';

  @override
  String get appErrorIpcInstanceNotFound => 'IPC インスタンスが存在しません。';

  @override
  String get appErrorIpcPanelNotFound => 'IPCパネルが存在しません。';

  @override
  String get appErrorIpcInvalidWindowId => 'ウィンドウハンドルが無効です。';

  @override
  String get appErrorIpcEmbedUnsupported => 'このプラットフォームでは埋め込みモードはサポートされていません。';

  @override
  String get appErrorActionRetryNetwork => 'ネットワークを確認して再試行してください。';

  @override
  String get appErrorActionCheckPayload => '入力データ形式を確認してください。';

  @override
  String get appErrorActionChangeFormat => 'サポートされているファイルまたは形式を使用してください。';

  @override
  String get appErrorActionDetachedMode => '分離モードに戻ってください。';

  @override
  String get actionRetry => 'リトライ';

  @override
  String get actionViewDetails => '詳細を見る';

  @override
  String get actionCancel => 'キャンセル';

  @override
  String get sourceAggregate => '集計';

  @override
  String get sourceQQMusic => 'QQミュージック';

  @override
  String get sourceKugou => 'クゴウミュージック';

  @override
  String get sourceNetease => 'ネットイーズミュージック';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => '地元';

  @override
  String get lyricOriginal => 'オリジナル';

  @override
  String get lyricTranslation => '翻訳';

  @override
  String get lyricRomanized => 'ローマ字表記';

  @override
  String get lyricsFormatVerbatimLrc => 'ワードタイムLRC';

  @override
  String get lyricsFormatLineByLineLrc => 'ラインタイミング LRC';

  @override
  String get lyricsFormatEnhancedLrc => '拡張 LRC (ESLyric)';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => 'お尻';

  @override
  String get lyricsTypeVerbatim => 'ワードタイム';

  @override
  String get lyricsTypeLineByLine => 'ラインタイミング';

  @override
  String get lyricsTypePlainText => 'プレーンテキスト';

  @override
  String get searchSong => '歌';

  @override
  String get searchAlbum => 'アルバム';

  @override
  String get searchSongList => 'プレイリスト';

  @override
  String get searchArtist => 'アーティスト';

  @override
  String get searchLyrics => '歌詞';

  @override
  String get searchSongId => 'ソングID';

  @override
  String get localMatchIteratingFiles => 'ファイルをスキャン中...';

  @override
  String get localMatchProgressImportCompleted => 'インポートが完了しました';

  @override
  String get localMatchProgressScanCompleted => 'スキャンが完了しました';

  @override
  String get localMatchProgressScanFailed => 'スキャンに失敗しました';

  @override
  String get localMatchProgressMatchCompleted => '試合終了';

  @override
  String get localMatchProgressMatchFailed => '試合に失敗しました';

  @override
  String get localMatchProgressPreparingMatch => 'マッチングの準備をしています...';

  @override
  String get localMatchPreviewTagOnly => 'タグのみを書き込みます';

  @override
  String get localMatchPreviewWriteTag => 'タグに書き込む';

  @override
  String get localMatchPreviewNoOutput => '出力が設定されていません';

  @override
  String get localMatchPreviewSongTagOnly => 'ソングタグのみ';

  @override
  String get localMatchPendingLyricsFileName => 'ファイル名を決定するために一致する歌詞情報を待機しています';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / ファイル名を決定するために一致する歌詞情報を待機しています';
  }

  @override
  String get localMatchCalcSavePathFailed => '保存パスの計算に失敗しました';

  @override
  String get localMatchNoticeBusyImportFiles =>
      'タスクが実行中であるため、現在ファイルをインポートできません';

  @override
  String get localMatchNoticeSelectedFilesUnavailable => '選択したファイルは使用できません';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return 'ファイルのインポートに失敗しました: $detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories =>
      'タスクが実行中であるため、現在ディレクトリをインポートできません';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return 'ディレクトリのインポートに失敗しました: $detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles =>
      'ドロップされたデータにはアクセス可能なファイルが含まれていません';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return 'ドロップされた曲を解決できませんでした: $detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors =>
      'インポートは完了しましたが、一部のエントリを解析できませんでした';

  @override
  String get localMatchNoticeSafTreeUnsupported =>
      'このプラットフォームではディレクトリ ツリー アクセスはサポートされていません';

  @override
  String get localMatchNoticeBusySwitchTree =>
      'タスクが実行中であるため、現在ディレクトリ ツリーを変更できません';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return 'ディレクトリ ツリーの選択に失敗しました: $detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue => 'タスクが実行中であるため、現在キューをクリアできません';

  @override
  String get localMatchNoticeSelectItemsToDelete => '最初に削除するエントリを選択してください';

  @override
  String get localMatchNoticeSelectItemsToSetRoot =>
      'ルートディレクトリを設定する前にエントリを選択してください';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return 'これらの曲は選択されたルートの外にあるためスキップされました: $detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return 'ルート ディレクトリの設定に失敗しました: $detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore => '最初に復元するエントリを選択してください';

  @override
  String get localMatchNoticeCancelling => '現在のタスクをキャンセルしています...';

  @override
  String get localMatchNoticeValidationFailed => '最初にローカル一致要件を解決します';

  @override
  String get localMatchNoticeSongDirectoryUnavailable =>
      'このエントリでは曲ディレクトリを開けません';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return '曲ディレクトリを開けませんでした: $detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable =>
      'このエントリには開く保存ディレクトリがまだありません';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return '歌詞を開けませんでした: $detail';
  }

  @override
  String get localMatchNoticeScanCancelled => 'スキャンがキャンセルされました';

  @override
  String get localMatchNoticeScanCompletedWithErrors =>
      'スキャンは完了しましたが、一部のファイルを解析できませんでした';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return 'スキャンが失敗しました: $detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return 'ディレクトリ ツリーのスキャンに失敗しました: $detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => '試合中止';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '合計 $total 曲、$success が一致、$failed は失敗、$skipped はスキップされました。';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return 'ローカル一致が失敗しました: $detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume =>
      '試合はキャンセルされました。チェックポイントから再開するには再起動してください';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF ローカル一致が失敗しました: $detail';
  }

  @override
  String get localMatchValidationEmptyLangs => '一致する歌詞の言語を選択してください';

  @override
  String get localMatchValidationEmptySources => '少なくとも 1 つのソースを選択してください';

  @override
  String get localMatchValidationEmptyQueue => '最初に一致する曲をインポートします';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      'ファイルを保存しながら既存の歌詞をスキップする場合、ファイル名モードでは一致する歌詞情報を使用できません';

  @override
  String get localMatchValidationMissingAndroidTree => '最初にディレクトリ ツリーを選択します';

  @override
  String get localMatchValidationNeedsSaveRoot => '保存パスが必要です';

  @override
  String get localMatchValidationNeedsSongRoot => '曲のルートディレクトリが必要です';

  @override
  String get localMatchValidationUnknownSavePath => '不明な保存パスエラー';

  @override
  String get localMatchIntro =>
      'ローカルの曲またはフォルダーをインポートし、出力をプレビューしてから、バッチ マッチングを実行します。';

  @override
  String get localMatchDropUnsupportedItem =>
      'ローカル マッチでは、曲ファイル、フォルダー、または解析可能なプレーヤー アイテムを受け入れます';

  @override
  String get localMatchReadyToStart => 'ローカルマッチングを開始する準備ができました';

  @override
  String get localMatchQueueTitle => 'タスクキュー';

  @override
  String get localMatchQueueEmptyHint => 'ファイルまたはフォルダーをインポートしてタスクキューを構築する';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '$count タスク。さらにアクションを実行するには、行を右クリックします';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '$count タスク。長押しまたはさらにタップしてアクションを開きます';
  }

  @override
  String get localMatchImportAndRunTitle => 'インポートして実行';

  @override
  String get localMatchActionStart => 'マッチングを開始する';

  @override
  String get localMatchActionAddFolders => 'フォルダーの追加';

  @override
  String get localMatchActionSelectSaveRoot => '「ルートの保存」を選択します';

  @override
  String get localMatchActionSelectTree => 'ツリーの選択';

  @override
  String get localMatchActionReselectTree => 'ツリーを再選択';

  @override
  String get localMatchActionBulkSelect => '一括選択';

  @override
  String get localMatchActionExitSelection => '一括選択を終了する';

  @override
  String get localMatchActionSelectAll => 'すべて選択';

  @override
  String get localMatchActionDeselectAll => 'すべての選択を解除';

  @override
  String get localMatchActionSetRoot => 'ルートの設定';

  @override
  String localMatchSelectedCount(int count) {
    return '$count が選択されました';
  }

  @override
  String get localMatchBulkActionHint => '一括アクションは選択したタスクに直接適用されます';

  @override
  String get localMatchPhaseIdle => '待っている';

  @override
  String get localMatchPhaseScanning => '走査';

  @override
  String get localMatchPhaseMatching => 'マッチング';

  @override
  String get localMatchPhaseWriting => '書き込み';

  @override
  String get localMatchPhaseCompleted => '完了';

  @override
  String get localMatchPhaseHintIdle => '曲をインポートしてマッチングを開始する';

  @override
  String get localMatchPhaseHintScanning => 'タスクキューの構築と出力の見積もり';

  @override
  String get localMatchPhaseHintMatching => 'ソースを照会し、最適な一致を計算する';

  @override
  String get localMatchPhaseHintWriting => '歌詞ファイルまたは曲タグの書き込み';

  @override
  String get localMatchPhaseHintCompleted => 'この実行は完了です。必要に応じて調整して再度実行します';

  @override
  String get localMatchPipelineIdle => 'スキャン -> 照合 -> 書き込み';

  @override
  String get localMatchPipelineScanning => '現在の段階: スキャン';

  @override
  String get localMatchPipelineMatching => '現在のステージ: 試合';

  @override
  String get localMatchPipelineWriting => '現在の段階: 書き込み';

  @override
  String get localMatchPipelineCompleted => 'スキャン、照合、書き込みが完了しました';

  @override
  String get localMatchUnknownSong => '未知の曲';

  @override
  String get localMatchUnknownDuration => '不明な期間';

  @override
  String get localMatchStatusNotStarted => '未開始';

  @override
  String get localMatchSongPathLabel => '歌の道';

  @override
  String get localMatchLyricsPathLabel => '歌詞の保存パス';

  @override
  String get localMatchExpandDetails => '詳細を展開する';

  @override
  String get localMatchCollapseDetails => '詳細を折りたたむ';

  @override
  String get localMatchRowActionOpenInSearch => '検索で開く';

  @override
  String get localMatchRowActionEnterSelection => '一括選択を入力してください';

  @override
  String get localMatchRowActionOpenSongDirectory => 'ソングフォルダーを開く';

  @override
  String get localMatchRowActionOpenSaveDirectory => '保存フォルダーを開く';

  @override
  String get localMatchRowActionOpenLyrics => '歌詞を開く';

  @override
  String get localMatchFieldLyricsType => '歌詞の種類';

  @override
  String get localMatchFieldOutputStrategy => 'アウトプット戦略';

  @override
  String get localMatchFieldSaveMode => 'セーブモード';

  @override
  String get localMatchFieldFileNameMode => 'ファイル名モード';

  @override
  String get localMatchFieldLyricsFormat => '歌詞の形式';

  @override
  String get localMatchFieldThreshold => '一致しきい値';

  @override
  String get localMatchFieldSaveRoot => 'ルートの保存';

  @override
  String get localMatchMoreSettings => 'その他の設定';

  @override
  String get localMatchRulesTitle => '試合ルール';

  @override
  String get localMatchRulesSubtitle => 'ソース、言語、出力戦略、およびしきい値';

  @override
  String get localMatchMinScore => '最低スコア';

  @override
  String get localMatchSkipExisting => '既存の歌詞をスキップする';

  @override
  String get localMatchSkipExistingConflictHint =>
      '現在の出力戦略とファイル名モードでは、既存の歌詞をスキップできません。ファイルを保存する必要がある場合は、一致する歌詞情報に基づいて名前を付けることは避けてください。';

  @override
  String get localMatchSaveToSongDirectoryHint =>
      'ソングフォルダーへの保存には、追加の保存ルートは必要ありません。';

  @override
  String get localMatchAndroidTreeSaveHint =>
      'Android ディレクトリ ツリーの保存は、承認されたツリーに直接書き込まれます。';

  @override
  String get localMatchFileNameTemplateHint =>
      'ファイル名のテンプレートは、設定の Lyrics_file_name_fmt を使用します。';

  @override
  String localMatchSaveRootPath(String path) {
    return 'ルートを保存: $path';
  }

  @override
  String get localMatchSaveRootRequired =>
      'この保存モードには保存ルートが必要です。まず 1 つ選択してください。';

  @override
  String get localMatchTreeNotSelected => 'ディレクトリツリーが選択されていません';

  @override
  String get localMatchSaveModeSong => 'ソングフォルダーに保存';

  @override
  String get localMatchSaveModeMirror => 'ミラーフォルダー';

  @override
  String get localMatchSaveModeSpecify => '特定のフォルダー';

  @override
  String get localMatchFileNameModeSong => 'ソングファイル名を使用する';

  @override
  String get localMatchFileNameModeFormatBySong => '曲情報による名前';

  @override
  String get localMatchFileNameModeFormatByLyrics => '歌詞情報による名前';

  @override
  String get localMatchFileNameHintSong => 'オーディオ ファイル名を再利用し、歌詞の拡張子のみを置き換えます。';

  @override
  String get localMatchFileNameHintFormatBySong =>
      'タイトル、アーティスト、アルバムなどの曲のメタデータからファイル名を生成します。';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      '一致した歌詞曲情報からファイル名を生成します。マッチングする前には分からない可能性があります。';

  @override
  String get localMatchSaveToTagOnlyFile => 'ファイルのみ';

  @override
  String get localMatchSaveToTagOnlyTag => 'タグのみ';

  @override
  String get localMatchSaveToTagBoth => 'ファイル + タグ';

  @override
  String get localMatchValidationTitle => '始める前に修正すべき問題';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '$count さらに多くの問題を修正する必要があります';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable =>
      '選択したファイルには直接アクセスできません';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return '$count 歌詞ファイルをインポートしました';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles =>
      'ドロップされたデータにはアクセス可能な歌詞ファイルが含まれていません';

  @override
  String get batchConvertNoticeEmptyQueue => '最初に変換する歌詞ファイルを追加します';

  @override
  String get batchConvertNoticeOverwriteCancelled => 'バッチ変換がキャンセルされました';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return 'バッチ変換がキャンセルされ、$count アイテムが完了しました';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return 'バッチ変換が完了しました: $success は成功しました、$failure は失敗しました';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return 'バッチ変換が完了しました: $count アイテム';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return 'バッチ変換が失敗しました: $detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return 'ソース ディレクトリを開けませんでした: $detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return '歌詞ファイルを開けませんでした: $detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles =>
      '選択したフォルダー内にサポートされている歌詞ファイルが見つかりませんでした';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return '$count 歌詞ファイルをフォルダーからインポートしました';
  }

  @override
  String get batchConvertNoticeDuplicateItems => '選択されたすべてのエントリはすでにキュー内にあります';

  @override
  String get batchConvertControlsTitle => 'インポートと設定';

  @override
  String get batchConvertCompactControlsTitle => 'インポートと出力の設定';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return '形式: $format';
  }

  @override
  String get batchConvertImportTitle => '輸入';

  @override
  String get batchConvertAddFolders => 'フォルダーの追加';

  @override
  String get batchConvertOutputSettingsTitle => '出力設定';

  @override
  String get batchConvertTargetFormat => 'ターゲットフォーマット';

  @override
  String get batchConvertSaveDirectoryTitle => '保存フォルダー';

  @override
  String get batchConvertSaveDirectoryDefault =>
      '設定を解除すると、出力はソース歌詞ファイルの次に出力されます。';

  @override
  String get batchConvertSelectSaveDirectory => '保存フォルダーを選択してください';

  @override
  String get batchConvertRestoreOriginalDirectory => 'ソースフォルダーを使用する';

  @override
  String get batchConvertRecursiveTitle => 'サブフォルダーをスキャンする';

  @override
  String get batchConvertRecursiveSubtitle =>
      'フォルダーをインポートするときに、サブフォルダー内の歌詞ファイルのスキャンを続けます';

  @override
  String get batchConvertStart => '変換の開始';

  @override
  String get batchConvertCancel => '変換のキャンセル';

  @override
  String get batchConvertQueueTitle => '変換キュー';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '$count 項目、出力形式 $format';
  }

  @override
  String get batchConvertPageErrorFallback => 'バッチ変換ページでエラーが発生しました';

  @override
  String get batchConvertRetryImport => '再インポート';

  @override
  String get batchConvertEmptyQueue =>
      '歌詞ファイルまたはフォルダーを追加すると、バッチ変換キューがここに表示されます。';

  @override
  String get batchConvertOutputPathLabel => '出力パス';

  @override
  String get batchConvertQueueStatusWaiting => '待っている';

  @override
  String get batchConvertQueueStatusRunning => '変換中';

  @override
  String get batchConvertQueueStatusSuccess => '変換された';

  @override
  String get batchConvertQueueStatusFailure => '失敗した';

  @override
  String get batchConvertMoreActions => 'さらなるアクション';

  @override
  String get batchConvertActionOpenSourceDirectory => 'オープンソースフォルダー';

  @override
  String get batchConvertActionOpenSaveDirectory => '保存フォルダーを開く';

  @override
  String get batchConvertActionOpenOutputFile => '歌詞ファイルを開く';

  @override
  String get batchConvertActionOpenInOpenLyrics => 'オープン・イン・オープン 歌詞';

  @override
  String get batchConvertPhaseIdle => '待っている';

  @override
  String get batchConvertPhaseScanning => '走査';

  @override
  String get batchConvertPhaseRunning => '変換中';

  @override
  String get batchConvertPhaseCompleted => '完了';

  @override
  String get batchConvertPipelineIdle => 'インポート -> スキャン -> 変換 -> 完了';

  @override
  String get batchConvertPipelineScanning => 'フォルダーのスキャン -> キューの構築';

  @override
  String get batchConvertPipelineRunning => '各項目を変換→ステータスを更新';

  @override
  String get batchConvertPipelineCompleted => 'フォーマットを調整するか、再度インポートしてください';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return 'キャンセルされました、$success は成功しました、$failure は失敗しました';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '$success は成功しました、$failure は失敗しました';
  }

  @override
  String get batchConvertHintNoQueue => 'ファイルまたはフォルダーを追加して変換を開始します';

  @override
  String get batchConvertHintReady => '行列の準備ができました';

  @override
  String get batchConvertMetricWaiting => '待っている';

  @override
  String get batchConvertDropUnsupported => 'バッチ変換ページは歌詞ファイルまたはフォルダーのみを受け入れます';

  @override
  String batchConvertDropFailed(String detail) {
    return 'ドロップの処理に失敗しました: $detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return '$fileName を変換しています';
  }

  @override
  String get batchConvertProgressItemSuccess => '変換された';

  @override
  String get batchConvertProgressItemFailure => '失敗した';

  @override
  String get batchConvertProgressPreparingConversion => '変換を準備しています...';

  @override
  String get batchConvertProgressCancellingConversion => '変換をキャンセルしています...';

  @override
  String get batchConvertProgressConversionCancelled => '変換がキャンセルされました';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return '変換が完了しました: $success は成功しました、$failure は失敗しました';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return '変換に失敗しました: $detail';
  }

  @override
  String get batchConvertProgressScanningFolders => 'フォルダーをスキャン中...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return '$directoryName をスキャンしています';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return '$count 歌詞ファイルが見つかりました';
  }

  @override
  String get batchConvertProgressScanCancelled => 'スキャンがキャンセルされました';

  @override
  String get batchConvertProgressScanNoSupportedFiles =>
      'サポートされている歌詞ファイルが見つかりません';

  @override
  String get batchConvertProgressScanCompleted => 'スキャンが完了しました';

  @override
  String get navSearch => '検索';

  @override
  String get navLocalMatch => 'ローカルマッチ';

  @override
  String get navOpenLyrics => '歌詞を開く';

  @override
  String get navBatchConvert => 'バッチ変換';

  @override
  String get navSettings => '設定';

  @override
  String get navAbout => 'について';

  @override
  String get commonSearch => '検索';

  @override
  String get commonSource => 'ソース';

  @override
  String get searchKeywordHint => 'キーワードを入力してください';

  @override
  String get uiLoading => '読み込み中...';

  @override
  String get uiLoadingStepFetching => 'リストとプレビューを取得しています...';

  @override
  String get uiEmpty => 'データなし';

  @override
  String get uiNoMoreResult => 'これ以上の結果はありません';

  @override
  String get searchInitialResultTitle => 'キーワードを入力して検索を開始します';

  @override
  String get searchInitialResultDescription => '上のソースを選択して検索を実行してください';

  @override
  String get searchResultTitle => '検索結果';

  @override
  String get searchResultReturn => '戻る';

  @override
  String get searchPreviewTitle => '歌詞プレビュー';

  @override
  String get searchPreviewLangsLabel => '言語';

  @override
  String get searchPreviewSongIdLabel => 'ソングID';

  @override
  String get searchPreviewPlaceholder => '最初に曲または歌詞項目を選択してください';

  @override
  String get searchPreviewNoLanguage => '少なくとも 1 つの歌詞言語を選択してください';

  @override
  String get searchPreviewNoContent => 'プレビュー可能なコンテンツはありません';

  @override
  String get searchPreviewLoading => '歌詞を読み込んでいます...';

  @override
  String get searchFormatLabel => '歌詞の形式';

  @override
  String get searchTranslateLyrics => '歌詞を翻訳する';

  @override
  String get searchResizeWorkspacePanes => '検索結果のサイズ変更と歌詞プレビュー';

  @override
  String get searchSavePreviewToDirectory => 'フォルダーに保存';

  @override
  String get searchSavePreviewToFile => 'ファイルに保存';

  @override
  String get searchSavePreviewToTag => 'プレビューをタグに保存';

  @override
  String get searchSaveListLyrics => 'アルバム/プレイリストの歌詞を保存';

  @override
  String get searchSaveListLyricsCancel => '一括保存をキャンセルする';

  @override
  String get searchSelectSavePath => '保存フォルダーを選択してください';

  @override
  String get searchBatchSaveProgressTitle => 'バッチ保存の進行状況';

  @override
  String get searchBatchSaveProgressPreparing => 'バッチ保存を準備しています...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return '$songName の歌詞を取得しています...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count 曲';
  }

  @override
  String get searchTableStatusAutoFetching => '自動取得中...';

  @override
  String get searchTableStatusSearching => '検索中...';

  @override
  String get searchTableStatusFetchingSongList => '曲リストを取得中...';

  @override
  String get searchTableStatusNoResults => '一致する結果が見つかりませんでした';

  @override
  String get searchTableStatusEmptyList => 'リストは空です';

  @override
  String get searchTableStatusUnsupportedSearchType =>
      '選択したソースはこの検索タイプをサポートしていません';

  @override
  String get searchTableStatusSearchFailed => '検索に失敗しました';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return '検索に失敗しました: $detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return '自動フェッチに失敗しました: $detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return '曲リストの取得に失敗しました: $detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable =>
      '一部のソースは利用できません。利用可能な結果を​​表示中';

  @override
  String get searchTableStatusLoadMoreFailed => '一部のソースがさらに結果をロードできませんでした';

  @override
  String get searchSourceFailureDetailsTitle => '検索エラーの詳細';

  @override
  String get searchSourceFailureRequest => 'リクエストが失敗しました';

  @override
  String get searchSourceFailureTimeout => 'リクエストがタイムアウトしました';

  @override
  String get searchSourceFailureParameters => '無効なパラメータ';

  @override
  String get searchSourceFailureUnsupported => 'サポートされていない操作';

  @override
  String get searchSourceFailureUnknown => '不明なエラー';

  @override
  String get searchResultLoadingMore => 'さらに結果を読み込んでいます...';

  @override
  String get searchResultLoadMoreFailed =>
      '自動ロードに失敗しました。残りの結果のロードを続行するには再試行してください';

  @override
  String get searchResultScrollForMore => '下にスクロールすると、さらに結果が自動的に読み込まれます';

  @override
  String get tableSavePath => 'パスの保存';

  @override
  String get settingsSectionSave => '保存';

  @override
  String get settingsSectionLyrics => '歌詞';

  @override
  String get settingsSectionDesktopLyrics => 'デスクトップの歌詞';

  @override
  String get settingsSectionTranslate => '翻訳する';

  @override
  String get settingsSectionSearch => '検索';

  @override
  String get settingsSectionApp => 'アプリ';

  @override
  String get settingsSectionTools => 'ツールとデータ';

  @override
  String get settingsSectionSaveSummary => '保存パス、ファイル名テンプレート、ID3 バージョン';

  @override
  String get settingsSectionSearchSummary =>
      '集約検索とローカルマッチング用のデフォルトの歌詞ソースを選択します。';

  @override
  String get settingsSectionDesktopLyricsSummary =>
      'デスクトップの歌詞の自動取得、表示言語、外観、リフレッシュ レート。';

  @override
  String get settingsSectionLyricsSummary => 'ローカルマッチング動作と歌詞ファイルのエクスポート形式。';

  @override
  String get settingsSectionTranslateSummary => '翻訳元、訳文言語、条件フィールド';

  @override
  String get settingsSectionAppSummary => '言語、テーマ、ログ、および更新ポリシー';

  @override
  String get settingsSectionToolsSummary =>
      'デスクトップ ツール、ログ フォルダー、およびキャッシュのクリーンアップ';

  @override
  String get settingsTranslateSourceBing => 'Bing 翻訳';

  @override
  String get settingsTranslateSourceGoogle => 'Google翻訳';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI互換API';

  @override
  String get settingsLangSimplifiedChinese => '簡体字中国語';

  @override
  String get settingsLangTraditionalChinese => '繁体字中国語';

  @override
  String get settingsLangEnglish => '英語';

  @override
  String get settingsLangJapanese => '日本語';

  @override
  String get settingsLangKorean => '韓国語';

  @override
  String get settingsLangSpanish => 'スペイン語';

  @override
  String get settingsLangFrench => 'フランス語';

  @override
  String get settingsLangPortuguese => 'ポルトガル語';

  @override
  String get settingsLangGerman => 'ドイツ語';

  @override
  String get settingsLangRussian => 'ロシア';

  @override
  String get settingsAppLanguageAuto => '自動';

  @override
  String get settingsColorSchemeAuto => 'フォローシステム';

  @override
  String get settingsColorSchemeLight => 'ライト';

  @override
  String get settingsColorSchemeDark => '暗い';

  @override
  String get settingsDesktopGradientColors => 'グラデーションカラー';

  @override
  String get settingsDesktopPlayedColors => '遊んだ色';

  @override
  String get settingsDesktopUnplayedColors => '未再生の色';

  @override
  String get settingsAddColor => '色を追加する';

  @override
  String get settingsEditColor => '色の編集';

  @override
  String get settingsDeleteColor => '色の削除';

  @override
  String get settingsBackToSections => '設定セクションに戻る';

  @override
  String get settingsAvailablePlaceholders => '利用可能なプレースホルダー';

  @override
  String get settingsPlaceholderTitleArtist =>
      'タイトル: %<title> アーティスト: %<artist>';

  @override
  String get settingsPlaceholderAlbumId => 'アルバム: %<album> 曲/歌詞 ID: %<id>';

  @override
  String get settingsPlaceholderLangs => '言語タイプ: %<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return '現在のテンプレート: $template';
  }

  @override
  String get settingsTranslateSourceLabel => '翻訳元';

  @override
  String get settingsTranslateTargetLabel => '対象言語';

  @override
  String get settingsOpenAiProfileLabel => 'プリセット';

  @override
  String get settingsOpenAiProfileHelper =>
      '組み込みプロバイダーは、ベース URL を自動的に入力します。 API キーとモデルを設定する必要があります。';

  @override
  String get settingsAppLanguageLabel => 'インターフェース言語';

  @override
  String get settingsColorSchemeLabel => 'テーマモード';

  @override
  String get settingsLogLevelLabel => 'ログレベル';

  @override
  String get settingsLogLevelHelper =>
      '情報は通常の使用のために保管してください。 TRACE と DEBUG はより詳細に記録し、より大きなログを作成します。';

  @override
  String get settingsAutoCheckUpdateLabel => 'アップデートの自動チェック';

  @override
  String get settingsRestoreDefaultsWarning =>
      'デフォルトを復元すると、構成がすぐに書き込まれます。続行する前に確認してください。';

  @override
  String get settingsRestoreAllTitle => 'デフォルト設定の復元';

  @override
  String get settingsRestoreAllContent => 'これにより、すべての設定が復元され、構成にすぐに書き込まれます。';

  @override
  String get settingsRestoreAllAction => 'デフォルト設定の復元';

  @override
  String get settingsOpenAssociationManager => 'オープン歌詞協会マネージャー';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      '次の設定ページを開いて、曲と歌詞の関連付けを管理します。';

  @override
  String get settingsOpenLogDirectory => 'ログディレクトリを開く';

  @override
  String get settingsOpenLogDirectorySubtitle =>
      '実行時ログとトラブルシューティング ファイルを表示します。';

  @override
  String get settingsClearCache => 'キャッシュのクリア';

  @override
  String get settingsClearCacheSubtitle => '設定ファイルを変更せずに検索と翻訳のキャッシュをクリアします。';

  @override
  String get settingsClearCacheContent =>
      'キャッシュをクリアした後、その後の検索や変換で再度データが要求される場合があります。';

  @override
  String get settingsRestoreSectionTitle => 'このセクションを復元する';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return '「$sectionTitle」セクションの設定のみが復元されます。他のセクションは変更されません。';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return '$sectionTitle をデフォルトに戻す';
  }

  @override
  String get settingsDefaultSavePathHelper =>
      'プラットフォームのデフォルトの音楽ディレクトリを使用するには、空のままにしておきます。';

  @override
  String get settingsChooseFolder => 'フォルダーの選択';

  @override
  String get settingsLyricsFileNameFormat => '歌詞ファイル名のテンプレート';

  @override
  String get settingsLyricsFileNameFormatHelper =>
      '保存されたファイル名を作成するには、以下のプレースホルダーを使用します。';

  @override
  String get settingsId3Version => 'ID3バージョン';

  @override
  String get settingsId3VersionHelper =>
      'オーディオタグに書き込まれた歌詞のみに影響します。不明な場合は、v2.3 をそのままにしておいてください。';

  @override
  String get settingsSearchSourcesTitle => '集約検索ソース';

  @override
  String get settingsSearchSourcesDescription =>
      '検索で集計を使用する場合、チェックされたソースがクエリされます。リストの上位にあるソースは、結果のグループ化と自動マッチングで最初にランクされます。 Local Match はデフォルトでこのリストを使用します。';

  @override
  String get settingsReorderPriorityHint => 'ドラッグして優先度を変更します';

  @override
  String get settingsReorderOrderHint => 'ドラッグして順序を変更します';

  @override
  String get settingsDefaultLanguage => 'デフォルトの表示言語';

  @override
  String get settingsDefaultLanguageDescription =>
      'デスクトップの歌詞にデフォルトで表示される言語を選択し、ドラッグして表示順序を変更します。';

  @override
  String get settingsDesktopAutoFetchSources => 'ソースの自動取得';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      'デスクトップの歌詞にリンクされた歌詞がない場合、ソースは上から下に試行されます。';

  @override
  String get settingsFont => 'フォント';

  @override
  String get settingsFollowSystemFont => 'システムフォントに従う';

  @override
  String get settingsFontSizeByResize =>
      'デスクトップの歌詞ウィンドウのサイズを変更して、メインのフォント サイズを調整します。';

  @override
  String get settingsPanelFontSize => '歌詞パネルのフォントサイズ';

  @override
  String get settingsAdaptiveRefreshRate => 'アダプティブリフレッシュレート';

  @override
  String get settingsAdaptiveRefreshRateSubtitle =>
      '歌詞アニメーションの状態に基づいて更新頻度を自動的に選択します。';

  @override
  String get settingsFixedRefreshRate => '固定リフレッシュレート';

  @override
  String get settingsShowFurigana => 'ふりがなを表示';

  @override
  String get settingsLyricsMatchBehavior => 'マッチング動作';

  @override
  String get settingsLyricsMatchBehaviorDescription =>
      'ローカルマッチングおよびKugou歌詞候補のデフォルトの処理を設定します。';

  @override
  String get settingsLyricsExport => 'LRC エクスポート';

  @override
  String get settingsLyricsExportDescription =>
      '歌詞ファイルを保存するときに使用する言語順序と LRC タイムスタンプ形式を設定します。';

  @override
  String get settingsDisplayOrder => 'エクスポート言語の順序';

  @override
  String get settingsDisplayOrderDescription =>
      'ドラッグして、エクスポートされたファイル内のオリジナルの歌詞、翻訳された歌詞、ローマ字表記の歌詞を配置します。';

  @override
  String get settingsSkipInstrumental => 'インストゥルメンタルトラックをスキップする';

  @override
  String get settingsSkipInstrumentalSubtitle =>
      'Local Match でインストゥルメンタル トラックが特定された場合は、歌詞を保存しないでください。';

  @override
  String get settingsAutoSelectKugou => '九号候補自動選択';

  @override
  String get settingsAutoSelectKugouSubtitle =>
      '検索で Kugou の曲を開くと、最適な歌詞候補が自動的に選択されます。';

  @override
  String get settingsAddLrcEndTimestamp => 'LRC のエクスポート時に終了タイムスタンプを追加する';

  @override
  String get settingsAddLrcEndTimestampSubtitle =>
      '行ごとの LRC にのみ影響し、必要に応じて行終了タイムスタンプを書き込みます。';

  @override
  String get settingsMillisecondsDigits => 'ミリ秒桁';

  @override
  String get settingsMillisecondsDigitsHelper =>
      'センチ秒には 2 桁を使用し、ミリ秒を完全に保持するには 3 桁を使用します。';

  @override
  String settingsDigitsValue(int value) {
    return '$value 桁';
  }

  @override
  String get settingsLastRefStyle => '最後の言語行のタイムスタンプ';

  @override
  String get settingsLastRefStyleHelper =>
      '複数言語の行ごとの LRC の場合は、現在の行時刻、または最後の言語行の次の行の 1 ミリ秒前を使用します。';

  @override
  String get settingsLastRefCurrentLine => '現在の行時間を使用';

  @override
  String get settingsLastRefNextLine => '次の行の前に 1 ミリ秒を使用する';

  @override
  String get settingsTagInfoSource => 'タグ情報ソース';

  @override
  String get settingsTagInfoLyricsSource => '歌詞ソース';

  @override
  String get settingsTagInfoSongInfo => '曲情報';

  @override
  String get settingsNoticeDefaultSavePathUpdated => 'デフォルトの保存先を更新しました';

  @override
  String get settingsNoticeDefaultSavePathRestored => 'デフォルトの保存先を復元しました';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated =>
      '歌詞ファイル名テンプレートを更新しました';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3バージョンが更新されました';

  @override
  String get settingsNoticeLyricsLangOrderEmpty => '歌詞の言語順序を空にすることはできません';

  @override
  String get settingsNoticeLyricsLangOrderUpdated => '歌詞の言語順序を更新しました';

  @override
  String get settingsNoticeSkipInstUpdated => '楽器スキップポリシーが更新されました';

  @override
  String get settingsNoticeAutoSelectUpdated => '自動選択ポリシーが更新されました';

  @override
  String get settingsNoticeAddEndTimestampUpdated => '終了タイムスタンプポリシーが更新されました';

  @override
  String get settingsNoticeMsDigitsUpdated => 'ミリ秒の桁が更新されました';

  @override
  String get settingsNoticeLastRefStyleUpdated => '最終行時間スタイルが更新されました';

  @override
  String get settingsNoticeTagInfoSourceUpdated => 'タグ情報ソースが更新されました';

  @override
  String get settingsNoticeDesktopSourcesEmpty => 'デスクトップの歌詞ソースを空にすることはできません';

  @override
  String get settingsNoticeDesktopSourcesUpdated => 'デスクトップの歌詞ソースが更新されました';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty =>
      'デスクトップのデフォルト言語を空にすることはできません';

  @override
  String get settingsNoticeDesktopLangsUpdated => 'デスクトップの歌詞言語設定が更新されました';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated => 'デスクトップの歌詞フォントが更新されました';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => 'リフレッシュレートが更新されました';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated => '再生色を更新しました';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated => '未再生のカラーが更新されました';

  @override
  String get settingsNoticeDesktopFontSizeUpdated =>
      'デスクトップの歌詞のフォントサイズが更新されました';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated =>
      'デスクトップパネルのフォントサイズが更新されました';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated => 'ふりがな表示ポリシーが更新されました';

  @override
  String get settingsNoticeTranslateSourceUpdated => '翻訳ソースを更新しました';

  @override
  String get settingsNoticeTranslateTargetLangUpdated => '翻訳対象言語が更新されました';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI プリセットが更新されました';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI ベース URL が更新されました';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI APIキーが更新されました';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI モデルが更新されました';

  @override
  String get settingsNoticeSearchSourcesEmpty => '集約検索ソースを空にすることはできません';

  @override
  String get settingsNoticeSearchSourcesUpdated => '集約検索ソースが更新されました';

  @override
  String get settingsNoticeAppLanguageUpdated => 'インターフェース言語が更新されました';

  @override
  String get settingsNoticeAppColorSchemeUpdated => 'テーマモードが更新されました';

  @override
  String get settingsNoticeAppLogLevelUpdated => 'ログレベルが更新されました';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated => '更新の自動チェック設定が更新されました';

  @override
  String get settingsNoticeSectionNoRestorableConfig =>
      'このセクションには復元可能な構成項目がありません';

  @override
  String get settingsNoticeSectionDefaultsRestored => '現在のセクションのデフォルトが復元されました';

  @override
  String get settingsNoticeAllDefaultsRestored => 'アプリケーション設定がデフォルトに復元されました';

  @override
  String get settingsNoticeAssociationManagerOpened => '作詞協会マネージャー開設';

  @override
  String get settingsNoticeLogDirectoryOpened => 'ログディレクトリが開かれました';

  @override
  String get settingsNoticeLogDirectoryOpenFailed => 'ログディレクトリを開けませんでした';

  @override
  String get settingsNoticeCacheCleared => 'キャッシュがクリアされました';

  @override
  String get settingsNoticeCacheClearFailed => 'キャッシュのクリアに失敗しました';

  @override
  String get settingsNoticeConfigWriteFailed => '設定の書き込みに失敗しました';

  @override
  String get settingsCurrentSavePathLabel => 'デフォルトの保存パス';

  @override
  String get aboutLoadFailed => 'メタデータに関する読み込みに失敗しました。';

  @override
  String get aboutActionOpenRepository => 'GitHub リポジトリ';

  @override
  String get aboutActionCheckUpdate => 'アップデートを確認する';

  @override
  String get aboutHeroHeadline => '正確な歌詞を実現するために構築';

  @override
  String get aboutHeroDescription =>
      'LDDC は、検索、変換、デスクトップ歌詞、およびバッチ ワークフローを 1 つの効率的な画面に統合するため、歌詞の検索、整理、使用を迅速かつ集中的に行うことができます。';

  @override
  String get aboutLinksSectionTitle => 'クイックリンク';

  @override
  String get aboutLinksSectionDescription =>
      'フィードバック チャネル、リリース ノート、またはライセンスの詳細が必要な場合は、これらのリンクを使用してください。';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return '著作権 (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return '$license に基づいてライセンスが付与されています。';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub リポジトリ';

  @override
  String get aboutLinkIssueTrackerTitle => '問題追跡ツール';

  @override
  String get aboutLinkIssueTrackerDescription => 'バグ、UX のギャップ、機能のリクエストを報告します。';

  @override
  String get aboutLinkLicenseTitle => 'ライセンス';

  @override
  String get aboutLinkLicenseDescription => '現在のオープンソース ライセンスを確認します。';

  @override
  String get aboutLinkChangelogTitle => 'リリースノート';

  @override
  String get aboutLinkChangelogDescription => '公開されたバージョンとその変更の概要を参照してください。';

  @override
  String get aboutExternalLinksUnavailable =>
      'このプラットフォームでは、外部リンクを開くことはサポートされていません。';

  @override
  String get aboutCheckUpdateUnavailable =>
      'このプラットフォームではアップデートの確認はサポートされていません。';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes => 'リリースノートページを開設しました。';

  @override
  String get aboutCheckUpdateUpToDate => 'すでに最新バージョンを使用しています。';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return '新しいバージョンが見つかりました: $version。詳細については、リリース ノート ページを開いてください。';
  }

  @override
  String get aboutCheckUpdateFailed => 'アップデートの確認に失敗しました。後でもう一度試してください。';

  @override
  String aboutActionOpenedLink(String title) {
    return '$title をオープンしました';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return '$title を開けませんでした';
  }

  @override
  String get actionConfirm => '確認する';

  @override
  String get libraryLinkManagerTitle => '作詞協会マネージャー';

  @override
  String get libraryLinkManagerReturnToSettings => '設定に戻る';

  @override
  String get libraryLinkManagerRefresh => 'リフレッシュ';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return '選択したものを削除 ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => 'すべて削除';

  @override
  String get libraryLinkManagerClearInvalid => '無効なデータの消去';

  @override
  String get libraryLinkManagerChangeDirectory => 'ディレクトリの一括変更';

  @override
  String get libraryLinkManagerBackupToJson => 'JSONへのバックアップ';

  @override
  String get libraryLinkManagerRestoreFromJson => 'JSONから復元';

  @override
  String get libraryLinkManagerRestoreAction => '復元する';

  @override
  String get libraryLinkManagerExportLyrics => '歌詞のエクスポート';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '$totalCount レコード · $selectedCount が選択されました';
  }

  @override
  String get libraryLinkManagerSearchHint => '曲、アーティスト、アルバム、またはパスを検索する';

  @override
  String get libraryLinkManagerClearSearch => '検索をクリア';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '$totalCount が一致 · $selectedCount が選択されました';
  }

  @override
  String get libraryLinkManagerEmpty => '歌詞リンクレコードなし';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return '歌詞リンク レコードのロードに失敗しました: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess => '選択した歌詞リンクを削除しました';

  @override
  String get libraryLinkManagerDeleteAllConfirm =>
      'すべての歌詞リンク レコードを削除してもよろしいですか?';

  @override
  String get libraryLinkManagerDeleteAllSuccess => 'すべての歌詞リンクレコードを削除しました';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return '$count 無効なレコードをクリアしました';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return 'ディレクトリの書き換え後に $count レコードを更新しました';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return '$path にバックアップされた歌詞リンク データ';
  }

  @override
  String get libraryLinkManagerRestoreConfirm =>
      '復元すると、現在の歌詞リンク レコードがすべて上書きされます。続く？';

  @override
  String get libraryLinkManagerRestoreSuccess => '歌詞リンクデータ復旧しました';

  @override
  String get libraryLinkManagerInvalidBackupFormat => '無効なバックアップ ファイル形式です';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return 'エクスポートされた $count 歌詞ファイル';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return '操作が失敗しました: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => '無題の歌';

  @override
  String get libraryLinkManagerUnknownArtist => '不明なアーティスト';

  @override
  String get libraryLinkManagerUnknownAlbum => '未知のアルバム';

  @override
  String get libraryLinkManagerSongPathLabel => '歌の道';

  @override
  String get libraryLinkManagerSongPathEmpty => 'ソングパスが記録されていません';

  @override
  String get libraryLinkManagerLyricsPathLabel => '歌詞パス';

  @override
  String get libraryLinkManagerLyricsPathEmpty => '歌詞がリンクされていません';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return 'トラック $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return 'トラック番号: $track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => 'なし';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return 'オフセット $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return '歌詞オフセット: $offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return '言語 $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return '歌詞言語: $langs';
  }

  @override
  String get libraryLinkManagerInstrumental => 'インストゥルメンタル';

  @override
  String get libraryLinkManagerInstrumentalTooltip =>
      'この曲はインストゥルメンタルとしてマークされています';

  @override
  String get libraryLinkManagerDisableAutoSearch => '自動検索を無効にする';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip => 'この曲の自動検索は無効になっています';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return 'その他の構成 $count';
  }

  @override
  String get libraryLinkManagerDefaultConfig => 'デフォルト設定';

  @override
  String get libraryLinkManagerDefaultConfigTooltip =>
      'このレコードには曲レベルのオーバーライド設定は保存されません';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return 'オープンに失敗しました: $detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable => '歌詞ファイルが利用できません';

  @override
  String get openLyricsNoticeSongFileUnavailable => '曲ファイルが利用できません';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics => 'この曲には判読可能な埋め込み歌詞が見つかりませんでした';

  @override
  String get openLyricsNoticeAlreadyConverted => 'この歌詞はすでに変換されています';

  @override
  String get openLyricsNoticeEmptyLyrics => '歌詞の内容を空にすることはできません';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return '変換に失敗しました: $detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => 'まず歌詞を変換してください';

  @override
  String get openLyricsNoticeNoLyricsToSave => '保存する歌詞がありません';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return '保存された歌詞: $detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return '保存に失敗しました: $detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => 'まず曲ファイルを開いてください';

  @override
  String get openLyricsNoticeAudioTagUnsupported =>
      'このプラットフォームでは曲タグを書き込むことができません';

  @override
  String get openLyricsDropUnsupportedItem =>
      'Open Lyrics は歌詞ファイルまたはオーディオ ファイルを受け入れます';

  @override
  String get openLyricsPreviewTitle => 'プレビュー';

  @override
  String get openLyricsPreviewRawText => '生のテキスト';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return '歌詞言語 · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => 'ロードされていません';

  @override
  String get openLyricsPreviewStateRawLoaded => '変換の準備ができました';

  @override
  String get openLyricsPreviewStateConverted => '変換された';

  @override
  String get openLyricsPreviewEmptyNoInput => '最初に歌詞ファイルまたは曲ファイルを開きます';

  @override
  String get openLyricsActionOpening => 'オープニング...';

  @override
  String get openLyricsActionOpenLyricsFile => '歌詞ファイルを開く';

  @override
  String get openLyricsActionOpenSongFile => 'ソングファイルを開く';

  @override
  String get openLyricsActionConvertFormat => 'フォーマットの変換';

  @override
  String get openLyricsActionSaveLyrics => '歌詞の保存';

  @override
  String get openLyricsActionSaveToTag => 'ソングタグに保存';

  @override
  String get openLyricsActionTranslate => '歌詞を翻訳する';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return '現在のエクスポート形式: $format · タグを書き込むことができます';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return '現在のエクスポート形式: $format · ファイル エクスポートのみ';
  }

  @override
  String get searchLyricsSelectorTitle => '歌詞を選択';

  @override
  String get searchLyricsSelectorOpenLocal => 'ローカルの歌詞を開く';

  @override
  String get searchLyricsSelectorSelect => '歌詞を選択';

  @override
  String get searchLyricsSelectorDescription =>
      'デスクトップ歌詞としてオンラインまたはローカルの歌詞を選択します';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return 'ローカルの歌詞を開けませんでした: $detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => '最初に歌詞を選択してください';

  @override
  String get searchLyricsSelectorSelectFailed => '歌詞の選択に失敗しました。後でもう一度試してください';

  @override
  String get searchDropUnsupportedItem => '検索では解析可能な曲アイテムまたはオーディオ ファイルを受け入れます';

  @override
  String get searchNoticePartialSourcesFailed =>
      '一部のソースが失敗しました。他のソースからの結果が表示されます';

  @override
  String get searchNoticeAllSourcesFailed => 'すべての検索ソースが失敗しました';

  @override
  String get searchNoticeLoadMoreFailed => '一部のソースがさらに結果をロードできませんでした';

  @override
  String get searchNoticeDirectoryPickerUnsupported =>
      'このプラットフォームではディレクトリの選択はサポートされていません';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return '$detail の歌詞を取得しました';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return '自動フェッチに失敗しました: $detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable => '利用可能な曲ファイルが選択されていません';

  @override
  String get searchNoticeFilePickerUnsupported =>
      'ソング ファイルの選択はこのプラットフォームではサポートされていません';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return '曲を開けませんでした: $detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable => 'ドロップされた曲ファイルは利用できません';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return 'ドロップされた曲を解決できませんでした: $detail';
  }

  @override
  String get searchNoticeEmptyKeyword => '検索キーワードを入力してください';

  @override
  String get searchNoticeGetLyricsFirst => 'まずは歌詞を入手';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return '保存された歌詞: $detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported =>
      'このプラットフォームではファイルの保存はサポートされていません';

  @override
  String get searchNoticeFilePickerForTagUnsupported =>
      'ソングタグファイルの選択はこのプラットフォームではサポートされていません';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return 'ファイルの選択に失敗しました: $detail';
  }

  @override
  String get searchNoticeBatchCancelling => '一括保存をキャンセルしています...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst =>
      '最初にアルバムまたはプレイリストを選択してください';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage =>
      '少なくとも 1 つの歌詞言語を選択してください';

  @override
  String get searchNoticeNoSongsToSave => '保存する曲がありません';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return 'バッチ保存がキャンセルされました: $saved は保存されました、$failed は失敗しました、$skipped はスキップされました';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return 'バッチ保存が完了しました: $saved は保存されました、$failed は失敗しました、$skipped はスキップされました';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return 'バッチ保存に失敗しました: $detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates =>
      '複数の歌詞候補が見つかりました。続行するには 1 つ選択してください';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return '歌詞の取得に失敗しました: $detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => '最初に保存パスを選択してください';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return 'ディレクトリの選択に失敗しました: $detail';
  }

  @override
  String get searchNoticePreviewLoading => '歌詞はまだ読み込み中です';

  @override
  String get searchNoticePreviewNoLanguage => '少なくとも 1 つの歌詞言語を選択してください';

  @override
  String get searchNoticePreviewNoContent => '現在の歌詞にはプレビュー可能なコンテンツがありません';

  @override
  String get searchNoticePreviewNoSelection => 'まずは歌詞をダウンロードしてプレビュー';

  @override
  String get desktopWindowActionSelectLyrics => '歌詞を選択';

  @override
  String get desktopWindowActionMarkInstrumental => '楽器としてマークする';

  @override
  String get desktopWindowActionDisableAutoSearch => 'この曲の自動検索を無効にする';

  @override
  String get desktopWindowActionUnlinkLyrics => '歌詞のリンクを解除する';

  @override
  String get desktopWindowActionAssociationManager => '作詞協会マネージャー';

  @override
  String get desktopWindowActionToggleFloating => 'デスクトップの歌詞を表示または非表示にする';

  @override
  String get desktopWindowActionShowMainWindow => 'メインウィンドウを表示';

  @override
  String get desktopWindowActionClickThrough => 'クリックスルー';

  @override
  String get desktopWindowActionPrevious => '前の';

  @override
  String get desktopWindowActionPlay => '遊ぶ';

  @override
  String get desktopWindowActionPause => '一時停止';

  @override
  String get desktopWindowActionNext => '次';

  @override
  String get desktopWindowActionHide => '隠れる';

  @override
  String get desktopTrayCurrentTarget => '現在の目標:';

  @override
  String get desktopTrayNoSelection => 'なし';

  @override
  String get desktopTrayTargetInstance => 'ターゲットインスタンス';

  @override
  String get desktopTrayInstance => '実例';

  @override
  String get desktopTrayExit => '出口';

  @override
  String get desktopWindowInfoInstrumental => 'インストゥルメンタル';

  @override
  String get desktopWindowControlConnectionLost =>
      'プレーヤーの接続が失われました。アクションは実行されませんでした。';

  @override
  String get desktopWindowClientDisconnected =>
      'プレーヤーの接続が失われました。デスクトップの歌詞が閉じられました。';
}
