import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'lyrics_ui_strings.dart';

/// 通用搜索表面的文案键。
///
/// 枚举值与搜索状态中的业务语义一一对应，避免共享组件携带 LDDC 宿主的生成式
/// 本地化类型。新增可见状态时必须先补充此处，analyzer 会要求宿主映射保持完整。
enum SearchUiTextKey {
  commonSearch,
  commonSource,
  keywordHint,
  batchSaveProgressTitle,
  batchSaveProgressPreparing,
  batchSaveProgressFetchingLyrics,
  loading,
  loadingStepFetching,
  initialResultTitle,
  initialResultDescription,
  commonError,
  retry,
  viewDetails,
  empty,
  resultLoadingMore,
  resultLoadMoreFailed,
  resultScrollForMore,
  noMoreResult,
  resultTitle,
  resultReturn,
  saveListLyrics,
  saveListLyricsCancel,
  previewTitle,
  tableStatusAutoFetching,
  tableStatusSearching,
  tableStatusFetchingSongList,
  tableStatusNoResults,
  tableStatusEmptyList,
  tableStatusUnsupportedSearchType,
  tableStatusSearchFailed,
  tableStatusSearchFailedWithDetail,
  tableStatusAutoFetchFailed,
  tableStatusSongListFailed,
  tableStatusPartialSourceUnavailable,
  tableStatusLoadMoreFailed,
  sourceFailureDetailsTitle,
  sourceFailureRequest,
  sourceFailureTimeout,
  sourceFailureParameters,
  sourceFailureUnsupported,
  sourceFailureUnknown,
  tableSongCount,
  previewLoading,
  previewLangsLabel,
  previewSongIdLabel,
  savePathLabel,
  selectSavePath,
  savePreviewToDirectory,
  savePreviewToFile,
  savePreviewToTag,
  saving,
  translateLyrics,
  previewNoLanguage,
  previewNoContent,
  previewPlaceholder,
  resizeWorkspacePanes,
  selectorTitle,
  selectorDescription,
  selectorOpenLocal,
  selectorSelect,
  selectorOpenLocalFailed,
  selectorSelectLyricsFirst,
  selectorSelectFailed,
  noticeDirectoryPickerUnsupported,
  noticeSearchPartialSourcesFailed,
  noticeSearchAllSourcesFailed,
  noticeSearchLoadMoreFailed,
  noticeAutoFetchSucceeded,
  noticeAutoFetchFailed,
  noticeSelectedSongUnavailable,
  noticeFilePickerUnsupported,
  noticeOpenSongFailed,
  noticeDroppedSongUnavailable,
  noticeDroppedSongResolveFailed,
  noticeEmptyKeyword,
  noticeGetLyricsFirst,
  noticeTranslationCancelled,
  noticeTranslationCompleted,
  noticeTranslationFailed,
  noticeLyricsSaved,
  noticeLyricsSaveSucceededWithPath,
  noticeLyricsSaveFailed,
  noticeSaveFileUnsupported,
  noticeFilePickerForTagUnsupported,
  noticeFilePickerFailed,
  noticeBatchCancelling,
  noticeSelectAlbumOrPlaylistFirst,
  noticeSelectAtLeastOneLyricsLanguage,
  noticeNoSongsToSave,
  noticeBatchSaveCancelled,
  noticeBatchSaveCompleted,
  noticeBatchSaveFailed,
  noticeMultipleLyricsCandidates,
  noticeGetLyricsFailed,
  noticeSelectSavePathFirst,
  noticeDirectoryPickFailed,
  noticePreviewLoading,
  noticePreviewNoLanguage,
  noticePreviewNoContent,
  noticePreviewNoSelection,
  noticeAudioTagRequiresLrc,
}

