// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => '警告';

  @override
  String get commonError => '错误';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonFailed => '失败';

  @override
  String get commonSkipped => '跳过';

  @override
  String get commonTotal => '总数';

  @override
  String get commonDelete => '删除';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonRestoreDefault => '恢复默认';

  @override
  String get commonEnabled => '已启用';

  @override
  String get commonDisabledByDefault => '默认关闭';

  @override
  String get commonFormat => '格式';

  @override
  String get commonOffset => '偏移';

  @override
  String get commonSaving => '保存中...';

  @override
  String get commonAddFiles => '添加文件';

  @override
  String get commonClearQueue => '清空队列';

  @override
  String get commonUnsupportedOperation => '当前平台不支持此操作';

  @override
  String get commonLyricsFileUnavailable => '当前条目还没有可打开的歌词文件';

  @override
  String get commonAudioTagRequiresLrc => '歌曲标签中的歌词应为 LRC 格式';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language（$type）';
  }

  @override
  String get commonTranslationCancelled => '已取消翻译';

  @override
  String get commonCancelTranslation => '取消翻译';

  @override
  String get commonTranslating => '翻译中...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return '翻译中 $completed/$total';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI 流式翻译中：$completed / $total 行';
  }

  @override
  String get commonTranslationCompleted => '翻译完成';

  @override
  String get commonLyricsSaved => '歌词保存成功';

  @override
  String commonDropFailed(String detail) {
    return '拖拽处理失败：$detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return '选择保存目录失败：$detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return '打开保存目录失败：$detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return '翻译失败：$detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return '歌词保存失败：$detail';
  }

  @override
  String get appErrorUnknown => '发生未知错误。';

  @override
  String get appErrorOperationTimeout => '操作超时，请稍后重试。';

  @override
  String get appErrorNetworkUnavailable => '网络不可用，请检查连接。';

  @override
  String get appErrorInvalidPayload => '数据格式错误。';

  @override
  String get appErrorUnsupportedOperation => '当前操作不受支持。';

  @override
  String get appErrorPermissionDenied => '没有执行此操作的权限。';

  @override
  String get appErrorIoFailure => '文件读写失败。';

  @override
  String get appErrorLyricsRequestFailed => '请求歌词失败。';

  @override
  String get appErrorLyricsNotFound => '没有找到歌词。';

  @override
  String get appErrorLyricsProcessing => '歌词处理失败。';

  @override
  String get appErrorLyricsDecrypt => '歌词解密失败。';

  @override
  String get appErrorLyricsFormatUnsupported => '不支持的歌词格式。';

  @override
  String get appErrorDecoding => '解码失败。';

  @override
  String get appErrorSongInfoRead => '获取歌曲信息失败。';

  @override
  String get appErrorUnsupportedFileType => '不支持的文件格式。';

  @override
  String get appErrorDragDropInvalid => '拖拽数据无效。';

  @override
  String get appErrorTranslateFailed => '翻译失败。';

  @override
  String get appErrorApiParamsInvalid => '请求参数不正确。';

  @override
  String get appErrorApiRequestFailed => '接口请求失败。';

  @override
  String get appErrorAutoFetchUnknown => '自动匹配发生未知错误。';

  @override
  String get appErrorNotEnoughInfo => '搜索信息不足。';

  @override
  String get appErrorIpcInvalidLength => 'IPC 消息长度无效。';

  @override
  String get appErrorIpcUnsupportedTask => 'IPC 任务不受支持。';

  @override
  String get appErrorIpcInstanceNotFound => 'IPC 实例不存在。';

  @override
  String get appErrorIpcPanelNotFound => 'IPC 面板不存在。';

  @override
  String get appErrorIpcInvalidWindowId => '窗口句柄无效。';

  @override
  String get appErrorIpcEmbedUnsupported => '当前平台不支持嵌入模式。';

  @override
  String get appErrorActionRetryNetwork => '请检查网络后重试。';

  @override
  String get appErrorActionCheckPayload => '请检查输入数据格式。';

  @override
  String get appErrorActionChangeFormat => '请更换支持的文件或格式。';

  @override
  String get appErrorActionDetachedMode => '请回退到 detached 模式。';

  @override
  String get actionRetry => '重试';

  @override
  String get actionViewDetails => '查看详情';

  @override
  String get actionCancel => '取消';

  @override
  String get sourceAggregate => '聚合';

  @override
  String get sourceQQMusic => 'QQ音乐';

  @override
  String get sourceKugou => '酷狗音乐';

  @override
  String get sourceNetease => '网易云音乐';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => '本地';

  @override
  String get lyricOriginal => '原文';

  @override
  String get lyricTranslation => '译文';

  @override
  String get lyricRomanized => '罗马音';

  @override
  String get lyricsFormatVerbatimLrc => 'LRC（逐字）';

  @override
  String get lyricsFormatLineByLineLrc => 'LRC（逐行）';

  @override
  String get lyricsFormatEnhancedLrc => '增强型 LRC（ESLyric）';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => 'ASS';

  @override
  String get lyricsTypeVerbatim => '逐字';

  @override
  String get lyricsTypeLineByLine => '逐行';

  @override
  String get lyricsTypePlainText => '纯文本';

  @override
  String get searchSong => '单曲';

  @override
  String get searchAlbum => '专辑';

  @override
  String get searchSongList => '歌单';

  @override
  String get searchArtist => '歌手';

  @override
  String get searchLyrics => '歌词';

  @override
  String get searchSongId => '歌曲id';

  @override
  String get localMatchIteratingFiles => '遍历文件...';

  @override
  String get localMatchProgressImportCompleted => '导入完成';

  @override
  String get localMatchProgressScanCompleted => '扫描完成';

  @override
  String get localMatchProgressScanFailed => '扫描失败';

  @override
  String get localMatchProgressMatchCompleted => '匹配完成';

  @override
  String get localMatchProgressMatchFailed => '匹配失败';

  @override
  String get localMatchProgressPreparingMatch => '准备开始匹配...';

  @override
  String get localMatchPreviewTagOnly => '仅写入标签';

  @override
  String get localMatchPreviewWriteTag => '保存到标签';

  @override
  String get localMatchPreviewNoOutput => '未配置输出';

  @override
  String get localMatchPreviewSongTagOnly => '仅写入歌曲标签';

  @override
  String get localMatchPendingLyricsFileName => '等待歌词信息后确定文件名';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / 等待歌词信息后确定文件名';
  }

  @override
  String get localMatchCalcSavePathFailed => '计算歌词保存路径失败';

  @override
  String get localMatchNoticeBusyImportFiles => '当前任务执行中，无法继续导入文件';

  @override
  String get localMatchNoticeSelectedFilesUnavailable => '所选文件不可访问';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return '导入文件失败：$detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories => '当前任务执行中，无法继续导入目录';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return '导入目录失败：$detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles => '拖拽数据中没有可访问的文件';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖拽歌曲失败：$detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors => '导入完成，但有部分条目解析失败';

  @override
  String get localMatchNoticeSafTreeUnsupported => '当前平台不支持目录树授权';

  @override
  String get localMatchNoticeBusySwitchTree => '当前任务执行中，无法切换目录树';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return '选择目录树失败：$detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue => '当前任务执行中，无法清空队列';

  @override
  String get localMatchNoticeSelectItemsToDelete => '请先选择要删除的条目';

  @override
  String get localMatchNoticeSelectItemsToSetRoot => '请先选择要设置根目录的条目';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return '以下歌曲不在所选根目录中，已跳过：$detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return '设置根目录失败：$detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore => '请先选择要恢复的条目';

  @override
  String get localMatchNoticeCancelling => '正在取消当前任务...';

  @override
  String get localMatchNoticeValidationFailed => '请先处理本地匹配启动条件';

  @override
  String get localMatchNoticeSongDirectoryUnavailable => '当前条目不支持打开歌曲目录';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return '打开歌曲目录失败：$detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable => '当前条目还没有可打开的保存目录';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return '打开歌词失败：$detail';
  }

  @override
  String get localMatchNoticeScanCancelled => '扫描已取消';

  @override
  String get localMatchNoticeScanCompletedWithErrors => '扫描完成，但有部分文件解析失败';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return '扫描失败：$detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return '目录树扫描失败：$detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => '匹配已取消';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '总共$total首歌曲，匹配成功$success首，匹配失败$failed首，跳过$skipped首。';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return '本地匹配执行失败：$detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume => '匹配已取消，可再次开始从断点继续';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF 本地匹配执行失败：$detail';
  }

  @override
  String get localMatchValidationEmptyLangs => '请选择要匹配的语言';

  @override
  String get localMatchValidationEmptySources => '请选择至少一个源';

  @override
  String get localMatchValidationEmptyQueue => '请先导入要匹配的歌曲';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      '跳过已有歌词时，如果还需要保存文件，则文件名模式不能为按歌词信息命名';

  @override
  String get localMatchValidationMissingAndroidTree => '请先选择目录树';

  @override
  String get localMatchValidationNeedsSaveRoot => '需要指定保存路径';

  @override
  String get localMatchValidationNeedsSongRoot => '需要指定歌曲根目录';

  @override
  String get localMatchValidationUnknownSavePath => '未知保存路径错误';

  @override
  String get localMatchIntro => '导入本地歌曲或目录，预估输出结果后执行批量匹配。';

  @override
  String get localMatchDropUnsupportedItem => '本地匹配页只接受歌曲文件、目录或可解析播放器条目拖入';

  @override
  String get localMatchReadyToStart => '准备开始本地匹配';

  @override
  String get localMatchQueueTitle => '任务队列';

  @override
  String get localMatchQueueEmptyHint => '先导入文件或文件夹以建立任务队列';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '共 $count 条任务，右键行可执行更多操作';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '共 $count 条任务，长按或点击更多按钮可打开操作菜单';
  }

  @override
  String get localMatchImportAndRunTitle => '导入与执行';

  @override
  String get localMatchActionStart => '开始匹配';

  @override
  String get localMatchActionAddFolders => '添加文件夹';

  @override
  String get localMatchActionSelectSaveRoot => '选择保存根目录';

  @override
  String get localMatchActionSelectTree => '选择目录树';

  @override
  String get localMatchActionReselectTree => '重新选择目录树';

  @override
  String get localMatchActionBulkSelect => '批量选择';

  @override
  String get localMatchActionExitSelection => '退出批量选择';

  @override
  String get localMatchActionSelectAll => '全选';

  @override
  String get localMatchActionDeselectAll => '取消全选';

  @override
  String get localMatchActionSetRoot => '设置根目录';

  @override
  String localMatchSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get localMatchBulkActionHint => '批量操作会直接作用于当前选中的任务';

  @override
  String get localMatchPhaseIdle => '等待开始';

  @override
  String get localMatchPhaseScanning => '扫描中';

  @override
  String get localMatchPhaseMatching => '匹配中';

  @override
  String get localMatchPhaseWriting => '写回中';

  @override
  String get localMatchPhaseCompleted => '已完成';

  @override
  String get localMatchPhaseHintIdle => '导入歌曲后即可开始匹配';

  @override
  String get localMatchPhaseHintScanning => '正在建立任务队列与预估输出';

  @override
  String get localMatchPhaseHintMatching => '正在请求来源并计算最佳匹配';

  @override
  String get localMatchPhaseHintWriting => '正在写入歌词文件或歌曲标签';

  @override
  String get localMatchPhaseHintCompleted => '本轮任务已完成，可继续调整后重跑';

  @override
  String get localMatchPipelineIdle => '扫描 -> 匹配 -> 写回';

  @override
  String get localMatchPipelineScanning => '当前阶段：扫描';

  @override
  String get localMatchPipelineMatching => '当前阶段：匹配';

  @override
  String get localMatchPipelineWriting => '当前阶段：写回';

  @override
  String get localMatchPipelineCompleted => '已完成本轮扫描、匹配与写回';

  @override
  String get localMatchUnknownSong => '未知歌曲';

  @override
  String get localMatchUnknownDuration => '未知时长';

  @override
  String get localMatchStatusNotStarted => '未开始';

  @override
  String get localMatchSongPathLabel => '歌曲路径';

  @override
  String get localMatchLyricsPathLabel => '歌词保存路径';

  @override
  String get localMatchExpandDetails => '展开详情';

  @override
  String get localMatchCollapseDetails => '收起详情';

  @override
  String get localMatchRowActionOpenInSearch => '在搜索中打开';

  @override
  String get localMatchRowActionEnterSelection => '进入批量选择';

  @override
  String get localMatchRowActionOpenSongDirectory => '打开歌曲目录';

  @override
  String get localMatchRowActionOpenSaveDirectory => '打开保存目录';

  @override
  String get localMatchRowActionOpenLyrics => '打开歌词';

  @override
  String get localMatchFieldLyricsType => '歌词类型';

  @override
  String get localMatchFieldOutputStrategy => '输出策略';

  @override
  String get localMatchFieldSaveMode => '保存模式';

  @override
  String get localMatchFieldFileNameMode => '文件名模式';

  @override
  String get localMatchFieldLyricsFormat => '歌词格式';

  @override
  String get localMatchFieldThreshold => '匹配门槛';

  @override
  String get localMatchFieldSaveRoot => '保存根目录';

  @override
  String get localMatchMoreSettings => '更多设置';

  @override
  String get localMatchRulesTitle => '匹配规则';

  @override
  String get localMatchRulesSubtitle => '来源、语言、输出策略与匹配门槛';

  @override
  String get localMatchMinScore => '最低匹配度';

  @override
  String get localMatchSkipExisting => '跳过已有歌词';

  @override
  String get localMatchSkipExistingConflictHint =>
      '当前“输出策略 + 文件名模式”组合不支持开启跳过已有歌词；若还需要保存文件，请避免选择“按歌词信息命名”。';

  @override
  String get localMatchSaveToSongDirectoryHint => '当前保存到歌曲目录，无需额外保存根目录。';

  @override
  String get localMatchAndroidTreeSaveHint => 'Android 目录树文件保存会直接写入已授权目录树。';

  @override
  String get localMatchFileNameTemplateHint =>
      '命名模板沿用设置页中的 lyrics_file_name_fmt。';

  @override
  String localMatchSaveRootPath(String path) {
    return '保存根目录：$path';
  }

  @override
  String get localMatchSaveRootRequired => '当前保存模式需要保存根目录，请先选择。';

  @override
  String get localMatchTreeNotSelected => '尚未选择目录树';

  @override
  String get localMatchSaveModeSong => '保存到歌曲目录';

  @override
  String get localMatchSaveModeMirror => '镜像目录';

  @override
  String get localMatchSaveModeSpecify => '指定目录';

  @override
  String get localMatchFileNameModeSong => '按歌曲文件名';

  @override
  String get localMatchFileNameModeFormatBySong => '按歌曲信息命名';

  @override
  String get localMatchFileNameModeFormatByLyrics => '按歌词信息命名';

  @override
  String get localMatchFileNameHintSong => '沿用音频文件名，仅替换歌词扩展名。';

  @override
  String get localMatchFileNameHintFormatBySong => '使用标题、艺术家、专辑等歌曲元数据生成文件名。';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      '使用匹配到的歌词歌曲信息生成文件名；未匹配前可能无法确定。';

  @override
  String get localMatchSaveToTagOnlyFile => '仅保存文件';

  @override
  String get localMatchSaveToTagOnlyTag => '仅写入标签';

  @override
  String get localMatchSaveToTagBoth => '文件 + 标签';

  @override
  String get localMatchValidationTitle => '开始前需要处理的问题';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '还有 $count 个问题需要先处理';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable => '所选文件当前不可直接访问';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return '已导入 $count 个歌词文件';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles => '拖拽数据中没有可访问的歌词文件';

  @override
  String get batchConvertNoticeEmptyQueue => '请先添加要转换的歌词文件';

  @override
  String get batchConvertNoticeOverwriteCancelled => '已取消批量转换';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return '批量转换已取消，已完成 $count 项';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return '批量转换完成：成功 $success，失败 $failure';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return '批量转换完成：共 $count 项';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return '批量转换失败：$detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return '打开原目录失败：$detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return '打开歌词文件失败：$detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles => '所选文件夹中没有找到支持的歌词文件';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return '已从文件夹导入 $count 个歌词文件';
  }

  @override
  String get batchConvertNoticeDuplicateItems => '所选条目都已在队列中';

  @override
  String get batchConvertControlsTitle => '导入与设置';

  @override
  String get batchConvertCompactControlsTitle => '导入与输出设置';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return '格式：$format';
  }

  @override
  String get batchConvertImportTitle => '导入';

  @override
  String get batchConvertAddFolders => '添加文件夹';

  @override
  String get batchConvertOutputSettingsTitle => '输出设置';

  @override
  String get batchConvertTargetFormat => '目标格式';

  @override
  String get batchConvertSaveDirectoryTitle => '保存目录';

  @override
  String get batchConvertSaveDirectoryDefault => '未设置时默认输出到原歌词所在目录';

  @override
  String get batchConvertSelectSaveDirectory => '选择保存目录';

  @override
  String get batchConvertRestoreOriginalDirectory => '恢复原目录';

  @override
  String get batchConvertRecursiveTitle => '遍历子文件夹';

  @override
  String get batchConvertRecursiveSubtitle => '目录导入时继续扫描子目录中的歌词文件';

  @override
  String get batchConvertStart => '开始转换';

  @override
  String get batchConvertCancel => '取消转换';

  @override
  String get batchConvertQueueTitle => '转换队列';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '共 $count 项，输出格式为 $format';
  }

  @override
  String get batchConvertPageErrorFallback => '批量转换页面出现错误';

  @override
  String get batchConvertRetryImport => '重新导入';

  @override
  String get batchConvertEmptyQueue => '添加歌词文件或文件夹后，这里会显示批量转换队列。';

  @override
  String get batchConvertOutputPathLabel => '输出路径';

  @override
  String get batchConvertQueueStatusWaiting => '等待转换';

  @override
  String get batchConvertQueueStatusRunning => '正在转换';

  @override
  String get batchConvertQueueStatusSuccess => '转换成功';

  @override
  String get batchConvertQueueStatusFailure => '转换失败';

  @override
  String get batchConvertMoreActions => '更多操作';

  @override
  String get batchConvertActionOpenSourceDirectory => '打开原歌词目录';

  @override
  String get batchConvertActionOpenSaveDirectory => '打开保存目录';

  @override
  String get batchConvertActionOpenOutputFile => '打开歌词文件';

  @override
  String get batchConvertActionOpenInOpenLyrics => '在打开歌词页中打开';

  @override
  String get batchConvertPhaseIdle => '等待开始';

  @override
  String get batchConvertPhaseScanning => '正在扫描';

  @override
  String get batchConvertPhaseRunning => '正在转换';

  @override
  String get batchConvertPhaseCompleted => '已完成';

  @override
  String get batchConvertPipelineIdle => '导入 -> 扫描 -> 转换 -> 完成';

  @override
  String get batchConvertPipelineScanning => '扫描目录 -> 建立队列';

  @override
  String get batchConvertPipelineRunning => '逐条转换 -> 持续更新状态';

  @override
  String get batchConvertPipelineCompleted => '可继续调整格式或重新导入';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return '已取消，成功 $success，失败 $failure';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '成功 $success，失败 $failure';
  }

  @override
  String get batchConvertHintNoQueue => '添加文件或文件夹后开始转换';

  @override
  String get batchConvertHintReady => '当前队列已就绪';

  @override
  String get batchConvertMetricWaiting => '待处理';

  @override
  String get batchConvertDropUnsupported => '批量转换页只接受歌词文件或目录拖入';

  @override
  String batchConvertDropFailed(String detail) {
    return '拖拽处理失败：$detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return '正在转换 $fileName';
  }

  @override
  String get batchConvertProgressItemSuccess => '转换成功';

  @override
  String get batchConvertProgressItemFailure => '转换失败';

  @override
  String get batchConvertProgressPreparingConversion => '准备开始转换...';

  @override
  String get batchConvertProgressCancellingConversion => '正在取消转换...';

  @override
  String get batchConvertProgressConversionCancelled => '转换已取消';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return '转换完成：成功 $success，失败 $failure';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return '转换失败：$detail';
  }

  @override
  String get batchConvertProgressScanningFolders => '正在遍历文件夹...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return '正在扫描 $directoryName';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return '已扫描到 $count 个歌词文件';
  }

  @override
  String get batchConvertProgressScanCancelled => '扫描已取消';

  @override
  String get batchConvertProgressScanNoSupportedFiles => '未找到支持的歌词文件';

  @override
  String get batchConvertProgressScanCompleted => '扫描完成';

  @override
  String get navSearch => '搜索';

  @override
  String get navLocalMatch => '本地匹配';

  @override
  String get navOpenLyrics => '打开歌词';

  @override
  String get navBatchConvert => '批量转换';

  @override
  String get navSettings => '设置';

  @override
  String get navAbout => '关于';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonSource => '来源';

  @override
  String get searchKeywordHint => '输入关键词';

  @override
  String get uiLoading => '加载中...';

  @override
  String get uiLoadingStepFetching => '正在获取列表与预览...';

  @override
  String get uiEmpty => '暂无数据';

  @override
  String get uiNoMoreResult => '没有更多结果';

  @override
  String get searchInitialResultTitle => '输入关键词开始搜索';

  @override
  String get searchInitialResultDescription => '在上方选择来源并发起搜索';

  @override
  String get searchResultTitle => '搜索结果';

  @override
  String get searchResultReturn => '返回上一层';

  @override
  String get searchPreviewTitle => '歌词预览';

  @override
  String get searchPreviewLangsLabel => '歌词语言';

  @override
  String get searchPreviewSongIdLabel => '歌曲ID';

  @override
  String get searchPreviewPlaceholder => '请先选择歌曲或歌词条目';

  @override
  String get searchPreviewNoLanguage => '请至少选择一种歌词语言';

  @override
  String get searchPreviewNoContent => '当前歌词暂无可预览内容';

  @override
  String get searchPreviewLoading => '正在加载歌词...';

  @override
  String get searchFormatLabel => '歌词格式';

  @override
  String get searchTranslateLyrics => '翻译歌词';

  @override
  String get searchResizeWorkspacePanes => '调整搜索结果与歌词预览宽度';

  @override
  String get searchSavePreviewToDirectory => '保存到文件夹';

  @override
  String get searchSavePreviewToFile => '保存到文件';

  @override
  String get searchSavePreviewToTag => '保存到歌曲标签';

  @override
  String get searchSaveListLyrics => '保存专辑/歌单的歌词';

  @override
  String get searchSaveListLyricsCancel => '取消批量保存';

  @override
  String get searchSelectSavePath => '选择保存路径';

  @override
  String get searchBatchSaveProgressTitle => '批量保存进度';

  @override
  String get searchBatchSaveProgressPreparing => '准备批量保存...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return '正在获取 $songName 的歌词...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count 首';
  }

  @override
  String get searchTableStatusAutoFetching => '正在自动获取...';

  @override
  String get searchTableStatusSearching => '正在搜索...';

  @override
  String get searchTableStatusFetchingSongList => '正在获取歌曲列表...';

  @override
  String get searchTableStatusNoResults => '没有搜索到相关结果';

  @override
  String get searchTableStatusEmptyList => '列表为空';

  @override
  String get searchTableStatusUnsupportedSearchType => '所选来源不支持当前搜索类型';

  @override
  String get searchTableStatusSearchFailed => '搜索失败';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return '搜索失败：$detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return '自动获取歌词失败：$detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return '获取歌曲列表失败：$detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable => '部分来源不可用，已展示可用结果';

  @override
  String get searchTableStatusLoadMoreFailed => '部分来源加载更多失败';

  @override
  String get searchSourceFailureDetailsTitle => '搜索错误详情';

  @override
  String get searchSourceFailureRequest => '请求失败';

  @override
  String get searchSourceFailureTimeout => '请求超时';

  @override
  String get searchSourceFailureParameters => '参数错误';

  @override
  String get searchSourceFailureUnsupported => '不支持的操作';

  @override
  String get searchSourceFailureUnknown => '未知错误';

  @override
  String get searchResultLoadingMore => '正在继续加载更多结果...';

  @override
  String get searchResultLoadMoreFailed => '自动续取失败，可重试继续加载剩余结果';

  @override
  String get searchResultScrollForMore => '继续向下滚动以自动加载更多结果';

  @override
  String get tableSavePath => '保存路径';

  @override
  String get settingsSectionSave => '保存';

  @override
  String get settingsSectionLyrics => '歌词';

  @override
  String get settingsSectionDesktopLyrics => '桌面歌词';

  @override
  String get settingsSectionTranslate => '翻译';

  @override
  String get settingsSectionSearch => '搜索';

  @override
  String get settingsSectionApp => '应用';

  @override
  String get settingsSectionTools => '工具与数据';

  @override
  String get settingsSectionSaveSummary => '保存路径、文件名模板与 ID3 版本';

  @override
  String get settingsSectionSearchSummary => '决定“聚合”搜索和本地匹配默认使用的歌词来源。';

  @override
  String get settingsSectionDesktopLyricsSummary => '桌面歌词自动获取、显示语言、外观与刷新率。';

  @override
  String get settingsSectionLyricsSummary => '本地匹配策略与歌词文件导出格式。';

  @override
  String get settingsSectionTranslateSummary => '翻译源、目标语言与条件字段';

  @override
  String get settingsSectionAppSummary => '语言、主题、日志与更新策略';

  @override
  String get settingsSectionToolsSummary => '桌面工具入口、日志目录与缓存清理';

  @override
  String get settingsTranslateSourceBing => '必应翻译';

  @override
  String get settingsTranslateSourceGoogle => '谷歌翻译';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI兼容API';

  @override
  String get settingsLangSimplifiedChinese => '简体中文';

  @override
  String get settingsLangTraditionalChinese => '繁体中文';

  @override
  String get settingsLangEnglish => '英语';

  @override
  String get settingsLangJapanese => '日语';

  @override
  String get settingsLangKorean => '韩语';

  @override
  String get settingsLangSpanish => '西班牙语';

  @override
  String get settingsLangFrench => '法语';

  @override
  String get settingsLangPortuguese => '葡萄牙语';

  @override
  String get settingsLangGerman => '德语';

  @override
  String get settingsLangRussian => '俄语';

  @override
  String get settingsAppLanguageAuto => '自动';

  @override
  String get settingsColorSchemeAuto => '跟随系统';

  @override
  String get settingsColorSchemeLight => '浅色';

  @override
  String get settingsColorSchemeDark => '深色';

  @override
  String get settingsDesktopGradientColors => '渐变颜色';

  @override
  String get settingsDesktopPlayedColors => '已播放颜色';

  @override
  String get settingsDesktopUnplayedColors => '未播放颜色';

  @override
  String get settingsAddColor => '添加颜色';

  @override
  String get settingsEditColor => '编辑颜色';

  @override
  String get settingsDeleteColor => '删除颜色';

  @override
  String get settingsBackToSections => '返回设置分组';

  @override
  String get settingsAvailablePlaceholders => '可用占位符';

  @override
  String get settingsPlaceholderTitleArtist => '歌名：%<title>    艺术家：%<artist>';

  @override
  String get settingsPlaceholderAlbumId => '专辑名：%<album>    歌曲/歌词 id：%<id>';

  @override
  String get settingsPlaceholderLangs => '语言类型：%<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return '当前模板：$template';
  }

  @override
  String get settingsTranslateSourceLabel => '翻译源';

  @override
  String get settingsTranslateTargetLabel => '目标语言';

  @override
  String get settingsOpenAiProfileLabel => '预设';

  @override
  String get settingsOpenAiProfileHelper =>
      '选择内置服务商会自动填入 Base URL，API Key 和模型仍需配置。';

  @override
  String get settingsAppLanguageLabel => '界面语言';

  @override
  String get settingsColorSchemeLabel => '主题模式';

  @override
  String get settingsLogLevelLabel => '日志级别';

  @override
  String get settingsLogLevelHelper => '通常保持 INFO；TRACE 和 DEBUG 会记录更多内容并增大日志。';

  @override
  String get settingsAutoCheckUpdateLabel => '自动检查更新';

  @override
  String get settingsRestoreDefaultsWarning => '恢复默认值会立即写入配置，请确认后执行。';

  @override
  String get settingsRestoreAllTitle => '恢复默认设置';

  @override
  String get settingsRestoreAllContent => '该操作会恢复所有设置项，并立即写入配置。';

  @override
  String get settingsRestoreAllAction => '恢复默认设置';

  @override
  String get settingsOpenAssociationManager => '打开歌词关联管理器';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      '进入设置下一级页面，统一管理歌曲与歌词关联记录。';

  @override
  String get settingsOpenLogDirectory => '打开日志目录';

  @override
  String get settingsOpenLogDirectorySubtitle => '查看运行日志与问题排查文件。';

  @override
  String get settingsClearCache => '清理缓存';

  @override
  String get settingsClearCacheSubtitle => '清理搜索与翻译缓存，不影响配置文件。';

  @override
  String get settingsClearCacheContent => '缓存清理后，后续搜索与翻译可能需要重新请求。';

  @override
  String get settingsRestoreSectionTitle => '恢复本组默认值';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return '仅恢复“$sectionTitle”分组中的设置项，其他分组不会被修改。';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return '恢复$sectionTitle分组默认值';
  }

  @override
  String get settingsDefaultSavePathHelper => '留空时使用平台默认音乐目录。';

  @override
  String get settingsChooseFolder => '选择文件夹';

  @override
  String get settingsLyricsFileNameFormat => '歌词文件名模板';

  @override
  String get settingsLyricsFileNameFormatHelper => '可使用下方占位符组合生成保存文件名。';

  @override
  String get settingsId3Version => 'ID3 版本';

  @override
  String get settingsId3VersionHelper => '仅影响把歌词写入音频标签；不确定时保持 v2.3。';

  @override
  String get settingsSearchSourcesTitle => '聚合搜索来源';

  @override
  String get settingsSearchSourcesDescription =>
      '搜索页选择“聚合”时查询已勾选来源；越靠上，结果排列和自动匹配优先级越高。本地匹配默认沿用此列表。';

  @override
  String get settingsReorderPriorityHint => '拖动调整优先级';

  @override
  String get settingsReorderOrderHint => '拖动调整顺序';

  @override
  String get settingsDefaultLanguage => '默认显示语言';

  @override
  String get settingsDefaultLanguageDescription =>
      '勾选桌面歌词默认显示的语言，拖动调整多语言歌词的排列顺序。';

  @override
  String get settingsDesktopAutoFetchSources => '自动获取来源';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      '桌面歌词没有关联歌词时，按从上到下的优先级自动获取。';

  @override
  String get settingsFont => '字体';

  @override
  String get settingsFollowSystemFont => '跟随系统字体';

  @override
  String get settingsFontSizeByResize => '桌面歌词主窗口字号通过拖拽窗口大小调整。';

  @override
  String get settingsPanelFontSize => '歌词面板字号';

  @override
  String get settingsAdaptiveRefreshRate => '自适应刷新率';

  @override
  String get settingsAdaptiveRefreshRateSubtitle => '开启后根据歌词动画状态自动选择刷新节奏。';

  @override
  String get settingsFixedRefreshRate => '固定刷新率';

  @override
  String get settingsShowFurigana => '显示注音';

  @override
  String get settingsLyricsMatchBehavior => '匹配行为';

  @override
  String get settingsLyricsMatchBehaviorDescription => '控制本地匹配和酷狗歌词候选的默认处理方式。';

  @override
  String get settingsLyricsExport => 'LRC 导出';

  @override
  String get settingsLyricsExportDescription => '控制保存歌词文件时使用的语言顺序和 LRC 时间戳格式。';

  @override
  String get settingsDisplayOrder => '导出语言顺序';

  @override
  String get settingsDisplayOrderDescription => '拖动调整原文、译文和罗马音在歌词文件中的顺序。';

  @override
  String get settingsSkipInstrumental => '跳过纯音乐';

  @override
  String get settingsSkipInstrumentalSubtitle => '本地匹配识别为纯音乐时不保存歌词。';

  @override
  String get settingsAutoSelectKugou => '自动选择酷狗候选';

  @override
  String get settingsAutoSelectKugouSubtitle => '搜索页打开酷狗歌曲时自动选择最佳歌词候选。';

  @override
  String get settingsAddLrcEndTimestamp => '导出 LRC 时添加结尾时间戳';

  @override
  String get settingsAddLrcEndTimestampSubtitle => '仅影响逐行 LRC，在需要时写入行结束时间戳。';

  @override
  String get settingsMillisecondsDigits => '毫秒位数';

  @override
  String get settingsMillisecondsDigitsHelper => '两位使用百分之一秒，三位保留完整毫秒。';

  @override
  String settingsDigitsValue(int value) {
    return '$value 位';
  }

  @override
  String get settingsLastRefStyle => '同句最后一行时间戳';

  @override
  String get settingsLastRefStyleHelper =>
      '决定多语言逐行 LRC 中同一句最后一种语言使用当前行时间，还是下一行前 1 毫秒。';

  @override
  String get settingsLastRefCurrentLine => '使用当前行时间';

  @override
  String get settingsLastRefNextLine => '使用下一行前一毫秒';

  @override
  String get settingsTagInfoSource => '标签信息来源';

  @override
  String get settingsTagInfoLyricsSource => '歌词来源';

  @override
  String get settingsTagInfoSongInfo => '歌曲信息';

  @override
  String get settingsNoticeDefaultSavePathUpdated => '默认保存路径已更新';

  @override
  String get settingsNoticeDefaultSavePathRestored => '默认保存路径已恢复';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated => '歌词文件名模板已更新';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3 版本已更新';

  @override
  String get settingsNoticeLyricsLangOrderEmpty => '歌词语言顺序不能为空';

  @override
  String get settingsNoticeLyricsLangOrderUpdated => '歌词语言顺序已更新';

  @override
  String get settingsNoticeSkipInstUpdated => '纯音乐跳过策略已更新';

  @override
  String get settingsNoticeAutoSelectUpdated => '自动选择策略已更新';

  @override
  String get settingsNoticeAddEndTimestampUpdated => '结尾时间戳策略已更新';

  @override
  String get settingsNoticeMsDigitsUpdated => '毫秒位数已更新';

  @override
  String get settingsNoticeLastRefStyleUpdated => '尾行时间样式已更新';

  @override
  String get settingsNoticeTagInfoSourceUpdated => '标签来源已更新';

  @override
  String get settingsNoticeDesktopSourcesEmpty => '桌面歌词来源不能为空';

  @override
  String get settingsNoticeDesktopSourcesUpdated => '桌面歌词来源已更新';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty => '桌面默认语言不能为空';

  @override
  String get settingsNoticeDesktopLangsUpdated => '桌面歌词语言设置已更新';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated => '桌面歌词字体已更新';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => '刷新率已更新';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated => '已播放颜色已更新';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated => '未播放颜色已更新';

  @override
  String get settingsNoticeDesktopFontSizeUpdated => '桌面歌词字号已更新';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated => '桌面面板字号已更新';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated => '注音显示策略已更新';

  @override
  String get settingsNoticeTranslateSourceUpdated => '翻译源已更新';

  @override
  String get settingsNoticeTranslateTargetLangUpdated => '翻译目标语言已更新';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI 预设已更新';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI Base URL 已更新';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI API Key 已更新';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI 模型已更新';

  @override
  String get settingsNoticeSearchSourcesEmpty => '聚合搜索来源不能为空';

  @override
  String get settingsNoticeSearchSourcesUpdated => '聚合搜索来源已更新';

  @override
  String get settingsNoticeAppLanguageUpdated => '界面语言已更新';

  @override
  String get settingsNoticeAppColorSchemeUpdated => '主题模式已更新';

  @override
  String get settingsNoticeAppLogLevelUpdated => '日志级别已更新';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated => '自动检查更新已更新';

  @override
  String get settingsNoticeSectionNoRestorableConfig => '当前分组没有可恢复的配置项';

  @override
  String get settingsNoticeSectionDefaultsRestored => '当前分组已恢复默认值';

  @override
  String get settingsNoticeAllDefaultsRestored => '应用设置已恢复默认值';

  @override
  String get settingsNoticeAssociationManagerOpened => '已打开歌词关联管理器';

  @override
  String get settingsNoticeLogDirectoryOpened => '日志目录已打开';

  @override
  String get settingsNoticeLogDirectoryOpenFailed => '打开日志目录失败';

  @override
  String get settingsNoticeCacheCleared => '缓存已清理';

  @override
  String get settingsNoticeCacheClearFailed => '清理缓存失败';

  @override
  String get settingsNoticeConfigWriteFailed => '设置写入失败';

  @override
  String get settingsCurrentSavePathLabel => '默认保存路径';

  @override
  String get aboutLoadFailed => '加载关于页信息失败';

  @override
  String get aboutActionOpenRepository => 'GitHub仓库';

  @override
  String get aboutActionCheckUpdate => '检查更新';

  @override
  String get aboutHeroHeadline => '为精准歌词而设计';

  @override
  String get aboutHeroDescription =>
      'LDDC 将搜索、转换、桌面歌词与批处理工作流收口到同一套高效率体验里，让精准歌词获取、整理与使用保持顺滑。';

  @override
  String get aboutLinksSectionTitle => '常用链接';

  @override
  String get aboutLinksSectionDescription => '需要继续了解项目时，可以从这里查看反馈、更新与许可证信息。';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return 'Copyright (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return 'Licensed under $license.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub 仓库';

  @override
  String get aboutLinkIssueTrackerTitle => '问题反馈';

  @override
  String get aboutLinkIssueTrackerDescription => '提交 Bug、交互建议和功能需求。';

  @override
  String get aboutLinkLicenseTitle => '许可证';

  @override
  String get aboutLinkLicenseDescription => '查看项目当前采用的开源许可证：';

  @override
  String get aboutLinkChangelogTitle => '更新日志';

  @override
  String get aboutLinkChangelogDescription => '浏览版本发布记录与变更摘要。';

  @override
  String get aboutExternalLinksUnavailable => '当前平台暂不支持打开外部链接。';

  @override
  String get aboutCheckUpdateUnavailable => '当前平台暂不支持检查更新。';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes => '已打开更新日志页面。';

  @override
  String get aboutCheckUpdateUpToDate => '当前已经是最新版本。';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return '发现新版本：$version。请打开更新日志页面查看详情。';
  }

  @override
  String get aboutCheckUpdateFailed => '检查更新失败，请稍后重试。';

  @override
  String aboutActionOpenedLink(String title) {
    return '已打开 $title';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return '打开 $title 失败';
  }

  @override
  String get actionConfirm => '确定';

  @override
  String get libraryLinkManagerTitle => '歌词关联管理器';

  @override
  String get libraryLinkManagerReturnToSettings => '返回设置';

  @override
  String get libraryLinkManagerRefresh => '刷新';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return '删除选中 ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => '删除全部';

  @override
  String get libraryLinkManagerClearInvalid => '清理无效数据';

  @override
  String get libraryLinkManagerChangeDirectory => '批量改目录';

  @override
  String get libraryLinkManagerBackupToJson => '备份到 JSON';

  @override
  String get libraryLinkManagerRestoreFromJson => '从 JSON 恢复';

  @override
  String get libraryLinkManagerRestoreAction => '恢复';

  @override
  String get libraryLinkManagerExportLyrics => '导出歌词';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '共 $totalCount 条记录 · 已选择 $selectedCount 条记录';
  }

  @override
  String get libraryLinkManagerSearchHint => '搜索歌曲、艺术家、专辑或路径';

  @override
  String get libraryLinkManagerClearSearch => '清除搜索';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '匹配 $totalCount 条记录 · 已选择 $selectedCount 条记录';
  }

  @override
  String get libraryLinkManagerEmpty => '暂无歌词关联记录';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return '加载关联记录失败: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess => '已删除选中的歌词关联';

  @override
  String get libraryLinkManagerDeleteAllConfirm => '确定要删除全部歌词关联记录吗？';

  @override
  String get libraryLinkManagerDeleteAllSuccess => '已删除全部歌词关联记录';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return '清理完成，共清理 $count 条无效数据';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return '批量改目录完成，共更新 $count 条记录';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return '歌词关联数据已备份到 $path';
  }

  @override
  String get libraryLinkManagerRestoreConfirm => '恢复会覆盖当前全部歌词关联记录，是否继续？';

  @override
  String get libraryLinkManagerRestoreSuccess => '歌词关联数据已恢复';

  @override
  String get libraryLinkManagerInvalidBackupFormat => '备份文件格式错误';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return '导出完成，共导出 $count 条歌词文件';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return '操作失败: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => '未命名歌曲';

  @override
  String get libraryLinkManagerUnknownArtist => '未知艺术家';

  @override
  String get libraryLinkManagerUnknownAlbum => '未知专辑';

  @override
  String get libraryLinkManagerSongPathLabel => '歌曲路径';

  @override
  String get libraryLinkManagerSongPathEmpty => '未记录歌曲路径';

  @override
  String get libraryLinkManagerLyricsPathLabel => '歌词路径';

  @override
  String get libraryLinkManagerLyricsPathEmpty => '未关联歌词';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return '轨道 $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return '轨道编号：$track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => '无';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return '偏移 $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return '歌词偏移：$offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return '语言 $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return '歌词语言：$langs';
  }

  @override
  String get libraryLinkManagerInstrumental => '纯音乐';

  @override
  String get libraryLinkManagerInstrumentalTooltip => '当前歌曲已标记为纯音乐';

  @override
  String get libraryLinkManagerDisableAutoSearch => '禁用自动搜索';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip => '当前歌曲已禁用自动搜索';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return '其他配置 $count 项';
  }

  @override
  String get libraryLinkManagerDefaultConfig => '默认配置';

  @override
  String get libraryLinkManagerDefaultConfigTooltip => '当前记录未保存歌曲级特殊配置';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return '打开失败：$detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable => '当前歌词文件不可访问';

  @override
  String get openLyricsNoticeSongFileUnavailable => '当前歌曲文件不可访问';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics => '歌曲内没有可读取的内嵌歌词';

  @override
  String get openLyricsNoticeAlreadyConverted => '当前歌词已经转换过了';

  @override
  String get openLyricsNoticeEmptyLyrics => '歌词内容不能为空';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return '转换失败：$detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => '请先转换歌词';

  @override
  String get openLyricsNoticeNoLyricsToSave => '没有歌词可以保存';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return '歌词保存成功：$detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return '保存失败：$detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => '请先打开歌曲文件';

  @override
  String get openLyricsNoticeAudioTagUnsupported => '当前平台不支持写入歌曲标签';

  @override
  String get openLyricsDropUnsupportedItem => '打开歌词页只接受歌词文件或音频文件拖入';

  @override
  String get openLyricsPreviewTitle => '预览';

  @override
  String get openLyricsPreviewRawText => '原始文本';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return '歌词语言 · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => '未加载';

  @override
  String get openLyricsPreviewStateRawLoaded => '待转换';

  @override
  String get openLyricsPreviewStateConverted => '已转换';

  @override
  String get openLyricsPreviewEmptyNoInput => '请先打开歌词文件或歌曲文件';

  @override
  String get openLyricsActionOpening => '打开中...';

  @override
  String get openLyricsActionOpenLyricsFile => '打开歌词文件';

  @override
  String get openLyricsActionOpenSongFile => '打开歌曲文件';

  @override
  String get openLyricsActionConvertFormat => '转换格式';

  @override
  String get openLyricsActionSaveLyrics => '保存歌词';

  @override
  String get openLyricsActionSaveToTag => '保存到歌曲标签';

  @override
  String get openLyricsActionTranslate => '翻译歌词';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return '当前导出格式：$format · 可写回标签';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return '当前导出格式：$format · 仅支持导出文件';
  }

  @override
  String get searchLyricsSelectorTitle => '选择歌词';

  @override
  String get searchLyricsSelectorOpenLocal => '打开本地歌词';

  @override
  String get searchLyricsSelectorSelect => '选定歌词';

  @override
  String get searchLyricsSelectorDescription => '为桌面歌词选择云端或本地歌词';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return '打开本地歌词失败：$detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => '请先选择歌词';

  @override
  String get searchLyricsSelectorSelectFailed => '选定歌词失败，请稍后重试';

  @override
  String get searchDropUnsupportedItem => '搜索页只接受可解析歌曲条目或音频文件拖入';

  @override
  String get searchNoticePartialSourcesFailed => '部分来源搜索失败，已显示其他来源结果';

  @override
  String get searchNoticeAllSourcesFailed => '所有来源搜索失败';

  @override
  String get searchNoticeLoadMoreFailed => '部分来源加载更多失败';

  @override
  String get searchNoticeDirectoryPickerUnsupported => '当前平台不支持选择目录';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return '已自动获取 $detail 的歌词';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return '自动获取歌词失败：$detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable => '未选择可用歌曲文件';

  @override
  String get searchNoticeFilePickerUnsupported => '当前平台不支持选择歌曲文件';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return '打开歌曲失败：$detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable => '拖入的歌曲文件不可用';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖入歌曲失败：$detail';
  }

  @override
  String get searchNoticeEmptyKeyword => '请输入搜索关键词';

  @override
  String get searchNoticeGetLyricsFirst => '请先获取歌词';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return '歌词保存成功：$detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported => '当前平台不支持保存文件';

  @override
  String get searchNoticeFilePickerForTagUnsupported => '当前平台不支持选择歌曲标签文件';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return '选择文件失败：$detail';
  }

  @override
  String get searchNoticeBatchCancelling => '正在取消批量保存...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst => '请先选择专辑或歌单';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage => '请至少选择一种歌词语言';

  @override
  String get searchNoticeNoSongsToSave => '没有可保存的歌曲';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return '批量保存已取消：成功$saved，失败$failed，跳过$skipped';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return '批量保存完成：成功$saved，失败$failed，跳过$skipped';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return '批量保存失败：$detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates => '发现多个候选歌词，请选择一个继续';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return '获取歌词失败：$detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => '请先选择保存路径';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return '选择目录失败：$detail';
  }

  @override
  String get searchNoticePreviewLoading => '歌词仍在加载中';

  @override
  String get searchNoticePreviewNoLanguage => '请至少选择一种歌词语言';

  @override
  String get searchNoticePreviewNoContent => '当前歌词暂无可预览内容';

  @override
  String get searchNoticePreviewNoSelection => '请先下载并预览歌词';

  @override
  String get desktopWindowActionSelectLyrics => '选择歌词';

  @override
  String get desktopWindowActionMarkInstrumental => '标记为纯音乐';

  @override
  String get desktopWindowActionDisableAutoSearch => '禁用自动搜索(仅本曲)';

  @override
  String get desktopWindowActionUnlinkLyrics => '取消歌词关联';

  @override
  String get desktopWindowActionAssociationManager => '歌词关联管理器';

  @override
  String get desktopWindowActionToggleFloating => '显示/隐藏桌面歌词';

  @override
  String get desktopWindowActionShowMainWindow => '显示主窗口';

  @override
  String get desktopWindowActionClickThrough => '鼠标穿透';

  @override
  String get desktopWindowActionPrevious => '上一首';

  @override
  String get desktopWindowActionPlay => '播放';

  @override
  String get desktopWindowActionPause => '暂停';

  @override
  String get desktopWindowActionNext => '下一首';

  @override
  String get desktopWindowActionHide => '隐藏';

  @override
  String get desktopTrayCurrentTarget => '当前目标：';

  @override
  String get desktopTrayNoSelection => '未选择';

  @override
  String get desktopTrayTargetInstance => '目标实例';

  @override
  String get desktopTrayInstance => '实例';

  @override
  String get desktopTrayExit => '退出';

  @override
  String get desktopWindowInfoInstrumental => '纯音乐';

  @override
  String get desktopWindowControlConnectionLost => '播放器连接已断开，操作未执行';

  @override
  String get desktopWindowClientDisconnected => '播放器连接已断开，桌面歌词已关闭';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => '警告';

  @override
  String get commonError => '错误';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonFailed => '失败';

  @override
  String get commonSkipped => '跳过';

  @override
  String get commonTotal => '总数';

  @override
  String get commonDelete => '删除';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonRestoreDefault => '恢复默认';

  @override
  String get commonEnabled => '已启用';

  @override
  String get commonDisabledByDefault => '默认关闭';

  @override
  String get commonFormat => '格式';

  @override
  String get commonOffset => '偏移';

  @override
  String get commonSaving => '保存中...';

  @override
  String get commonAddFiles => '添加文件';

  @override
  String get commonClearQueue => '清空队列';

  @override
  String get commonUnsupportedOperation => '当前平台不支持此操作';

  @override
  String get commonLyricsFileUnavailable => '当前条目还没有可打开的歌词文件';

  @override
  String get commonAudioTagRequiresLrc => '歌曲标签中的歌词应为 LRC 格式';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language（$type）';
  }

  @override
  String get commonTranslationCancelled => '已取消翻译';

  @override
  String get commonCancelTranslation => '取消翻译';

  @override
  String get commonTranslating => '翻译中...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return '翻译中 $completed/$total';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI 流式翻译中：$completed / $total 行';
  }

  @override
  String get commonTranslationCompleted => '翻译完成';

  @override
  String get commonLyricsSaved => '歌词保存成功';

  @override
  String commonDropFailed(String detail) {
    return '拖拽处理失败：$detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return '选择保存目录失败：$detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return '打开保存目录失败：$detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return '翻译失败：$detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return '歌词保存失败：$detail';
  }

  @override
  String get appErrorUnknown => '发生未知错误。';

  @override
  String get appErrorOperationTimeout => '操作超时，请稍后重试。';

  @override
  String get appErrorNetworkUnavailable => '网络不可用，请检查连接。';

  @override
  String get appErrorInvalidPayload => '数据格式错误。';

  @override
  String get appErrorUnsupportedOperation => '当前操作不受支持。';

  @override
  String get appErrorPermissionDenied => '没有执行此操作的权限。';

  @override
  String get appErrorIoFailure => '文件读写失败。';

  @override
  String get appErrorLyricsRequestFailed => '请求歌词失败。';

  @override
  String get appErrorLyricsNotFound => '没有找到歌词。';

  @override
  String get appErrorLyricsProcessing => '歌词处理失败。';

  @override
  String get appErrorLyricsDecrypt => '歌词解密失败。';

  @override
  String get appErrorLyricsFormatUnsupported => '不支持的歌词格式。';

  @override
  String get appErrorDecoding => '解码失败。';

  @override
  String get appErrorSongInfoRead => '获取歌曲信息失败。';

  @override
  String get appErrorUnsupportedFileType => '不支持的文件格式。';

  @override
  String get appErrorDragDropInvalid => '拖拽数据无效。';

  @override
  String get appErrorTranslateFailed => '翻译失败。';

  @override
  String get appErrorApiParamsInvalid => '请求参数不正确。';

  @override
  String get appErrorApiRequestFailed => '接口请求失败。';

  @override
  String get appErrorAutoFetchUnknown => '自动匹配发生未知错误。';

  @override
  String get appErrorNotEnoughInfo => '搜索信息不足。';

  @override
  String get appErrorIpcInvalidLength => 'IPC 消息长度无效。';

  @override
  String get appErrorIpcUnsupportedTask => 'IPC 任务不受支持。';

  @override
  String get appErrorIpcInstanceNotFound => 'IPC 实例不存在。';

  @override
  String get appErrorIpcPanelNotFound => 'IPC 面板不存在。';

  @override
  String get appErrorIpcInvalidWindowId => '窗口句柄无效。';

  @override
  String get appErrorIpcEmbedUnsupported => '当前平台不支持嵌入模式。';

  @override
  String get appErrorActionRetryNetwork => '请检查网络后重试。';

  @override
  String get appErrorActionCheckPayload => '请检查输入数据格式。';

  @override
  String get appErrorActionChangeFormat => '请更换支持的文件或格式。';

  @override
  String get appErrorActionDetachedMode => '请回退到 detached 模式。';

  @override
  String get actionRetry => '重试';

  @override
  String get actionViewDetails => '查看详情';

  @override
  String get actionCancel => '取消';

  @override
  String get sourceAggregate => '聚合';

  @override
  String get sourceQQMusic => 'QQ音乐';

  @override
  String get sourceKugou => '酷狗音乐';

  @override
  String get sourceNetease => '网易云音乐';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => '本地';

  @override
  String get lyricOriginal => '原文';

  @override
  String get lyricTranslation => '译文';

  @override
  String get lyricRomanized => '罗马音';

  @override
  String get lyricsFormatVerbatimLrc => 'LRC（逐字）';

  @override
  String get lyricsFormatLineByLineLrc => 'LRC（逐行）';

  @override
  String get lyricsFormatEnhancedLrc => '增强型 LRC（ESLyric）';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => 'ASS';

  @override
  String get lyricsTypeVerbatim => '逐字';

  @override
  String get lyricsTypeLineByLine => '逐行';

  @override
  String get lyricsTypePlainText => '纯文本';

  @override
  String get searchSong => '单曲';

  @override
  String get searchAlbum => '专辑';

  @override
  String get searchSongList => '歌单';

  @override
  String get searchArtist => '歌手';

  @override
  String get searchLyrics => '歌词';

  @override
  String get searchSongId => '歌曲id';

  @override
  String get localMatchIteratingFiles => '遍历文件...';

  @override
  String get localMatchProgressImportCompleted => '导入完成';

  @override
  String get localMatchProgressScanCompleted => '扫描完成';

  @override
  String get localMatchProgressScanFailed => '扫描失败';

  @override
  String get localMatchProgressMatchCompleted => '匹配完成';

  @override
  String get localMatchProgressMatchFailed => '匹配失败';

  @override
  String get localMatchProgressPreparingMatch => '准备开始匹配...';

  @override
  String get localMatchPreviewTagOnly => '仅写入标签';

  @override
  String get localMatchPreviewWriteTag => '保存到标签';

  @override
  String get localMatchPreviewNoOutput => '未配置输出';

  @override
  String get localMatchPreviewSongTagOnly => '仅写入歌曲标签';

  @override
  String get localMatchPendingLyricsFileName => '等待歌词信息后确定文件名';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / 等待歌词信息后确定文件名';
  }

  @override
  String get localMatchCalcSavePathFailed => '计算歌词保存路径失败';

  @override
  String get localMatchNoticeBusyImportFiles => '当前任务执行中，无法继续导入文件';

  @override
  String get localMatchNoticeSelectedFilesUnavailable => '所选文件不可访问';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return '导入文件失败：$detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories => '当前任务执行中，无法继续导入目录';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return '导入目录失败：$detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles => '拖拽数据中没有可访问的文件';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖拽歌曲失败：$detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors => '导入完成，但有部分条目解析失败';

  @override
  String get localMatchNoticeSafTreeUnsupported => '当前平台不支持目录树授权';

  @override
  String get localMatchNoticeBusySwitchTree => '当前任务执行中，无法切换目录树';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return '选择目录树失败：$detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue => '当前任务执行中，无法清空队列';

  @override
  String get localMatchNoticeSelectItemsToDelete => '请先选择要删除的条目';

  @override
  String get localMatchNoticeSelectItemsToSetRoot => '请先选择要设置根目录的条目';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return '以下歌曲不在所选根目录中，已跳过：$detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return '设置根目录失败：$detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore => '请先选择要恢复的条目';

  @override
  String get localMatchNoticeCancelling => '正在取消当前任务...';

  @override
  String get localMatchNoticeValidationFailed => '请先处理本地匹配启动条件';

  @override
  String get localMatchNoticeSongDirectoryUnavailable => '当前条目不支持打开歌曲目录';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return '打开歌曲目录失败：$detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable => '当前条目还没有可打开的保存目录';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return '打开歌词失败：$detail';
  }

  @override
  String get localMatchNoticeScanCancelled => '扫描已取消';

  @override
  String get localMatchNoticeScanCompletedWithErrors => '扫描完成，但有部分文件解析失败';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return '扫描失败：$detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return '目录树扫描失败：$detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => '匹配已取消';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '总共$total首歌曲，匹配成功$success首，匹配失败$failed首，跳过$skipped首。';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return '本地匹配执行失败：$detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume => '匹配已取消，可再次开始从断点继续';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF 本地匹配执行失败：$detail';
  }

  @override
  String get localMatchValidationEmptyLangs => '请选择要匹配的语言';

  @override
  String get localMatchValidationEmptySources => '请选择至少一个源';

  @override
  String get localMatchValidationEmptyQueue => '请先导入要匹配的歌曲';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      '跳过已有歌词时，如果还需要保存文件，则文件名模式不能为按歌词信息命名';

  @override
  String get localMatchValidationMissingAndroidTree => '请先选择目录树';

  @override
  String get localMatchValidationNeedsSaveRoot => '需要指定保存路径';

  @override
  String get localMatchValidationNeedsSongRoot => '需要指定歌曲根目录';

  @override
  String get localMatchValidationUnknownSavePath => '未知保存路径错误';

  @override
  String get localMatchIntro => '导入本地歌曲或目录，预估输出结果后执行批量匹配。';

  @override
  String get localMatchDropUnsupportedItem => '本地匹配页只接受歌曲文件、目录或可解析播放器条目拖入';

  @override
  String get localMatchReadyToStart => '准备开始本地匹配';

  @override
  String get localMatchQueueTitle => '任务队列';

  @override
  String get localMatchQueueEmptyHint => '先导入文件或文件夹以建立任务队列';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '共 $count 条任务，右键行可执行更多操作';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '共 $count 条任务，长按或点击更多按钮可打开操作菜单';
  }

  @override
  String get localMatchImportAndRunTitle => '导入与执行';

  @override
  String get localMatchActionStart => '开始匹配';

  @override
  String get localMatchActionAddFolders => '添加文件夹';

  @override
  String get localMatchActionSelectSaveRoot => '选择保存根目录';

  @override
  String get localMatchActionSelectTree => '选择目录树';

  @override
  String get localMatchActionReselectTree => '重新选择目录树';

  @override
  String get localMatchActionBulkSelect => '批量选择';

  @override
  String get localMatchActionExitSelection => '退出批量选择';

  @override
  String get localMatchActionSelectAll => '全选';

  @override
  String get localMatchActionDeselectAll => '取消全选';

  @override
  String get localMatchActionSetRoot => '设置根目录';

  @override
  String localMatchSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get localMatchBulkActionHint => '批量操作会直接作用于当前选中的任务';

  @override
  String get localMatchPhaseIdle => '等待开始';

  @override
  String get localMatchPhaseScanning => '扫描中';

  @override
  String get localMatchPhaseMatching => '匹配中';

  @override
  String get localMatchPhaseWriting => '写回中';

  @override
  String get localMatchPhaseCompleted => '已完成';

  @override
  String get localMatchPhaseHintIdle => '导入歌曲后即可开始匹配';

  @override
  String get localMatchPhaseHintScanning => '正在建立任务队列与预估输出';

  @override
  String get localMatchPhaseHintMatching => '正在请求来源并计算最佳匹配';

  @override
  String get localMatchPhaseHintWriting => '正在写入歌词文件或歌曲标签';

  @override
  String get localMatchPhaseHintCompleted => '本轮任务已完成，可继续调整后重跑';

  @override
  String get localMatchPipelineIdle => '扫描 -> 匹配 -> 写回';

  @override
  String get localMatchPipelineScanning => '当前阶段：扫描';

  @override
  String get localMatchPipelineMatching => '当前阶段：匹配';

  @override
  String get localMatchPipelineWriting => '当前阶段：写回';

  @override
  String get localMatchPipelineCompleted => '已完成本轮扫描、匹配与写回';

  @override
  String get localMatchUnknownSong => '未知歌曲';

  @override
  String get localMatchUnknownDuration => '未知时长';

  @override
  String get localMatchStatusNotStarted => '未开始';

  @override
  String get localMatchSongPathLabel => '歌曲路径';

  @override
  String get localMatchLyricsPathLabel => '歌词保存路径';

  @override
  String get localMatchExpandDetails => '展开详情';

  @override
  String get localMatchCollapseDetails => '收起详情';

  @override
  String get localMatchRowActionOpenInSearch => '在搜索中打开';

  @override
  String get localMatchRowActionEnterSelection => '进入批量选择';

  @override
  String get localMatchRowActionOpenSongDirectory => '打开歌曲目录';

  @override
  String get localMatchRowActionOpenSaveDirectory => '打开保存目录';

  @override
  String get localMatchRowActionOpenLyrics => '打开歌词';

  @override
  String get localMatchFieldLyricsType => '歌词类型';

  @override
  String get localMatchFieldOutputStrategy => '输出策略';

  @override
  String get localMatchFieldSaveMode => '保存模式';

  @override
  String get localMatchFieldFileNameMode => '文件名模式';

  @override
  String get localMatchFieldLyricsFormat => '歌词格式';

  @override
  String get localMatchFieldThreshold => '匹配门槛';

  @override
  String get localMatchFieldSaveRoot => '保存根目录';

  @override
  String get localMatchMoreSettings => '更多设置';

  @override
  String get localMatchRulesTitle => '匹配规则';

  @override
  String get localMatchRulesSubtitle => '来源、语言、输出策略与匹配门槛';

  @override
  String get localMatchMinScore => '最低匹配度';

  @override
  String get localMatchSkipExisting => '跳过已有歌词';

  @override
  String get localMatchSkipExistingConflictHint =>
      '当前“输出策略 + 文件名模式”组合不支持开启跳过已有歌词；若还需要保存文件，请避免选择“按歌词信息命名”。';

  @override
  String get localMatchSaveToSongDirectoryHint => '当前保存到歌曲目录，无需额外保存根目录。';

  @override
  String get localMatchAndroidTreeSaveHint => 'Android 目录树文件保存会直接写入已授权目录树。';

  @override
  String get localMatchFileNameTemplateHint =>
      '命名模板沿用设置页中的 lyrics_file_name_fmt。';

  @override
  String localMatchSaveRootPath(String path) {
    return '保存根目录：$path';
  }

  @override
  String get localMatchSaveRootRequired => '当前保存模式需要保存根目录，请先选择。';

  @override
  String get localMatchTreeNotSelected => '尚未选择目录树';

  @override
  String get localMatchSaveModeSong => '保存到歌曲目录';

  @override
  String get localMatchSaveModeMirror => '镜像目录';

  @override
  String get localMatchSaveModeSpecify => '指定目录';

  @override
  String get localMatchFileNameModeSong => '按歌曲文件名';

  @override
  String get localMatchFileNameModeFormatBySong => '按歌曲信息命名';

  @override
  String get localMatchFileNameModeFormatByLyrics => '按歌词信息命名';

  @override
  String get localMatchFileNameHintSong => '沿用音频文件名，仅替换歌词扩展名。';

  @override
  String get localMatchFileNameHintFormatBySong => '使用标题、艺术家、专辑等歌曲元数据生成文件名。';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      '使用匹配到的歌词歌曲信息生成文件名；未匹配前可能无法确定。';

  @override
  String get localMatchSaveToTagOnlyFile => '仅保存文件';

  @override
  String get localMatchSaveToTagOnlyTag => '仅写入标签';

  @override
  String get localMatchSaveToTagBoth => '文件 + 标签';

  @override
  String get localMatchValidationTitle => '开始前需要处理的问题';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '还有 $count 个问题需要先处理';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable => '所选文件当前不可直接访问';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return '已导入 $count 个歌词文件';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles => '拖拽数据中没有可访问的歌词文件';

  @override
  String get batchConvertNoticeEmptyQueue => '请先添加要转换的歌词文件';

  @override
  String get batchConvertNoticeOverwriteCancelled => '已取消批量转换';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return '批量转换已取消，已完成 $count 项';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return '批量转换完成：成功 $success，失败 $failure';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return '批量转换完成：共 $count 项';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return '批量转换失败：$detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return '打开原目录失败：$detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return '打开歌词文件失败：$detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles => '所选文件夹中没有找到支持的歌词文件';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return '已从文件夹导入 $count 个歌词文件';
  }

  @override
  String get batchConvertNoticeDuplicateItems => '所选条目都已在队列中';

  @override
  String get batchConvertControlsTitle => '导入与设置';

  @override
  String get batchConvertCompactControlsTitle => '导入与输出设置';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return '格式：$format';
  }

  @override
  String get batchConvertImportTitle => '导入';

  @override
  String get batchConvertAddFolders => '添加文件夹';

  @override
  String get batchConvertOutputSettingsTitle => '输出设置';

  @override
  String get batchConvertTargetFormat => '目标格式';

  @override
  String get batchConvertSaveDirectoryTitle => '保存目录';

  @override
  String get batchConvertSaveDirectoryDefault => '未设置时默认输出到原歌词所在目录';

  @override
  String get batchConvertSelectSaveDirectory => '选择保存目录';

  @override
  String get batchConvertRestoreOriginalDirectory => '恢复原目录';

  @override
  String get batchConvertRecursiveTitle => '遍历子文件夹';

  @override
  String get batchConvertRecursiveSubtitle => '目录导入时继续扫描子目录中的歌词文件';

  @override
  String get batchConvertStart => '开始转换';

  @override
  String get batchConvertCancel => '取消转换';

  @override
  String get batchConvertQueueTitle => '转换队列';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '共 $count 项，输出格式为 $format';
  }

  @override
  String get batchConvertPageErrorFallback => '批量转换页面出现错误';

  @override
  String get batchConvertRetryImport => '重新导入';

  @override
  String get batchConvertEmptyQueue => '添加歌词文件或文件夹后，这里会显示批量转换队列。';

  @override
  String get batchConvertOutputPathLabel => '输出路径';

  @override
  String get batchConvertQueueStatusWaiting => '等待转换';

  @override
  String get batchConvertQueueStatusRunning => '正在转换';

  @override
  String get batchConvertQueueStatusSuccess => '转换成功';

  @override
  String get batchConvertQueueStatusFailure => '转换失败';

  @override
  String get batchConvertMoreActions => '更多操作';

  @override
  String get batchConvertActionOpenSourceDirectory => '打开原歌词目录';

  @override
  String get batchConvertActionOpenSaveDirectory => '打开保存目录';

  @override
  String get batchConvertActionOpenOutputFile => '打开歌词文件';

  @override
  String get batchConvertActionOpenInOpenLyrics => '在打开歌词页中打开';

  @override
  String get batchConvertPhaseIdle => '等待开始';

  @override
  String get batchConvertPhaseScanning => '正在扫描';

  @override
  String get batchConvertPhaseRunning => '正在转换';

  @override
  String get batchConvertPhaseCompleted => '已完成';

  @override
  String get batchConvertPipelineIdle => '导入 -> 扫描 -> 转换 -> 完成';

  @override
  String get batchConvertPipelineScanning => '扫描目录 -> 建立队列';

  @override
  String get batchConvertPipelineRunning => '逐条转换 -> 持续更新状态';

  @override
  String get batchConvertPipelineCompleted => '可继续调整格式或重新导入';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return '已取消，成功 $success，失败 $failure';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '成功 $success，失败 $failure';
  }

  @override
  String get batchConvertHintNoQueue => '添加文件或文件夹后开始转换';

  @override
  String get batchConvertHintReady => '当前队列已就绪';

  @override
  String get batchConvertMetricWaiting => '待处理';

  @override
  String get batchConvertDropUnsupported => '批量转换页只接受歌词文件或目录拖入';

  @override
  String batchConvertDropFailed(String detail) {
    return '拖拽处理失败：$detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return '正在转换 $fileName';
  }

  @override
  String get batchConvertProgressItemSuccess => '转换成功';

  @override
  String get batchConvertProgressItemFailure => '转换失败';

  @override
  String get batchConvertProgressPreparingConversion => '准备开始转换...';

  @override
  String get batchConvertProgressCancellingConversion => '正在取消转换...';

  @override
  String get batchConvertProgressConversionCancelled => '转换已取消';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return '转换完成：成功 $success，失败 $failure';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return '转换失败：$detail';
  }

  @override
  String get batchConvertProgressScanningFolders => '正在遍历文件夹...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return '正在扫描 $directoryName';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return '已扫描到 $count 个歌词文件';
  }

  @override
  String get batchConvertProgressScanCancelled => '扫描已取消';

  @override
  String get batchConvertProgressScanNoSupportedFiles => '未找到支持的歌词文件';

  @override
  String get batchConvertProgressScanCompleted => '扫描完成';

  @override
  String get navSearch => '搜索';

  @override
  String get navLocalMatch => '本地匹配';

  @override
  String get navOpenLyrics => '打开歌词';

  @override
  String get navBatchConvert => '批量转换';

  @override
  String get navSettings => '设置';

  @override
  String get navAbout => '关于';

  @override
  String get commonSearch => '搜索';

  @override
  String get commonSource => '来源';

  @override
  String get searchKeywordHint => '输入关键词';

  @override
  String get uiLoading => '加载中...';

  @override
  String get uiLoadingStepFetching => '正在获取列表与预览...';

  @override
  String get uiEmpty => '暂无数据';

  @override
  String get uiNoMoreResult => '没有更多结果';

  @override
  String get searchInitialResultTitle => '输入关键词开始搜索';

  @override
  String get searchInitialResultDescription => '在上方选择来源并发起搜索';

  @override
  String get searchResultTitle => '搜索结果';

  @override
  String get searchResultReturn => '返回上一层';

  @override
  String get searchPreviewTitle => '歌词预览';

  @override
  String get searchPreviewLangsLabel => '歌词语言';

  @override
  String get searchPreviewSongIdLabel => '歌曲ID';

  @override
  String get searchPreviewPlaceholder => '请先选择歌曲或歌词条目';

  @override
  String get searchPreviewNoLanguage => '请至少选择一种歌词语言';

  @override
  String get searchPreviewNoContent => '当前歌词暂无可预览内容';

  @override
  String get searchPreviewLoading => '正在加载歌词...';

  @override
  String get searchFormatLabel => '歌词格式';

  @override
  String get searchTranslateLyrics => '翻译歌词';

  @override
  String get searchResizeWorkspacePanes => '调整搜索结果与歌词预览宽度';

  @override
  String get searchSavePreviewToDirectory => '保存到文件夹';

  @override
  String get searchSavePreviewToFile => '保存到文件';

  @override
  String get searchSavePreviewToTag => '保存到歌曲标签';

  @override
  String get searchSaveListLyrics => '保存专辑/歌单的歌词';

  @override
  String get searchSaveListLyricsCancel => '取消批量保存';

  @override
  String get searchSelectSavePath => '选择保存路径';

  @override
  String get searchBatchSaveProgressTitle => '批量保存进度';

  @override
  String get searchBatchSaveProgressPreparing => '准备批量保存...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return '正在获取 $songName 的歌词...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count 首';
  }

  @override
  String get searchTableStatusAutoFetching => '正在自动获取...';

  @override
  String get searchTableStatusSearching => '正在搜索...';

  @override
  String get searchTableStatusFetchingSongList => '正在获取歌曲列表...';

  @override
  String get searchTableStatusNoResults => '没有搜索到相关结果';

  @override
  String get searchTableStatusEmptyList => '列表为空';

  @override
  String get searchTableStatusUnsupportedSearchType => '所选来源不支持当前搜索类型';

  @override
  String get searchTableStatusSearchFailed => '搜索失败';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return '搜索失败：$detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return '自动获取歌词失败：$detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return '获取歌曲列表失败：$detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable => '部分来源不可用，已展示可用结果';

  @override
  String get searchTableStatusLoadMoreFailed => '部分来源加载更多失败';

  @override
  String get searchSourceFailureDetailsTitle => '搜索错误详情';

  @override
  String get searchSourceFailureRequest => '请求失败';

  @override
  String get searchSourceFailureTimeout => '请求超时';

  @override
  String get searchSourceFailureParameters => '参数错误';

  @override
  String get searchSourceFailureUnsupported => '不支持的操作';

  @override
  String get searchSourceFailureUnknown => '未知错误';

  @override
  String get searchResultLoadingMore => '正在继续加载更多结果...';

  @override
  String get searchResultLoadMoreFailed => '自动续取失败，可重试继续加载剩余结果';

  @override
  String get searchResultScrollForMore => '继续向下滚动以自动加载更多结果';

  @override
  String get tableSavePath => '保存路径';

  @override
  String get settingsSectionSave => '保存';

  @override
  String get settingsSectionLyrics => '歌词';

  @override
  String get settingsSectionDesktopLyrics => '桌面歌词';

  @override
  String get settingsSectionTranslate => '翻译';

  @override
  String get settingsSectionSearch => '搜索';

  @override
  String get settingsSectionApp => '应用';

  @override
  String get settingsSectionTools => '工具与数据';

  @override
  String get settingsSectionSaveSummary => '保存路径、文件名模板与 ID3 版本';

  @override
  String get settingsSectionSearchSummary => '决定“聚合”搜索和本地匹配默认使用的歌词来源。';

  @override
  String get settingsSectionDesktopLyricsSummary => '桌面歌词自动获取、显示语言、外观与刷新率。';

  @override
  String get settingsSectionLyricsSummary => '本地匹配策略与歌词文件导出格式。';

  @override
  String get settingsSectionTranslateSummary => '翻译源、目标语言与条件字段';

  @override
  String get settingsSectionAppSummary => '语言、主题、日志与更新策略';

  @override
  String get settingsSectionToolsSummary => '桌面工具入口、日志目录与缓存清理';

  @override
  String get settingsTranslateSourceBing => '必应翻译';

  @override
  String get settingsTranslateSourceGoogle => '谷歌翻译';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI兼容API';

  @override
  String get settingsLangSimplifiedChinese => '简体中文';

  @override
  String get settingsLangTraditionalChinese => '繁体中文';

  @override
  String get settingsLangEnglish => '英语';

  @override
  String get settingsLangJapanese => '日语';

  @override
  String get settingsLangKorean => '韩语';

  @override
  String get settingsLangSpanish => '西班牙语';

  @override
  String get settingsLangFrench => '法语';

  @override
  String get settingsLangPortuguese => '葡萄牙语';

  @override
  String get settingsLangGerman => '德语';

  @override
  String get settingsLangRussian => '俄语';

  @override
  String get settingsAppLanguageAuto => '自动';

  @override
  String get settingsColorSchemeAuto => '跟随系统';

  @override
  String get settingsColorSchemeLight => '浅色';

  @override
  String get settingsColorSchemeDark => '深色';

  @override
  String get settingsDesktopGradientColors => '渐变颜色';

  @override
  String get settingsDesktopPlayedColors => '已播放颜色';

  @override
  String get settingsDesktopUnplayedColors => '未播放颜色';

  @override
  String get settingsAddColor => '添加颜色';

  @override
  String get settingsEditColor => '编辑颜色';

  @override
  String get settingsDeleteColor => '删除颜色';

  @override
  String get settingsBackToSections => '返回设置分组';

  @override
  String get settingsAvailablePlaceholders => '可用占位符';

  @override
  String get settingsPlaceholderTitleArtist => '歌名：%<title>    艺术家：%<artist>';

  @override
  String get settingsPlaceholderAlbumId => '专辑名：%<album>    歌曲/歌词 id：%<id>';

  @override
  String get settingsPlaceholderLangs => '语言类型：%<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return '当前模板：$template';
  }

  @override
  String get settingsTranslateSourceLabel => '翻译源';

  @override
  String get settingsTranslateTargetLabel => '目标语言';

  @override
  String get settingsOpenAiProfileLabel => '预设';

  @override
  String get settingsOpenAiProfileHelper =>
      '选择内置服务商会自动填入 Base URL，API Key 和模型仍需配置。';

  @override
  String get settingsAppLanguageLabel => '界面语言';

  @override
  String get settingsColorSchemeLabel => '主题模式';

  @override
  String get settingsLogLevelLabel => '日志级别';

  @override
  String get settingsLogLevelHelper => '通常保持 INFO；TRACE 和 DEBUG 会记录更多内容并增大日志。';

  @override
  String get settingsAutoCheckUpdateLabel => '自动检查更新';

  @override
  String get settingsRestoreDefaultsWarning => '恢复默认值会立即写入配置，请确认后执行。';

  @override
  String get settingsRestoreAllTitle => '恢复默认设置';

  @override
  String get settingsRestoreAllContent => '该操作会恢复所有设置项，并立即写入配置。';

  @override
  String get settingsRestoreAllAction => '恢复默认设置';

  @override
  String get settingsOpenAssociationManager => '打开歌词关联管理器';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      '进入设置下一级页面，统一管理歌曲与歌词关联记录。';

  @override
  String get settingsOpenLogDirectory => '打开日志目录';

  @override
  String get settingsOpenLogDirectorySubtitle => '查看运行日志与问题排查文件。';

  @override
  String get settingsClearCache => '清理缓存';

  @override
  String get settingsClearCacheSubtitle => '清理搜索与翻译缓存，不影响配置文件。';

  @override
  String get settingsClearCacheContent => '缓存清理后，后续搜索与翻译可能需要重新请求。';

  @override
  String get settingsRestoreSectionTitle => '恢复本组默认值';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return '仅恢复“$sectionTitle”分组中的设置项，其他分组不会被修改。';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return '恢复$sectionTitle分组默认值';
  }

  @override
  String get settingsDefaultSavePathHelper => '留空时使用平台默认音乐目录。';

  @override
  String get settingsChooseFolder => '选择文件夹';

  @override
  String get settingsLyricsFileNameFormat => '歌词文件名模板';

  @override
  String get settingsLyricsFileNameFormatHelper => '可使用下方占位符组合生成保存文件名。';

  @override
  String get settingsId3Version => 'ID3 版本';

  @override
  String get settingsId3VersionHelper => '仅影响把歌词写入音频标签；不确定时保持 v2.3。';

  @override
  String get settingsSearchSourcesTitle => '聚合搜索来源';

  @override
  String get settingsSearchSourcesDescription =>
      '搜索页选择“聚合”时查询已勾选来源；越靠上，结果排列和自动匹配优先级越高。本地匹配默认沿用此列表。';

  @override
  String get settingsReorderPriorityHint => '拖动调整优先级';

  @override
  String get settingsReorderOrderHint => '拖动调整顺序';

  @override
  String get settingsDefaultLanguage => '默认显示语言';

  @override
  String get settingsDefaultLanguageDescription =>
      '勾选桌面歌词默认显示的语言，拖动调整多语言歌词的排列顺序。';

  @override
  String get settingsDesktopAutoFetchSources => '自动获取来源';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      '桌面歌词没有关联歌词时，按从上到下的优先级自动获取。';

  @override
  String get settingsFont => '字体';

  @override
  String get settingsFollowSystemFont => '跟随系统字体';

  @override
  String get settingsFontSizeByResize => '桌面歌词主窗口字号通过拖拽窗口大小调整。';

  @override
  String get settingsPanelFontSize => '歌词面板字号';

  @override
  String get settingsAdaptiveRefreshRate => '自适应刷新率';

  @override
  String get settingsAdaptiveRefreshRateSubtitle => '开启后根据歌词动画状态自动选择刷新节奏。';

  @override
  String get settingsFixedRefreshRate => '固定刷新率';

  @override
  String get settingsShowFurigana => '显示注音';

  @override
  String get settingsLyricsMatchBehavior => '匹配行为';

  @override
  String get settingsLyricsMatchBehaviorDescription => '控制本地匹配和酷狗歌词候选的默认处理方式。';

  @override
  String get settingsLyricsExport => 'LRC 导出';

  @override
  String get settingsLyricsExportDescription => '控制保存歌词文件时使用的语言顺序和 LRC 时间戳格式。';

  @override
  String get settingsDisplayOrder => '导出语言顺序';

  @override
  String get settingsDisplayOrderDescription => '拖动调整原文、译文和罗马音在歌词文件中的顺序。';

  @override
  String get settingsSkipInstrumental => '跳过纯音乐';

  @override
  String get settingsSkipInstrumentalSubtitle => '本地匹配识别为纯音乐时不保存歌词。';

  @override
  String get settingsAutoSelectKugou => '自动选择酷狗候选';

  @override
  String get settingsAutoSelectKugouSubtitle => '搜索页打开酷狗歌曲时自动选择最佳歌词候选。';

  @override
  String get settingsAddLrcEndTimestamp => '导出 LRC 时添加结尾时间戳';

  @override
  String get settingsAddLrcEndTimestampSubtitle => '仅影响逐行 LRC，在需要时写入行结束时间戳。';

  @override
  String get settingsMillisecondsDigits => '毫秒位数';

  @override
  String get settingsMillisecondsDigitsHelper => '两位使用百分之一秒，三位保留完整毫秒。';

  @override
  String settingsDigitsValue(int value) {
    return '$value 位';
  }

  @override
  String get settingsLastRefStyle => '同句最后一行时间戳';

  @override
  String get settingsLastRefStyleHelper =>
      '决定多语言逐行 LRC 中同一句最后一种语言使用当前行时间，还是下一行前 1 毫秒。';

  @override
  String get settingsLastRefCurrentLine => '使用当前行时间';

  @override
  String get settingsLastRefNextLine => '使用下一行前一毫秒';

  @override
  String get settingsTagInfoSource => '标签信息来源';

  @override
  String get settingsTagInfoLyricsSource => '歌词来源';

  @override
  String get settingsTagInfoSongInfo => '歌曲信息';

  @override
  String get settingsNoticeDefaultSavePathUpdated => '默认保存路径已更新';

  @override
  String get settingsNoticeDefaultSavePathRestored => '默认保存路径已恢复';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated => '歌词文件名模板已更新';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3 版本已更新';

  @override
  String get settingsNoticeLyricsLangOrderEmpty => '歌词语言顺序不能为空';

  @override
  String get settingsNoticeLyricsLangOrderUpdated => '歌词语言顺序已更新';

  @override
  String get settingsNoticeSkipInstUpdated => '纯音乐跳过策略已更新';

  @override
  String get settingsNoticeAutoSelectUpdated => '自动选择策略已更新';

  @override
  String get settingsNoticeAddEndTimestampUpdated => '结尾时间戳策略已更新';

  @override
  String get settingsNoticeMsDigitsUpdated => '毫秒位数已更新';

  @override
  String get settingsNoticeLastRefStyleUpdated => '尾行时间样式已更新';

  @override
  String get settingsNoticeTagInfoSourceUpdated => '标签来源已更新';

  @override
  String get settingsNoticeDesktopSourcesEmpty => '桌面歌词来源不能为空';

  @override
  String get settingsNoticeDesktopSourcesUpdated => '桌面歌词来源已更新';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty => '桌面默认语言不能为空';

  @override
  String get settingsNoticeDesktopLangsUpdated => '桌面歌词语言设置已更新';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated => '桌面歌词字体已更新';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => '刷新率已更新';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated => '已播放颜色已更新';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated => '未播放颜色已更新';

  @override
  String get settingsNoticeDesktopFontSizeUpdated => '桌面歌词字号已更新';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated => '桌面面板字号已更新';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated => '注音显示策略已更新';

  @override
  String get settingsNoticeTranslateSourceUpdated => '翻译源已更新';

  @override
  String get settingsNoticeTranslateTargetLangUpdated => '翻译目标语言已更新';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI 预设已更新';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI Base URL 已更新';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI API Key 已更新';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI 模型已更新';

  @override
  String get settingsNoticeSearchSourcesEmpty => '聚合搜索来源不能为空';

  @override
  String get settingsNoticeSearchSourcesUpdated => '聚合搜索来源已更新';

  @override
  String get settingsNoticeAppLanguageUpdated => '界面语言已更新';

  @override
  String get settingsNoticeAppColorSchemeUpdated => '主题模式已更新';

  @override
  String get settingsNoticeAppLogLevelUpdated => '日志级别已更新';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated => '自动检查更新已更新';

  @override
  String get settingsNoticeSectionNoRestorableConfig => '当前分组没有可恢复的配置项';

  @override
  String get settingsNoticeSectionDefaultsRestored => '当前分组已恢复默认值';

  @override
  String get settingsNoticeAllDefaultsRestored => '应用设置已恢复默认值';

  @override
  String get settingsNoticeAssociationManagerOpened => '已打开歌词关联管理器';

  @override
  String get settingsNoticeLogDirectoryOpened => '日志目录已打开';

  @override
  String get settingsNoticeLogDirectoryOpenFailed => '打开日志目录失败';

  @override
  String get settingsNoticeCacheCleared => '缓存已清理';

  @override
  String get settingsNoticeCacheClearFailed => '清理缓存失败';

  @override
  String get settingsNoticeConfigWriteFailed => '设置写入失败';

  @override
  String get settingsCurrentSavePathLabel => '默认保存路径';

  @override
  String get aboutLoadFailed => '加载关于页信息失败';

  @override
  String get aboutActionOpenRepository => 'GitHub仓库';

  @override
  String get aboutActionCheckUpdate => '检查更新';

  @override
  String get aboutHeroHeadline => '为精准歌词而设计';

  @override
  String get aboutHeroDescription =>
      'LDDC 将搜索、转换、桌面歌词与批处理工作流收口到同一套高效率体验里，让精准歌词获取、整理与使用保持顺滑。';

  @override
  String get aboutLinksSectionTitle => '常用链接';

  @override
  String get aboutLinksSectionDescription => '需要继续了解项目时，可以从这里查看反馈、更新与许可证信息。';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return 'Copyright (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return 'Licensed under $license.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub 仓库';

  @override
  String get aboutLinkIssueTrackerTitle => '问题反馈';

  @override
  String get aboutLinkIssueTrackerDescription => '提交 Bug、交互建议和功能需求。';

  @override
  String get aboutLinkLicenseTitle => '许可证';

  @override
  String get aboutLinkLicenseDescription => '查看项目当前采用的开源许可证：';

  @override
  String get aboutLinkChangelogTitle => '更新日志';

  @override
  String get aboutLinkChangelogDescription => '浏览版本发布记录与变更摘要。';

  @override
  String get aboutExternalLinksUnavailable => '当前平台暂不支持打开外部链接。';

  @override
  String get aboutCheckUpdateUnavailable => '当前平台暂不支持检查更新。';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes => '已打开更新日志页面。';

  @override
  String get aboutCheckUpdateUpToDate => '当前已经是最新版本。';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return '发现新版本：$version。请打开更新日志页面查看详情。';
  }

  @override
  String get aboutCheckUpdateFailed => '检查更新失败，请稍后重试。';

  @override
  String aboutActionOpenedLink(String title) {
    return '已打开 $title';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return '打开 $title 失败';
  }

  @override
  String get actionConfirm => '确定';

  @override
  String get libraryLinkManagerTitle => '歌词关联管理器';

  @override
  String get libraryLinkManagerReturnToSettings => '返回设置';

  @override
  String get libraryLinkManagerRefresh => '刷新';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return '删除选中 ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => '删除全部';

  @override
  String get libraryLinkManagerClearInvalid => '清理无效数据';

  @override
  String get libraryLinkManagerChangeDirectory => '批量改目录';

  @override
  String get libraryLinkManagerBackupToJson => '备份到 JSON';

  @override
  String get libraryLinkManagerRestoreFromJson => '从 JSON 恢复';

  @override
  String get libraryLinkManagerRestoreAction => '恢复';

  @override
  String get libraryLinkManagerExportLyrics => '导出歌词';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '共 $totalCount 条记录 · 已选择 $selectedCount 条记录';
  }

  @override
  String get libraryLinkManagerSearchHint => '搜索歌曲、艺术家、专辑或路径';

  @override
  String get libraryLinkManagerClearSearch => '清除搜索';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '匹配 $totalCount 条记录 · 已选择 $selectedCount 条记录';
  }

  @override
  String get libraryLinkManagerEmpty => '暂无歌词关联记录';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return '加载关联记录失败: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess => '已删除选中的歌词关联';

  @override
  String get libraryLinkManagerDeleteAllConfirm => '确定要删除全部歌词关联记录吗？';

  @override
  String get libraryLinkManagerDeleteAllSuccess => '已删除全部歌词关联记录';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return '清理完成，共清理 $count 条无效数据';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return '批量改目录完成，共更新 $count 条记录';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return '歌词关联数据已备份到 $path';
  }

  @override
  String get libraryLinkManagerRestoreConfirm => '恢复会覆盖当前全部歌词关联记录，是否继续？';

  @override
  String get libraryLinkManagerRestoreSuccess => '歌词关联数据已恢复';

  @override
  String get libraryLinkManagerInvalidBackupFormat => '备份文件格式错误';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return '导出完成，共导出 $count 条歌词文件';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return '操作失败: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => '未命名歌曲';

  @override
  String get libraryLinkManagerUnknownArtist => '未知艺术家';

  @override
  String get libraryLinkManagerUnknownAlbum => '未知专辑';

  @override
  String get libraryLinkManagerSongPathLabel => '歌曲路径';

  @override
  String get libraryLinkManagerSongPathEmpty => '未记录歌曲路径';

  @override
  String get libraryLinkManagerLyricsPathLabel => '歌词路径';

  @override
  String get libraryLinkManagerLyricsPathEmpty => '未关联歌词';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return '轨道 $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return '轨道编号：$track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => '无';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return '偏移 $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return '歌词偏移：$offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return '语言 $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return '歌词语言：$langs';
  }

  @override
  String get libraryLinkManagerInstrumental => '纯音乐';

  @override
  String get libraryLinkManagerInstrumentalTooltip => '当前歌曲已标记为纯音乐';

  @override
  String get libraryLinkManagerDisableAutoSearch => '禁用自动搜索';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip => '当前歌曲已禁用自动搜索';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return '其他配置 $count 项';
  }

  @override
  String get libraryLinkManagerDefaultConfig => '默认配置';

  @override
  String get libraryLinkManagerDefaultConfigTooltip => '当前记录未保存歌曲级特殊配置';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return '打开失败：$detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable => '当前歌词文件不可访问';

  @override
  String get openLyricsNoticeSongFileUnavailable => '当前歌曲文件不可访问';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics => '歌曲内没有可读取的内嵌歌词';

  @override
  String get openLyricsNoticeAlreadyConverted => '当前歌词已经转换过了';

  @override
  String get openLyricsNoticeEmptyLyrics => '歌词内容不能为空';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return '转换失败：$detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => '请先转换歌词';

  @override
  String get openLyricsNoticeNoLyricsToSave => '没有歌词可以保存';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return '歌词保存成功：$detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return '保存失败：$detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => '请先打开歌曲文件';

  @override
  String get openLyricsNoticeAudioTagUnsupported => '当前平台不支持写入歌曲标签';

  @override
  String get openLyricsDropUnsupportedItem => '打开歌词页只接受歌词文件或音频文件拖入';

  @override
  String get openLyricsPreviewTitle => '预览';

  @override
  String get openLyricsPreviewRawText => '原始文本';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return '歌词语言 · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => '未加载';

  @override
  String get openLyricsPreviewStateRawLoaded => '待转换';

  @override
  String get openLyricsPreviewStateConverted => '已转换';

  @override
  String get openLyricsPreviewEmptyNoInput => '请先打开歌词文件或歌曲文件';

  @override
  String get openLyricsActionOpening => '打开中...';

  @override
  String get openLyricsActionOpenLyricsFile => '打开歌词文件';

  @override
  String get openLyricsActionOpenSongFile => '打开歌曲文件';

  @override
  String get openLyricsActionConvertFormat => '转换格式';

  @override
  String get openLyricsActionSaveLyrics => '保存歌词';

  @override
  String get openLyricsActionSaveToTag => '保存到歌曲标签';

  @override
  String get openLyricsActionTranslate => '翻译歌词';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return '当前导出格式：$format · 可写回标签';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return '当前导出格式：$format · 仅支持导出文件';
  }

  @override
  String get searchLyricsSelectorTitle => '选择歌词';

  @override
  String get searchLyricsSelectorOpenLocal => '打开本地歌词';

  @override
  String get searchLyricsSelectorSelect => '选定歌词';

  @override
  String get searchLyricsSelectorDescription => '为桌面歌词选择云端或本地歌词';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return '打开本地歌词失败：$detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => '请先选择歌词';

  @override
  String get searchLyricsSelectorSelectFailed => '选定歌词失败，请稍后重试';

  @override
  String get searchDropUnsupportedItem => '搜索页只接受可解析歌曲条目或音频文件拖入';

  @override
  String get searchNoticePartialSourcesFailed => '部分来源搜索失败，已显示其他来源结果';

  @override
  String get searchNoticeAllSourcesFailed => '所有来源搜索失败';

  @override
  String get searchNoticeLoadMoreFailed => '部分来源加载更多失败';

  @override
  String get searchNoticeDirectoryPickerUnsupported => '当前平台不支持选择目录';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return '已自动获取 $detail 的歌词';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return '自动获取歌词失败：$detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable => '未选择可用歌曲文件';

  @override
  String get searchNoticeFilePickerUnsupported => '当前平台不支持选择歌曲文件';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return '打开歌曲失败：$detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable => '拖入的歌曲文件不可用';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖入歌曲失败：$detail';
  }

  @override
  String get searchNoticeEmptyKeyword => '请输入搜索关键词';

  @override
  String get searchNoticeGetLyricsFirst => '请先获取歌词';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return '歌词保存成功：$detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported => '当前平台不支持保存文件';

  @override
  String get searchNoticeFilePickerForTagUnsupported => '当前平台不支持选择歌曲标签文件';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return '选择文件失败：$detail';
  }

  @override
  String get searchNoticeBatchCancelling => '正在取消批量保存...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst => '请先选择专辑或歌单';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage => '请至少选择一种歌词语言';

  @override
  String get searchNoticeNoSongsToSave => '没有可保存的歌曲';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return '批量保存已取消：成功$saved，失败$failed，跳过$skipped';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return '批量保存完成：成功$saved，失败$failed，跳过$skipped';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return '批量保存失败：$detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates => '发现多个候选歌词，请选择一个继续';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return '获取歌词失败：$detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => '请先选择保存路径';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return '选择目录失败：$detail';
  }

  @override
  String get searchNoticePreviewLoading => '歌词仍在加载中';

  @override
  String get searchNoticePreviewNoLanguage => '请至少选择一种歌词语言';

  @override
  String get searchNoticePreviewNoContent => '当前歌词暂无可预览内容';

  @override
  String get searchNoticePreviewNoSelection => '请先下载并预览歌词';

  @override
  String get desktopWindowActionSelectLyrics => '选择歌词';

  @override
  String get desktopWindowActionMarkInstrumental => '标记为纯音乐';

  @override
  String get desktopWindowActionDisableAutoSearch => '禁用自动搜索(仅本曲)';

  @override
  String get desktopWindowActionUnlinkLyrics => '取消歌词关联';

  @override
  String get desktopWindowActionAssociationManager => '歌词关联管理器';

  @override
  String get desktopWindowActionToggleFloating => '显示/隐藏桌面歌词';

  @override
  String get desktopWindowActionShowMainWindow => '显示主窗口';

  @override
  String get desktopWindowActionClickThrough => '鼠标穿透';

  @override
  String get desktopWindowActionPrevious => '上一首';

  @override
  String get desktopWindowActionPlay => '播放';

  @override
  String get desktopWindowActionPause => '暂停';

  @override
  String get desktopWindowActionNext => '下一首';

  @override
  String get desktopWindowActionHide => '隐藏';

  @override
  String get desktopTrayCurrentTarget => '当前目标：';

  @override
  String get desktopTrayNoSelection => '未选择';

  @override
  String get desktopTrayTargetInstance => '目标实例';

  @override
  String get desktopTrayInstance => '实例';

  @override
  String get desktopTrayExit => '退出';

  @override
  String get desktopWindowInfoInstrumental => '纯音乐';

  @override
  String get desktopWindowControlConnectionLost => '播放器连接已断开，操作未执行';

  @override
  String get desktopWindowClientDisconnected => '播放器连接已断开，桌面歌词已关闭';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => '警告';

  @override
  String get commonError => '錯誤';

  @override
  String get commonSuccess => '成功';

  @override
  String get commonFailed => '失敗';

  @override
  String get commonSkipped => '跳過';

  @override
  String get commonTotal => '總數';

  @override
  String get commonDelete => '刪除';

  @override
  String get commonConfirm => '確認';

  @override
  String get commonRestoreDefault => '恢復預設';

  @override
  String get commonEnabled => '已啟用';

  @override
  String get commonDisabledByDefault => '預設關閉';

  @override
  String get commonFormat => '格式';

  @override
  String get commonOffset => '偏移';

  @override
  String get commonSaving => '儲存中...';

  @override
  String get commonAddFiles => '新增檔案';

  @override
  String get commonClearQueue => '清空佇列';

  @override
  String get commonUnsupportedOperation => '當前平臺不支援此操作';

  @override
  String get commonLyricsFileUnavailable => '當前條目還沒有可開啟的歌詞檔案';

  @override
  String get commonAudioTagRequiresLrc => '歌曲標籤中的歌詞應為 LRC 格式';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language（$type）';
  }

  @override
  String get commonTranslationCancelled => '已取消翻譯';

  @override
  String get commonCancelTranslation => '取消翻譯';

  @override
  String get commonTranslating => '翻譯中...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return '翻譯中 $completed/$total';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI 流式翻譯中：$completed / $total 行';
  }

  @override
  String get commonTranslationCompleted => '翻譯完成';

  @override
  String get commonLyricsSaved => '歌詞儲存成功';

  @override
  String commonDropFailed(String detail) {
    return '拖拽處理失敗：$detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return '選擇儲存目錄失敗：$detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return '開啟儲存目錄失敗：$detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return '翻譯失敗：$detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return '歌詞儲存失敗：$detail';
  }

  @override
  String get appErrorUnknown => '發生未知錯誤。';

  @override
  String get appErrorOperationTimeout => '操作超時，請稍後重試。';

  @override
  String get appErrorNetworkUnavailable => '網路不可用，請檢查連線。';

  @override
  String get appErrorInvalidPayload => '資料格式錯誤。';

  @override
  String get appErrorUnsupportedOperation => '當前操作不受支援。';

  @override
  String get appErrorPermissionDenied => '沒有執行此操作的許可權。';

  @override
  String get appErrorIoFailure => '檔案讀寫失敗。';

  @override
  String get appErrorLyricsRequestFailed => '請求歌詞失敗。';

  @override
  String get appErrorLyricsNotFound => '沒有找到歌詞。';

  @override
  String get appErrorLyricsProcessing => '歌詞處理失敗。';

  @override
  String get appErrorLyricsDecrypt => '歌詞解密失敗。';

  @override
  String get appErrorLyricsFormatUnsupported => '不支援的歌詞格式。';

  @override
  String get appErrorDecoding => '解碼失敗。';

  @override
  String get appErrorSongInfoRead => '獲取歌曲資訊失敗。';

  @override
  String get appErrorUnsupportedFileType => '不支援的檔案格式。';

  @override
  String get appErrorDragDropInvalid => '拖拽資料無效。';

  @override
  String get appErrorTranslateFailed => '翻譯失敗。';

  @override
  String get appErrorApiParamsInvalid => '請求引數不正確。';

  @override
  String get appErrorApiRequestFailed => '介面請求失敗。';

  @override
  String get appErrorAutoFetchUnknown => '自動匹配發生未知錯誤。';

  @override
  String get appErrorNotEnoughInfo => '搜尋資訊不足。';

  @override
  String get appErrorIpcInvalidLength => 'IPC 訊息長度無效。';

  @override
  String get appErrorIpcUnsupportedTask => 'IPC 任務不受支援。';

  @override
  String get appErrorIpcInstanceNotFound => 'IPC 例項不存在。';

  @override
  String get appErrorIpcPanelNotFound => 'IPC 面板不存在。';

  @override
  String get appErrorIpcInvalidWindowId => '視窗控制代碼無效。';

  @override
  String get appErrorIpcEmbedUnsupported => '當前平臺不支援嵌入模式。';

  @override
  String get appErrorActionRetryNetwork => '請檢查網路後重試。';

  @override
  String get appErrorActionCheckPayload => '請檢查輸入資料格式。';

  @override
  String get appErrorActionChangeFormat => '請更換支援的檔案或格式。';

  @override
  String get appErrorActionDetachedMode => '請回退到 detached 模式。';

  @override
  String get actionRetry => '重試';

  @override
  String get actionViewDetails => '檢視詳情';

  @override
  String get actionCancel => '取消';

  @override
  String get sourceAggregate => '聚合';

  @override
  String get sourceQQMusic => 'QQ音樂';

  @override
  String get sourceKugou => '酷狗音樂';

  @override
  String get sourceNetease => '網易雲音樂';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => '本地';

  @override
  String get lyricOriginal => '原文';

  @override
  String get lyricTranslation => '譯文';

  @override
  String get lyricRomanized => '羅馬音';

  @override
  String get lyricsFormatVerbatimLrc => 'LRC（逐字）';

  @override
  String get lyricsFormatLineByLineLrc => 'LRC（逐行）';

  @override
  String get lyricsFormatEnhancedLrc => '增強型 LRC（ESLyric）';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => 'ASS';

  @override
  String get lyricsTypeVerbatim => '逐字';

  @override
  String get lyricsTypeLineByLine => '逐行';

  @override
  String get lyricsTypePlainText => '純文本';

  @override
  String get searchSong => '單曲';

  @override
  String get searchAlbum => '專輯';

  @override
  String get searchSongList => '歌單';

  @override
  String get searchArtist => '歌手';

  @override
  String get searchLyrics => '歌詞';

  @override
  String get searchSongId => '歌曲id';

  @override
  String get localMatchIteratingFiles => '遍歷檔案...';

  @override
  String get localMatchProgressImportCompleted => '匯入完成';

  @override
  String get localMatchProgressScanCompleted => '掃描完成';

  @override
  String get localMatchProgressScanFailed => '掃描失敗';

  @override
  String get localMatchProgressMatchCompleted => '匹配完成';

  @override
  String get localMatchProgressMatchFailed => '匹配失敗';

  @override
  String get localMatchProgressPreparingMatch => '準備開始匹配...';

  @override
  String get localMatchPreviewTagOnly => '僅寫入標籤';

  @override
  String get localMatchPreviewWriteTag => '儲存到標籤';

  @override
  String get localMatchPreviewNoOutput => '未配置輸出';

  @override
  String get localMatchPreviewSongTagOnly => '僅寫入歌曲標籤';

  @override
  String get localMatchPendingLyricsFileName => '等待歌詞資訊後確定檔名';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / 等待歌詞資訊後確定檔名';
  }

  @override
  String get localMatchCalcSavePathFailed => '計算歌詞儲存路徑失敗';

  @override
  String get localMatchNoticeBusyImportFiles => '當前任務執行中，無法繼續匯入檔案';

  @override
  String get localMatchNoticeSelectedFilesUnavailable => '所選檔案不可訪問';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return '匯入檔案失敗：$detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories => '當前任務執行中，無法繼續匯入目錄';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return '匯入目錄失敗：$detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles => '拖拽資料中沒有可訪問的檔案';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖拽歌曲失敗：$detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors => '匯入完成，但有部分條目解析失敗';

  @override
  String get localMatchNoticeSafTreeUnsupported => '當前平臺不支援目錄樹授權';

  @override
  String get localMatchNoticeBusySwitchTree => '當前任務執行中，無法切換目錄樹';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return '選擇目錄樹失敗：$detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue => '當前任務執行中，無法清空佇列';

  @override
  String get localMatchNoticeSelectItemsToDelete => '請先選擇要刪除的條目';

  @override
  String get localMatchNoticeSelectItemsToSetRoot => '請先選擇要設定根目錄的條目';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return '以下歌曲不在所選根目錄中，已跳過：$detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return '設定根目錄失敗：$detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore => '請先選擇要恢復的條目';

  @override
  String get localMatchNoticeCancelling => '正在取消當前任務...';

  @override
  String get localMatchNoticeValidationFailed => '請先處理本地匹配啟動條件';

  @override
  String get localMatchNoticeSongDirectoryUnavailable => '當前條目不支援開啟歌曲目錄';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return '開啟歌曲目錄失敗：$detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable => '當前條目還沒有可開啟的儲存目錄';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return '開啟歌詞失敗：$detail';
  }

  @override
  String get localMatchNoticeScanCancelled => '掃描已取消';

  @override
  String get localMatchNoticeScanCompletedWithErrors => '掃描完成，但有部分檔案解析失敗';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return '掃描失敗：$detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return '目錄樹掃描失敗：$detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => '匹配已取消';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '總共$total首歌曲，匹配成功$success首，匹配失敗$failed首，跳過$skipped首。';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return '本地匹配執行失敗：$detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume => '匹配已取消，可再次開始從斷點繼續';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF 本地匹配執行失敗：$detail';
  }

  @override
  String get localMatchValidationEmptyLangs => '請選擇要匹配的語言';

  @override
  String get localMatchValidationEmptySources => '請選擇至少一個源';

  @override
  String get localMatchValidationEmptyQueue => '請先匯入要匹配的歌曲';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      '跳過已有歌詞時，如果還需要儲存檔案，則檔名模式不能為按歌詞資訊命名';

  @override
  String get localMatchValidationMissingAndroidTree => '請先選擇目錄樹';

  @override
  String get localMatchValidationNeedsSaveRoot => '需要指定儲存路徑';

  @override
  String get localMatchValidationNeedsSongRoot => '需要指定歌曲根目錄';

  @override
  String get localMatchValidationUnknownSavePath => '未知儲存路徑錯誤';

  @override
  String get localMatchIntro => '匯入本地歌曲或目錄，預估輸出結果後執行批次匹配。';

  @override
  String get localMatchDropUnsupportedItem => '本地匹配頁只接受歌曲檔案、目錄或可解析播放器條目拖入';

  @override
  String get localMatchReadyToStart => '準備開始本地匹配';

  @override
  String get localMatchQueueTitle => '任務佇列';

  @override
  String get localMatchQueueEmptyHint => '先匯入檔案或資料夾以建立任務佇列';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '共 $count 條任務，右鍵行可執行更多操作';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '共 $count 條任務，長按或點選更多按鈕可開啟操作選單';
  }

  @override
  String get localMatchImportAndRunTitle => '匯入與執行';

  @override
  String get localMatchActionStart => '開始匹配';

  @override
  String get localMatchActionAddFolders => '新增資料夾';

  @override
  String get localMatchActionSelectSaveRoot => '選擇儲存根目錄';

  @override
  String get localMatchActionSelectTree => '選擇目錄樹';

  @override
  String get localMatchActionReselectTree => '重新選擇目錄樹';

  @override
  String get localMatchActionBulkSelect => '批次選擇';

  @override
  String get localMatchActionExitSelection => '退出批次選擇';

  @override
  String get localMatchActionSelectAll => '全選';

  @override
  String get localMatchActionDeselectAll => '取消全選';

  @override
  String get localMatchActionSetRoot => '設定根目錄';

  @override
  String localMatchSelectedCount(int count) {
    return '已選 $count 項';
  }

  @override
  String get localMatchBulkActionHint => '批次操作會直接作用於當前選中的任務';

  @override
  String get localMatchPhaseIdle => '等待開始';

  @override
  String get localMatchPhaseScanning => '掃描中';

  @override
  String get localMatchPhaseMatching => '匹配中';

  @override
  String get localMatchPhaseWriting => '寫回中';

  @override
  String get localMatchPhaseCompleted => '已完成';

  @override
  String get localMatchPhaseHintIdle => '匯入歌曲後即可開始匹配';

  @override
  String get localMatchPhaseHintScanning => '正在建立任務佇列與預估輸出';

  @override
  String get localMatchPhaseHintMatching => '正在請求來源並計算最佳匹配';

  @override
  String get localMatchPhaseHintWriting => '正在寫入歌詞檔案或歌曲標籤';

  @override
  String get localMatchPhaseHintCompleted => '本輪任務已完成，可繼續調整後重跑';

  @override
  String get localMatchPipelineIdle => '掃描 -> 匹配 -> 寫回';

  @override
  String get localMatchPipelineScanning => '當前階段：掃描';

  @override
  String get localMatchPipelineMatching => '當前階段：匹配';

  @override
  String get localMatchPipelineWriting => '當前階段：寫回';

  @override
  String get localMatchPipelineCompleted => '已完成本輪掃描、匹配與寫回';

  @override
  String get localMatchUnknownSong => '未知歌曲';

  @override
  String get localMatchUnknownDuration => '未知時長';

  @override
  String get localMatchStatusNotStarted => '未開始';

  @override
  String get localMatchSongPathLabel => '歌曲路徑';

  @override
  String get localMatchLyricsPathLabel => '歌詞儲存路徑';

  @override
  String get localMatchExpandDetails => '展開詳情';

  @override
  String get localMatchCollapseDetails => '收起詳情';

  @override
  String get localMatchRowActionOpenInSearch => '在搜尋中開啟';

  @override
  String get localMatchRowActionEnterSelection => '進入批次選擇';

  @override
  String get localMatchRowActionOpenSongDirectory => '開啟歌曲目錄';

  @override
  String get localMatchRowActionOpenSaveDirectory => '開啟儲存目錄';

  @override
  String get localMatchRowActionOpenLyrics => '開啟歌詞';

  @override
  String get localMatchFieldLyricsType => '歌詞型別';

  @override
  String get localMatchFieldOutputStrategy => '輸出策略';

  @override
  String get localMatchFieldSaveMode => '儲存模式';

  @override
  String get localMatchFieldFileNameMode => '檔名模式';

  @override
  String get localMatchFieldLyricsFormat => '歌詞格式';

  @override
  String get localMatchFieldThreshold => '匹配門檻';

  @override
  String get localMatchFieldSaveRoot => '儲存根目錄';

  @override
  String get localMatchMoreSettings => '更多設定';

  @override
  String get localMatchRulesTitle => '匹配規則';

  @override
  String get localMatchRulesSubtitle => '來源、語言、輸出策略與匹配門檻';

  @override
  String get localMatchMinScore => '最低匹配度';

  @override
  String get localMatchSkipExisting => '跳過已有歌詞';

  @override
  String get localMatchSkipExistingConflictHint =>
      '當前“輸出策略 + 檔名模式”組合不支援開啟跳過已有歌詞；若還需要儲存檔案，請避免選擇“按歌詞資訊命名”。';

  @override
  String get localMatchSaveToSongDirectoryHint => '當前儲存到歌曲目錄，無需額外儲存根目錄。';

  @override
  String get localMatchAndroidTreeSaveHint => 'Android 目錄樹檔案儲存會直接寫入已授權目錄樹。';

  @override
  String get localMatchFileNameTemplateHint =>
      '命名模板沿用設定頁中的 lyrics_file_name_fmt。';

  @override
  String localMatchSaveRootPath(String path) {
    return '儲存根目錄：$path';
  }

  @override
  String get localMatchSaveRootRequired => '當前儲存模式需要儲存根目錄，請先選擇。';

  @override
  String get localMatchTreeNotSelected => '尚未選擇目錄樹';

  @override
  String get localMatchSaveModeSong => '儲存到歌曲目錄';

  @override
  String get localMatchSaveModeMirror => '映象目錄';

  @override
  String get localMatchSaveModeSpecify => '指定目錄';

  @override
  String get localMatchFileNameModeSong => '按歌曲檔名';

  @override
  String get localMatchFileNameModeFormatBySong => '按歌曲資訊命名';

  @override
  String get localMatchFileNameModeFormatByLyrics => '按歌詞資訊命名';

  @override
  String get localMatchFileNameHintSong => '沿用音訊檔名，僅替換歌詞副檔名。';

  @override
  String get localMatchFileNameHintFormatBySong => '使用標題、藝術家、專輯等歌曲後設資料生成檔名。';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      '使用匹配到的歌詞歌曲資訊生成檔名；未匹配前可能無法確定。';

  @override
  String get localMatchSaveToTagOnlyFile => '僅儲存檔案';

  @override
  String get localMatchSaveToTagOnlyTag => '僅寫入標籤';

  @override
  String get localMatchSaveToTagBoth => '檔案 + 標籤';

  @override
  String get localMatchValidationTitle => '開始前需要處理的問題';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '還有 $count 個問題需要先處理';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable => '所選檔案當前不可直接訪問';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return '已匯入 $count 個歌詞檔案';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles => '拖拽資料中沒有可訪問的歌詞檔案';

  @override
  String get batchConvertNoticeEmptyQueue => '請先新增要轉換的歌詞檔案';

  @override
  String get batchConvertNoticeOverwriteCancelled => '已取消批次轉換';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return '批次轉換已取消，已完成 $count 項';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return '批次轉換完成：成功 $success，失敗 $failure';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return '批次轉換完成：共 $count 項';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return '批次轉換失敗：$detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return '開啟原目錄失敗：$detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return '開啟歌詞檔案失敗：$detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles => '所選資料夾中沒有找到支援的歌詞檔案';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return '已從資料夾匯入 $count 個歌詞檔案';
  }

  @override
  String get batchConvertNoticeDuplicateItems => '所選條目都已在佇列中';

  @override
  String get batchConvertControlsTitle => '匯入與設定';

  @override
  String get batchConvertCompactControlsTitle => '匯入與輸出設定';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return '格式：$format';
  }

  @override
  String get batchConvertImportTitle => '匯入';

  @override
  String get batchConvertAddFolders => '新增資料夾';

  @override
  String get batchConvertOutputSettingsTitle => '輸出設定';

  @override
  String get batchConvertTargetFormat => '目標格式';

  @override
  String get batchConvertSaveDirectoryTitle => '儲存目錄';

  @override
  String get batchConvertSaveDirectoryDefault => '未設定時預設輸出到原歌詞所在目錄';

  @override
  String get batchConvertSelectSaveDirectory => '選擇儲存目錄';

  @override
  String get batchConvertRestoreOriginalDirectory => '恢復原目錄';

  @override
  String get batchConvertRecursiveTitle => '遍歷子資料夾';

  @override
  String get batchConvertRecursiveSubtitle => '目錄匯入時繼續掃描子目錄中的歌詞檔案';

  @override
  String get batchConvertStart => '開始轉換';

  @override
  String get batchConvertCancel => '取消轉換';

  @override
  String get batchConvertQueueTitle => '轉換佇列';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '共 $count 項，輸出格式為 $format';
  }

  @override
  String get batchConvertPageErrorFallback => '批次轉換頁面出現錯誤';

  @override
  String get batchConvertRetryImport => '重新匯入';

  @override
  String get batchConvertEmptyQueue => '新增歌詞檔案或資料夾後，這裡會顯示批次轉換佇列。';

  @override
  String get batchConvertOutputPathLabel => '輸出路徑';

  @override
  String get batchConvertQueueStatusWaiting => '等待轉換';

  @override
  String get batchConvertQueueStatusRunning => '正在轉換';

  @override
  String get batchConvertQueueStatusSuccess => '轉換成功';

  @override
  String get batchConvertQueueStatusFailure => '轉換失敗';

  @override
  String get batchConvertMoreActions => '更多操作';

  @override
  String get batchConvertActionOpenSourceDirectory => '開啟原歌詞目錄';

  @override
  String get batchConvertActionOpenSaveDirectory => '開啟儲存目錄';

  @override
  String get batchConvertActionOpenOutputFile => '開啟歌詞檔案';

  @override
  String get batchConvertActionOpenInOpenLyrics => '在開啟歌詞頁中開啟';

  @override
  String get batchConvertPhaseIdle => '等待開始';

  @override
  String get batchConvertPhaseScanning => '正在掃描';

  @override
  String get batchConvertPhaseRunning => '正在轉換';

  @override
  String get batchConvertPhaseCompleted => '已完成';

  @override
  String get batchConvertPipelineIdle => '匯入 -> 掃描 -> 轉換 -> 完成';

  @override
  String get batchConvertPipelineScanning => '掃描目錄 -> 建立佇列';

  @override
  String get batchConvertPipelineRunning => '逐條轉換 -> 持續更新狀態';

  @override
  String get batchConvertPipelineCompleted => '可繼續調整格式或重新匯入';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return '已取消，成功 $success，失敗 $failure';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '成功 $success，失敗 $failure';
  }

  @override
  String get batchConvertHintNoQueue => '新增檔案或資料夾後開始轉換';

  @override
  String get batchConvertHintReady => '當前佇列已就緒';

  @override
  String get batchConvertMetricWaiting => '待處理';

  @override
  String get batchConvertDropUnsupported => '批次轉換頁只接受歌詞檔案或目錄拖入';

  @override
  String batchConvertDropFailed(String detail) {
    return '拖拽處理失敗：$detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return '正在轉換 $fileName';
  }

  @override
  String get batchConvertProgressItemSuccess => '轉換成功';

  @override
  String get batchConvertProgressItemFailure => '轉換失敗';

  @override
  String get batchConvertProgressPreparingConversion => '準備開始轉換...';

  @override
  String get batchConvertProgressCancellingConversion => '正在取消轉換...';

  @override
  String get batchConvertProgressConversionCancelled => '轉換已取消';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return '轉換完成：成功 $success，失敗 $failure';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return '轉換失敗：$detail';
  }

  @override
  String get batchConvertProgressScanningFolders => '正在遍歷資料夾...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return '正在掃描 $directoryName';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return '已掃描到 $count 個歌詞檔案';
  }

  @override
  String get batchConvertProgressScanCancelled => '掃描已取消';

  @override
  String get batchConvertProgressScanNoSupportedFiles => '未找到支援的歌詞檔案';

  @override
  String get batchConvertProgressScanCompleted => '掃描完成';

  @override
  String get navSearch => '搜尋';

  @override
  String get navLocalMatch => '本地匹配';

  @override
  String get navOpenLyrics => '開啟歌詞';

  @override
  String get navBatchConvert => '批次轉換';

  @override
  String get navSettings => '設定';

  @override
  String get navAbout => '關於';

  @override
  String get commonSearch => '搜尋';

  @override
  String get commonSource => '來源';

  @override
  String get searchKeywordHint => '輸入關鍵詞';

  @override
  String get uiLoading => '載入中...';

  @override
  String get uiLoadingStepFetching => '正在獲取列表與預覽...';

  @override
  String get uiEmpty => '暫無資料';

  @override
  String get uiNoMoreResult => '沒有更多結果';

  @override
  String get searchInitialResultTitle => '輸入關鍵詞開始搜尋';

  @override
  String get searchInitialResultDescription => '在上方選擇來源併發起搜尋';

  @override
  String get searchResultTitle => '搜尋結果';

  @override
  String get searchResultReturn => '返回上一層';

  @override
  String get searchPreviewTitle => '歌詞預覽';

  @override
  String get searchPreviewLangsLabel => '歌詞語言';

  @override
  String get searchPreviewSongIdLabel => '歌曲ID';

  @override
  String get searchPreviewPlaceholder => '請先選擇歌曲或歌詞條目';

  @override
  String get searchPreviewNoLanguage => '請至少選擇一種歌詞語言';

  @override
  String get searchPreviewNoContent => '當前歌詞暫無可預覽內容';

  @override
  String get searchPreviewLoading => '正在載入歌詞...';

  @override
  String get searchFormatLabel => '歌詞格式';

  @override
  String get searchTranslateLyrics => '翻譯歌詞';

  @override
  String get searchResizeWorkspacePanes => '調整搜尋結果與歌詞預覽寬度';

  @override
  String get searchSavePreviewToDirectory => '儲存到資料夾';

  @override
  String get searchSavePreviewToFile => '儲存到檔案';

  @override
  String get searchSavePreviewToTag => '儲存到歌曲標籤';

  @override
  String get searchSaveListLyrics => '儲存專輯/歌單的歌詞';

  @override
  String get searchSaveListLyricsCancel => '取消批次儲存';

  @override
  String get searchSelectSavePath => '選擇儲存路徑';

  @override
  String get searchBatchSaveProgressTitle => '批次儲存進度';

  @override
  String get searchBatchSaveProgressPreparing => '準備批次儲存...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return '正在獲取 $songName 的歌詞...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count 首';
  }

  @override
  String get searchTableStatusAutoFetching => '正在自動獲取...';

  @override
  String get searchTableStatusSearching => '正在搜尋...';

  @override
  String get searchTableStatusFetchingSongList => '正在獲取歌曲列表...';

  @override
  String get searchTableStatusNoResults => '沒有搜尋到相關結果';

  @override
  String get searchTableStatusEmptyList => '列表為空';

  @override
  String get searchTableStatusUnsupportedSearchType => '所選來源不支援當前搜尋型別';

  @override
  String get searchTableStatusSearchFailed => '搜尋失敗';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return '搜尋失敗：$detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return '自動獲取歌詞失敗：$detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return '獲取歌曲列表失敗：$detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable => '部分來源不可用，已展示可用結果';

  @override
  String get searchTableStatusLoadMoreFailed => '部分來源載入更多失敗';

  @override
  String get searchSourceFailureDetailsTitle => '搜尋錯誤詳情';

  @override
  String get searchSourceFailureRequest => '請求失敗';

  @override
  String get searchSourceFailureTimeout => '請求超時';

  @override
  String get searchSourceFailureParameters => '引數錯誤';

  @override
  String get searchSourceFailureUnsupported => '不支援的操作';

  @override
  String get searchSourceFailureUnknown => '未知錯誤';

  @override
  String get searchResultLoadingMore => '正在繼續載入更多結果...';

  @override
  String get searchResultLoadMoreFailed => '自動續取失敗，可重試繼續載入剩餘結果';

  @override
  String get searchResultScrollForMore => '繼續向下滾動以自動載入更多結果';

  @override
  String get tableSavePath => '儲存路徑';

  @override
  String get settingsSectionSave => '儲存';

  @override
  String get settingsSectionLyrics => '歌詞';

  @override
  String get settingsSectionDesktopLyrics => '桌面歌詞';

  @override
  String get settingsSectionTranslate => '翻譯';

  @override
  String get settingsSectionSearch => '搜尋';

  @override
  String get settingsSectionApp => '應用';

  @override
  String get settingsSectionTools => '工具與資料';

  @override
  String get settingsSectionSaveSummary => '儲存路徑、檔名模板與 ID3 版本';

  @override
  String get settingsSectionSearchSummary => '決定“聚合”搜尋和本地匹配預設使用的歌詞來源。';

  @override
  String get settingsSectionDesktopLyricsSummary => '桌面歌詞自動獲取、顯示語言、外觀與重新整理率。';

  @override
  String get settingsSectionLyricsSummary => '本地匹配策略與歌詞檔案匯出格式。';

  @override
  String get settingsSectionTranslateSummary => '翻譯源、目標語言與條件欄位';

  @override
  String get settingsSectionAppSummary => '語言、主題、日誌與更新策略';

  @override
  String get settingsSectionToolsSummary => '桌面工具入口、日誌目錄與快取清理';

  @override
  String get settingsTranslateSourceBing => '必應翻譯';

  @override
  String get settingsTranslateSourceGoogle => '谷歌翻譯';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI相容API';

  @override
  String get settingsLangSimplifiedChinese => '簡體中文';

  @override
  String get settingsLangTraditionalChinese => '繁體中文';

  @override
  String get settingsLangEnglish => '英語';

  @override
  String get settingsLangJapanese => '日語';

  @override
  String get settingsLangKorean => '韓語';

  @override
  String get settingsLangSpanish => '西班牙語';

  @override
  String get settingsLangFrench => '法語';

  @override
  String get settingsLangPortuguese => '葡萄牙語';

  @override
  String get settingsLangGerman => '德語';

  @override
  String get settingsLangRussian => '俄語';

  @override
  String get settingsAppLanguageAuto => '自動';

  @override
  String get settingsColorSchemeAuto => '跟隨系統';

  @override
  String get settingsColorSchemeLight => '淺色';

  @override
  String get settingsColorSchemeDark => '深色';

  @override
  String get settingsDesktopGradientColors => '漸變顏色';

  @override
  String get settingsDesktopPlayedColors => '已播放顏色';

  @override
  String get settingsDesktopUnplayedColors => '未播放顏色';

  @override
  String get settingsAddColor => '新增顏色';

  @override
  String get settingsEditColor => '編輯顏色';

  @override
  String get settingsDeleteColor => '刪除顏色';

  @override
  String get settingsBackToSections => '返回設定分組';

  @override
  String get settingsAvailablePlaceholders => '可用佔位符';

  @override
  String get settingsPlaceholderTitleArtist => '歌名：%<title>    藝術家：%<artist>';

  @override
  String get settingsPlaceholderAlbumId => '專輯名：%<album>    歌曲/歌詞 id：%<id>';

  @override
  String get settingsPlaceholderLangs => '語言型別：%<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return '當前模板：$template';
  }

  @override
  String get settingsTranslateSourceLabel => '翻譯源';

  @override
  String get settingsTranslateTargetLabel => '目標語言';

  @override
  String get settingsOpenAiProfileLabel => '預設';

  @override
  String get settingsOpenAiProfileHelper =>
      '選擇內建服務商會自動填入 Base URL，API Key 和模型仍需配置。';

  @override
  String get settingsAppLanguageLabel => '介面語言';

  @override
  String get settingsColorSchemeLabel => '主題模式';

  @override
  String get settingsLogLevelLabel => '日誌級別';

  @override
  String get settingsLogLevelHelper => '通常保持 INFO；TRACE 和 DEBUG 會記錄更多內容並增大日誌。';

  @override
  String get settingsAutoCheckUpdateLabel => '自動檢查更新';

  @override
  String get settingsRestoreDefaultsWarning => '恢復預設值會立即寫入配置，請確認後執行。';

  @override
  String get settingsRestoreAllTitle => '恢復預設設定';

  @override
  String get settingsRestoreAllContent => '該操作會恢復所有設定項，並立即寫入配置。';

  @override
  String get settingsRestoreAllAction => '恢復預設設定';

  @override
  String get settingsOpenAssociationManager => '開啟歌詞關聯管理器';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      '進入設定下一級頁面，統一管理歌曲與歌詞關聯記錄。';

  @override
  String get settingsOpenLogDirectory => '開啟日誌目錄';

  @override
  String get settingsOpenLogDirectorySubtitle => '檢視執行日誌與問題排查檔案。';

  @override
  String get settingsClearCache => '清理快取';

  @override
  String get settingsClearCacheSubtitle => '清理搜尋與翻譯快取，不影響配置檔案。';

  @override
  String get settingsClearCacheContent => '快取清理後，後續搜尋與翻譯可能需要重新請求。';

  @override
  String get settingsRestoreSectionTitle => '恢復本組預設值';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return '僅恢復“$sectionTitle”分組中的設定項，其他分組不會被修改。';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return '恢復$sectionTitle分組預設值';
  }

  @override
  String get settingsDefaultSavePathHelper => '留空時使用平臺預設音樂目錄。';

  @override
  String get settingsChooseFolder => '選擇資料夾';

  @override
  String get settingsLyricsFileNameFormat => '歌詞檔名模板';

  @override
  String get settingsLyricsFileNameFormatHelper => '可使用下方佔位符組合生成儲存檔名。';

  @override
  String get settingsId3Version => 'ID3 版本';

  @override
  String get settingsId3VersionHelper => '僅影響把歌詞寫入音訊標籤；不確定時保持 v2.3。';

  @override
  String get settingsSearchSourcesTitle => '聚合搜尋來源';

  @override
  String get settingsSearchSourcesDescription =>
      '搜尋頁選擇“聚合”時查詢已勾選來源；越靠上，結果排列和自動匹配優先順序越高。本地匹配預設沿用此列表。';

  @override
  String get settingsReorderPriorityHint => '拖動調整優先順序';

  @override
  String get settingsReorderOrderHint => '拖動調整順序';

  @override
  String get settingsDefaultLanguage => '預設顯示語言';

  @override
  String get settingsDefaultLanguageDescription =>
      '勾選桌面歌詞預設顯示的語言，拖動調整多語言歌詞的排列順序。';

  @override
  String get settingsDesktopAutoFetchSources => '自動獲取來源';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      '桌面歌詞沒有關聯歌詞時，按從上到下的優先順序自動獲取。';

  @override
  String get settingsFont => '字型';

  @override
  String get settingsFollowSystemFont => '跟隨系統字型';

  @override
  String get settingsFontSizeByResize => '桌面歌詞主視窗字號通過拖拽視窗大小調整。';

  @override
  String get settingsPanelFontSize => '歌詞面板字號';

  @override
  String get settingsAdaptiveRefreshRate => '自適應重新整理率';

  @override
  String get settingsAdaptiveRefreshRateSubtitle => '開啟後根據歌詞動畫狀態自動選擇重新整理節奏。';

  @override
  String get settingsFixedRefreshRate => '固定重新整理率';

  @override
  String get settingsShowFurigana => '顯示注音';

  @override
  String get settingsLyricsMatchBehavior => '匹配行為';

  @override
  String get settingsLyricsMatchBehaviorDescription => '控制本地匹配和酷狗歌詞候選的預設處理方式。';

  @override
  String get settingsLyricsExport => 'LRC 匯出';

  @override
  String get settingsLyricsExportDescription => '控制儲存歌詞檔案時使用的語言順序和 LRC 時間戳格式。';

  @override
  String get settingsDisplayOrder => '匯出語言順序';

  @override
  String get settingsDisplayOrderDescription => '拖動調整原文、譯文和羅馬音在歌詞檔案中的順序。';

  @override
  String get settingsSkipInstrumental => '跳過純音樂';

  @override
  String get settingsSkipInstrumentalSubtitle => '本地匹配識別為純音樂時不儲存歌詞。';

  @override
  String get settingsAutoSelectKugou => '自動選擇酷狗候選';

  @override
  String get settingsAutoSelectKugouSubtitle => '搜尋頁開啟酷狗歌曲時自動選擇最佳歌詞候選。';

  @override
  String get settingsAddLrcEndTimestamp => '匯出 LRC 時新增結尾時間戳';

  @override
  String get settingsAddLrcEndTimestampSubtitle => '僅影響逐行 LRC，在需要時寫入行結束時間戳。';

  @override
  String get settingsMillisecondsDigits => '毫秒位數';

  @override
  String get settingsMillisecondsDigitsHelper => '兩位使用百分之一秒，三位保留完整毫秒。';

  @override
  String settingsDigitsValue(int value) {
    return '$value 位';
  }

  @override
  String get settingsLastRefStyle => '同句最後一行時間戳';

  @override
  String get settingsLastRefStyleHelper =>
      '決定多語言逐行 LRC 中同一句最後一種語言使用當前行時間，還是下一行前 1 毫秒。';

  @override
  String get settingsLastRefCurrentLine => '使用當前行時間';

  @override
  String get settingsLastRefNextLine => '使用下一行前一毫秒';

  @override
  String get settingsTagInfoSource => '標籤資訊來源';

  @override
  String get settingsTagInfoLyricsSource => '歌詞來源';

  @override
  String get settingsTagInfoSongInfo => '歌曲資訊';

  @override
  String get settingsNoticeDefaultSavePathUpdated => '預設儲存路徑已更新';

  @override
  String get settingsNoticeDefaultSavePathRestored => '預設儲存路徑已恢復';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated => '歌詞檔名模板已更新';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3 版本已更新';

  @override
  String get settingsNoticeLyricsLangOrderEmpty => '歌詞語言順序不能為空';

  @override
  String get settingsNoticeLyricsLangOrderUpdated => '歌詞語言順序已更新';

  @override
  String get settingsNoticeSkipInstUpdated => '純音樂跳過策略已更新';

  @override
  String get settingsNoticeAutoSelectUpdated => '自動選擇策略已更新';

  @override
  String get settingsNoticeAddEndTimestampUpdated => '結尾時間戳策略已更新';

  @override
  String get settingsNoticeMsDigitsUpdated => '毫秒位數已更新';

  @override
  String get settingsNoticeLastRefStyleUpdated => '尾行時間樣式已更新';

  @override
  String get settingsNoticeTagInfoSourceUpdated => '標籤來源已更新';

  @override
  String get settingsNoticeDesktopSourcesEmpty => '桌面歌詞來源不能為空';

  @override
  String get settingsNoticeDesktopSourcesUpdated => '桌面歌詞來源已更新';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty => '桌面預設語言不能為空';

  @override
  String get settingsNoticeDesktopLangsUpdated => '桌面歌詞語言設定已更新';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated => '桌面歌詞字型已更新';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => '重新整理率已更新';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated => '已播放顏色已更新';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated => '未播放顏色已更新';

  @override
  String get settingsNoticeDesktopFontSizeUpdated => '桌面歌詞字號已更新';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated => '桌面面板字號已更新';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated => '注音顯示策略已更新';

  @override
  String get settingsNoticeTranslateSourceUpdated => '翻譯源已更新';

  @override
  String get settingsNoticeTranslateTargetLangUpdated => '翻譯目標語言已更新';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI 預設已更新';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI Base URL 已更新';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI API Key 已更新';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI 模型已更新';

  @override
  String get settingsNoticeSearchSourcesEmpty => '聚合搜尋來源不能為空';

  @override
  String get settingsNoticeSearchSourcesUpdated => '聚合搜尋來源已更新';

  @override
  String get settingsNoticeAppLanguageUpdated => '介面語言已更新';

  @override
  String get settingsNoticeAppColorSchemeUpdated => '主題模式已更新';

  @override
  String get settingsNoticeAppLogLevelUpdated => '日誌級別已更新';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated => '自動檢查更新已更新';

  @override
  String get settingsNoticeSectionNoRestorableConfig => '當前分組沒有可恢復的配置項';

  @override
  String get settingsNoticeSectionDefaultsRestored => '當前分組已恢復預設值';

  @override
  String get settingsNoticeAllDefaultsRestored => '應用設定已恢復預設值';

  @override
  String get settingsNoticeAssociationManagerOpened => '已開啟歌詞關聯管理器';

  @override
  String get settingsNoticeLogDirectoryOpened => '日誌目錄已開啟';

  @override
  String get settingsNoticeLogDirectoryOpenFailed => '開啟日誌目錄失敗';

  @override
  String get settingsNoticeCacheCleared => '快取已清理';

  @override
  String get settingsNoticeCacheClearFailed => '清理快取失敗';

  @override
  String get settingsNoticeConfigWriteFailed => '設定寫入失敗';

  @override
  String get settingsCurrentSavePathLabel => '預設儲存路徑';

  @override
  String get aboutLoadFailed => '載入關於頁資訊失敗';

  @override
  String get aboutActionOpenRepository => 'GitHub倉庫';

  @override
  String get aboutActionCheckUpdate => '檢查更新';

  @override
  String get aboutHeroHeadline => '為精準歌詞而設計';

  @override
  String get aboutHeroDescription =>
      'LDDC 將搜尋、轉換、桌面歌詞與批處理工作流收口到同一套高效率體驗裡，讓精準歌詞獲取、整理與使用保持順滑。';

  @override
  String get aboutLinksSectionTitle => '常用連結';

  @override
  String get aboutLinksSectionDescription => '需要繼續瞭解專案時，可以從這裡檢視反饋、更新與許可證資訊。';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return 'Copyright (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return 'Licensed under $license.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub 倉庫';

  @override
  String get aboutLinkIssueTrackerTitle => '問題反饋';

  @override
  String get aboutLinkIssueTrackerDescription => '提交 Bug、互動建議和功能需求。';

  @override
  String get aboutLinkLicenseTitle => '許可證';

  @override
  String get aboutLinkLicenseDescription => '檢視專案當前採用的開源許可證：';

  @override
  String get aboutLinkChangelogTitle => '更新日誌';

  @override
  String get aboutLinkChangelogDescription => '瀏覽版本釋出記錄與變更摘要。';

  @override
  String get aboutExternalLinksUnavailable => '當前平臺暫不支援開啟外部連結。';

  @override
  String get aboutCheckUpdateUnavailable => '當前平臺暫不支援檢查更新。';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes => '已開啟更新日誌頁面。';

  @override
  String get aboutCheckUpdateUpToDate => '當前已經是最新版本。';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return '發現新版本：$version。請開啟更新日誌頁面檢視詳情。';
  }

  @override
  String get aboutCheckUpdateFailed => '檢查更新失敗，請稍後重試。';

  @override
  String aboutActionOpenedLink(String title) {
    return '已開啟 $title';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return '開啟 $title 失敗';
  }

  @override
  String get actionConfirm => '確定';

  @override
  String get libraryLinkManagerTitle => '歌詞關聯管理器';

  @override
  String get libraryLinkManagerReturnToSettings => '返回設定';

  @override
  String get libraryLinkManagerRefresh => '重新整理';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return '刪除選中 ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => '刪除全部';

  @override
  String get libraryLinkManagerClearInvalid => '清理無效資料';

  @override
  String get libraryLinkManagerChangeDirectory => '批次改目錄';

  @override
  String get libraryLinkManagerBackupToJson => '備份到 JSON';

  @override
  String get libraryLinkManagerRestoreFromJson => '從 JSON 恢復';

  @override
  String get libraryLinkManagerRestoreAction => '恢復';

  @override
  String get libraryLinkManagerExportLyrics => '匯出歌詞';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '共 $totalCount 條記錄 · 已選擇 $selectedCount 條記錄';
  }

  @override
  String get libraryLinkManagerSearchHint => '搜尋歌曲、藝術家、專輯或路徑';

  @override
  String get libraryLinkManagerClearSearch => '清除搜尋';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '匹配 $totalCount 條記錄 · 已選擇 $selectedCount 條記錄';
  }

  @override
  String get libraryLinkManagerEmpty => '暫無歌詞關聯記錄';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return '載入關聯記錄失敗: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess => '已刪除選中的歌詞關聯';

  @override
  String get libraryLinkManagerDeleteAllConfirm => '確定要刪除全部歌詞關聯記錄嗎？';

  @override
  String get libraryLinkManagerDeleteAllSuccess => '已刪除全部歌詞關聯記錄';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return '清理完成，共清理 $count 條無效資料';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return '批次改目錄完成，共更新 $count 條記錄';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return '歌詞關聯資料已備份到 $path';
  }

  @override
  String get libraryLinkManagerRestoreConfirm => '恢復會覆蓋當前全部歌詞關聯記錄，是否繼續？';

  @override
  String get libraryLinkManagerRestoreSuccess => '歌詞關聯資料已恢復';

  @override
  String get libraryLinkManagerInvalidBackupFormat => '備份檔案格式錯誤';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return '匯出完成，共匯出 $count 條歌詞檔案';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return '操作失敗: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => '未命名歌曲';

  @override
  String get libraryLinkManagerUnknownArtist => '未知藝術家';

  @override
  String get libraryLinkManagerUnknownAlbum => '未知專輯';

  @override
  String get libraryLinkManagerSongPathLabel => '歌曲路徑';

  @override
  String get libraryLinkManagerSongPathEmpty => '未記錄歌曲路徑';

  @override
  String get libraryLinkManagerLyricsPathLabel => '歌詞路徑';

  @override
  String get libraryLinkManagerLyricsPathEmpty => '未關聯歌詞';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return '軌道 $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return '軌道編號：$track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => '無';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return '偏移 $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return '歌詞偏移：$offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return '語言 $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return '歌詞語言：$langs';
  }

  @override
  String get libraryLinkManagerInstrumental => '純音樂';

  @override
  String get libraryLinkManagerInstrumentalTooltip => '當前歌曲已標記為純音樂';

  @override
  String get libraryLinkManagerDisableAutoSearch => '停用自動搜尋';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip => '當前歌曲已停用自動搜尋';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return '其他配置 $count 項';
  }

  @override
  String get libraryLinkManagerDefaultConfig => '預設配置';

  @override
  String get libraryLinkManagerDefaultConfigTooltip => '當前記錄未儲存歌曲級特殊配置';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return '開啟失敗：$detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable => '當前歌詞檔案不可訪問';

  @override
  String get openLyricsNoticeSongFileUnavailable => '當前歌曲檔案不可訪問';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics => '歌曲內沒有可讀取的內嵌歌詞';

  @override
  String get openLyricsNoticeAlreadyConverted => '當前歌詞已經轉換過了';

  @override
  String get openLyricsNoticeEmptyLyrics => '歌詞內容不能為空';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return '轉換失敗：$detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => '請先轉換歌詞';

  @override
  String get openLyricsNoticeNoLyricsToSave => '沒有歌詞可以儲存';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return '歌詞儲存成功：$detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return '儲存失敗：$detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => '請先開啟歌曲檔案';

  @override
  String get openLyricsNoticeAudioTagUnsupported => '當前平臺不支援寫入歌曲標籤';

  @override
  String get openLyricsDropUnsupportedItem => '開啟歌詞頁只接受歌詞檔案或音訊檔案拖入';

  @override
  String get openLyricsPreviewTitle => '預覽';

  @override
  String get openLyricsPreviewRawText => '原始文本';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return '歌詞語言 · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => '未載入';

  @override
  String get openLyricsPreviewStateRawLoaded => '待轉換';

  @override
  String get openLyricsPreviewStateConverted => '已轉換';

  @override
  String get openLyricsPreviewEmptyNoInput => '請先開啟歌詞檔案或歌曲檔案';

  @override
  String get openLyricsActionOpening => '開啟中...';

  @override
  String get openLyricsActionOpenLyricsFile => '開啟歌詞檔案';

  @override
  String get openLyricsActionOpenSongFile => '開啟歌曲檔案';

  @override
  String get openLyricsActionConvertFormat => '轉換格式';

  @override
  String get openLyricsActionSaveLyrics => '儲存歌詞';

  @override
  String get openLyricsActionSaveToTag => '儲存到歌曲標籤';

  @override
  String get openLyricsActionTranslate => '翻譯歌詞';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return '當前匯出格式：$format · 可寫回標籤';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return '當前匯出格式：$format · 僅支援匯出檔案';
  }

  @override
  String get searchLyricsSelectorTitle => '選擇歌詞';

  @override
  String get searchLyricsSelectorOpenLocal => '開啟本地歌詞';

  @override
  String get searchLyricsSelectorSelect => '選定歌詞';

  @override
  String get searchLyricsSelectorDescription => '為桌面歌詞選擇雲端或本地歌詞';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return '開啟本地歌詞失敗：$detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => '請先選擇歌詞';

  @override
  String get searchLyricsSelectorSelectFailed => '選定歌詞失敗，請稍後重試';

  @override
  String get searchDropUnsupportedItem => '搜尋頁只接受可解析歌曲條目或音訊檔案拖入';

  @override
  String get searchNoticePartialSourcesFailed => '部分來源搜尋失敗，已顯示其他來源結果';

  @override
  String get searchNoticeAllSourcesFailed => '所有來源搜尋失敗';

  @override
  String get searchNoticeLoadMoreFailed => '部分來源載入更多失敗';

  @override
  String get searchNoticeDirectoryPickerUnsupported => '當前平臺不支援選擇目錄';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return '已自動獲取 $detail 的歌詞';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return '自動獲取歌詞失敗：$detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable => '未選擇可用歌曲檔案';

  @override
  String get searchNoticeFilePickerUnsupported => '當前平臺不支援選擇歌曲檔案';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return '開啟歌曲失敗：$detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable => '拖入的歌曲檔案不可用';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return '解析拖入歌曲失敗：$detail';
  }

  @override
  String get searchNoticeEmptyKeyword => '請輸入搜尋關鍵詞';

  @override
  String get searchNoticeGetLyricsFirst => '請先獲取歌詞';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return '歌詞儲存成功：$detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported => '當前平臺不支援儲存檔案';

  @override
  String get searchNoticeFilePickerForTagUnsupported => '當前平臺不支援選擇歌曲標籤檔案';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return '選擇檔案失敗：$detail';
  }

  @override
  String get searchNoticeBatchCancelling => '正在取消批次儲存...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst => '請先選擇專輯或歌單';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage => '請至少選擇一種歌詞語言';

  @override
  String get searchNoticeNoSongsToSave => '沒有可儲存的歌曲';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return '批次儲存已取消：成功$saved，失敗$failed，跳過$skipped';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return '批次儲存完成：成功$saved，失敗$failed，跳過$skipped';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return '批次儲存失敗：$detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates => '發現多個候選歌詞，請選擇一個繼續';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return '獲取歌詞失敗：$detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => '請先選擇儲存路徑';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return '選擇目錄失敗：$detail';
  }

  @override
  String get searchNoticePreviewLoading => '歌詞仍在載入中';

  @override
  String get searchNoticePreviewNoLanguage => '請至少選擇一種歌詞語言';

  @override
  String get searchNoticePreviewNoContent => '當前歌詞暫無可預覽內容';

  @override
  String get searchNoticePreviewNoSelection => '請先下載並預覽歌詞';

  @override
  String get desktopWindowActionSelectLyrics => '選擇歌詞';

  @override
  String get desktopWindowActionMarkInstrumental => '標記為純音樂';

  @override
  String get desktopWindowActionDisableAutoSearch => '停用自動搜尋(僅本曲)';

  @override
  String get desktopWindowActionUnlinkLyrics => '取消歌詞關聯';

  @override
  String get desktopWindowActionAssociationManager => '歌詞關聯管理器';

  @override
  String get desktopWindowActionToggleFloating => '顯示/隱藏桌面歌詞';

  @override
  String get desktopWindowActionShowMainWindow => '顯示主視窗';

  @override
  String get desktopWindowActionClickThrough => '滑鼠穿透';

  @override
  String get desktopWindowActionPrevious => '上一首';

  @override
  String get desktopWindowActionPlay => '播放';

  @override
  String get desktopWindowActionPause => '暫停';

  @override
  String get desktopWindowActionNext => '下一首';

  @override
  String get desktopWindowActionHide => '隱藏';

  @override
  String get desktopTrayCurrentTarget => '當前目標：';

  @override
  String get desktopTrayNoSelection => '未選擇';

  @override
  String get desktopTrayTargetInstance => '目標例項';

  @override
  String get desktopTrayInstance => '例項';

  @override
  String get desktopTrayExit => '退出';

  @override
  String get desktopWindowInfoInstrumental => '純音樂';

  @override
  String get desktopWindowControlConnectionLost => '播放器連線已斷開，操作未執行';

  @override
  String get desktopWindowClientDisconnected => '播放器連線已斷開，桌面歌詞已關閉';
}
