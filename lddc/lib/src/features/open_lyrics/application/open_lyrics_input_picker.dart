import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 打开歌词页输入选择端口：只暴露该页面真正需要的选择能力。
abstract interface class OpenLyricsInputPicker {
  Future<PickedFileHandle?> pickLyricsFile({String? initialDirectory});

  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory});

  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  );

  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  });

  Future<void> releaseAudioFile(PickedAudioFileHandle file);
}

class OpenLyricsInputPickerImpl implements OpenLyricsInputPicker {
  const OpenLyricsInputPickerImpl({required AppFilePicker filePicker})
    : _filePicker = filePicker;

  final AppFilePicker _filePicker;

  @override
  Future<PickedFileHandle?> pickLyricsFile({String? initialDirectory}) {
    return _filePicker.pickFile(
      allowedExtensions: localLyricsInputSupportedExtensions,
      initialDirectory: initialDirectory,
      label: 'lyrics',
    );
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory}) {
    return _filePicker.pickAudioFile(initialDirectory: initialDirectory);
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) {
    return _filePicker.openAudioFileForWrite(file);
  }

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) {
    return _filePicker.saveTextFile(
      fileName: fileName,
      text: text,
      initialDirectory: initialDirectory,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) {
    return _filePicker.releaseAudioFile(file);
  }
}
