import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'open_lyrics_dependencies.dart';
import 'open_lyrics_file_reader.dart';
import 'open_lyrics_input_decoder.dart';
import 'open_lyrics_input_picker.dart';
import 'open_lyrics_page_state.dart';

final NotifierProvider<OpenLyricsPageController, OpenLyricsPageState>
openLyricsPageControllerProvider =
    NotifierProvider<OpenLyricsPageController, OpenLyricsPageState>(
      OpenLyricsPageController.new,
      // 打开歌词页持有临时音频句柄；controller 必须跟随局部依赖 scope 创建和释放，
      // 这样测试替身与真实 app 注入都能正确接管资源生命周期。
      dependencies: [openLyricsDependenciesProvider],
    );

class OpenLyricsPageController extends Notifier<OpenLyricsPageState> {
  int _noticeId = 0;
  final OperationEpoch _inputEpoch = OperationEpoch();
  int _translationRequestId = 0;
  int _conversionRequestId = 0;
  int _saveRequestId = 0;
  OpenLyricsInputPicker? _inputPickerCache;
  PickedAudioFileHandle? _activeAudioFileHandle;

  OpenLyricsInputPicker get _inputPicker {
    final OpenLyricsInputPicker cached =
        _inputPickerCache ??
        ref.read(openLyricsDependenciesProvider).inputPicker;
    _inputPickerCache = cached;
    return cached;
  }

  OpenLyricsDependencies get _dependencies =>
      ref.read(openLyricsDependenciesProvider);
  LyricsClient get _lyricsApi => _dependencies.lyricsApi;
  TranslationClient get _translateApi => _dependencies.translateApi;
  LocalMatchMediaGateway get _mediaGateway => _dependencies.mediaGateway;
  ConfigRepository get _configRepository => _dependencies.configRepository;
  OpenLyricsFileReader get _fileReader => _dependencies.fileReader;

  AppConfig get _config => _configRepository.current;

  @override
  OpenLyricsPageState build() {
    ref.onDispose(() {
      final PickedAudioFileHandle? audioFileHandle = _activeAudioFileHandle;
      final OpenLyricsInputPicker? inputPicker = _inputPickerCache;
      if (audioFileHandle != null && inputPicker != null) {
        unawaited(
          _safeReleaseAudioFile(audioFileHandle, inputPicker: inputPicker),
        );
      }
    });
    return OpenLyricsPageState.initial();
  }

  void dismissNotice([int? id]) {
    if (id != null && state.notice?.id != id) {
      return;
    }
    state = state.copyWith(clearNotice: true);
  }

  Future<void> disposeSession() async {
    _inputEpoch.invalidate();
    _translationRequestId += 1;
    _conversionRequestId += 1;
    _saveRequestId += 1;
    final PickedAudioFileHandle? audioFileHandle = _activeAudioFileHandle;
    _activeAudioFileHandle = null;
    state = OpenLyricsPageState.initial();
    if (audioFileHandle != null) {
      await _safeReleaseAudioFile(audioFileHandle);
    }
  }

  void updateSelectedLangs(Set<String> langs) {
    _updatePreviewOptions(selectedLangs: langs.toList(growable: false));
  }

  void updateLyricsFormat(LyricsFormat lyricsFormat) {
    _updatePreviewOptions(lyricsFormat: lyricsFormat);
  }

  void updateOffsetMs(int offsetMs) {
    _updatePreviewOptions(offsetMs: offsetMs);
  }

