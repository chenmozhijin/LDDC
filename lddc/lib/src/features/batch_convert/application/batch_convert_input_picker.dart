import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

abstract interface class BatchConvertInputPicker {
  Future<List<PickedFileHandle>> pickLyricsFiles({String? initialDirectory});

  Future<List<String>> pickLyricsDirectories({String? initialDirectory});

  Future<String?> pickSaveRootDirectory({String? initialDirectory});
}

class BatchConvertInputPickerImpl implements BatchConvertInputPicker {
  const BatchConvertInputPickerImpl({required AppFilePicker filePicker})
    : _filePicker = filePicker;

  final AppFilePicker _filePicker;

  @override
  Future<List<PickedFileHandle>> pickLyricsFiles({String? initialDirectory}) {
    return _filePicker.pickFiles(
      allowedExtensions: localLyricsInputSupportedExtensions,
      initialDirectory: initialDirectory,
      label: 'lyrics',
    );
  }

  @override
  Future<List<String>> pickLyricsDirectories({String? initialDirectory}) async {
    final String? directory = await _filePicker.pickDirectory(
      initialDirectory: initialDirectory,
    );
    if (directory == null || directory.trim().isEmpty) {
      return const <String>[];
    }
    return <String>[directory.trim()];
  }

  @override
  Future<String?> pickSaveRootDirectory({String? initialDirectory}) {
    return _filePicker.pickDirectory(initialDirectory: initialDirectory);
  }
}
