// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'НРСД';

  @override
  String get commonWarning => 'Предупреждение';

  @override
  String get commonError => 'Ошибка';

  @override
  String get commonSuccess => 'Успех';

  @override
  String get commonFailed => 'Неуспешный';

  @override
  String get commonSkipped => 'Пропущено';

  @override
  String get commonTotal => 'Общий';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonConfirm => 'Подтверждать';

  @override
  String get commonRestoreDefault => 'Восстановить настройки по умолчанию';

  @override
  String get commonEnabled => 'Включено';

  @override
  String get commonDisabledByDefault => 'Отключено по умолчанию';

  @override
  String get commonFormat => 'Формат';

  @override
  String get commonOffset => 'Компенсировать';

  @override
  String get commonSaving => 'Сохранение...';

  @override
  String get commonAddFiles => 'Добавить файлы';

  @override
  String get commonClearQueue => 'Очистить очередь';

  @override
  String get commonUnsupportedOperation =>
      'Эта операция не поддерживается на этой платформе.';

  @override
  String get commonLyricsFileUnavailable =>
      'У этой записи пока нет файла с текстами песен, который можно было бы открыть.';

  @override
  String get commonAudioTagRequiresLrc =>
      'Тексты песен должны быть в формате LRC.';

  @override
  String commonLyricsLanguageTypeSummary(String language, String type) {
    return '$language ($type)';
  }

  @override
  String get commonTranslationCancelled => 'Перевод удален';

  @override
  String get commonCancelTranslation => 'Удалить перевод';

  @override
  String get commonTranslating => 'Перевод...';

  @override
  String commonTranslationProgress(int completed, int total) {
    return 'Перевод $completed/$total';
  }

  @override
  String commonOpenAiTranslationProgress(int completed, int total) {
    return 'Потоковая трансляция OpenAI: $completed / $total строк';
  }

  @override
  String get commonTranslationCompleted => 'Перевод завершен';

  @override
  String get commonLyricsSaved => 'Текст сохранен.';

  @override
  String commonDropFailed(String detail) {
    return 'Не удалось удалить: $detail';
  }

  @override
  String commonSelectSaveDirectoryFailed(String detail) {
    return 'Не удалось выбрать каталог для сохранения: $detail.';
  }

  @override
  String commonOpenSaveDirectoryFailed(String detail) {
    return 'Не удалось открыть каталог сохранения: $detail.';
  }

  @override
  String commonTranslationFailed(String detail) {
    return 'Не удалось выполнить перевод: $detail.';
  }

  @override
  String commonLyricsSaveFailed(String detail) {
    return 'Не удалось сохранить текст: $detail.';
  }

  @override
  String get appErrorUnknown => 'Произошла неизвестная ошибка.';

  @override
  String get appErrorOperationTimeout =>
      'Время операции истекло. Пожалуйста, повторите попытку позже.';

  @override
  String get appErrorNetworkUnavailable =>
      'Сеть недоступна. Пожалуйста, проверьте ваше соединение.';

  @override
  String get appErrorInvalidPayload => 'Неверный формат данных.';

  @override
  String get appErrorUnsupportedOperation => 'Эта операция не поддерживается.';

  @override
  String get appErrorPermissionDenied =>
      'У вас нет разрешения на выполнение этой операции.';

  @override
  String get appErrorIoFailure => 'Ошибка чтения или записи файла.';

  @override
  String get appErrorLyricsRequestFailed => 'Не удалось запросить текст песни.';

  @override
  String get appErrorLyricsNotFound => 'Тексты песен не найдены.';

  @override
  String get appErrorLyricsProcessing => 'Не удалось обработать текст.';

  @override
  String get appErrorLyricsDecrypt => 'Не удалось расшифровать текст.';

  @override
  String get appErrorLyricsFormatUnsupported =>
      'Неподдерживаемый формат текста.';

  @override
  String get appErrorDecoding => 'Декодирование не удалось.';

  @override
  String get appErrorSongInfoRead => 'Не удалось прочитать информацию о песне.';

  @override
  String get appErrorUnsupportedFileType => 'Неподдерживаемый формат файла.';

  @override
  String get appErrorDragDropInvalid => 'Неверные данные перетаскивания.';

  @override
  String get appErrorTranslateFailed => 'Перевод не удался.';

  @override
  String get appErrorApiParamsInvalid => 'Параметры запроса недействительны.';

  @override
  String get appErrorApiRequestFailed => 'Запрос API не выполнен.';

  @override
  String get appErrorAutoFetchUnknown =>
      'Автоматическое сопоставление не удалось из-за неизвестной ошибки.';

  @override
  String get appErrorNotEnoughInfo => 'Недостаточно информации для поиска.';

  @override
  String get appErrorIpcInvalidLength => 'Длина сообщения IPC недействительна.';

  @override
  String get appErrorIpcUnsupportedTask => 'Задача IPC не поддерживается.';

  @override
  String get appErrorIpcInstanceNotFound => 'Экземпляр IPC не существует.';

  @override
  String get appErrorIpcPanelNotFound => 'Панель IPC не существует.';

  @override
  String get appErrorIpcInvalidWindowId => 'Дескриптор окна недействителен.';

  @override
  String get appErrorIpcEmbedUnsupported =>
      'Встроенный режим не поддерживается на этой платформе.';

  @override
  String get appErrorActionRetryNetwork =>
      'Пожалуйста, проверьте сеть и повторите попытку.';

  @override
  String get appErrorActionCheckPayload =>
      'Пожалуйста, проверьте формат входных данных.';

  @override
  String get appErrorActionChangeFormat =>
      'Пожалуйста, используйте поддерживаемый файл или формат.';

  @override
  String get appErrorActionDetachedMode =>
      'Пожалуйста, вернитесь в режим отсоединения.';

  @override
  String get actionRetry => 'Повторить попытку';

  @override
  String get actionViewDetails => 'Посмотреть детали';

  @override
  String get actionCancel => 'Отмена';

  @override
  String get sourceAggregate => 'Совокупный';

  @override
  String get sourceQQMusic => 'QQ Музыка';

  @override
  String get sourceKugou => 'Куго Музыка';

  @override
  String get sourceNetease => 'Нетиз Музыка';

  @override
  String get sourceLrclib => 'Лрклиб';

  @override
  String get sourceLocal => 'Местный';

  @override
  String get lyricOriginal => 'Оригинал';

  @override
  String get lyricTranslation => 'Перевод';

  @override
  String get lyricRomanized => 'романизированный';

  @override
  String get lyricsFormatVerbatimLrc => 'Синхронизированный LRC';

  @override
  String get lyricsFormatLineByLineLrc => 'LRC с линейной синхронизацией';

  @override
  String get lyricsFormatEnhancedLrc => 'Улучшенный LRC (ESLyric)';

  @override
  String get lyricsFormatSrt => 'СТО';

  @override
  String get lyricsFormatAss => 'ЖОПА';

  @override
  String get lyricsTypeVerbatim => 'по времени';

  @override
  String get lyricsTypeLineByLine => 'по времени';

  @override
  String get lyricsTypePlainText => 'Обычный текст';

  @override
  String get searchSong => 'Песня';

  @override
  String get searchAlbum => 'Альбом';

  @override
  String get searchSongList => 'Плейлист';

  @override
  String get searchArtist => 'Художник';

  @override
  String get searchLyrics => 'Тексты песен';

  @override
  String get searchSongId => 'Идентификатор песни';

  @override
  String get localMatchIteratingFiles => 'Сканирование файлов...';

  @override
  String get localMatchProgressImportCompleted => 'Импорт завершен';

  @override
  String get localMatchProgressScanCompleted => 'Сканирование завершено';

  @override
  String get localMatchProgressScanFailed => 'Сканирование не удалось';

  @override
  String get localMatchProgressMatchCompleted => 'Матч завершен';

  @override
  String get localMatchProgressMatchFailed => 'Матч не удался';

  @override
  String get localMatchProgressPreparingMatch => 'Готовимся к матчу...';

  @override
  String get localMatchPreviewTagOnly => 'Пишите только теги';

  @override
  String get localMatchPreviewWriteTag => 'Пишите в теги';

  @override
  String get localMatchPreviewNoOutput => 'Выход не настроен';

  @override
  String get localMatchPreviewSongTagOnly => 'Только теги песен';

  @override
  String get localMatchPendingLyricsFileName =>
      'Ожидание совпадающей информации о тексте песни, чтобы определить имя файла';

  @override
  String localMatchPendingLyricsFileNameAt(String root) {
    return '$root / ожидание совпадающей информации о тексте песни для определения имени файла';
  }

  @override
  String get localMatchCalcSavePathFailed =>
      'Не удалось рассчитать путь сохранения.';

  @override
  String get localMatchNoticeBusyImportFiles =>
      'Задача запущена, поэтому импорт файлов сейчас невозможен.';

  @override
  String get localMatchNoticeSelectedFilesUnavailable =>
      'Выбранные файлы недоступны';

  @override
  String localMatchNoticeImportFilesFailed(String detail) {
    return 'Не удалось импортировать файлы: $detail.';
  }

  @override
  String get localMatchNoticeBusyImportDirectories =>
      'Задача выполняется, поэтому импорт каталогов сейчас невозможен.';

  @override
  String localMatchNoticeImportDirectoriesFailed(String detail) {
    return 'Не удалось импортировать каталоги: $detail.';
  }

  @override
  String get localMatchNoticeDroppedNoAccessibleFiles =>
      'Перенесенные данные не содержат доступных файлов.';

  @override
  String localMatchNoticeDroppedSongResolveFailed(String detail) {
    return 'Не удалось разрешить удаленную песню: $detail.';
  }

  @override
  String get localMatchNoticeImportCompletedWithErrors =>
      'Импорт завершен, но некоторые записи не удалось проанализировать.';

  @override
  String get localMatchNoticeSafTreeUnsupported =>
      'Доступ к дереву каталогов не поддерживается на этой платформе.';

  @override
  String get localMatchNoticeBusySwitchTree =>
      'Задача запущена, поэтому изменить дерево каталогов сейчас невозможно.';

  @override
  String localMatchNoticeSelectTreeFailed(String detail) {
    return 'Не удалось выбрать дерево каталогов: $detail.';
  }

  @override
  String get localMatchNoticeBusyClearQueue =>
      'Задача выполняется, поэтому очистить очередь сейчас невозможно.';

  @override
  String get localMatchNoticeSelectItemsToDelete =>
      'Выберите записи, которые нужно удалить в первую очередь';

  @override
  String get localMatchNoticeSelectItemsToSetRoot =>
      'Выберите записи перед установкой корневого каталога';

  @override
  String localMatchNoticeSelectedRootSkippedSongs(String detail) {
    return 'Эти песни находятся за пределами выбранного корня и были пропущены: $detail';
  }

  @override
  String localMatchNoticeSetRootFailed(String detail) {
    return 'Не удалось установить корневой каталог: $detail.';
  }

  @override
  String get localMatchNoticeSelectItemsToRestore =>
      'Выберите записи для восстановления в первую очередь';

  @override
  String get localMatchNoticeCancelling => 'Отмена текущей задачи...';

  @override
  String get localMatchNoticeValidationFailed =>
      'Сначала решите локальные требования к совпадению';

  @override
  String get localMatchNoticeSongDirectoryUnavailable =>
      'Эта запись не может открыть каталог песен.';

  @override
  String localMatchNoticeOpenSongDirectoryFailed(String detail) {
    return 'Не удалось открыть каталог песен: $detail.';
  }

  @override
  String get localMatchNoticeSaveDirectoryUnavailable =>
      'У этой записи пока нет каталога для сохранения, который можно было бы открыть.';

  @override
  String localMatchNoticeOpenLyricsFailed(String detail) {
    return 'Не удалось открыть текст песни: $detail.';
  }

  @override
  String get localMatchNoticeScanCancelled => 'Сканирование отменено';

  @override
  String get localMatchNoticeScanCompletedWithErrors =>
      'Сканирование завершено, но некоторые файлы не удалось проанализировать';

  @override
  String localMatchNoticeScanFailed(String detail) {
    return 'Сканирование не удалось: $detail';
  }

  @override
  String localMatchNoticeTreeScanFailed(String detail) {
    return 'Ошибка сканирования дерева каталогов: $detail';
  }

  @override
  String get localMatchNoticeMatchCancelled => 'Матч отменен';

  @override
  String localMatchNoticeMatchCompleted(
    int total,
    int success,
    int failed,
    int skipped,
  ) {
    return 'Всего песен $total, $success соответствует, $failed не удалось, $skipped пропущено.';
  }

  @override
  String localMatchNoticeMatchFailed(String detail) {
    return 'Не удалось локальное сопоставление: $detail.';
  }

  @override
  String get localMatchNoticeAndroidMatchCancelledResume =>
      'Матч отменен. Начните снова, чтобы возобновить работу с контрольной точки.';

  @override
  String localMatchNoticeAndroidMatchFailed(String detail) {
    return 'Не удалось локальное сопоставление Android SAF: $detail';
  }

  @override
  String get localMatchValidationEmptyLangs =>
      'Выберите языки текстов песен для соответствия';

  @override
  String get localMatchValidationEmptySources =>
      'Выберите хотя бы один источник';

  @override
  String get localMatchValidationEmptyQueue =>
      'Импортируйте песни, чтобы они соответствовали первым';

  @override
  String get localMatchValidationSkipExistingFileNameConflict =>
      'При пропуске существующих текстов песен при одновременном сохранении файлов режим имени файла не может использовать соответствующую информацию о текстах песен.';

  @override
  String get localMatchValidationMissingAndroidTree =>
      'Сначала выберите дерево каталогов';

  @override
  String get localMatchValidationNeedsSaveRoot => 'Укажите путь сохранения.';

  @override
  String get localMatchValidationNeedsSongRoot =>
      'Требуется корневой каталог песни.';

  @override
  String get localMatchValidationUnknownSavePath =>
      'Неизвестная ошибка пути сохранения';

  @override
  String get localMatchIntro =>
      'Импортируйте локальные песни или папки, просмотрите результат, а затем запустите пакетное сопоставление.';

  @override
  String get localMatchDropUnsupportedItem =>
      'Локальное совпадение принимает файлы песен, папки или анализируемые элементы проигрывателя.';

  @override
  String get localMatchReadyToStart => 'Готовы начать локальное сопоставление';

  @override
  String get localMatchQueueTitle => 'Очередь задач';

  @override
  String get localMatchQueueEmptyHint =>
      'Импортируйте файлы или папки для создания очереди задач.';

  @override
  String localMatchQueueDesktopHint(int count) {
    return '$count задач. Щелкните строку правой кнопкой мыши, чтобы увидеть дополнительные действия.';
  }

  @override
  String localMatchQueueMobileHint(int count) {
    return '$count задач. Нажмите и удерживайте кнопку «Еще», чтобы открыть действия.';
  }

  @override
  String get localMatchImportAndRunTitle => 'Импортируйте и запускайте';

  @override
  String get localMatchActionStart => 'Начать сопоставление';

  @override
  String get localMatchActionAddFolders => 'Добавить папки';

  @override
  String get localMatchActionSelectSaveRoot => 'Выберите «Сохранить корень».';

  @override
  String get localMatchActionSelectTree => 'Выберите дерево';

  @override
  String get localMatchActionReselectTree => 'Повторно выбрать дерево';

  @override
  String get localMatchActionBulkSelect => 'Массовый выбор';

  @override
  String get localMatchActionExitSelection => 'Выйти из массового выбора';

  @override
  String get localMatchActionSelectAll => 'Выбрать все';

  @override
  String get localMatchActionDeselectAll => 'Отменить выбор всех';

  @override
  String get localMatchActionSetRoot => 'Установить корень';

  @override
  String localMatchSelectedCount(int count) {
    return '$count выбрано';
  }

  @override
  String get localMatchBulkActionHint =>
      'Массовые действия применяются непосредственно к выбранным задачам.';

  @override
  String get localMatchPhaseIdle => 'Ожидающий';

  @override
  String get localMatchPhaseScanning => 'Сканирование';

  @override
  String get localMatchPhaseMatching => 'Соответствие';

  @override
  String get localMatchPhaseWriting => 'Письмо';

  @override
  String get localMatchPhaseCompleted => 'Завершенный';

  @override
  String get localMatchPhaseHintIdle =>
      'Импортируйте песни, чтобы начать сопоставление';

  @override
  String get localMatchPhaseHintScanning =>
      'Построение очереди задач и оценка результатов';

  @override
  String get localMatchPhaseHintMatching =>
      'Запрос источников и вычисление наилучшего соответствия';

  @override
  String get localMatchPhaseHintWriting =>
      'Написание файлов с текстами песен или тегов песен';

  @override
  String get localMatchPhaseHintCompleted =>
      'Этот пробег завершен. Отрегулируйте и запустите снова, если необходимо.';

  @override
  String get localMatchPipelineIdle => 'Сканировать -> Сопоставить -> Записать';

  @override
  String get localMatchPipelineScanning => 'Текущий этап: сканирование';

  @override
  String get localMatchPipelineMatching => 'Текущий этап: матч';

  @override
  String get localMatchPipelineWriting => 'Текущий этап: написать';

  @override
  String get localMatchPipelineCompleted =>
      'Сканирование, сопоставление и запись завершены';

  @override
  String get localMatchUnknownSong => 'Неизвестная песня';

  @override
  String get localMatchUnknownDuration => 'Неизвестная продолжительность';

  @override
  String get localMatchStatusNotStarted => 'Не запущено';

  @override
  String get localMatchSongPathLabel => 'Путь песни';

  @override
  String get localMatchLyricsPathLabel => 'Тексты песен Сохранить путь';

  @override
  String get localMatchExpandDetails => 'Развернуть детали';

  @override
  String get localMatchCollapseDetails => 'Свернуть детали';

  @override
  String get localMatchRowActionOpenInSearch => 'Открыть в поиске';

  @override
  String get localMatchRowActionEnterSelection => 'Введите массовый выбор';

  @override
  String get localMatchRowActionOpenSongDirectory => 'Открыть папку с песнями';

  @override
  String get localMatchRowActionOpenSaveDirectory => 'Открыть папку сохранения';

  @override
  String get localMatchRowActionOpenLyrics => 'Открыть тексты песен';

  @override
  String get localMatchFieldLyricsType => 'Тип текста';

  @override
  String get localMatchFieldOutputStrategy => 'Стратегия вывода';

  @override
  String get localMatchFieldSaveMode => 'Режим сохранения';

  @override
  String get localMatchFieldFileNameMode => 'Режим имени файла';

  @override
  String get localMatchFieldLyricsFormat => 'Формат текста';

  @override
  String get localMatchFieldThreshold => 'Порог совпадения';

  @override
  String get localMatchFieldSaveRoot => 'Сохранить корень';

  @override
  String get localMatchMoreSettings => 'Дополнительные настройки';

  @override
  String get localMatchRulesTitle => 'Правила матча';

  @override
  String get localMatchRulesSubtitle =>
      'Источники, языки, стратегия вывода и пороговое значение.';

  @override
  String get localMatchMinScore => 'Минимальный балл';

  @override
  String get localMatchSkipExisting => 'Пропустить существующие тексты песен';

  @override
  String get localMatchSkipExistingConflictHint =>
      'Текущая стратегия вывода и режим имени файла не могут пропускать существующие тексты песен. Если файлы все еще необходимо сохранить, избегайте присвоения им названий по совпадающей информации о тексте песни.';

  @override
  String get localMatchSaveToSongDirectoryHint =>
      'Для сохранения в папке песни не требуется дополнительный корень сохранения.';

  @override
  String get localMatchAndroidTreeSaveHint =>
      'Сохранения дерева каталогов Android записываются непосредственно в авторизованное дерево.';

  @override
  String get localMatchFileNameTemplateHint =>
      'В шаблоне имени файла используется текст_файла_имя_fmt из настроек.';

  @override
  String localMatchSaveRootPath(String path) {
    return 'Сохранить корень: $path';
  }

  @override
  String get localMatchSaveRootRequired =>
      'Для этого режима сохранения требуется корень сохранения. Сначала выберите один.';

  @override
  String get localMatchTreeNotSelected => 'Дерево каталогов не выбрано';

  @override
  String get localMatchSaveModeSong => 'Сохранить в папку песни';

  @override
  String get localMatchSaveModeMirror => 'Зеркальные папки';

  @override
  String get localMatchSaveModeSpecify => 'Конкретная папка';

  @override
  String get localMatchFileNameModeSong => 'Использовать имя файла песни';

  @override
  String get localMatchFileNameModeFormatBySong =>
      'Название по информации о песне';

  @override
  String get localMatchFileNameModeFormatByLyrics =>
      'Название По словам Информация';

  @override
  String get localMatchFileNameHintSong =>
      'Повторно используйте имя аудиофайла и замените только расширение текста.';

  @override
  String get localMatchFileNameHintFormatBySong =>
      'Создайте имя файла на основе метаданных песни, таких как название, исполнитель и альбом.';

  @override
  String get localMatchFileNameHintFormatByLyrics =>
      'Создайте имя файла на основе информации о совпадающей песне с текстом; он может быть неизвестен до сопоставления.';

  @override
  String get localMatchSaveToTagOnlyFile => 'Только файл';

  @override
  String get localMatchSaveToTagOnlyTag => 'Только тег';

  @override
  String get localMatchSaveToTagBoth => 'Файл + Тег';

  @override
  String get localMatchValidationTitle =>
      'Проблемы, которые нужно исправить перед запуском';

  @override
  String localMatchValidationMoreIssues(int count) {
    return '$count необходимо исправить еще несколько проблем';
  }

  @override
  String get batchConvertNoticeSelectedFilesUnavailable =>
      'Выбранные файлы не доступны напрямую';

  @override
  String batchConvertNoticeImportFilesCompleted(int count) {
    return 'Импортированы файлы с текстами песен $count.';
  }

  @override
  String get batchConvertNoticeDroppedNoAccessibleFiles =>
      'Перенесенные данные не содержат доступных файлов с текстами песен.';

  @override
  String get batchConvertNoticeEmptyQueue =>
      'Добавьте файлы с текстами песен для конвертации в первую очередь';

  @override
  String get batchConvertNoticeOverwriteCancelled =>
      'Пакетное преобразование отменено.';

  @override
  String batchConvertNoticeConversionCancelledCompleted(int count) {
    return 'Пакетное преобразование отменено, $count элементов выполнено';
  }

  @override
  String batchConvertNoticeConversionCompletedWithFailures(
    int success,
    int failure,
  ) {
    return 'Пакетное преобразование завершено: $success выполнено успешно, $failure не выполнено.';
  }

  @override
  String batchConvertNoticeConversionCompleted(int count) {
    return 'Пакетное преобразование завершено: $count элементов.';
  }

  @override
  String batchConvertNoticeConversionFailed(String detail) {
    return 'Не удалось выполнить пакетное преобразование: $detail.';
  }

  @override
  String batchConvertNoticeOpenSourceDirectoryFailed(String detail) {
    return 'Не удалось открыть каталог с исходным кодом: $detail.';
  }

  @override
  String batchConvertNoticeOpenOutputFileFailed(String detail) {
    return 'Не удалось открыть файл с текстом песни: $detail.';
  }

  @override
  String get batchConvertNoticeScanNoSupportedFiles =>
      'В выбранной папке не найдены поддерживаемые файлы с текстами песен.';

  @override
  String batchConvertNoticeScanImportedFromDirectory(int count) {
    return 'Импортированы файлы с текстами песен $count из папки.';
  }

  @override
  String get batchConvertNoticeDuplicateItems =>
      'Все выбранные записи уже в очереди';

  @override
  String get batchConvertControlsTitle => 'Импорт и настройки';

  @override
  String get batchConvertCompactControlsTitle => 'Настройки импорта и вывода';

  @override
  String batchConvertCompactControlsSubtitle(String format) {
    return 'Формат: $format';
  }

  @override
  String get batchConvertImportTitle => 'Импорт';

  @override
  String get batchConvertAddFolders => 'Добавить папку';

  @override
  String get batchConvertOutputSettingsTitle => 'Настройки вывода';

  @override
  String get batchConvertTargetFormat => 'Целевой формат';

  @override
  String get batchConvertSaveDirectoryTitle => 'Сохранить папку';

  @override
  String get batchConvertSaveDirectoryDefault =>
      'Если этот параметр не установлен, вывод идет рядом с исходным файлом текста песни.';

  @override
  String get batchConvertSelectSaveDirectory => 'Выберите папку сохранения.';

  @override
  String get batchConvertRestoreOriginalDirectory =>
      'Использовать исходную папку';

  @override
  String get batchConvertRecursiveTitle => 'Сканировать подпапки';

  @override
  String get batchConvertRecursiveSubtitle =>
      'При импорте папки продолжайте сканирование файлов с текстами песен в подпапках.';

  @override
  String get batchConvertStart => 'Начать преобразование';

  @override
  String get batchConvertCancel => 'Отменить преобразование';

  @override
  String get batchConvertQueueTitle => 'Очередь конверсий';

  @override
  String batchConvertQueueSubtitle(int count, String format) {
    return '$count элементов, формат вывода $format';
  }

  @override
  String get batchConvertPageErrorFallback =>
      'На странице пакетного преобразования произошла ошибка';

  @override
  String get batchConvertRetryImport => 'Импортировать снова';

  @override
  String get batchConvertEmptyQueue =>
      'Добавьте файлы или папки с текстами песен, и здесь появится очередь пакетного преобразования.';

  @override
  String get batchConvertOutputPathLabel => 'Выходной путь';

  @override
  String get batchConvertQueueStatusWaiting => 'Ожидающий';

  @override
  String get batchConvertQueueStatusRunning => 'Преобразование';

  @override
  String get batchConvertQueueStatusSuccess => 'Преобразовано';

  @override
  String get batchConvertQueueStatusFailure => 'Неуспешный';

  @override
  String get batchConvertMoreActions => 'Дополнительные действия';

  @override
  String get batchConvertActionOpenSourceDirectory =>
      'Папка с открытым исходным кодом';

  @override
  String get batchConvertActionOpenSaveDirectory => 'Открыть папку сохранения';

  @override
  String get batchConvertActionOpenOutputFile =>
      'Открыть файл с текстами песен';

  @override
  String get batchConvertActionOpenInOpenLyrics => 'Открыть в открытом тексте';

  @override
  String get batchConvertPhaseIdle => 'Ожидающий';

  @override
  String get batchConvertPhaseScanning => 'Сканирование';

  @override
  String get batchConvertPhaseRunning => 'Преобразование';

  @override
  String get batchConvertPhaseCompleted => 'Завершенный';

  @override
  String get batchConvertPipelineIdle =>
      'Импорт -> Сканировать -> Конвертировать -> Готово.';

  @override
  String get batchConvertPipelineScanning =>
      'Сканировать папки -> Построить очередь';

  @override
  String get batchConvertPipelineRunning =>
      'Конвертировать каждый элемент -> Обновить статус';

  @override
  String get batchConvertPipelineCompleted =>
      'Измените формат или импортируйте еще раз.';

  @override
  String batchConvertHintCancelled(int success, int failure) {
    return 'Отменено, $success успешно, $failure не удалось';
  }

  @override
  String batchConvertHintCompleted(int success, int failure) {
    return '$success выполнено успешно, $failure не выполнено';
  }

  @override
  String get batchConvertHintNoQueue =>
      'Добавьте файлы или папки, чтобы начать конвертацию';

  @override
  String get batchConvertHintReady => 'Очередь готова';

  @override
  String get batchConvertMetricWaiting => 'Ожидающий';

  @override
  String get batchConvertDropUnsupported =>
      'Страница пакетного преобразования принимает только файлы или папки с текстами песен.';

  @override
  String batchConvertDropFailed(String detail) {
    return 'Не удалось обработать удаление: $detail.';
  }

  @override
  String batchConvertProgressConvertingFile(String fileName) {
    return 'Преобразование $fileName';
  }

  @override
  String get batchConvertProgressItemSuccess => 'Преобразовано';

  @override
  String get batchConvertProgressItemFailure => 'Неуспешный';

  @override
  String get batchConvertProgressPreparingConversion =>
      'Подготовка преобразования...';

  @override
  String get batchConvertProgressCancellingConversion =>
      'Отмена преобразования...';

  @override
  String get batchConvertProgressConversionCancelled => 'Конверсия отменена';

  @override
  String batchConvertProgressConversionCompleted(int success, int failure) {
    return 'Преобразование завершено: $success успешно, $failure не удалось.';
  }

  @override
  String batchConvertProgressConversionFailed(String detail) {
    return 'Не удалось преобразовать: $detail.';
  }

  @override
  String get batchConvertProgressScanningFolders => 'Сканирование папок...';

  @override
  String batchConvertProgressScanningDirectory(String directoryName) {
    return 'Сканирование $directoryName';
  }

  @override
  String batchConvertProgressScannedLyricsFiles(int count) {
    return 'Найдено $count файлов с текстами песен.';
  }

  @override
  String get batchConvertProgressScanCancelled => 'Сканирование отменено';

  @override
  String get batchConvertProgressScanNoSupportedFiles =>
      'Не найдено поддерживаемых файлов с текстами песен.';

  @override
  String get batchConvertProgressScanCompleted => 'Сканирование завершено';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navLocalMatch => 'Локальное совпадение';

  @override
  String get navOpenLyrics => 'Открыть тексты песен';

  @override
  String get navBatchConvert => 'Пакетное преобразование';

  @override
  String get navSettings => 'Настройки';

  @override
  String get navAbout => 'О';

  @override
  String get commonSearch => 'Поиск';

  @override
  String get commonSource => 'Источник';

  @override
  String get searchKeywordHint => 'Введите ключевое слово';

  @override
  String get uiLoading => 'Загрузка...';

  @override
  String get uiLoadingStepFetching =>
      'Получение списка и предварительный просмотр...';

  @override
  String get uiEmpty => 'Нет данных';

  @override
  String get uiNoMoreResult => 'Больше нет результатов';

  @override
  String get searchInitialResultTitle =>
      'Введите ключевые слова, чтобы начать поиск';

  @override
  String get searchInitialResultDescription =>
      'Выберите источник выше и запустите поиск';

  @override
  String get searchResultTitle => 'Результаты поиска';

  @override
  String get searchResultReturn => 'Назад';

  @override
  String get searchPreviewTitle => 'Предварительный просмотр текста';

  @override
  String get searchPreviewLangsLabel => 'Языки';

  @override
  String get searchPreviewSongIdLabel => 'Идентификатор песни';

  @override
  String get searchPreviewPlaceholder =>
      'Сначала выберите песню или текст песни';

  @override
  String get searchPreviewNoLanguage => 'Выберите хотя бы один язык текстов';

  @override
  String get searchPreviewNoContent =>
      'Контент для предварительного просмотра недоступен.';

  @override
  String get searchPreviewLoading => 'Загрузка текста...';

  @override
  String get searchFormatLabel => 'Формат текста';

  @override
  String get searchTranslateLyrics => 'Перевести текст';

  @override
  String get searchResizeWorkspacePanes =>
      'Изменение размера результатов поиска и предварительного просмотра текстов песен';

  @override
  String get searchSavePreviewToDirectory => 'Сохранить в папку';

  @override
  String get searchSavePreviewToFile => 'Сохранить в файл';

  @override
  String get searchSavePreviewToTag => 'Сохранить превью в тег';

  @override
  String get searchSaveListLyrics =>
      'Сохранить альбом/плейлист с текстами песен';

  @override
  String get searchSaveListLyricsCancel => 'Отменить пакетное сохранение';

  @override
  String get searchSelectSavePath => 'Выберите папку сохранения.';

  @override
  String get searchBatchSaveProgressTitle => 'Пакетное сохранение прогресса';

  @override
  String get searchBatchSaveProgressPreparing =>
      'Подготовка пакетного сохранения...';

  @override
  String searchBatchSaveProgressFetchingLyrics(String songName) {
    return 'Получение текста песни $songName...';
  }

  @override
  String searchTableSongCountValue(int count) {
    return '$count песен';
  }

  @override
  String get searchTableStatusAutoFetching => 'Автоматическое получение...';

  @override
  String get searchTableStatusSearching => 'Идет поиск...';

  @override
  String get searchTableStatusFetchingSongList => 'Получение списка песен...';

  @override
  String get searchTableStatusNoResults =>
      'Соответствующих результатов не найдено';

  @override
  String get searchTableStatusEmptyList => 'Список пуст';

  @override
  String get searchTableStatusUnsupportedSearchType =>
      'Выбранный источник не поддерживает этот тип поиска.';

  @override
  String get searchTableStatusSearchFailed => 'Поиск не удался';

  @override
  String searchTableStatusSearchFailedWithDetail(String detail) {
    return 'Поиск не удался: $detail';
  }

  @override
  String searchTableStatusAutoFetchFailed(String detail) {
    return 'Не удалось выполнить автоматическое получение: $detail.';
  }

  @override
  String searchTableStatusSongListFailed(String detail) {
    return 'Не удалось получить список песен: $detail.';
  }

  @override
  String get searchTableStatusPartialSourceUnavailable =>
      'Некоторые источники недоступны. Показаны доступные результаты';

  @override
  String get searchTableStatusLoadMoreFailed =>
      'Некоторым источникам не удалось загрузить больше результатов.';

  @override
  String get searchSourceFailureDetailsTitle => 'Поиск сведений об ошибке';

  @override
  String get searchSourceFailureRequest => 'Запрос не выполнен';

  @override
  String get searchSourceFailureTimeout => 'Время запроса истекло';

  @override
  String get searchSourceFailureParameters => 'Неверные параметры';

  @override
  String get searchSourceFailureUnsupported => 'Неподдерживаемая операция';

  @override
  String get searchSourceFailureUnknown => 'Неизвестная ошибка';

  @override
  String get searchResultLoadingMore =>
      'Загрузка дополнительных результатов...';

  @override
  String get searchResultLoadMoreFailed =>
      'Автозагрузка не удалась. Повторите попытку, чтобы продолжить загрузку оставшихся результатов.';

  @override
  String get searchResultScrollForMore =>
      'Прокрутите вниз, чтобы автоматически загрузить дополнительные результаты.';

  @override
  String get tableSavePath => 'Сохранить путь';

  @override
  String get settingsSectionSave => 'Сохранять';

  @override
  String get settingsSectionLyrics => 'Тексты песен';

  @override
  String get settingsSectionDesktopLyrics => 'Рабочий стол';

  @override
  String get settingsSectionTranslate => 'Переводить';

  @override
  String get settingsSectionSearch => 'Поиск';

  @override
  String get settingsSectionApp => 'Приложение';

  @override
  String get settingsSectionTools => 'Инструменты и данные';

  @override
  String get settingsSectionSaveSummary =>
      'Пути сохранения, шаблон имени файла и версия ID3.';

  @override
  String get settingsSectionSearchSummary =>
      'Выберите источники текстов по умолчанию для совокупного поиска и локального сопоставления.';

  @override
  String get settingsSectionDesktopLyricsSummary =>
      'Тексты песен на рабочем столе автоматически выбираются, языки отображения, внешний вид и частота обновления.';

  @override
  String get settingsSectionLyricsSummary =>
      'Локальное соответствие и формат экспорта файлов текстов песен.';

  @override
  String get settingsSectionTranslateSummary =>
      'Источник перевода, целевой язык и условные поля';

  @override
  String get settingsSectionAppSummary =>
      'Язык, тема, журналы и политика обновлений';

  @override
  String get settingsSectionToolsSummary =>
      'Инструменты рабочего стола, папка журнала и очистка кеша';

  @override
  String get settingsTranslateSourceBing => 'Бинг-переводчик';

  @override
  String get settingsTranslateSourceGoogle => 'Гугл переводчик';

  @override
  String get settingsTranslateSourceOpenAi => 'OpenAI-совместимый API';

  @override
  String get settingsLangSimplifiedChinese => 'Упрощенный китайский';

  @override
  String get settingsLangTraditionalChinese => 'Традиционный китайский';

  @override
  String get settingsLangEnglish => 'Английский';

  @override
  String get settingsLangJapanese => 'японский';

  @override
  String get settingsLangKorean => 'корейский';

  @override
  String get settingsLangSpanish => 'испанский';

  @override
  String get settingsLangFrench => 'Французский';

  @override
  String get settingsLangPortuguese => 'португальский';

  @override
  String get settingsLangGerman => 'немецкий';

  @override
  String get settingsLangRussian => 'Русский';

  @override
  String get settingsAppLanguageAuto => 'Авто';

  @override
  String get settingsColorSchemeAuto => 'Следовать за системой';

  @override
  String get settingsColorSchemeLight => 'Свет';

  @override
  String get settingsColorSchemeDark => 'Темный';

  @override
  String get settingsDesktopGradientColors => 'Градиентные цвета';

  @override
  String get settingsDesktopPlayedColors => 'Играемые цвета';

  @override
  String get settingsDesktopUnplayedColors => 'Неигранные цвета';

  @override
  String get settingsAddColor => 'Добавить цвет';

  @override
  String get settingsEditColor => 'Редактировать цвет';

  @override
  String get settingsDeleteColor => 'Удалить цвет';

  @override
  String get settingsBackToSections => 'Вернуться к разделам настроек';

  @override
  String get settingsAvailablePlaceholders => 'Доступные заполнители';

  @override
  String get settingsPlaceholderTitleArtist =>
      'Название: %<title> Исполнитель: %<artist>';

  @override
  String get settingsPlaceholderAlbumId =>
      'Альбом: %<album> Идентификатор песни/текста: %<id>';

  @override
  String get settingsPlaceholderLangs => 'Типы языков: %<langs>';

  @override
  String settingsCurrentTemplate(String template) {
    return 'Текущий шаблон: $template';
  }

  @override
  String get settingsTranslateSourceLabel => 'Источник перевода';

  @override
  String get settingsTranslateTargetLabel => 'Целевой язык';

  @override
  String get settingsOpenAiProfileLabel => 'Предустановка';

  @override
  String get settingsOpenAiProfileHelper =>
      'Встроенные поставщики автоматически заполняют базовый URL-адрес. Вам все равно необходимо настроить ключ API и модель.';

  @override
  String get settingsAppLanguageLabel => 'Язык интерфейса';

  @override
  String get settingsColorSchemeLabel => 'Тематический режим';

  @override
  String get settingsLogLevelLabel => 'Уровень журнала';

  @override
  String get settingsLogLevelHelper =>
      'Сохраните ИНФОРМАЦИЮ для обычного использования. TRACE и DEBUG записывают больше деталей и создают более крупные журналы.';

  @override
  String get settingsAutoCheckUpdateLabel =>
      'Автоматическая проверка обновлений';

  @override
  String get settingsRestoreDefaultsWarning =>
      'Восстановление настроек по умолчанию немедленно записывает конфигурацию. Пожалуйста, подтвердите, прежде чем продолжить.';

  @override
  String get settingsRestoreAllTitle => 'Восстановить настройки по умолчанию';

  @override
  String get settingsRestoreAllContent =>
      'Это восстанавливает все настройки и сразу записывает их в конфиг.';

  @override
  String get settingsRestoreAllAction => 'Восстановить настройки по умолчанию';

  @override
  String get settingsOpenAssociationManager =>
      'Менеджер ассоциации Open Lyrics';

  @override
  String get settingsOpenAssociationManagerSubtitle =>
      'Откройте следующую страницу настроек, чтобы управлять ассоциациями песен и текстов.';

  @override
  String get settingsOpenLogDirectory => 'Открыть каталог журналов';

  @override
  String get settingsOpenLogDirectorySubtitle =>
      'Просмотр журналов выполнения и файлов устранения неполадок.';

  @override
  String get settingsClearCache => 'Очистить кэш';

  @override
  String get settingsClearCacheSubtitle =>
      'Очистите кеш поиска и перевода без изменения файлов конфигурации.';

  @override
  String get settingsClearCacheContent =>
      'После очистки кэша последующие поиски и переводы могут снова запросить данные.';

  @override
  String get settingsRestoreSectionTitle => 'Восстановить этот раздел';

  @override
  String settingsRestoreSectionContent(String sectionTitle) {
    return 'Будут восстановлены только настройки в разделе «$sectionTitle». Остальные разделы не изменятся.';
  }

  @override
  String settingsRestoreSectionTooltip(String sectionTitle) {
    return 'Восстановить настройки по умолчанию для $sectionTitle';
  }

  @override
  String get settingsDefaultSavePathHelper =>
      'Оставьте пустым, чтобы использовать музыкальный каталог платформы по умолчанию.';

  @override
  String get settingsChooseFolder => 'Выберите папку';

  @override
  String get settingsLyricsFileNameFormat =>
      'Шаблон имени файла с текстами песен';

  @override
  String get settingsLyricsFileNameFormatHelper =>
      'Используйте заполнители ниже, чтобы составить имена сохраненных файлов.';

  @override
  String get settingsId3Version => 'Версия ID3';

  @override
  String get settingsId3VersionHelper =>
      'Влияет только на тексты песен, записанные в аудиотеги. Если вы не уверены, сохраните версию 2.3.';

  @override
  String get settingsSearchSourcesTitle => 'Совокупные источники поиска';

  @override
  String get settingsSearchSourcesDescription =>
      'Проверенные источники запрашиваются, когда поиск использует агрегат. Источники, расположенные выше в списке, занимают первое место по группировке результатов и автоматическому сопоставлению. Local Match использует этот список по умолчанию.';

  @override
  String get settingsReorderPriorityHint =>
      'Перетащите, чтобы изменить приоритет';

  @override
  String get settingsReorderOrderHint => 'Перетащите, чтобы изменить порядок';

  @override
  String get settingsDefaultLanguage => 'Языки отображения по умолчанию';

  @override
  String get settingsDefaultLanguageDescription =>
      'Выберите языки, отображаемые по умолчанию в текстах песен на рабочем столе, затем перетащите их, чтобы изменить порядок их отображения.';

  @override
  String get settingsDesktopAutoFetchSources => 'Автозагрузка источников';

  @override
  String get settingsDesktopAutoFetchSourcesDescription =>
      'Если в текстах песен на рабочем столе нет связанных текстов, источники проверяются сверху вниз.';

  @override
  String get settingsFont => 'Шрифт';

  @override
  String get settingsFollowSystemFont => 'Следовать системному шрифту';

  @override
  String get settingsFontSizeByResize =>
      'Измените размер окна текстов песен на рабочем столе, чтобы настроить размер основного шрифта.';

  @override
  String get settingsPanelFontSize => 'Размер шрифта панели «Тексты»';

  @override
  String get settingsAdaptiveRefreshRate => 'Адаптивная частота обновления';

  @override
  String get settingsAdaptiveRefreshRateSubtitle =>
      'Автоматически выбирать частоту обновления в зависимости от состояния анимации текста песни.';

  @override
  String get settingsFixedRefreshRate => 'Фиксированная частота обновления';

  @override
  String get settingsShowFurigana => 'Показать Фуригану';

  @override
  String get settingsLyricsMatchBehavior => 'Соответствующее поведение';

  @override
  String get settingsLyricsMatchBehaviorDescription =>
      'Установите обработку по умолчанию для локальных совпадений и кандидатов на тексты Kugou.';

  @override
  String get settingsLyricsExport => 'ЛРК Экспорт';

  @override
  String get settingsLyricsExportDescription =>
      'Установите порядок языков и формат временных меток LRC, используемый при сохранении файлов с текстами песен.';

  @override
  String get settingsDisplayOrder => 'Экспортировать порядок языков';

  @override
  String get settingsDisplayOrderDescription =>
      'Перетащите, чтобы упорядочить оригинальные, переведенные и латинизированные тексты песен в экспортированных файлах.';

  @override
  String get settingsSkipInstrumental => 'Пропустить инструментальные треки';

  @override
  String get settingsSkipInstrumentalSubtitle =>
      'Не сохраняйте тексты песен, если Local Match идентифицирует инструментальный трек.';

  @override
  String get settingsAutoSelectKugou => 'Автоматический выбор кандидата Куго';

  @override
  String get settingsAutoSelectKugouSubtitle =>
      'Автоматически выбирать лучшего кандидата на текст при открытии песни Kugou в Поиске.';

  @override
  String get settingsAddLrcEndTimestamp =>
      'Добавить временную метку окончания при экспорте LRC';

  @override
  String get settingsAddLrcEndTimestampSubtitle =>
      'Влияет только на построчный LRC и записывает временные метки конца строки, когда это необходимо.';

  @override
  String get settingsMillisecondsDigits => 'Миллисекундные цифры';

  @override
  String get settingsMillisecondsDigitsHelper =>
      'Используйте две цифры для сантисекунд или три цифры для полных миллисекунд.';

  @override
  String settingsDigitsValue(int value) {
    return '$value цифр';
  }

  @override
  String get settingsLastRefStyle =>
      'Временная метка последней языковой строки';

  @override
  String get settingsLastRefStyleHelper =>
      'Для построчного LRC на нескольких языках используйте текущее время строки или одну миллисекунду перед следующей строкой для последней языковой строки.';

  @override
  String get settingsLastRefCurrentLine => 'Использовать текущее время линии';

  @override
  String get settingsLastRefNextLine =>
      'Используйте одну миллисекунду перед следующей строкой';

  @override
  String get settingsTagInfoSource => 'Источник информации о тегах';

  @override
  String get settingsTagInfoLyricsSource => 'Источник текста';

  @override
  String get settingsTagInfoSongInfo => 'Информация о песне';

  @override
  String get settingsNoticeDefaultSavePathUpdated =>
      'Путь сохранения по умолчанию обновлен.';

  @override
  String get settingsNoticeDefaultSavePathRestored =>
      'Путь сохранения по умолчанию восстановлен.';

  @override
  String get settingsNoticeLyricsFileNameFormatUpdated =>
      'Обновлен шаблон имени файла с текстами песен.';

  @override
  String get settingsNoticeId3VersionUpdated => 'Версия ID3 обновлена';

  @override
  String get settingsNoticeLyricsLangOrderEmpty =>
      'Порядок языка текста не может быть пустым.';

  @override
  String get settingsNoticeLyricsLangOrderUpdated =>
      'Порядок языков текста изменен.';

  @override
  String get settingsNoticeSkipInstUpdated =>
      'Обновлена ​​политика инструментального пропуска.';

  @override
  String get settingsNoticeAutoSelectUpdated =>
      'Политика автоматического выбора обновлена.';

  @override
  String get settingsNoticeAddEndTimestampUpdated =>
      'Политика в отношении отметки времени окончания обновлена.';

  @override
  String get settingsNoticeMsDigitsUpdated => 'Обновлены цифры миллисекунд.';

  @override
  String get settingsNoticeLastRefStyleUpdated =>
      'Обновлен стиль времени последней строки.';

  @override
  String get settingsNoticeTagInfoSourceUpdated =>
      'Источник информации о теге обновлен.';

  @override
  String get settingsNoticeDesktopSourcesEmpty =>
      'Исходные тексты песен на рабочем столе не могут быть пустыми.';

  @override
  String get settingsNoticeDesktopSourcesUpdated =>
      'Обновлены исходные тексты песен для рабочего стола';

  @override
  String get settingsNoticeDesktopDefaultLangsEmpty =>
      'Языки рабочего стола по умолчанию не могут быть пустыми.';

  @override
  String get settingsNoticeDesktopLangsUpdated =>
      'Обновлены языковые настройки текстов песен на рабочем столе.';

  @override
  String get settingsNoticeDesktopFontFamilyUpdated =>
      'Обновлен шрифт текстов песен на рабочем столе.';

  @override
  String get settingsNoticeDesktopRefreshRateUpdated =>
      'Частота обновления обновлена';

  @override
  String get settingsNoticeDesktopPlayedColorsUpdated =>
      'Воспроизводимые цвета обновлены.';

  @override
  String get settingsNoticeDesktopUnplayedColorsUpdated =>
      'Обновлены невоспроизводимые цвета';

  @override
  String get settingsNoticeDesktopFontSizeUpdated =>
      'Обновлен размер шрифта текстов песен на рабочем столе.';

  @override
  String get settingsNoticeDesktopPanelFontSizeUpdated =>
      'Обновлен размер шрифта панели рабочего стола.';

  @override
  String get settingsNoticeDesktopShowFuriganaUpdated =>
      'Обновлена ​​политика отображения Фуриганы';

  @override
  String get settingsNoticeTranslateSourceUpdated =>
      'Источник перевода обновлен.';

  @override
  String get settingsNoticeTranslateTargetLangUpdated =>
      'Целевой язык перевода обновлен.';

  @override
  String get settingsNoticeOpenAiProfileUpdated => 'Обновлен пресет OpenAI.';

  @override
  String get settingsNoticeOpenAiBaseUrlUpdated =>
      'URL-адрес базы OpenAI обновлен.';

  @override
  String get settingsNoticeOpenAiApiKeyUpdated => 'Ключ API OpenAI обновлен.';

  @override
  String get settingsNoticeOpenAiModelUpdated => 'Обновлена ​​модель OpenAI';

  @override
  String get settingsNoticeSearchSourcesEmpty =>
      'Совокупные источники поиска не могут быть пустыми.';

  @override
  String get settingsNoticeSearchSourcesUpdated =>
      'Совокупные источники поиска обновлены.';

  @override
  String get settingsNoticeAppLanguageUpdated => 'Обновлен язык интерфейса';

  @override
  String get settingsNoticeAppColorSchemeUpdated => 'Режим темы обновлен.';

  @override
  String get settingsNoticeAppLogLevelUpdated => 'Уровень журнала обновлен.';

  @override
  String get settingsNoticeAutoCheckUpdateUpdated =>
      'Обновлена ​​настройка автоматической проверки обновлений.';

  @override
  String get settingsNoticeSectionNoRestorableConfig =>
      'В этом разделе нет восстанавливаемых элементов конфигурации.';

  @override
  String get settingsNoticeSectionDefaultsRestored =>
      'Настройки текущего раздела по умолчанию восстановлены';

  @override
  String get settingsNoticeAllDefaultsRestored =>
      'Настройки приложения восстановлены до значений по умолчанию';

  @override
  String get settingsNoticeAssociationManagerOpened =>
      'Открыт менеджер ассоциации текстов песен';

  @override
  String get settingsNoticeLogDirectoryOpened => 'Каталог журналов открыт';

  @override
  String get settingsNoticeLogDirectoryOpenFailed =>
      'Не удалось открыть каталог журналов';

  @override
  String get settingsNoticeCacheCleared => 'Кэш очищен';

  @override
  String get settingsNoticeCacheClearFailed => 'Не удалось очистить кэш';

  @override
  String get settingsNoticeConfigWriteFailed => 'Не удалось записать настройки';

  @override
  String get settingsCurrentSavePathLabel => 'Путь сохранения по умолчанию';

  @override
  String get aboutLoadFailed => 'Не удалось загрузить метаданные.';

  @override
  String get aboutActionOpenRepository => 'Репозиторий GitHub';

  @override
  String get aboutActionCheckUpdate => 'Проверить обновление';

  @override
  String get aboutHeroHeadline => 'Создан для точных текстов';

  @override
  String get aboutHeroDescription =>
      'LDDC объединяет поиск, преобразование, тексты песен на рабочем столе и пакетные рабочие процессы в одну эффективную поверхность, поэтому поиск, организация и использование текстов остается быстрым и целенаправленным.';

  @override
  String get aboutLinksSectionTitle => 'Быстрые ссылки';

  @override
  String get aboutLinksSectionDescription =>
      'Используйте эти ссылки, если вам нужны каналы обратной связи, примечания к выпуску или сведения о лицензии.';

  @override
  String aboutCopyrightNoticeBody(String years, String author) {
    return 'Авторские права (C) $years $author';
  }

  @override
  String aboutLicenseNoticeBody(String license) {
    return 'Лицензия $license.';
  }

  @override
  String get aboutLinkRepositoryTitle => 'Репозиторий GitHub';

  @override
  String get aboutLinkIssueTrackerTitle => 'Трекер проблем';

  @override
  String get aboutLinkIssueTrackerDescription =>
      'Сообщайте об ошибках, пробелах в UX и запросах функций.';

  @override
  String get aboutLinkLicenseTitle => 'Лицензия';

  @override
  String get aboutLinkLicenseDescription =>
      'Ознакомьтесь с текущей лицензией открытого исходного кода:';

  @override
  String get aboutLinkChangelogTitle => 'Примечания к выпуску';

  @override
  String get aboutLinkChangelogDescription =>
      'См. опубликованные версии и сводку их изменений.';

  @override
  String get aboutExternalLinksUnavailable =>
      'Открытие внешних ссылок на этой платформе не поддерживается.';

  @override
  String get aboutCheckUpdateUnavailable =>
      'Проверка обновлений не поддерживается на этой платформе.';

  @override
  String get aboutCheckUpdateOpenedReleaseNotes =>
      'Открыл страницу примечаний к выпуску.';

  @override
  String get aboutCheckUpdateUpToDate =>
      'У вас уже установлена ​​последняя версия.';

  @override
  String aboutCheckUpdateAvailable(Object version) {
    return 'Обнаружена новая версия: $version. Откройте страницу примечаний к выпуску для получения подробной информации.';
  }

  @override
  String get aboutCheckUpdateFailed =>
      'Не удалось проверить наличие обновлений. Пожалуйста, повторите попытку позже.';

  @override
  String aboutActionOpenedLink(String title) {
    return 'Открыт $title';
  }

  @override
  String aboutActionOpenLinkFailed(String title) {
    return 'Не удалось открыть $title.';
  }

  @override
  String get actionConfirm => 'Подтверждать';

  @override
  String get libraryLinkManagerTitle => 'Менеджер Ассоциации лирики';

  @override
  String get libraryLinkManagerReturnToSettings => 'Вернуться к настройкам';

  @override
  String get libraryLinkManagerRefresh => 'Обновить';

  @override
  String libraryLinkManagerDeleteSelected(int count) {
    return 'Удалить выбранное ($count)';
  }

  @override
  String get libraryLinkManagerDeleteAll => 'Удалить все';

  @override
  String get libraryLinkManagerClearInvalid => 'Очистить неверные данные';

  @override
  String get libraryLinkManagerChangeDirectory => 'Каталог пакетного изменения';

  @override
  String get libraryLinkManagerBackupToJson => 'Резервное копирование в JSON';

  @override
  String get libraryLinkManagerRestoreFromJson => 'Восстановить из JSON';

  @override
  String get libraryLinkManagerRestoreAction => 'Восстановить';

  @override
  String get libraryLinkManagerExportLyrics => 'Экспортировать тексты песен';

  @override
  String libraryLinkManagerSummary(int totalCount, int selectedCount) {
    return '$totalCount записи · $selectedCount выбрано';
  }

  @override
  String get libraryLinkManagerSearchHint =>
      'Поиск песен, исполнителей, альбомов или дорожек';

  @override
  String get libraryLinkManagerClearSearch => 'Очистить поиск';

  @override
  String libraryLinkManagerSearchSummary(int totalCount, int selectedCount) {
    return '$totalCount соответствует · $selectedCount выбран';
  }

  @override
  String get libraryLinkManagerEmpty =>
      'Нет записей с ссылками на тексты песен';

  @override
  String libraryLinkManagerLoadFailed(String error) {
    return 'Не удалось загрузить записи ссылок на тексты песен: $error.';
  }

  @override
  String get libraryLinkManagerDeleteSelectedSuccess =>
      'Удалены выбранные ссылки на тексты песен';

  @override
  String get libraryLinkManagerDeleteAllConfirm =>
      'Вы уверены, что хотите удалить все записи ссылок на тексты песен?';

  @override
  String get libraryLinkManagerDeleteAllSuccess =>
      'Удалены все записи ссылок на тексты песен.';

  @override
  String libraryLinkManagerClearInvalidSuccess(int count) {
    return 'Удалены $count неверные записи.';
  }

  @override
  String libraryLinkManagerChangeDirectorySuccess(int count) {
    return 'Обновлены записи $count после перезаписи каталога.';
  }

  @override
  String libraryLinkManagerBackupSuccess(String path) {
    return 'Данные ссылки на тексты песен сохранены в $path.';
  }

  @override
  String get libraryLinkManagerRestoreConfirm =>
      'При восстановлении будут перезаписаны все текущие записи ссылок на тексты песен. Продолжать?';

  @override
  String get libraryLinkManagerRestoreSuccess =>
      'Данные ссылки на тексты песен восстановлены.';

  @override
  String get libraryLinkManagerInvalidBackupFormat =>
      'Неверный формат файла резервной копии';

  @override
  String libraryLinkManagerExportSuccess(int count) {
    return 'Экспортированы файлы с текстами песен $count.';
  }

  @override
  String libraryLinkManagerOperationFailed(String error) {
    return 'Операция не удалась: $error';
  }

  @override
  String get libraryLinkManagerUnnamedSong => 'Песня без названия';

  @override
  String get libraryLinkManagerUnknownArtist => 'Неизвестный исполнитель';

  @override
  String get libraryLinkManagerUnknownAlbum => 'Неизвестный альбом';

  @override
  String get libraryLinkManagerSongPathLabel => 'Путь песни';

  @override
  String get libraryLinkManagerSongPathEmpty => 'Путь к песне не записан';

  @override
  String get libraryLinkManagerLyricsPathLabel => 'Тексты песен Путь';

  @override
  String get libraryLinkManagerLyricsPathEmpty => 'Тексты песен не связаны';

  @override
  String libraryLinkManagerTrackLabel(String track) {
    return 'Трек $track';
  }

  @override
  String libraryLinkManagerTrackTooltip(String track) {
    return 'Номер трека: $track';
  }

  @override
  String get libraryLinkManagerTrackEmpty => 'Никто';

  @override
  String libraryLinkManagerOffsetLabel(String offset) {
    return 'Смещение $offset';
  }

  @override
  String libraryLinkManagerOffsetTooltip(String offset) {
    return 'Лирическое смещение: $offset';
  }

  @override
  String libraryLinkManagerLanguagesLabel(String langs) {
    return 'Языки $langs';
  }

  @override
  String libraryLinkManagerLanguagesTooltip(String langs) {
    return 'Языки текста: $langs';
  }

  @override
  String get libraryLinkManagerInstrumental => 'Инструментальный';

  @override
  String get libraryLinkManagerInstrumentalTooltip =>
      'Эта песня отмечена как инструментальная';

  @override
  String get libraryLinkManagerDisableAutoSearch =>
      'Отключить автоматический поиск';

  @override
  String get libraryLinkManagerDisableAutoSearchTooltip =>
      'Для этой песни отключен автоматический поиск';

  @override
  String libraryLinkManagerOtherConfig(int count) {
    return 'Другая конфигурация $count';
  }

  @override
  String get libraryLinkManagerDefaultConfig => 'Конфигурация по умолчанию';

  @override
  String get libraryLinkManagerDefaultConfigTooltip =>
      'Для этой записи не сохранена конфигурация переопределения на уровне песни.';

  @override
  String openLyricsNoticeOpenFailed(String detail) {
    return 'Не удалось открыть: $detail';
  }

  @override
  String get openLyricsNoticeLyricsFileUnavailable =>
      'Файл с текстом песни недоступен.';

  @override
  String get openLyricsNoticeSongFileUnavailable => 'Файл песни недоступен.';

  @override
  String get openLyricsNoticeNoEmbeddedLyrics =>
      'В этой песне не найдено читаемых встроенных текстов.';

  @override
  String get openLyricsNoticeAlreadyConverted =>
      'Эти тексты песен уже конвертированы';

  @override
  String get openLyricsNoticeEmptyLyrics =>
      'Содержание текста не может быть пустым.';

  @override
  String openLyricsNoticeConvertFailed(String detail) {
    return 'Не удалось преобразовать: $detail.';
  }

  @override
  String get openLyricsNoticeConvertFirst =>
      'Сначала конвертируйте тексты песен';

  @override
  String get openLyricsNoticeNoLyricsToSave => 'Нет текстов для сохранения';

  @override
  String openLyricsNoticeSaveFileSucceeded(String detail) {
    return 'Текст сохранен: $detail';
  }

  @override
  String openLyricsNoticeSaveFileFailed(String detail) {
    return 'Не удалось сохранить: $detail';
  }

  @override
  String get openLyricsNoticeOpenSongFirst => 'Сначала откройте файл песни';

  @override
  String get openLyricsNoticeAudioTagUnsupported =>
      'Эта платформа не может писать теги песен';

  @override
  String get openLyricsDropUnsupportedItem =>
      'Open Lyrics принимает файлы с текстами песен или аудиофайлы.';

  @override
  String get openLyricsPreviewTitle => 'Предварительный просмотр';

  @override
  String get openLyricsPreviewRawText => 'Необработанный текст';

  @override
  String openLyricsPreviewLanguages(String langs) {
    return 'Языки текста · $langs';
  }

  @override
  String get openLyricsPreviewStateIdle => 'Не загружено';

  @override
  String get openLyricsPreviewStateRawLoaded => 'Готов к конвертации';

  @override
  String get openLyricsPreviewStateConverted => 'Преобразовано';

  @override
  String get openLyricsPreviewEmptyNoInput =>
      'Сначала откройте файл текста или песню.';

  @override
  String get openLyricsActionOpening => 'Открытие...';

  @override
  String get openLyricsActionOpenLyricsFile => 'Открыть файл с текстами песен';

  @override
  String get openLyricsActionOpenSongFile => 'Открыть файл песни';

  @override
  String get openLyricsActionConvertFormat => 'Преобразование формата';

  @override
  String get openLyricsActionSaveLyrics => 'Сохранить текст';

  @override
  String get openLyricsActionSaveToTag => 'Сохранить в тег песни';

  @override
  String get openLyricsActionTranslate => 'Перевести текст';

  @override
  String openLyricsExportFormatCanWriteTag(String format) {
    return 'Текущий формат экспорта: $format · можно записывать теги.';
  }

  @override
  String openLyricsExportFormatFileOnly(String format) {
    return 'Текущий формат экспорта: $format · только экспорт файлов';
  }

  @override
  String get searchLyricsSelectorTitle => 'Выберите текст';

  @override
  String get searchLyricsSelectorOpenLocal => 'Открыть локальные тексты песен';

  @override
  String get searchLyricsSelectorSelect => 'Выберите текст';

  @override
  String get searchLyricsSelectorDescription =>
      'Выберите онлайн-или локальные тексты песен для настольных компьютеров.';

  @override
  String searchLyricsSelectorOpenLocalFailed(String detail) {
    return 'Не удалось открыть локальный текст песни: $detail.';
  }

  @override
  String get searchLyricsSelectorSelectLyricsFirst => 'Сначала выберите текст';

  @override
  String get searchLyricsSelectorSelectFailed =>
      'Не удалось выбрать текст. Повторите попытку позже';

  @override
  String get searchDropUnsupportedItem =>
      'Поиск принимает анализируемые элементы песен или аудиофайлы.';

  @override
  String get searchNoticePartialSourcesFailed =>
      'Некоторые источники потерпели неудачу. Показаны результаты из других источников';

  @override
  String get searchNoticeAllSourcesFailed => 'Все источники поиска не удались';

  @override
  String get searchNoticeLoadMoreFailed =>
      'Некоторым источникам не удалось загрузить больше результатов.';

  @override
  String get searchNoticeDirectoryPickerUnsupported =>
      'Выбор каталога не поддерживается на этой платформе.';

  @override
  String searchNoticeAutoFetchSucceeded(String detail) {
    return 'Получен текст песни $detail.';
  }

  @override
  String searchNoticeAutoFetchFailed(String detail) {
    return 'Не удалось выполнить автоматическое получение: $detail.';
  }

  @override
  String get searchNoticeSelectedSongUnavailable =>
      'Доступный файл песни не выбран.';

  @override
  String get searchNoticeFilePickerUnsupported =>
      'Выбор файла песни не поддерживается на этой платформе.';

  @override
  String searchNoticeOpenSongFailed(String detail) {
    return 'Не удалось открыть песню: $detail.';
  }

  @override
  String get searchNoticeDroppedSongUnavailable =>
      'Переброшенный файл песни недоступен.';

  @override
  String searchNoticeDroppedSongResolveFailed(String detail) {
    return 'Не удалось разрешить удаленную песню: $detail.';
  }

  @override
  String get searchNoticeEmptyKeyword => 'Введите ключевое слово для поиска';

  @override
  String get searchNoticeGetLyricsFirst => 'Сначала получите тексты песен';

  @override
  String searchNoticeLyricsSaveSucceededWithPath(String detail) {
    return 'Текст сохранен: $detail';
  }

  @override
  String get searchNoticeSaveFileUnsupported =>
      'Сохранение файлов не поддерживается на этой платформе.';

  @override
  String get searchNoticeFilePickerForTagUnsupported =>
      'Выбор файла тега песни не поддерживается на этой платформе.';

  @override
  String searchNoticeFilePickerFailed(String detail) {
    return 'Не удалось выбрать файл: $detail.';
  }

  @override
  String get searchNoticeBatchCancelling => 'Отмена пакетного сохранения...';

  @override
  String get searchNoticeSelectAlbumOrPlaylistFirst =>
      'Сначала выберите альбом или плейлист';

  @override
  String get searchNoticeSelectAtLeastOneLyricsLanguage =>
      'Выберите хотя бы один язык текстов песен';

  @override
  String get searchNoticeNoSongsToSave => 'Нет песен для сохранения';

  @override
  String searchNoticeBatchSaveCancelled(int saved, int failed, int skipped) {
    return 'Пакетное сохранение отменено: $saved сохранен, $failed не выполнен, $skipped пропущен';
  }

  @override
  String searchNoticeBatchSaveCompleted(int saved, int failed, int skipped) {
    return 'Пакетное сохранение завершено: $saved сохранен, $failed не выполнен, $skipped пропущен';
  }

  @override
  String searchNoticeBatchSaveFailed(String detail) {
    return 'Не удалось выполнить пакетное сохранение: $detail.';
  }

  @override
  String get searchNoticeMultipleLyricsCandidates =>
      'Было найдено несколько лирических кандидатов. Выберите один, чтобы продолжить';

  @override
  String searchNoticeGetLyricsFailed(String detail) {
    return 'Не удалось получить текст песни: $detail.';
  }

  @override
  String get searchNoticeSelectSavePathFirst =>
      'Сначала выберите путь сохранения';

  @override
  String searchNoticeDirectoryPickFailed(String detail) {
    return 'Не удалось выбрать каталог: $detail.';
  }

  @override
  String get searchNoticePreviewLoading => 'Тексты еще загружаются';

  @override
  String get searchNoticePreviewNoLanguage =>
      'Выберите хотя бы один язык текстов песен';

  @override
  String get searchNoticePreviewNoContent =>
      'Текущие тексты песен не имеют содержания, доступного для предварительного просмотра.';

  @override
  String get searchNoticePreviewNoSelection =>
      'Сначала скачайте и просмотрите тексты песен';

  @override
  String get desktopWindowActionSelectLyrics => 'Выберите текст';

  @override
  String get desktopWindowActionMarkInstrumental =>
      'Отметить как инструментальную';

  @override
  String get desktopWindowActionDisableAutoSearch =>
      'Отключить автоматический поиск этой песни';

  @override
  String get desktopWindowActionUnlinkLyrics => 'Отсоединить тексты песен';

  @override
  String get desktopWindowActionAssociationManager =>
      'Менеджер ассоциации лирики';

  @override
  String get desktopWindowActionToggleFloating =>
      'Показать или скрыть тексты песен на рабочем столе';

  @override
  String get desktopWindowActionShowMainWindow => 'Показать главное окно';

  @override
  String get desktopWindowActionClickThrough => 'Переход по кликам';

  @override
  String get desktopWindowActionPrevious => 'Предыдущий';

  @override
  String get desktopWindowActionPlay => 'Играть';

  @override
  String get desktopWindowActionPause => 'Пауза';

  @override
  String get desktopWindowActionNext => 'Следующий';

  @override
  String get desktopWindowActionHide => 'Скрывать';

  @override
  String get desktopTrayCurrentTarget => 'Текущая цель:';

  @override
  String get desktopTrayNoSelection => 'Никто';

  @override
  String get desktopTrayTargetInstance => 'Целевой экземпляр';

  @override
  String get desktopTrayInstance => 'Пример';

  @override
  String get desktopTrayExit => 'Выход';

  @override
  String get desktopWindowInfoInstrumental => 'Инструментальный';

  @override
  String get desktopWindowControlConnectionLost =>
      'Соединение с плеером потеряно. Действие не было выполнено.';

  @override
  String get desktopWindowClientDisconnected =>
      'Соединение с плеером потеряно. Тексты песен на рабочем столе были закрыты.';
}