  Future<void> openLyricsFile() async {
    final int generation = _inputEpoch.next();
    state = state.copyWith(isOpening: true, clearNotice: true);
    try {
      final PickedFileHandle? file = await _inputPicker.pickLyricsFile(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (file == null) {
        state = state.copyWith(isOpening: false);
        return;
      }
      final Uint8List bytes = await _fileReader.readPickedFile(file);
      final String rawText = OpenLyricsInputDecoder().decodeLyricsFile(
        data: bytes,
        path: file.path ?? file.name,
      );
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      await _replaceInput(
        generation: generation,
        inputType: OpenLyricsInputType.lyricsFile,
        inputName: file.name,
        inputPath: file.path,
        rawText: rawText,
        lyricsFileBytes: bytes,
      );
    } on Exception catch (error) {
      _emitNotice(
        OpenLyricsNoticeCode.openFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isOpening: false);
    }
  }

  Future<void> openExternalLyricsFile(String path) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      _emitNotice(
        OpenLyricsNoticeCode.lyricsFileUnavailable,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _inputEpoch.next();
    state = state.copyWith(isOpening: true, clearNotice: true);
    try {
      final Uint8List bytes = await _fileReader.readLocalPath(normalizedPath);
      final String rawText = OpenLyricsInputDecoder().decodeLyricsFile(
        data: bytes,
        path: normalizedPath,
      );
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      await _replaceInput(
        generation: generation,
        inputType: OpenLyricsInputType.lyricsFile,
        inputName: p.basename(normalizedPath),
        inputPath: normalizedPath,
        rawText: rawText,
        lyricsFileBytes: bytes,
      );
    } on Exception catch (error) {
      _emitNotice(
        OpenLyricsNoticeCode.openFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isOpening: false);
    }
  }

  Future<void> openSongFile() async {
    final int generation = _inputEpoch.next();
    state = state.copyWith(isOpening: true, clearNotice: true);
    PickedAudioFileHandle? pickedFile;
    try {
      pickedFile = await _inputPicker.pickAudioFile(
        initialDirectory: _resolveInitialDirectory(),
      );
      if (pickedFile == null) {
        state = state.copyWith(isOpening: false);
        return;
      }
      final String? songPath = pickedFile.targetPath;
      if (songPath == null || songPath.trim().isEmpty) {
        throw const FormatException('所选歌曲文件不可访问');
      }
      final String? rawText = await _mediaGateway.readAudioLyricsText(
        songPath: songPath,
        fileDescriptor: pickedFile.fileDescriptor,
        fileDescriptorNameHint: pickedFile.fileDescriptorNameHint,
      );
      if (!_isCurrentGeneration(generation)) {
        await _inputPicker.releaseAudioFile(pickedFile);
        return;
      }
      if (rawText == null || rawText.trim().isEmpty) {
        await _safeReleaseAudioFile(pickedFile);
        state = state.copyWith(isOpening: false);
        _emitNotice(
          OpenLyricsNoticeCode.noEmbeddedLyrics,
          PageNoticeSeverity.warning,
        );
        return;
      }
      await _replaceInput(
        generation: generation,
        inputType: OpenLyricsInputType.songFile,
        inputName: pickedFile.name,
        inputPath: songPath,
        rawText: rawText,
        audioFileHandle: pickedFile,
      );
    } on Exception catch (error) {
      if (pickedFile != null) {
        await _safeReleaseAudioFile(pickedFile);
      }
      _emitNotice(
        OpenLyricsNoticeCode.openFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isOpening: false);
    }
  }

  Future<void> openExternalSongFile(String path) async {
    final String normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      _emitNotice(
        OpenLyricsNoticeCode.songFileUnavailable,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _inputEpoch.next();
    state = state.copyWith(isOpening: true, clearNotice: true);
    try {
      final String? rawText = await _mediaGateway.readAudioLyricsText(
        songPath: normalizedPath,
      );
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      if (rawText == null || rawText.trim().isEmpty) {
        state = state.copyWith(isOpening: false);
        _emitNotice(
          OpenLyricsNoticeCode.noEmbeddedLyrics,
          PageNoticeSeverity.warning,
        );
        return;
      }
      await _replaceInput(
        generation: generation,
        inputType: OpenLyricsInputType.songFile,
        inputName: p.basename(normalizedPath),
        inputPath: normalizedPath,
        rawText: rawText,
      );
    } on Exception catch (error) {
      _emitNotice(
        OpenLyricsNoticeCode.openFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isOpening: false);
    }
  }

  Future<void> convert() async {
    if (state.currentLyrics != null) {
      _emitNotice(
        OpenLyricsNoticeCode.alreadyConverted,
        PageNoticeSeverity.info,
      );
      return;
    }
    if (state.rawText.trim().isEmpty) {
      _emitNotice(OpenLyricsNoticeCode.emptyLyrics, PageNoticeSeverity.warning);
      return;
    }
    final int generation = _inputEpoch.current;
    final int requestId = ++_conversionRequestId;
    state = state.copyWith(isConverting: true, clearNotice: true);
    try {
      final Lyrics lyrics = switch (state.inputType) {
        OpenLyricsInputType.lyricsFile => await _convertLyricsFile(),
        OpenLyricsInputType.songFile => await _convertSongLyrics(),
        null => throw StateError('请先打开文件'),
      };
      if (!_isCurrentGeneration(generation) ||
          requestId != _conversionRequestId) {
        return;
      }
      _applyLyrics(lyrics, clearLyricsFileBytes: true);
    } on Exception catch (error) {
      if (!_isCurrentGeneration(generation) ||
          requestId != _conversionRequestId) {
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.convertFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isConverting: false);
    }
  }

  Future<void> toggleTranslation() async {
    final Lyrics? lyrics = state.currentLyrics;
    if (lyrics == null) {
      _emitNotice(
        OpenLyricsNoticeCode.convertFirst,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (lyrics.data.containsKey('LDDC_ts')) {
      final Map<String, LyricsData> nextData = <String, LyricsData>{
        ...lyrics.data,
      }..remove('LDDC_ts');
      _translationRequestId += 1;
      _applyLyrics(lyrics.copyWith(data: nextData));
      _emitNotice(
        OpenLyricsNoticeCode.translationCancelled,
        PageNoticeSeverity.info,
      );
      return;
    }
    final int generation = _inputEpoch.current;
    final int requestId = ++_translationRequestId;
    final bool reportsOpenAiProgress =
        _config.translate.source == TranslateSource.openai;
    state = state.copyWith(
      isTranslating: true,
      clearNotice: true,
      translationProgress: reportsOpenAiProgress
          ? OpenAiTranslationProgress.initial(
              totalLines: lyrics['orig']?.length ?? 0,
            )
          : null,
      clearTranslationProgress: !reportsOpenAiProgress,
    );
    try {
      final LyricsData tsData = await _translateApi.translateLyrics(
        lyrics,
        onOpenAiProgress: reportsOpenAiProgress
            ? (OpenAiTranslationProgress progress) {
                if (!_isCurrentGeneration(generation) ||
                    requestId != _translationRequestId ||
                    state.currentLyrics != lyrics) {
                  return;
                }
                state = state.copyWith(translationProgress: progress);
              }
            : null,
      );
      if (!_isCurrentGeneration(generation) ||
          requestId != _translationRequestId ||
          state.currentLyrics == null) {
        return;
      }
      final Map<String, LyricsData> nextData = <String, LyricsData>{
        ...state.currentLyrics!.data,
        'LDDC_ts': tsData,
      };
      _applyLyrics(state.currentLyrics!.copyWith(data: nextData));
      _emitNotice(
        OpenLyricsNoticeCode.translationCompleted,
        PageNoticeSeverity.success,
      );
    } on Exception catch (error) {
      if (!_isCurrentGeneration(generation) ||
          requestId != _translationRequestId) {
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.translationFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(
        isTranslating: false,
        clearTranslationProgress: true,
      );
    }
  }

  Future<void> saveToFile() async {
    if (state.previewText.trim().isEmpty) {
      _emitNotice(
        OpenLyricsNoticeCode.noLyricsToSave,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final int generation = _inputEpoch.current;
    final int requestId = ++_saveRequestId;
    final String previewText = state.previewText;
    final String fileName = _buildSuggestedFileName();
    final String? initialDirectory = _resolveInitialDirectory();
    final List<String>? allowedExtensions = _allowedSaveExtensions();
    state = state.copyWith(isSaving: true, clearNotice: true);
    try {
      final SavedTextFileResult? saveResult = await _inputPicker.saveTextFile(
        fileName: fileName,
        text: previewText,
        initialDirectory: initialDirectory,
        allowedExtensions: allowedExtensions,
      );
      if (!_isCurrentGeneration(generation) || requestId != _saveRequestId) {
        return;
      }
      if (saveResult == null) {
        state = state.copyWith(isSaving: false);
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.saveFileSucceeded,
        PageNoticeSeverity.success,
        detail: saveResult.displayPath,
      );
      state = state.copyWith(isSaving: false);
    } on Exception catch (error) {
      if (!_isCurrentGeneration(generation) || requestId != _saveRequestId) {
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.saveFileFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isSaving: false);
    }
  }

  Future<void> saveToTag() async {
    final Lyrics? lyrics = state.currentLyrics;
    final PickedAudioFileHandle? audioFileHandle = state.audioFileHandle;
    if (lyrics == null || state.previewText.trim().isEmpty) {
      _emitNotice(
        OpenLyricsNoticeCode.noLyricsToSave,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (audioFileHandle == null ||
        state.inputType != OpenLyricsInputType.songFile) {
      _emitNotice(
        OpenLyricsNoticeCode.openSongFirst,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (!_dependencies.capability.audioTagWrite) {
      _emitNotice(
        OpenLyricsNoticeCode.audioTagUnsupported,
        PageNoticeSeverity.warning,
      );
      return;
    }
    if (!LyricsFormatCapabilities.isLrcFamily(state.lyricsFormat)) {
      _emitNotice(
        OpenLyricsNoticeCode.audioTagRequiresLrc,
        PageNoticeSeverity.warning,
      );
      return;
    }
    final String? songPath = audioFileHandle.targetPath;
    if (songPath == null || songPath.trim().isEmpty) {
      _emitNotice(
        OpenLyricsNoticeCode.songFileUnavailable,
        PageNoticeSeverity.error,
      );
      return;
    }
    final int generation = _inputEpoch.current;
    final int requestId = ++_saveRequestId;
    final String previewText = state.previewText;
    final Id3Version id3Version = _config.lyrics.id3Version;
    state = state.copyWith(isSaving: true, clearNotice: true);
    PickedAudioFileHandle? writableAudioFile;
    try {
      writableAudioFile = await _inputPicker.openAudioFileForWrite(
        audioFileHandle,
      );
      await _mediaGateway.writeLyricsTag(
        songPath: songPath,
        lyricsText: previewText,
        lyrics: lyrics,
        id3Version: id3Version,
        fileDescriptor: writableAudioFile.fileDescriptor,
        fileDescriptorNameHint: writableAudioFile.fileDescriptorNameHint,
      );
      if (!_isCurrentGeneration(generation) || requestId != _saveRequestId) {
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.saveTagSucceeded,
        PageNoticeSeverity.success,
      );
      state = state.copyWith(isSaving: false);
    } on Exception catch (error) {
      if (!_isCurrentGeneration(generation) || requestId != _saveRequestId) {
        return;
      }
      _emitNotice(
        OpenLyricsNoticeCode.saveTagFailed,
        PageNoticeSeverity.error,
        detail: error.toString(),
      );
      state = state.copyWith(isSaving: false);
    } finally {
      if (writableAudioFile != null && writableAudioFile != audioFileHandle) {
        await _safeReleaseAudioFile(writableAudioFile);
      }
    }
  }

  void _updatePreviewOptions({
    List<String>? selectedLangs,
    LyricsFormat? lyricsFormat,
    int? offsetMs,
  }) {
    state = state.copyWith(
      selectedLangs: selectedLangs ?? state.selectedLangs,
      lyricsFormat: lyricsFormat ?? state.lyricsFormat,
      offsetMs: offsetMs ?? state.offsetMs,
      isSaving: false,
      clearNotice: true,
    );
    // 预览参数改变后，旧保存动作仍可能在系统文件选择器或标签写入中返回；
    // 递增保存代际可以阻止旧完成提示误指向新的预览内容。
    _saveRequestId += 1;
    final Lyrics? lyrics = state.currentLyrics;
    if (lyrics != null) {
      _applyLyrics(lyrics, clearTranslationProgress: false);
    }
  }

  Future<Lyrics> _convertLyricsFile() async {
    final Uint8List? data = state.lyricsFileBytes;
    if (data == null || data.isEmpty) {
      throw StateError('原始歌词文件数据已丢失');
    }
    return _lyricsApi.getLyrics(path: state.inputPath, data: data);
  }

  Future<Lyrics> _convertSongLyrics() async {
    return _lyricsApi.getLyrics(
      path: null,
      data: Uint8List.fromList(utf8.encode(state.rawText)),
    );
  }

  void _applyLyrics(
    Lyrics lyrics, {
    bool clearLyricsFileBytes = false,
    bool clearTranslationProgress = true,
  }) {
    _saveRequestId += 1;
    final String previewText = LyricsPreviewComposer.buildPreviewText(
      lyrics: lyrics,
      selectedLangs: state.selectedLangs,
      lyricsFormat: state.lyricsFormat,
      offsetMs: state.offsetMs,
      options: _config.toLyricsConvertOptions(),
    );
    state = state.copyWith(
      currentLyrics: lyrics,
      previewText: previewText,
      previewState: OpenLyricsPreviewState.converted,
      emptyReason: _resolveEmptyReason(
        previewText: previewText,
        currentLyrics: lyrics,
      ),
      isConverting: false,
      isTranslating: false,
      clearTranslationProgress: clearTranslationProgress,
      clearLyricsFileBytes: clearLyricsFileBytes,
    );
  }

  Future<void> _replaceInput({
    required int generation,
    required OpenLyricsInputType inputType,
    required String inputName,
    required String? inputPath,
    required String rawText,
    Uint8List? lyricsFileBytes,
    PickedAudioFileHandle? audioFileHandle,
  }) async {
    if (!_isCurrentGeneration(generation)) {
      if (audioFileHandle != null) {
        await _safeReleaseAudioFile(audioFileHandle);
      }
      return;
    }
    _translationRequestId += 1;
    _conversionRequestId += 1;
    _saveRequestId += 1;
    await _releaseCurrentAudioHandle();
    _activeAudioFileHandle = audioFileHandle;
    state = state.copyWith(
      inputType: inputType,
      inputName: inputName,
      inputPath: inputPath,
      audioFileHandle: audioFileHandle,
      clearAudioFileHandle: audioFileHandle == null,
      lyricsFileBytes: lyricsFileBytes,
      clearLyricsFileBytes: lyricsFileBytes == null,
      rawText: rawText,
      previewText: rawText,
      clearCurrentLyrics: true,
      clearTranslationProgress: true,
      previewState: OpenLyricsPreviewState.rawLoaded,
      emptyReason: rawText.trim().isEmpty
          ? OpenLyricsEmptyReason.noContent
          : null,
      isOpening: false,
      isConverting: false,
      isTranslating: false,
      isSaving: false,
    );
  }

  OpenLyricsEmptyReason? _resolveEmptyReason({
    required String previewText,
    required Lyrics? currentLyrics,
  }) {
    if (previewText.trim().isNotEmpty) {
      return null;
    }
    if (currentLyrics == null) {
      return OpenLyricsEmptyReason.noInput;
    }
    if (state.selectedLangs.isEmpty) {
      return OpenLyricsEmptyReason.noLanguage;
    }
    return OpenLyricsEmptyReason.noContent;
  }

  bool _isCurrentGeneration(int generation) {
    return _inputEpoch.isCurrent(generation);
  }

  String? _resolveInitialDirectory() {
    final String? path = state.inputPath?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    return p.dirname(path);
  }

  List<String>? _allowedSaveExtensions() {
    final String ext = _resolveSaveExtension();
    if (ext.isEmpty) {
      return null;
    }
    return <String>[ext];
  }

  String _buildSuggestedFileName() {
    final String inputName = state.inputName.trim().isEmpty
        ? 'lyrics'
        : state.inputName.trim();
    final String baseName = p.basenameWithoutExtension(inputName);
    return '$baseName.${_resolveSaveExtension()}';
  }

  String _resolveSaveExtension() {
    if (state.currentLyrics != null) {
      return state.lyricsFormat.ext.replaceFirst('.', '');
    }
    if (state.inputType == OpenLyricsInputType.songFile) {
      return 'txt';
    }
    final String ext = p
        .extension(state.inputName)
        .replaceFirst('.', '')
        .trim();
    if (ext.isNotEmpty) {
      return ext;
    }
    return 'txt';
  }

  Future<void> _releaseCurrentAudioHandle() async {
    final PickedAudioFileHandle? audioFileHandle = _activeAudioFileHandle;
    if (audioFileHandle == null) {
      return;
    }
    _activeAudioFileHandle = null;
    await _safeReleaseAudioFile(audioFileHandle);
  }

  Future<void> _safeReleaseAudioFile(
    PickedAudioFileHandle audioFileHandle, {
    OpenLyricsInputPicker? inputPicker,
  }) async {
    final OpenLyricsInputPicker picker = inputPicker ?? _inputPicker;
    try {
      await picker.releaseAudioFile(audioFileHandle);
    } on Exception {
      // 释放失败不覆盖主链路结果，避免误报业务失败。
    }
  }

  void _emitNotice(
    OpenLyricsNoticeCode code,
    PageNoticeSeverity severity, {
    String? detail,
  }) {
    _noticeId += 1;
    state = state.copyWith(
      notice: OpenLyricsNotice(
        id: _noticeId,
        severity: severity,
        code: code,
        detail: detail,
      ),
    );
  }
}
