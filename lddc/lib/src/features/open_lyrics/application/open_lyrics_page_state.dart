import 'dart:typed_data';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

enum OpenLyricsNoticeCode {
  openFailed,
  lyricsFileUnavailable,
  songFileUnavailable,
  noEmbeddedLyrics,
  alreadyConverted,
  emptyLyrics,
  convertFailed,
  convertFirst,
  translationCancelled,
  translationCompleted,
  translationFailed,
  noLyricsToSave,
  saveFileSucceeded,
  saveFileFailed,
  openSongFirst,
  audioTagUnsupported,
  audioTagRequiresLrc,
  saveTagSucceeded,
  saveTagFailed,
}

typedef OpenLyricsNotice = PageNotice<OpenLyricsNoticeCode>;

enum OpenLyricsInputType { lyricsFile, songFile }

enum OpenLyricsPreviewState { idle, rawLoaded, converted }

enum OpenLyricsEmptyReason { noInput, noLanguage, noContent }

class OpenLyricsPageState {
  const OpenLyricsPageState({
    required this.inputType,
    required this.inputName,
    required this.inputPath,
    required this.audioFileHandle,
    required this.lyricsFileBytes,
    required this.rawText,
    required this.previewText,
    required this.currentLyrics,
    required this.lyricsFormat,
    required this.selectedLangs,
    required this.offsetMs,
    required this.previewState,
    required this.emptyReason,
    required this.isOpening,
    required this.isConverting,
    required this.isTranslating,
    required this.translationProgress,
    required this.isSaving,
    required this.notice,
  });

  final OpenLyricsInputType? inputType;
  final String inputName;
  final String? inputPath;
  final PickedAudioFileHandle? audioFileHandle;
  final Uint8List? lyricsFileBytes;
  final String rawText;
  final String previewText;
  final Lyrics? currentLyrics;
  final LyricsFormat lyricsFormat;
  final List<String> selectedLangs;
  final int offsetMs;
  final OpenLyricsPreviewState previewState;
  final OpenLyricsEmptyReason? emptyReason;
  final bool isOpening;
  final bool isConverting;
  final bool isTranslating;
  final OpenAiTranslationProgress? translationProgress;
  final bool isSaving;
  final OpenLyricsNotice? notice;

  bool get hasPreview => previewText.trim().isNotEmpty;

  bool get canConvert =>
      !isOpening &&
      !isConverting &&
      rawText.trim().isNotEmpty &&
      currentLyrics == null;

  bool get canTranslate =>
      currentLyrics != null && !isTranslating && !isOpening && !isConverting;

  bool get canSaveFile => hasPreview && !isSaving && !isOpening;

  bool get canSaveToTag =>
      audioFileHandle != null &&
      currentLyrics != null &&
      hasPreview &&
      !isSaving &&
      !isOpening;

  OpenLyricsPageState copyWith({
    OpenLyricsInputType? inputType,
    bool clearInputType = false,
    String? inputName,
    String? inputPath,
    bool clearInputPath = false,
    PickedAudioFileHandle? audioFileHandle,
    bool clearAudioFileHandle = false,
    Uint8List? lyricsFileBytes,
    bool clearLyricsFileBytes = false,
    String? rawText,
    String? previewText,
    Lyrics? currentLyrics,
    bool clearCurrentLyrics = false,
    LyricsFormat? lyricsFormat,
    List<String>? selectedLangs,
    int? offsetMs,
    OpenLyricsPreviewState? previewState,
    OpenLyricsEmptyReason? emptyReason,
    bool clearEmptyReason = false,
    bool? isOpening,
    bool? isConverting,
    bool? isTranslating,
    OpenAiTranslationProgress? translationProgress,
    bool clearTranslationProgress = false,
    bool? isSaving,
    OpenLyricsNotice? notice,
    bool clearNotice = false,
  }) {
    return OpenLyricsPageState(
      inputType: clearInputType ? null : (inputType ?? this.inputType),
      inputName: inputName ?? this.inputName,
      inputPath: clearInputPath ? null : (inputPath ?? this.inputPath),
      audioFileHandle: clearAudioFileHandle
          ? null
          : (audioFileHandle ?? this.audioFileHandle),
      lyricsFileBytes: clearLyricsFileBytes
          ? null
          : (lyricsFileBytes ?? this.lyricsFileBytes),
      rawText: rawText ?? this.rawText,
      previewText: previewText ?? this.previewText,
      currentLyrics: clearCurrentLyrics
          ? null
          : (currentLyrics ?? this.currentLyrics),
      lyricsFormat: lyricsFormat ?? this.lyricsFormat,
      selectedLangs: selectedLangs ?? this.selectedLangs,
      offsetMs: offsetMs ?? this.offsetMs,
      previewState: previewState ?? this.previewState,
      emptyReason: clearEmptyReason ? null : (emptyReason ?? this.emptyReason),
      isOpening: isOpening ?? this.isOpening,
      isConverting: isConverting ?? this.isConverting,
      isTranslating: isTranslating ?? this.isTranslating,
      translationProgress: clearTranslationProgress
          ? null
          : (translationProgress ?? this.translationProgress),
      isSaving: isSaving ?? this.isSaving,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }

  static OpenLyricsPageState initial() {
    return const OpenLyricsPageState(
      inputType: null,
      inputName: '',
      inputPath: null,
      audioFileHandle: null,
      lyricsFileBytes: null,
      rawText: '',
      previewText: '',
      currentLyrics: null,
      lyricsFormat: LyricsFormat.verbatimLrc,
      selectedLangs: <String>['orig', 'ts'],
      offsetMs: 0,
      previewState: OpenLyricsPreviewState.idle,
      emptyReason: OpenLyricsEmptyReason.noInput,
      isOpening: false,
      isConverting: false,
      isTranslating: false,
      translationProgress: null,
      isSaving: false,
      notice: null,
    );
  }
}
