// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'LDDC';

  @override
  String get commonWarning => '경고';

  @override
  String get commonError => '오류';

  @override
  String get commonSuccess => '성공';

  @override
  String get commonFailed => '실패한';

  @override
  String get commonSkipped => '건너뛰었습니다.';

  @override
  String get commonTotal => '총';

  @override
  String get commonDelete => '삭제';

  @override
  String get commonConfirm => '확인하다';

  @override
  String get commonRestoreDefault => '기본값 복원';

  @override
  String get commonEnabled => '활성화됨';

  @override
  String get commonDisabledByDefault => '기본적으로 비활성화됨';

  @override
  String get commonFormat => '체재';

  @override
  String get commonOffset => '오프셋';

  @override
  String get commonSaving => '절약...';

  @override
  String get commonAddFiles => '파일 추가';

  @override
  String get commonClearQueue => '대기열 지우기';

  @override
  String get commonUnsupportedOperation => '이 작업은 이 플랫폼에서 지원되지 않습니다';

  @override
  String get commonLyricsFileUnavailable => '이 항목에는 아직 열 수 있는 가사 파일이 없습니다.';

  @override
  String get commonAudioTagRequiresLrc => '노래 태그 가사는 LRC 형식을 사용해야 합니다.';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language($type)';
  }

  @override
  String get commonTranslationCancelled => '번역이 삭제됨';

  @override
  String get commonCancelTranslation => '번역 제거';

  @override
  String get commonTranslating => '번역 중...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return '$completed/$total 번역 중';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'OpenAI 스트리밍 번역: $completed / $total 라인';
  }

  @override
  String get commonTranslationCompleted => '번역 완료';

  @override
  String get commonLyricsSaved => '가사가 저장되었습니다';

  @override
  String commonDropFailed(String detail) {
    return '삭제 실패: $detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return '저장 디렉터리를 선택하지 못했습니다: $detail';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return '저장 디렉터리를 열지 못했습니다: $detail';
  }

  @override
  String commonTranslationFailed(String detail) {
    return '번역 실패: $detail';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return '가사 저장 실패: $detail';
  }

  @override
  String get appErrorUnknown => '알 수 없는 오류가 발생했습니다.';

  @override
  String get appErrorOperationTimeout => '작업 시간이 초과되었습니다. 나중에 다시 시도해 주세요.';

  @override
  String get appErrorNetworkUnavailable => '네트워크를 사용할 수 없습니다. 연결을 확인해주세요.';

  @override
  String get appErrorInvalidPayload => '데이터 형식이 잘못되었습니다.';

  @override
  String get appErrorUnsupportedOperation => '이 작업은 지원되지 않습니다.';

  @override
  String get appErrorPermissionDenied => '이 작업을 수행할 권한이 없습니다.';

  @override
  String get appErrorIoFailure => '파일 읽기 또는 쓰기에 실패했습니다.';

  @override
  String get appErrorLyricsRequestFailed => '가사를 요청하지 못했습니다.';

  @override
  String get appErrorLyricsNotFound => '가사를 찾을 수 없습니다.';

  @override
  String get appErrorLyricsProcessing => '가사를 처리하지 못했습니다.';

  @override
  String get appErrorLyricsDecrypt => '가사를 해독하지 못했습니다.';

  @override
  String get appErrorLyricsFormatUnsupported => '지원되지 않는 가사 형식입니다.';

  @override
  String get appErrorDecoding => '디코딩에 실패했습니다.';

  @override
  String get appErrorSongInfoRead => '노래 정보를 읽지 못했습니다.';

  @override
  String get appErrorUnsupportedFileType => '지원되지 않는 파일 형식입니다.';

  @override
  String get appErrorDragDropInvalid => '드래그 앤 드롭 데이터가 잘못되었습니다.';

  @override
  String get appErrorTranslateFailed => '번역에 실패했습니다.';

  @override
  String get appErrorApiParamsInvalid => '요청 매개변수가 잘못되었습니다.';

  @override
  String get appErrorApiRequestFailed => 'API 요청이 실패했습니다.';

  @override
  String get appErrorAutoFetchUnknown => '알 수 없는 오류로 인해 자동 일치에 실패했습니다.';

  @override
  String get appErrorNotEnoughInfo => '검색할 정보가 부족합니다.';

  @override
  String get appErrorIpcInvalidLength => 'IPC 메시지 길이가 잘못되었습니다.';

  @override
  String get appErrorIpcUnsupportedTask => 'IPC 작업은 지원되지 않습니다.';

  @override
  String get appErrorIpcInstanceNotFound => 'IPC 인스턴스가 존재하지 않습니다.';

  @override
  String get appErrorIpcPanelNotFound => 'IPC 패널이 존재하지 않습니다.';

  @override
  String get appErrorIpcInvalidWindowId => '창 핸들이 잘못되었습니다.';

  @override
  String get appErrorIpcEmbedUnsupported => '이 플랫폼에서는 임베디드 모드가 지원되지 않습니다.';

  @override
  String get appErrorActionRetryNetwork => '네트워크를 확인하고 다시 시도해 주세요.';

  @override
  String get appErrorActionCheckPayload => '입력 데이터 형식을 확인하세요.';

  @override
  String get appErrorActionChangeFormat => '지원되는 파일이나 형식을 사용하세요.';

  @override
  String get appErrorActionDetachedMode => '분리 모드로 돌아가십시오.';

  @override
  String get actionRetry => '다시 해 보다';

  @override
  String get actionViewDetails => '세부정보 보기';

  @override
  String get actionCancel => '취소';

  @override
  String get sourceAggregate => '골재';

  @override
  String get sourceQQMusic => 'QQ 음악';

  @override
  String get sourceKugou => '쿠고우 음악';

  @override
  String get sourceNetease => '넷이즈 음악';

  @override
  String get sourceLrclib => 'Lrclib';

  @override
  String get sourceLocal => '현지의';

  @override
  String get lyricOriginal => '원래의';

  @override
  String get lyricTranslation => '번역';

  @override
  String get lyricRomanized => '로마자 표기';

  @override
  String get lyricsFormatVerbatimLrc => '워드타임 LRC';

  @override
  String get lyricsFormatLineByLineLrc => '회선 시간 LRC';

  @override
  String get lyricsFormatEnhancedLrc => '향상된 LRC(ESLyric)';

  @override
  String get lyricsFormatSrt => 'SRT';

  @override
  String get lyricsFormatAss => '나귀';

  @override
  String get lyricsTypeVerbatim => '워드타임';

  @override
  String get lyricsTypeLineByLine => '회선 시간에 따른';

  @override
  String get lyricsTypePlainText => '일반 텍스트';

  @override
  String get searchSong => '노래';

  @override
  String get searchAlbum => '앨범';

  @override
  String get searchSongList => '재생목록';

  @override
  String get searchArtist => '아티스트';

  @override
  String get searchLyrics => '가사';

  @override
  String get searchSongId => '노래 ID';

  @override
  String get localMatchIteratingFiles => '파일을 스캔하는 중...';

  @override
  String get localMatchProgressImportCompleted => '가져오기 완료';

  @override
  String get localMatchProgressScanCompleted => '스캔 완료';

  @override
  String get localMatchProgressScanFailed => '스캔 실패';

  @override
  String get localMatchProgressMatchCompleted => '경기 완료';

  @override
  String get localMatchProgressMatchFailed => '경기 실패';

  @override
  String get localMatchProgressPreparingMatch => '시합 준비 중...';

  @override
  String get localMatchPreviewTagOnly => '태그만 쓰기';

  @override
  String get localMatchPreviewWriteTag => '태그에 쓰기';

  @override
  String get localMatchPreviewNoOutput => '구성된 출력 없음';

  @override
  String get localMatchPreviewSongTagOnly => '노래 태그만';

  @override
  String get localMatchPendingLyricsFileName =>
      '파일 이름을 결정하기 위해 일치하는 가사 정보를 기다리는 중';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / 파일 이름을 결정하기 위해 일치하는 가사 정보를 기다리는 중';
  }

  @override
  String get localMatchCalcSavePathFailed => '저장 경로를 계산하지 못했습니다.';

  @override
  String get localMatchNoticeBusyImportFiles =>
      '작업이 실행 중이므로 지금은 파일을 가져올 수 없습니다.';

  @override
  String get localMatchNoticeSelectedFilesUnavailable => '선택한 파일을 사용할 수 없습니다.';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return '파일을 가져오지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeBusyImportDirectories =>
      '작업이 실행 중이므로 지금은 디렉터리를 가져올 수 없습니다.';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return '디렉터리를 가져오지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles =>
      '삭제된 데이터에 액세스 가능한 파일이 없습니다.';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return '삭제된 노래를 해결하지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors =>
      '가져오기가 완료되었지만 일부 항목을 구문 분석할 수 없습니다.';

  @override
  String get localMatchNoticeSafTreeUnsupported =>
      '이 플랫폼에서는 디렉터리 트리 액세스가 지원되지 않습니다.';

  @override
  String get localMatchNoticeBusySwitchTree =>
      '작업이 실행 중이므로 지금은 디렉터리 트리를 변경할 수 없습니다.';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return '디렉터리 트리를 선택하지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeBusyClearQueue =>
      '작업이 실행 중이므로 지금은 대기열을 지울 수 없습니다.';

  @override
  String get localMatchNoticeSelectItemsToDelete => '먼저 삭제할 항목을 선택하세요.';

  @override
  String get localMatchNoticeSelectItemsToSetRoot =>
      '루트 디렉터리를 설정하기 전에 항목을 선택하세요';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return '다음 노래는 선택한 루트 외부에 있으므로 건너뛰었습니다: $detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return '루트 디렉터리를 설정하지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore => '먼저 복원할 항목을 선택하세요.';

  @override
  String get localMatchNoticeCancelling => '현재 작업을 취소하는 중...';

  @override
  String get localMatchNoticeValidationFailed => '먼저 로컬 일치 요구사항을 해결하세요.';

  @override
  String get localMatchNoticeSongDirectoryUnavailable =>
      '이 항목은 노래 디렉토리를 열 수 없습니다';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return '노래 디렉터리를 열지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable =>
      '이 항목에는 아직 열 수 있는 저장 디렉터리가 없습니다.';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return '가사를 열지 못했습니다: $detail';
  }

  @override
  String get localMatchNoticeScanCancelled => '스캔이 취소되었습니다.';

  @override
  String get localMatchNoticeScanCompletedWithErrors =>
      '스캔이 완료되었지만 일부 파일을 구문 분석할 수 없습니다.';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return '스캔 실패: $detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return '디렉터리 트리 검색 실패: $detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => '경기가 취소되었습니다';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return '총 $total곡, $success 일치, $failed 실패, $skipped 건너뛰었습니다.';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return '로컬 일치 실패: $detail';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume =>
      '경기가 취소되었습니다. 체크포인트에서 다시 시작하려면 다시 시작하세요.';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Android SAF 로컬 일치 실패: $detail';
  }

  @override
  String get localMatchValidationEmptyLangs => '일치하는 가사 언어를 선택하세요';

  @override
  String get localMatchValidationEmptySources => '소스를 하나 이상 선택하세요.';

  @override
  String get localMatchValidationEmptyQueue => '먼저 일치하도록 노래 가져오기';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      '파일 저장 중 기존 가사 건너뛰기 시 파일명 모드에서 일치하는 가사 정보를 사용할 수 없는 문제';

  @override
  String get localMatchValidationMissingAndroidTree => '먼저 디렉터리 트리를 선택하세요.';

  @override
  String get localMatchValidationNeedsSaveRoot => '저장 경로가 필요합니다.';

  @override
  String get localMatchValidationNeedsSongRoot => '노래 루트 디렉터리가 필요합니다.';

  @override
  String get localMatchValidationUnknownSavePath => '알 수 없는 저장 경로 오류';

  @override
  String get localMatchIntro => '로컬 노래나 폴더를 가져오고 출력을 미리 본 다음 일괄 일치를 실행합니다.';

  @override
  String get localMatchDropUnsupportedItem =>
      '로컬 일치에서는 노래 파일, 폴더 또는 구문 분석 가능한 플레이어 항목을 허용합니다.';

  @override
  String get localMatchReadyToStart => '지역 매칭 시작 준비 완료';

  @override
  String get localMatchQueueTitle => '작업 대기열';

  @override
  String get localMatchQueueEmptyHint => '작업 대기열을 구축하기 위해 파일 또는 폴더 가져오기';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '$count 작업. 추가 작업을 보려면 행을 마우스 오른쪽 버튼으로 클릭하세요.';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '$count 작업. 작업을 열려면 길게 누르거나 추가 항목을 탭하세요.';
  }

  @override
  String get localMatchImportAndRunTitle => '가져오기 및 실행';

  @override
  String get localMatchActionStart => '매칭 시작';

  @override
  String get localMatchActionAddFolders => '폴더 추가';

  @override
  String get localMatchActionSelectSaveRoot => '루트 저장을 선택하세요.';

  @override
  String get localMatchActionSelectTree => '트리 선택';

  @override
  String get localMatchActionReselectTree => '트리 다시 선택';

  @override
  String get localMatchActionBulkSelect => '대량 선택';

  @override
  String get localMatchActionExitSelection => '일괄 선택 종료';

  @override
  String get localMatchActionSelectAll => '모두 선택';

  @override
  String get localMatchActionDeselectAll => '모두 선택 취소';

  @override
  String get localMatchActionSetRoot => '루트 설정';

  @override
  String localMatchSelectedCount(int count) {
    return '$count 선택됨';
  }

  @override
  String get localMatchBulkActionHint => '대량 작업은 선택한 작업에 직접 적용됩니다.';

  @override
  String get localMatchPhaseIdle => '대기 중';

  @override
  String get localMatchPhaseScanning => '스캐닝';

  @override
  String get localMatchPhaseMatching => '어울리는';

  @override
  String get localMatchPhaseWriting => '글쓰기';

  @override
  String get localMatchPhaseCompleted => '완전한';

  @override
  String get localMatchPhaseHintIdle => '일치를 시작하려면 노래를 가져오세요.';

  @override
  String get localMatchPhaseHintScanning => '작업 대기열 구축 및 출력 추정';

  @override
  String get localMatchPhaseHintMatching => '소스 쿼리 및 가장 일치하는 항목 계산';

  @override
  String get localMatchPhaseHintWriting => '가사 파일 또는 노래 태그 작성';

  @override
  String get localMatchPhaseHintCompleted =>
      '이 실행이 완료되었습니다. 필요한 경우 조정하고 다시 실행하세요.';

  @override
  String get localMatchPipelineIdle => '스캔 -> 일치 -> 쓰기';

  @override
  String get localMatchPipelineScanning => '현재 단계: 스캔';

  @override
  String get localMatchPipelineMatching => '현재 단계: 경기';

  @override
  String get localMatchPipelineWriting => '현재 단계: 쓰기';

  @override
  String get localMatchPipelineCompleted => '스캔, 일치 및 쓰기 완료';

  @override
  String get localMatchUnknownSong => '알 수 없는 노래';

  @override
  String get localMatchUnknownDuration => '알 수 없는 기간';

  @override
  String get localMatchStatusNotStarted => '시작되지 않음';

  @override
  String get localMatchSongPathLabel => '노래 경로';

  @override
  String get localMatchLyricsPathLabel => '가사 저장 경로';

  @override
  String get localMatchExpandDetails => '세부정보 펼치기';

  @override
  String get localMatchCollapseDetails => '세부정보 접기';

  @override
  String get localMatchRowActionOpenInSearch => '검색에서 열기';

  @override
  String get localMatchRowActionEnterSelection => '대량 선택 입력';

  @override
  String get localMatchRowActionOpenSongDirectory => '노래 폴더 열기';

  @override
  String get localMatchRowActionOpenSaveDirectory => '저장 폴더 열기';

  @override
  String get localMatchRowActionOpenLyrics => '가사 열기';

  @override
  String get localMatchFieldLyricsType => '가사 유형';

  @override
  String get localMatchFieldOutputStrategy => '출력 전략';

  @override
  String get localMatchFieldSaveMode => '저장 모드';

  @override
  String get localMatchFieldFileNameMode => '파일 이름 모드';

  @override
  String get localMatchFieldLyricsFormat => '가사 형식';

  @override
  String get localMatchFieldThreshold => '일치 임계값';

  @override
  String get localMatchFieldSaveRoot => '루트 저장';

  @override
  String get localMatchMoreSettings => '추가 설정';

  @override
  String get localMatchRulesTitle => '경기 규칙';

  @override
  String get localMatchRulesSubtitle => '소스, 언어, 출력 전략 및 임계값';

  @override
  String get localMatchMinScore => '최소 점수';

  @override
  String get localMatchSkipExisting => '기존 가사 건너뛰기';

  @override
  String get localMatchSkipExistingConflictHint =>
      '현재 출력 전략 및 파일 이름 모드는 기존 가사를 건너뛸 수 없습니다. 파일을 계속 저장해야 하는 경우 일치하는 가사 정보로 이름을 지정하지 마세요.';

  @override
  String get localMatchSaveToSongDirectoryHint =>
      '노래 폴더에 저장하는 경우 추가 저장 루트가 필요하지 않습니다.';

  @override
  String get localMatchAndroidTreeSaveHint =>
      'Android 디렉터리 트리 저장은 승인된 트리에 직접 기록됩니다.';

  @override
  String get localMatchFileNameTemplateHint =>
      '파일 이름 템플릿은 설정의 Lyrics_file_name_fmt를 사용합니다.';

  @override
  String localMatchSaveRootPath(String path) {
    return '저장 루트: $path';
  }

  @override
  String get localMatchSaveRootRequired =>
      '이 저장 모드에는 저장 루트가 필요합니다. 먼저 하나를 선택하세요.';

  @override
  String get localMatchTreeNotSelected => '선택한 디렉터리 트리가 없습니다.';

  @override
  String get localMatchSaveModeSong => '노래 폴더에 저장';

  @override
  String get localMatchSaveModeMirror => '미러 폴더';

  @override
  String get localMatchSaveModeSpecify => '특정 폴더';

  @override
  String get localMatchFileNameModeSong => '노래 파일 이름 사용';

  @override
  String get localMatchFileNameModeFormatBySong => '노래 정보별 이름';

  @override
  String get localMatchFileNameModeFormatByLyrics => '이름별 가사 정보';

  @override
  String get localMatchFileNameHintSong => '오디오 파일 이름을 재사용하고 가사 확장자만 바꾸세요.';

  @override
  String get localMatchFileNameHintFormatBySong =>
      '제목, 아티스트, 앨범과 같은 노래 메타데이터에서 파일 이름을 생성합니다.';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      '일치하는 가사 노래 정보에서 파일 이름을 생성합니다. 일치하기 전에는 알 수 없습니다.';

  @override
  String get localMatchSaveToTagOnlyFile => '파일만';

  @override
  String get localMatchSaveToTagOnlyTag => '태그만';

  @override
  String get localMatchSaveToTagBoth => '파일 + 태그';

  @override
  String get localMatchValidationTitle => '시작하기 전에 해결해야 할 문제';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '$count 더 많은 문제를 해결해야 합니다.';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable =>
      '선택한 파일에 직접 액세스할 수 없습니다.';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return '$count 가사 파일을 가져왔습니다.';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles =>
      '삭제된 데이터에는 접근 가능한 가사 파일이 없습니다.';

  @override
  String get batchConvertNoticeEmptyQueue => '먼저 변환할 가사 파일을 추가하세요';

  @override
  String get batchConvertNoticeOverwriteCancelled => '일괄 변환이 취소되었습니다.';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return '일괄 변환이 취소되고 $count 항목이 완료되었습니다.';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return '일괄 변환 완료: $success 성공, $failure 실패';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return '일괄 변환 완료: $count 항목';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return '일괄 변환 실패: $detail';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return '소스 디렉터리를 열지 못했습니다: $detail';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return '가사 파일을 열지 못했습니다: $detail';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles =>
      '선택한 폴더에서 지원되는 가사 파일을 찾을 수 없습니다.';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return '폴더에서 $count 가사 파일을 가져왔습니다.';
  }

  @override
  String get batchConvertNoticeDuplicateItems => '선택한 모든 항목이 이미 대기열에 있습니다.';

  @override
  String get batchConvertControlsTitle => '가져오기 및 설정';

  @override
  String get batchConvertCompactControlsTitle => '가져오기 및 출력 설정';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return '형식: $format';
  }

  @override
  String get batchConvertImportTitle => '수입';

  @override
  String get batchConvertAddFolders => '폴더 추가';

  @override
  String get batchConvertOutputSettingsTitle => '출력 설정';

  @override
  String get batchConvertTargetFormat => '대상 형식';

  @override
  String get batchConvertSaveDirectoryTitle => '폴더 저장';

  @override
  String get batchConvertSaveDirectoryDefault =>
      '설정하지 않으면 출력은 소스 가사 파일 옆으로 이동합니다.';

  @override
  String get batchConvertSelectSaveDirectory => '폴더 저장을 선택하세요';

  @override
  String get batchConvertRestoreOriginalDirectory => '소스 폴더 사용';

  @override
  String get batchConvertRecursiveTitle => '하위 폴더 스캔';

  @override
  String get batchConvertRecursiveSubtitle =>
      '폴더를 가져올 때 하위 폴더의 가사 파일을 계속 검색합니다.';

  @override
  String get batchConvertStart => '변환 시작';

  @override
  String get batchConvertCancel => '변환 취소';

  @override
  String get batchConvertQueueTitle => '전환 대기열';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '$count 항목, 출력 형식 $format';
  }

  @override
  String get batchConvertPageErrorFallback => '일괄 변환 페이지에 오류가 발생했습니다.';

  @override
  String get batchConvertRetryImport => '다시 가져오기';

  @override
  String get batchConvertEmptyQueue => '가사 파일이나 폴더를 추가하면 일괄 변환 대기열이 여기에 나타납니다.';

  @override
  String get batchConvertOutputPathLabel => '출력 경로';

  @override
  String get batchConvertQueueStatusWaiting => '대기 중';

  @override
  String get batchConvertQueueStatusRunning => '변환 중';

  @override
  String get batchConvertQueueStatusSuccess => '변환됨';

  @override
  String get batchConvertQueueStatusFailure => '실패한';

  @override
  String get batchConvertMoreActions => '추가 작업';

  @override
  String get batchConvertActionOpenSourceDirectory => '오픈 소스 폴더';

  @override
  String get batchConvertActionOpenSaveDirectory => '저장 폴더 열기';

  @override
  String get batchConvertActionOpenOutputFile => '가사 파일 열기';

  @override
  String get batchConvertActionOpenInOpenLyrics => 'Open in Open 가사';

  @override
  String get batchConvertPhaseIdle => '대기 중';

  @override
  String get batchConvertPhaseScanning => '스캐닝';

  @override
  String get batchConvertPhaseRunning => '변환 중';

  @override
  String get batchConvertPhaseCompleted => '완전한';

  @override
  String get batchConvertPipelineIdle => '가져오기 -> 스캔 -> 변환 -> 완료';

  @override
  String get batchConvertPipelineScanning => '폴더 스캔 -> 대기열 구축';

  @override
  String get batchConvertPipelineRunning => '각 항목 변환 -> 상태 업데이트';

  @override
  String get batchConvertPipelineCompleted => '형식을 조정하거나 다시 가져오기';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return '취소됨, $success 성공, $failure 실패';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '$success 성공, $failure 실패';
  }

  @override
  String get batchConvertHintNoQueue => '변환을 시작하려면 파일이나 폴더를 추가하세요.';

  @override
  String get batchConvertHintReady => '대기열이 준비되었습니다';

  @override
  String get batchConvertMetricWaiting => '대기 중';

  @override
  String get batchConvertDropUnsupported => '일괄 변환 페이지에서는 가사 파일이나 폴더만 허용됩니다.';

  @override
  String batchConvertDropFailed(String detail) {
    return '삭제 처리 실패: $detail';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return '$fileName 변환 중';
  }

  @override
  String get batchConvertProgressItemSuccess => '변환됨';

  @override
  String get batchConvertProgressItemFailure => '실패한';

  @override
  String get batchConvertProgressPreparingConversion => '변환 준비 중...';

  @override
  String get batchConvertProgressCancellingConversion => '변환 취소 중...';

  @override
  String get batchConvertProgressConversionCancelled => '전환이 취소되었습니다.';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return '변환 완료: $success 성공, $failure 실패';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return '변환 실패: $detail';
  }

  @override
  String get batchConvertProgressScanningFolders => '폴더 검색 중...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return '$directoryName 스캔 중';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return '$count 가사 파일을 찾았습니다.';
  }

  @override
  String get batchConvertProgressScanCancelled => '스캔이 취소되었습니다.';

  @override
  String get batchConvertProgressScanNoSupportedFiles => '지원되는 가사 파일이 없습니다.';

  @override
  String get batchConvertProgressScanCompleted => '스캔 완료';

  @override
  String get navSearch => '찾다';

  @override
  String get navLocalMatch => '지역 경기';

  @override
  String get navOpenLyrics => '가사 열기';

  @override
  String get navBatchConvert => '일괄 변환';

  @override
  String get navSettings => '설정';

  @override
  String get navAbout => '에 대한';

  @override
  String get commonSearch => '찾다';

  @override
  String get commonSource => '원천';

  @override
  String get searchKeywordHint => '키워드 입력';

  @override
  String get uiLoading => '로드 중...';

  @override
  String get uiLoadingStepFetching => '목록 및 미리보기를 가져오는 중...';

  @override
  String get uiEmpty => '데이터 없음';

  @override
  String get uiNoMoreResult => '더 이상 결과가 없습니다.';

  @override
  String get searchInitialResultTitle => '검색을 시작하려면 키워드를 입력하세요';

  @override
  String get searchInitialResultDescription => '위에서 소스를 선택하고 검색을 실행하세요.';

  @override
  String get searchResultTitle => '검색결과';

  @override
  String get searchResultReturn => '뒤쪽에';

  @override
  String get searchPreviewTitle => '가사 미리보기';

  @override
  String get searchPreviewLangsLabel => '언어';

  @override
  String get searchPreviewSongIdLabel => '노래 ID';

  @override
  String get searchPreviewPlaceholder => '먼저 노래나 가사 항목을 선택하세요.';

  @override
  String get searchPreviewNoLanguage => '가사 언어를 하나 이상 선택하세요.';

  @override
  String get searchPreviewNoContent => '미리 볼 수 있는 콘텐츠가 없습니다.';

  @override
  String get searchPreviewLoading => '가사 로드 중...';

  @override
  String get searchFormatLabel => '가사 형식';

  @override
  String get searchTranslateLyrics => '가사 번역';

  @override
  String get searchResizeWorkspacePanes => '검색 결과 및 가사 미리보기 크기 조정';

  @override
  String get searchSavePreviewToDirectory => '폴더에 저장';

  @override
  String get searchSavePreviewToFile => '파일에 저장';

  @override
  String get searchSavePreviewToTag => '태그에 미리보기 저장';

  @override
  String get searchSaveListLyrics => '앨범/재생 목록 가사 저장';

  @override
  String get searchSaveListLyricsCancel => '일괄 저장 취소';

  @override
  String get searchSelectSavePath => '폴더 저장을 선택하세요';

  @override
  String get searchBatchSaveProgressTitle => '일괄 저장 진행';

  @override
  String get searchBatchSaveProgressPreparing => '일괄 저장 준비 중...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return '$songName 가사를 가져오는 중...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count 노래';
  }

  @override
  String get searchTableStatusAutoFetching => '자동 가져오는 중...';

  @override
  String get searchTableStatusSearching => '수색...';

  @override
  String get searchTableStatusFetchingSongList => '노래 목록을 가져오는 중...';

  @override
  String get searchTableStatusNoResults => '일치하는 결과가 없습니다';

  @override
  String get searchTableStatusEmptyList => '목록이 비어 있습니다.';

  @override
  String get searchTableStatusUnsupportedSearchType =>
      '선택한 소스는 이 검색 유형을 지원하지 않습니다.';

  @override
  String get searchTableStatusSearchFailed => '검색 실패';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return '검색 실패: $detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return '자동 가져오기 실패: $detail';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return '노래 목록을 가져오지 못했습니다: $detail';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable =>
      '일부 소스를 사용할 수 없습니다. 사용 가능한 결과 표시 중';

  @override
  String get searchTableStatusLoadMoreFailed => '일부 소스에서 더 많은 결과를 로드하지 못했습니다.';

  @override
  String get searchSourceFailureDetailsTitle => '검색 오류 세부정보';

  @override
  String get searchSourceFailureRequest => '요청 실패';

  @override
  String get searchSourceFailureTimeout => '요청 시간이 초과되었습니다.';

  @override
  String get searchSourceFailureParameters => '잘못된 매개변수';

  @override
  String get searchSourceFailureUnsupported => '지원되지 않는 작업';

  @override
  String get searchSourceFailureUnknown => '알 수 없는 오류';

  @override
  String get searchResultLoadingMore => '더 많은 결과 로드 중...';

  @override
  String get searchResultLoadMoreFailed =>
      '자동 로드에 실패했습니다. 나머지 결과를 계속 로드하려면 다시 시도하세요.';

  @override
  String get searchResultScrollForMore => '더 많은 결과를 자동으로 로드하려면 아래로 스크롤하세요.';

  @override
  String get tableSavePath => '경로 저장';

  @override
  String get settingsSectionSave => '구하다';

  @override
  String get settingsSectionLyrics => '가사';

  @override
  String get settingsSectionDesktopLyrics => '데스크탑 가사';

  @override
  String get settingsSectionTranslate => '번역하다';

  @override
  String get settingsSectionSearch => '찾다';

  @override
  String get settingsSectionApp => '앱';

  @override
  String get settingsSectionTools => '도구 및 데이터';

  @override
  String get settingsSectionSaveSummary => '저장 경로, 파일 이름 템플릿 및 ID3 버전';

  @override
  String get settingsSectionSearchSummary =>
      '집계 검색 및 로컬 일치를 위한 기본 가사 소스를 선택하세요.';

  @override
  String get settingsSectionDesktopLyricsSummary =>
      '데스크탑 가사 자동 가져오기, 표시 언어, 모양 및 새로 고침 빈도.';

  @override
  String get settingsSectionLyricsSummary => '로컬 매칭 동작 및 가사 파일 내보내기 형식.';

  @override
  String get settingsSectionTranslateSummary => '번역 소스, 대상 언어 및 조건부 필드';

  @override
  String get settingsSectionAppSummary => '언어, 테마, 로그, 업데이트 정책';

  @override
  String get settingsSectionToolsSummary => '데스크탑 도구, 로그 폴더 및 캐시 정리';

  @override
  String get settingsTranslateSourceBing => '빙 번역';

  @override
  String get settingsTranslateSourceGoogle => '구글 번역';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI 호환 API';

  @override
  String get settingsLangSimplifiedChinese => '중국어 간체';

  @override
  String get settingsLangTraditionalChinese => '중국어 번체';

  @override
  String get settingsLangEnglish => '영어';

  @override
  String get settingsLangJapanese => '일본어';

  @override
  String get settingsLangKorean => '한국인';

  @override
  String get settingsLangSpanish => '스페인 사람';

  @override
  String get settingsLangFrench => '프랑스 국민';

  @override
  String get settingsLangPortuguese => '포르투갈 인';

  @override
  String get settingsLangGerman => '독일 사람';

  @override
  String get settingsLangRussian => '러시아인';

  @override
  String get settingsAppLanguageAuto => '자동';

  @override
  String get settingsColorSchemeAuto => '팔로우 시스템';

  @override
  String get settingsColorSchemeLight => '빛';

  @override
  String get settingsColorSchemeDark => '어두운';

  @override
  String get settingsDesktopGradientColors => '그라데이션 색상';

  @override
  String get settingsDesktopPlayedColors => '재생된 색상';

  @override
  String get settingsDesktopUnplayedColors => '재생되지 않은 색상';

  @override
  String get settingsAddColor => '색상 추가';

  @override
  String get settingsEditColor => '색상 편집';

  @override
  String get settingsDeleteColor => '색상 삭제';

  @override
  String get settingsBackToSections => '설정 섹션으로 돌아가기';

  @override
  String get settingsAvailablePlaceholders => '사용 가능한 자리 표시자';

  @override
  String get settingsPlaceholderTitleArtist => '제목: %<title> 아티스트: %<artist>';

  @override
  String get settingsPlaceholderAlbumId => '앨범: %<album> 노래/가사 ID: %<id>';

  @override
  String get settingsPlaceholderLangs => '언어 유형: %<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return '현재 템플릿: $template';
  }

  @override
  String get settingsTranslateSourceLabel => '번역 소스';

  @override
  String get settingsTranslateTargetLabel => '대상 언어';

  @override
  String get settingsOpenAiProfileLabel => '프리셋';

  @override
  String get settingsOpenAiProfileHelper =>
      '내장 공급자는 기본 URL을 자동으로 채웁니다. API 키와 모델을 구성해야 합니다.';

  @override
  String get settingsAppLanguageLabel => '인터페이스 언어';

  @override
  String get settingsColorSchemeLabel => '테마 모드';

  @override
  String get settingsLogLevelLabel => '로그 수준';

  @override
  String get settingsLogLevelHelper =>
      '일반적인 사용을 위해 INFO를 보관하세요. TRACE 및 DEBUG는 더 자세한 내용을 기록하고 더 큰 로그를 생성합니다.';

  @override
  String get settingsAutoCheckUpdateLabel => '업데이트 자동 확인';

  @override
  String get settingsRestoreDefaultsWarning =>
      '기본값을 복원하면 구성이 즉시 작성됩니다. 계속하기 전에 확인해 주세요.';

  @override
  String get settingsRestoreAllTitle => '기본 설정 복원';

  @override
  String get settingsRestoreAllContent => '이렇게 하면 모든 설정이 복원되고 즉시 구성에 기록됩니다.';

  @override
  String get settingsRestoreAllAction => '기본 설정 복원';

  @override
  String get settingsOpenAssociationManager => '가사협회 매니저 열기';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      '노래 및 가사 연결을 관리하려면 다음 설정 페이지를 엽니다.';

  @override
  String get settingsOpenLogDirectory => '로그 디렉토리 열기';

  @override
  String get settingsOpenLogDirectorySubtitle => '런타임 로그 및 문제 해결 파일을 봅니다.';

  @override
  String get settingsClearCache => '캐시 지우기';

  @override
  String get settingsClearCacheSubtitle => '구성 파일을 변경하지 않고 검색 및 번역 캐시를 지웁니다.';

  @override
  String get settingsClearCacheContent =>
      '캐시를 지운 후 나중에 검색 및 번역할 때 데이터를 다시 요청할 수 있습니다.';

  @override
  String get settingsRestoreSectionTitle => '이 섹션 복원';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return '“$sectionTitle” 섹션의 설정만 복원됩니다. 다른 섹션은 변경되지 않습니다.';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return '$sectionTitle의 기본값 복원';
  }

  @override
  String get settingsDefaultSavePathHelper => '플랫폼 기본 음악 디렉터리를 사용하려면 비워 두세요.';

  @override
  String get settingsChooseFolder => '폴더 선택';

  @override
  String get settingsLyricsFileNameFormat => '가사 파일 이름 템플릿';

  @override
  String get settingsLyricsFileNameFormatHelper =>
      '아래 자리 표시자를 사용하여 저장된 파일 이름을 구성하세요.';

  @override
  String get settingsId3Version => 'ID3 버전';

  @override
  String get settingsId3VersionHelper =>
      '오디오 태그에 작성된 가사에만 영향을 미칩니다. 확실하지 않은 경우 v2.3을 유지하세요.';

  @override
  String get settingsSearchSourcesTitle => '집계 검색 소스';

  @override
  String get settingsSearchSourcesDescription =>
      '검색에서 집계를 사용할 때 확인된 소스가 쿼리됩니다. 결과 그룹화 및 자동 일치 시 목록에서 상위에 있는 소스가 첫 번째 순위를 차지합니다. 로컬 일치에서는 기본적으로 이 목록을 사용합니다.';

  @override
  String get settingsReorderPriorityHint => '우선순위를 변경하려면 드래그하세요.';

  @override
  String get settingsReorderOrderHint => '순서를 변경하려면 드래그하세요.';

  @override
  String get settingsDefaultLanguage => '기본 표시 언어';

  @override
  String get settingsDefaultLanguageDescription =>
      '데스크탑 가사에 기본적으로 표시되는 언어를 선택한 다음 드래그하여 표시 순서를 변경하세요.';

  @override
  String get settingsDesktopAutoFetchSources => '자동 가져오기 소스';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      '데스크톱 가사에 연결된 가사가 없으면 소스는 위에서 아래로 시도됩니다.';

  @override
  String get settingsFont => '세례반';

  @override
  String get settingsFollowSystemFont => '시스템 글꼴 따르기';

  @override
  String get settingsFontSizeByResize => '데스크탑 가사 창의 크기를 조정하여 기본 글꼴 크기를 조정하세요.';

  @override
  String get settingsPanelFontSize => '가사 패널 글꼴 크기';

  @override
  String get settingsAdaptiveRefreshRate => '적응형 재생률';

  @override
  String get settingsAdaptiveRefreshRateSubtitle =>
      '가사 애니메이션 상태에 따라 새로 고침 주기를 자동으로 선택합니다.';

  @override
  String get settingsFixedRefreshRate => '고정 새로 고침 빈도';

  @override
  String get settingsShowFurigana => '후리가나 표시';

  @override
  String get settingsLyricsMatchBehavior => '일치하는 동작';

  @override
  String get settingsLyricsMatchBehaviorDescription =>
      '로컬 일치 및 Kugou 가사 후보에 대한 기본 처리를 설정합니다.';

  @override
  String get settingsLyricsExport => 'LRC 수출';

  @override
  String get settingsLyricsExportDescription =>
      '가사 파일을 저장할 때 사용되는 언어 순서와 LRC 타임스탬프 형식을 설정합니다.';

  @override
  String get settingsDisplayOrder => '언어 순서 내보내기';

  @override
  String get settingsDisplayOrderDescription =>
      '내보낸 파일에서 원본, 번역, 로마자 표기 가사를 드래그하여 정렬하세요.';

  @override
  String get settingsSkipInstrumental => '악기 트랙 건너뛰기';

  @override
  String get settingsSkipInstrumentalSubtitle =>
      '로컬 일치가 악기 트랙을 식별하는 경우 가사를 저장하지 마십시오.';

  @override
  String get settingsAutoSelectKugou => 'Kugou 후보 자동 선택';

  @override
  String get settingsAutoSelectKugouSubtitle =>
      '검색에서 Kugou 노래를 열 때 가장 적합한 가사 후보를 자동으로 선택합니다.';

  @override
  String get settingsAddLrcEndTimestamp => 'LRC를 내보낼 때 종료 타임스탬프 추가';

  @override
  String get settingsAddLrcEndTimestampSubtitle =>
      '한 줄씩 LRC에만 영향을 미치고 필요할 때 줄 끝 타임스탬프를 씁니다.';

  @override
  String get settingsMillisecondsDigits => '밀리초 숫자';

  @override
  String get settingsMillisecondsDigitsHelper =>
      '100분의 1초는 두 자리, 전체 밀리초를 유지하려면 세 자리를 사용하세요.';

  @override
  String settingsDigitsValue(int value) {
    return '$value 자리';
  }

  @override
  String get settingsLastRefStyle => '마지막 언어 라인 타임스탬프';

  @override
  String get settingsLastRefStyleHelper =>
      '다중 언어 라인별 LRC의 경우 현재 라인 시간을 사용하거나 마지막 언어 라인의 다음 라인 이전 1밀리초를 사용합니다.';

  @override
  String get settingsLastRefCurrentLine => '현재 회선 시간 사용';

  @override
  String get settingsLastRefNextLine => '다음 줄 앞에 1밀리초 사용';

  @override
  String get settingsTagInfoSource => '태그 정보 소스';

  @override
  String get settingsTagInfoLyricsSource => '가사 소스';

  @override
  String get settingsTagInfoSongInfo => '노래 정보';

  @override
  String get settingsNoticeDefaultSavePathUpdated => '기본 저장 경로가 업데이트되었습니다.';

  @override
  String get settingsNoticeDefaultSavePathRestored => '기본 저장 경로가 복원되었습니다.';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated =>
      '가사 파일 이름 템플릿이 업데이트되었습니다.';

  @override
  String get settingsNoticeId3VersionUpdated => 'ID3 버전이 업데이트되었습니다.';

  @override
  String get settingsNoticeLyricsLangOrderEmpty => '가사 언어 순서는 비워둘 수 없습니다.';

  @override
  String get settingsNoticeLyricsLangOrderUpdated => '가사 언어 순서가 업데이트되었습니다.';

  @override
  String get settingsNoticeSkipInstUpdated => '악기 건너뛰기 정책이 업데이트되었습니다.';

  @override
  String get settingsNoticeAutoSelectUpdated => '자동 선택 정책이 업데이트되었습니다.';

  @override
  String get settingsNoticeAddEndTimestampUpdated => '종료 타임스탬프 정책이 업데이트되었습니다.';

  @override
  String get settingsNoticeMsDigitsUpdated => '밀리초 자릿수가 업데이트되었습니다.';

  @override
  String get settingsNoticeLastRefStyleUpdated => '마지막 줄 시간 스타일이 업데이트되었습니다.';

  @override
  String get settingsNoticeTagInfoSourceUpdated => '태그 정보 소스가 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopSourcesEmpty => '데스크톱 가사 소스는 비워둘 수 없습니다.';

  @override
  String get settingsNoticeDesktopSourcesUpdated => '데스크톱 가사 소스가 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty =>
      '데스크톱 기본 언어는 비워둘 수 없습니다.';

  @override
  String get settingsNoticeDesktopLangsUpdated => '데스크톱 가사 언어 설정이 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated => '데스크탑 가사 글꼴이 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated => '새로고침 빈도가 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated => '재생된 색상이 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated =>
      '재생되지 않은 색상이 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopFontSizeUpdated =>
      '데스크톱 가사 글꼴 크기가 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated =>
      '데스크탑 패널 글꼴 크기가 업데이트되었습니다.';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated =>
      '후리가나 표시 정책이 업데이트되었습니다.';

  @override
  String get settingsNoticeTranslateSourceUpdated => '번역 소스가 업데이트되었습니다.';

  @override
  String get settingsNoticeTranslateTargetLangUpdated => '번역 대상 언어가 업데이트되었습니다.';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'OpenAI 사전 설정이 업데이트되었습니다.';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated => 'OpenAI 기본 URL이 업데이트되었습니다.';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'OpenAI API 키가 업데이트되었습니다.';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'OpenAI 모델 업데이트';

  @override
  String get settingsNoticeSearchSourcesEmpty => '집계 검색 소스는 비워둘 수 없습니다.';

  @override
  String get settingsNoticeSearchSourcesUpdated => '집계 검색 소스가 업데이트되었습니다.';

  @override
  String get settingsNoticeAppLanguageUpdated => '인터페이스 언어가 업데이트되었습니다.';

  @override
  String get settingsNoticeAppColorSchemeUpdated => '테마 모드가 업데이트되었습니다.';

  @override
  String get settingsNoticeAppLogLevelUpdated => '로그 수준이 업데이트되었습니다.';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated =>
      '업데이트 자동 확인 설정이 업데이트되었습니다.';

  @override
  String get settingsNoticeSectionNoRestorableConfig =>
      '이 섹션에는 복원 가능한 구성 항목이 없습니다.';

  @override
  String get settingsNoticeSectionDefaultsRestored => '현재 섹션 기본값이 복원되었습니다.';

  @override
  String get settingsNoticeAllDefaultsRestored => '애플리케이션 설정이 기본값으로 복원됨';

  @override
  String get settingsNoticeAssociationManagerOpened => '가사협회 관리자 개설';

  @override
  String get settingsNoticeLogDirectoryOpened => '로그 디렉터리가 열렸습니다.';

  @override
  String get settingsNoticeLogDirectoryOpenFailed => '로그 디렉터리를 열지 못했습니다.';

  @override
  String get settingsNoticeCacheCleared => '캐시가 삭제되었습니다.';

  @override
  String get settingsNoticeCacheClearFailed => '캐시를 지우지 못했습니다.';

  @override
  String get settingsNoticeConfigWriteFailed => '설정을 쓰지 못했습니다.';

  @override
  String get settingsCurrentSavePathLabel => '기본 저장 경로';

  @override
  String get aboutLoadFailed => '메타데이터에 대한 로드에 실패했습니다.';

  @override
  String get aboutActionOpenRepository => 'GitHub 레포';

  @override
  String get aboutActionCheckUpdate => '업데이트 확인';

  @override
  String get aboutHeroHeadline => '정확한 가사를 위해 제작됨';

  @override
  String get aboutHeroDescription =>
      'LDDC는 검색, 변환, 데스크톱 가사 및 일괄 작업 흐름을 하나의 효율적인 화면으로 가져오므로 가사 찾기, 구성 및 사용이 빠르고 집중적으로 이루어집니다.';

  @override
  String get aboutLinksSectionTitle => '빠른 링크';

  @override
  String get aboutLinksSectionDescription =>
      '피드백 채널, 릴리스 노트 또는 라이선스 세부 정보를 원할 때 이 링크를 사용하세요.';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return '저작권 (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return '$license에 따라 라이센스가 부여되었습니다.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'GitHub 저장소';

  @override
  String get aboutLinkIssueTrackerTitle => '이슈 트래커';

  @override
  String get aboutLinkIssueTrackerDescription => '버그, UX 격차 및 기능 요청을 보고하세요.';

  @override
  String get aboutLinkLicenseTitle => '특허';

  @override
  String get aboutLinkLicenseDescription => '현재 오픈소스 라이선스를 검토하세요.';

  @override
  String get aboutLinkChangelogTitle => '릴리스 노트';

  @override
  String get aboutLinkChangelogDescription => '게시된 버전과 해당 변경 사항 요약을 확인하세요.';

  @override
  String get aboutExternalLinksUnavailable => '이 플랫폼에서는 외부 링크 열기가 지원되지 않습니다.';

  @override
  String get aboutCheckUpdateUnavailable => '이 플랫폼에서는 업데이트 확인이 지원되지 않습니다.';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes => '출시 노트 페이지를 열었습니다.';

  @override
  String get aboutCheckUpdateUpToDate => '이미 최신 버전을 사용하고 있습니다.';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return '새 버전이 발견되었습니다: $version. 자세한 내용을 보려면 릴리스 노트 페이지를 여세요.';
  }

  @override
  String get aboutCheckUpdateFailed => '업데이트를 확인하지 못했습니다. 나중에 다시 시도해 주세요.';

  @override
  String aboutActionOpenedLink(String title) {
    return '$title 개설됨';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return '$title을(를) 열지 못했습니다.';
  }

  @override
  String get actionConfirm => '확인하다';

  @override
  String get libraryLinkManagerTitle => '가사협회 매니저';

  @override
  String get libraryLinkManagerReturnToSettings => '설정으로 돌아가기';

  @override
  String get libraryLinkManagerRefresh => '새로 고치다';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return '선택 항목 삭제($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => '모두 삭제';

  @override
  String get libraryLinkManagerClearInvalid => '잘못된 데이터 지우기';

  @override
  String get libraryLinkManagerChangeDirectory => '일괄 변경 디렉토리';

  @override
  String get libraryLinkManagerBackupToJson => 'JSON으로 백업';

  @override
  String get libraryLinkManagerRestoreFromJson => 'JSON에서 복원';

  @override
  String get libraryLinkManagerRestoreAction => '복원하다';

  @override
  String get libraryLinkManagerExportLyrics => '가사 내보내기';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '$totalCount 레코드 · $selectedCount 선택됨';
  }

  @override
  String get libraryLinkManagerSearchHint => '노래, 아티스트, 앨범 또는 경로 검색';

  @override
  String get libraryLinkManagerClearSearch => '검색 지우기';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '$totalCount 일치 · $selectedCount 선택됨';
  }

  @override
  String get libraryLinkManagerEmpty => '가사 링크 기록이 없습니다';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return '가사 링크 레코드를 로드하지 못했습니다: $error';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess => '선택한 가사 링크를 삭제했습니다.';

  @override
  String get libraryLinkManagerDeleteAllConfirm => '모든 가사 링크 기록을 삭제하시겠습니까?';

  @override
  String get libraryLinkManagerDeleteAllSuccess => '가사 링크 기록을 모두 삭제했습니다.';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return '$count 잘못된 레코드를 삭제했습니다.';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return '디렉터리 재작성 후 $count 레코드가 업데이트되었습니다.';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return '$path에 백업된 가사 링크 데이터';
  }

  @override
  String get libraryLinkManagerRestoreConfirm =>
      '복원하면 현재의 모든 가사 링크 레코드를 덮어쓰게 됩니다. 계속하다?';

  @override
  String get libraryLinkManagerRestoreSuccess => '가사 링크 데이터가 복원되었습니다.';

  @override
  String get libraryLinkManagerInvalidBackupFormat => '잘못된 백업 파일 형식';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return '$count 가사 파일을 내보냈습니다.';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return '작업 실패: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => '제목 없는 노래';

  @override
  String get libraryLinkManagerUnknownArtist => '알 수 없는 아티스트';

  @override
  String get libraryLinkManagerUnknownAlbum => '알 수 없는 앨범';

  @override
  String get libraryLinkManagerSongPathLabel => '노래 경로';

  @override
  String get libraryLinkManagerSongPathEmpty => '녹음된 노래 경로가 없습니다.';

  @override
  String get libraryLinkManagerLyricsPathLabel => '가사 경로';

  @override
  String get libraryLinkManagerLyricsPathEmpty => '연결된 가사 없음';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return '$track 추적';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return '트랙 번호: $track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => '없음';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return '오프셋 $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return '가사 오프셋: $offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return '언어 $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return '가사 언어: $langs';
  }

  @override
  String get libraryLinkManagerInstrumental => '조격';

  @override
  String get libraryLinkManagerInstrumentalTooltip => '이 노래는 악기로 표시되어 있습니다.';

  @override
  String get libraryLinkManagerDisableAutoSearch => '자동 검색 비활성화';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip =>
      '이 노래에 대한 자동 검색이 비활성화되었습니다.';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return '기타 구성 $count';
  }

  @override
  String get libraryLinkManagerDefaultConfig => '기본 구성';

  @override
  String get libraryLinkManagerDefaultConfigTooltip =>
      '이 레코드에는 노래 수준 재정의 구성이 저장되지 않았습니다.';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return '열기 실패: $detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable => '가사 파일을 사용할 수 없습니다';

  @override
  String get openLyricsNoticeSongFileUnavailable => '노래 파일을 사용할 수 없습니다.';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics => '이 노래에는 읽을 수 있는 내장 가사가 없습니다.';

  @override
  String get openLyricsNoticeAlreadyConverted => '이 가사는 이미 변환되었습니다.';

  @override
  String get openLyricsNoticeEmptyLyrics => '가사 내용은 비워둘 수 없습니다.';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return '변환 실패: $detail';
  }

  @override
  String get openLyricsNoticeConvertFirst => '먼저 가사를 변환하세요';

  @override
  String get openLyricsNoticeNoLyricsToSave => '저장할 가사가 없습니다';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return '저장된 가사: $detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return '저장 실패: $detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => '먼저 노래 파일을 엽니다.';

  @override
  String get openLyricsNoticeAudioTagUnsupported => '이 플랫폼은 노래 태그를 작성할 수 없습니다';

  @override
  String get openLyricsDropUnsupportedItem =>
      'Open Lyrics에서는 가사 파일이나 오디오 파일을 허용합니다.';

  @override
  String get openLyricsPreviewTitle => '시사';

  @override
  String get openLyricsPreviewRawText => '원시 텍스트';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return '가사 언어 · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => '로드되지 않음';

  @override
  String get openLyricsPreviewStateRawLoaded => '변환 준비 완료';

  @override
  String get openLyricsPreviewStateConverted => '변환됨';

  @override
  String get openLyricsPreviewEmptyNoInput => '가사 파일이나 노래 파일을 먼저 열어주세요';

  @override
  String get openLyricsActionOpening => '열기...';

  @override
  String get openLyricsActionOpenLyricsFile => '가사 파일 열기';

  @override
  String get openLyricsActionOpenSongFile => '노래 파일 열기';

  @override
  String get openLyricsActionConvertFormat => '형식 변환';

  @override
  String get openLyricsActionSaveLyrics => '가사 저장';

  @override
  String get openLyricsActionSaveToTag => '노래 태그에 저장';

  @override
  String get openLyricsActionTranslate => '가사 번역';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return '현재 내보내기 형식: $format · 태그를 쓸 수 있습니다.';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return '현재 내보내기 형식: $format · 파일 내보내기 전용';
  }

  @override
  String get searchLyricsSelectorTitle => '가사 선택';

  @override
  String get searchLyricsSelectorOpenLocal => '로컬 가사 열기';

  @override
  String get searchLyricsSelectorSelect => '가사 선택';

  @override
  String get searchLyricsSelectorDescription =>
      '데스크톱 가사를 보려면 온라인 또는 로컬 가사를 선택하세요.';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return '로컬 가사를 열지 못했습니다: $detail';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => '가사를 먼저 선택하세요';

  @override
  String get searchLyricsSelectorSelectFailed =>
      '가사를 선택하지 못했습니다. 나중에 다시 시도해 보세요';

  @override
  String get searchDropUnsupportedItem =>
      '검색에서는 구문 분석 가능한 노래 항목 또는 오디오 파일을 허용합니다.';

  @override
  String get searchNoticePartialSourcesFailed =>
      '일부 소스가 실패했습니다. 다른 소스의 결과가 표시됩니다.';

  @override
  String get searchNoticeAllSourcesFailed => '모든 검색 소스가 실패했습니다.';

  @override
  String get searchNoticeLoadMoreFailed => '일부 소스에서 더 많은 결과를 로드하지 못했습니다.';

  @override
  String get searchNoticeDirectoryPickerUnsupported =>
      '이 플랫폼에서는 디렉터리 선택이 지원되지 않습니다.';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return '$detail에 대한 가사를 가져왔습니다.';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return '자동 가져오기 실패: $detail';
  }

  @override
  String get searchNoticeSelectedSongUnavailable => '사용 가능한 노래 파일이 선택되지 않았습니다.';

  @override
  String get searchNoticeFilePickerUnsupported =>
      '이 플랫폼에서는 노래 파일 선택이 지원되지 않습니다.';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return '노래를 열지 못했습니다: $detail';
  }

  @override
  String get searchNoticeDroppedSongUnavailable => '삭제된 노래 파일을 사용할 수 없습니다.';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return '삭제된 노래를 해결하지 못했습니다: $detail';
  }

  @override
  String get searchNoticeEmptyKeyword => '검색 키워드를 입력하세요';

  @override
  String get searchNoticeGetLyricsFirst => '가사를 먼저 받아보세요';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return '저장된 가사: $detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported => '이 플랫폼에서는 파일 저장이 지원되지 않습니다.';

  @override
  String get searchNoticeFilePickerForTagUnsupported =>
      '이 플랫폼에서는 노래 태그 파일 선택이 지원되지 않습니다.';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return '파일 선택 실패: $detail';
  }

  @override
  String get searchNoticeBatchCancelling => '일괄 저장 취소 중...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst => '먼저 앨범이나 재생목록을 선택하세요.';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage =>
      '가사 언어를 하나 이상 선택하세요.';

  @override
  String get searchNoticeNoSongsToSave => '저장할 노래가 없습니다.';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return '일괄 저장 취소됨: $saved 저장됨, $failed 실패, $skipped 건너뛰음';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return '일괄 저장 완료: $saved 저장됨, $failed 실패, $skipped 건너뛰기';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return '일괄 저장 실패: $detail';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates =>
      '여러 가사 후보가 발견되었습니다. 계속하려면 하나를 선택하세요.';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return '가사를 가져오지 못했습니다: $detail';
  }

  @override
  String get searchNoticeSelectSavePathFirst => '먼저 저장 경로를 선택하세요';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return '디렉터리 선택 실패: $detail';
  }

  @override
  String get searchNoticePreviewLoading => '가사가 아직 로드 중입니다.';

  @override
  String get searchNoticePreviewNoLanguage => '가사 언어를 하나 이상 선택하세요.';

  @override
  String get searchNoticePreviewNoContent => '현재 가사에는 미리 볼 수 있는 콘텐츠가 없습니다.';

  @override
  String get searchNoticePreviewNoSelection => '먼저 가사 다운로드 및 미리보기';

  @override
  String get desktopWindowActionSelectLyrics => '가사 선택';

  @override
  String get desktopWindowActionMarkInstrumental => '도구로 표시';

  @override
  String get desktopWindowActionDisableAutoSearch => '이 노래에 대한 자동 검색 비활성화';

  @override
  String get desktopWindowActionUnlinkLyrics => '가사 연결 해제';

  @override
  String get desktopWindowActionAssociationManager => '가사협회 매니저';

  @override
  String get desktopWindowActionToggleFloating => '데스크탑 가사 표시 또는 숨기기';

  @override
  String get desktopWindowActionShowMainWindow => '기본 창 표시';

  @override
  String get desktopWindowActionClickThrough => '클릭연결';

  @override
  String get desktopWindowActionPrevious => '이전의';

  @override
  String get desktopWindowActionPlay => '놀다';

  @override
  String get desktopWindowActionPause => '정지시키다';

  @override
  String get desktopWindowActionNext => '다음';

  @override
  String get desktopWindowActionHide => '숨다';

  @override
  String get desktopTrayCurrentTarget => '현재 목표:';

  @override
  String get desktopTrayNoSelection => '없음';

  @override
  String get desktopTrayTargetInstance => '대상 인스턴스';

  @override
  String get desktopTrayInstance => '사례';

  @override
  String get desktopTrayExit => '출구';

  @override
  String get desktopWindowInfoInstrumental => '조격';

  @override
  String get desktopWindowControlConnectionLost =>
      '플레이어 연결이 끊어졌습니다. 작업이 수행되지 않았습니다.';

  @override
  String get desktopWindowClientDisconnected =>
      '플레이어 연결이 끊어졌습니다. 데스크톱 가사가 닫혔습니다.';
}