/// 搜索文案的动态参数，避免各组件重复定义数量和错误详情参数。
final class SearchUiTextArguments {
  const SearchUiTextArguments({
    this.detail = '',
    this.songName = '',
    this.count = 0,
    this.saved = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final String detail;
  final String songName;
  final int count;
  final int saved;
  final int failed;
  final int skipped;
}

typedef SearchUiTextResolver =
    String Function(SearchUiTextKey key, SearchUiTextArguments arguments);
typedef SearchSourceLabelResolver = String Function(Source source);
typedef SearchTypeLabelResolver = String Function(SearchType type);

/// 搜索 workspace、结果区、预览区和选择器共同使用的本地化边界。
final class SearchUiStrings {
  const SearchUiStrings({
    required this.lyrics,
    required this._textResolver,
    required this._sourceLabelResolver,
    required this._searchTypeLabelResolver,
  });

  factory SearchUiStrings.zhHans() {
    return SearchUiStrings(
      lyrics: LyricsUiStrings.zhHans(),
      textResolver: _zhHansSearchText,
      sourceLabelResolver: _zhHansSourceLabel,
      searchTypeLabelResolver: _zhHansSearchTypeLabel,
    );
  }

  final LyricsUiStrings lyrics;
  final SearchUiTextResolver _textResolver;
  final SearchSourceLabelResolver _sourceLabelResolver;
  final SearchTypeLabelResolver _searchTypeLabelResolver;

  String text(
    SearchUiTextKey key, {
    SearchUiTextArguments arguments = const SearchUiTextArguments(),
  }) {
    return _textResolver(key, arguments);
  }

  String sourceLabel(Source source) => _sourceLabelResolver(source);

  String searchTypeLabel(SearchType type) => _searchTypeLabelResolver(type);
}

String _zhHansSearchText(SearchUiTextKey key, SearchUiTextArguments arguments) {
  final String detail = arguments.detail;
  return switch (key) {
    SearchUiTextKey.commonSearch => '搜索',
    SearchUiTextKey.commonSource => '来源',
    SearchUiTextKey.keywordHint => '输入歌曲、歌手、专辑或歌词关键词',
    SearchUiTextKey.batchSaveProgressTitle => '批量保存歌词',
    SearchUiTextKey.batchSaveProgressPreparing => '正在准备...',
    SearchUiTextKey.batchSaveProgressFetchingLyrics =>
      '正在获取 ${arguments.songName} 的歌词',
    SearchUiTextKey.loading => '加载中',
    SearchUiTextKey.loadingStepFetching => '正在获取数据',
    SearchUiTextKey.initialResultTitle => '搜索歌词',
    SearchUiTextKey.initialResultDescription => '输入关键词后开始搜索',
    SearchUiTextKey.commonError => '发生错误',
    SearchUiTextKey.retry => '重试',
    SearchUiTextKey.viewDetails => '查看详情',
    SearchUiTextKey.empty => '暂无内容',
    SearchUiTextKey.resultLoadingMore => '正在加载更多...',
    SearchUiTextKey.resultLoadMoreFailed => '加载更多失败',
    SearchUiTextKey.resultScrollForMore => '继续滚动以加载更多',
    SearchUiTextKey.noMoreResult => '没有更多结果',
    SearchUiTextKey.resultTitle => '搜索结果',
    SearchUiTextKey.resultReturn => '返回',
    SearchUiTextKey.saveListLyrics => '保存专辑/歌单的歌词',
    SearchUiTextKey.saveListLyricsCancel => '取消批量保存',
    SearchUiTextKey.previewTitle => '歌词预览',
    SearchUiTextKey.tableStatusAutoFetching => '正在自动获取歌词',
    SearchUiTextKey.tableStatusSearching => '正在搜索',
    SearchUiTextKey.tableStatusFetchingSongList => '正在获取歌曲列表',
    SearchUiTextKey.tableStatusNoResults => '没有找到结果',
    SearchUiTextKey.tableStatusEmptyList => '歌曲列表为空',
    SearchUiTextKey.tableStatusUnsupportedSearchType => '当前来源不支持此搜索类型',
    SearchUiTextKey.tableStatusSearchFailed => '搜索失败',
    SearchUiTextKey.tableStatusSearchFailedWithDetail => '搜索失败：$detail',
    SearchUiTextKey.tableStatusAutoFetchFailed => '自动获取歌词失败：$detail',
    SearchUiTextKey.tableStatusSongListFailed => '获取歌曲列表失败：$detail',
    SearchUiTextKey.tableStatusPartialSourceUnavailable => '部分来源暂不可用',
    SearchUiTextKey.tableStatusLoadMoreFailed => '加载更多失败',
    SearchUiTextKey.sourceFailureDetailsTitle => '搜索错误详情',
    SearchUiTextKey.sourceFailureRequest => '请求失败',
    SearchUiTextKey.sourceFailureTimeout => '请求超时',
    SearchUiTextKey.sourceFailureParameters => '参数错误',
    SearchUiTextKey.sourceFailureUnsupported => '不支持的操作',
    SearchUiTextKey.sourceFailureUnknown => '未知错误',
    SearchUiTextKey.tableSongCount => '${arguments.count} 首歌曲',
    SearchUiTextKey.previewLoading => '正在生成歌词预览...',
    SearchUiTextKey.previewLangsLabel => '歌词语言',
    SearchUiTextKey.previewSongIdLabel => '歌曲 ID',
    SearchUiTextKey.savePathLabel => '保存路径',
    SearchUiTextKey.selectSavePath => '选择保存路径',
    SearchUiTextKey.savePreviewToDirectory => '保存到文件夹',
    SearchUiTextKey.savePreviewToFile => '保存到文件',
    SearchUiTextKey.savePreviewToTag => '保存到歌曲标签',
    SearchUiTextKey.saving => '保存中...',
    SearchUiTextKey.translateLyrics => '翻译歌词',
    SearchUiTextKey.previewNoLanguage => '请至少选择一种歌词语言',
    SearchUiTextKey.previewNoContent => '所选语言没有可预览内容',
    SearchUiTextKey.previewPlaceholder => '请选择歌曲并获取歌词',
    SearchUiTextKey.resizeWorkspacePanes => '调整搜索结果与歌词预览宽度',
    SearchUiTextKey.selectorTitle => '选择歌词',
    SearchUiTextKey.selectorDescription => '搜索或打开本地歌词，然后选定当前歌词',
    SearchUiTextKey.selectorOpenLocal => '打开本地歌词',
    SearchUiTextKey.selectorSelect => '选定歌词',
    SearchUiTextKey.selectorOpenLocalFailed => '打开本地歌词失败：$detail',
    SearchUiTextKey.selectorSelectLyricsFirst => '请先选择歌词',
    SearchUiTextKey.selectorSelectFailed => '歌词选择结果回传失败',
    SearchUiTextKey.noticeSearchPartialSourcesFailed => '部分来源搜索失败，已显示其他来源结果',
    SearchUiTextKey.noticeSearchAllSourcesFailed => '所有来源搜索失败',
    SearchUiTextKey.noticeSearchLoadMoreFailed => '部分来源加载更多失败',
    SearchUiTextKey.noticeDirectoryPickerUnsupported => '当前平台不支持选择文件夹',
    SearchUiTextKey.noticeAutoFetchSucceeded => '已自动获取歌词：$detail',
    SearchUiTextKey.noticeAutoFetchFailed => '自动获取歌词失败：$detail',
    SearchUiTextKey.noticeSelectedSongUnavailable => '所选结果没有可用的歌曲信息',
    SearchUiTextKey.noticeFilePickerUnsupported => '当前平台不支持选择文件',
    SearchUiTextKey.noticeOpenSongFailed => '打开歌曲失败：$detail',
    SearchUiTextKey.noticeDroppedSongUnavailable => '拖入内容不包含可用歌曲',
    SearchUiTextKey.noticeDroppedSongResolveFailed => '解析拖入歌曲失败：$detail',
    SearchUiTextKey.noticeEmptyKeyword => '请输入搜索关键词',
    SearchUiTextKey.noticeGetLyricsFirst => '请先获取歌词',
    SearchUiTextKey.noticeTranslationCancelled => '已取消翻译',
    SearchUiTextKey.noticeTranslationCompleted => '翻译完成',
    SearchUiTextKey.noticeTranslationFailed => '翻译失败：$detail',
    SearchUiTextKey.noticeLyricsSaved => '歌词已保存',
    SearchUiTextKey.noticeLyricsSaveSucceededWithPath => '歌词已保存到 $detail',
    SearchUiTextKey.noticeLyricsSaveFailed => '歌词保存失败：$detail',
    SearchUiTextKey.noticeSaveFileUnsupported => '当前平台不支持保存文件',
    SearchUiTextKey.noticeFilePickerForTagUnsupported => '当前平台不支持选择歌曲文件',
    SearchUiTextKey.noticeFilePickerFailed => '选择文件失败：$detail',
    SearchUiTextKey.noticeBatchCancelling => '正在取消批量保存...',
    SearchUiTextKey.noticeSelectAlbumOrPlaylistFirst => '请先选择专辑或歌单',
    SearchUiTextKey.noticeSelectAtLeastOneLyricsLanguage => '请至少选择一种歌词语言',
    SearchUiTextKey.noticeNoSongsToSave => '没有可保存的歌曲',
    SearchUiTextKey.noticeBatchSaveCancelled =>
      '批量保存已取消：成功 ${arguments.saved}，失败 ${arguments.failed}，跳过 ${arguments.skipped}',
    SearchUiTextKey.noticeBatchSaveCompleted =>
      '批量保存完成：成功 ${arguments.saved}，失败 ${arguments.failed}，跳过 ${arguments.skipped}',
    SearchUiTextKey.noticeBatchSaveFailed => '批量保存失败：$detail',
    SearchUiTextKey.noticeMultipleLyricsCandidates => '找到多个歌词候选，请选择一项',
    SearchUiTextKey.noticeGetLyricsFailed => '获取歌词失败：$detail',
    SearchUiTextKey.noticeSelectSavePathFirst => '请先选择保存路径',
    SearchUiTextKey.noticeDirectoryPickFailed => '选择文件夹失败：$detail',
    SearchUiTextKey.noticePreviewLoading => '歌词预览正在生成',
    SearchUiTextKey.noticePreviewNoLanguage => '请至少选择一种歌词语言',
    SearchUiTextKey.noticePreviewNoContent => '所选语言没有可预览内容',
    SearchUiTextKey.noticePreviewNoSelection => '请先选择歌词',
    SearchUiTextKey.noticeAudioTagRequiresLrc => '写入音频标签时必须使用 LRC 格式',
  };
}

String _zhHansSourceLabel(Source source) {
  return switch (source) {
    Source.multi => '聚合',
    Source.qm => 'QQ 音乐',
    Source.kg => '酷狗音乐',
    Source.ne => '网易云音乐',
    Source.lrclib => 'LRCLIB',
    Source.local => '本地',
  };
}

String _zhHansSearchTypeLabel(SearchType type) {
  return switch (type) {
    SearchType.song => '歌曲',
    SearchType.album => '专辑',
    SearchType.songlist => '歌单',
    SearchType.artist => '歌手',
    SearchType.lyrics => '歌词',
    SearchType.songId => '歌曲 ID',
  };
}
