import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_file_reader.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_input_decoder.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_input_picker.dart';

void main() {
  test('打开歌词选择器使用统一本地歌词扩展名能力', () async {
    final _RecordingAppFilePicker filePicker = _RecordingAppFilePicker();
    final OpenLyricsInputPicker picker = OpenLyricsInputPickerImpl(
      filePicker: filePicker,
    );

    await picker.pickLyricsFile(initialDirectory: r'D:\lyrics');

    expect(filePicker.lastInitialDirectory, r'D:\lyrics');
    expect(
      filePicker.lastAllowedExtensions,
      localLyricsInputSupportedExtensions,
    );
    expect(
      filePicker.lastAllowedExtensions,
      containsAll(<String>['json', 'yrc', 'txt']),
    );
  });

  test('打开歌词原始展示解码支持 JSON、YRC 与 TXT 文本歌词', () {
    final OpenLyricsInputDecoder decoder = OpenLyricsInputDecoder();

    expect(
      decoder.decodeLyricsFile(
        data: utf8.encode('{"version":1,"info":{}}'),
        path: r'D:\lyrics\demo.json',
      ),
      contains('"version"'),
    );
    expect(
      decoder.decodeLyricsFile(
        data: utf8.encode('[0,1000](0,1000,0)逐字歌词'),
        path: r'D:\lyrics\demo.yrc',
      ),
      contains('逐字歌词'),
    );
    expect(
      decoder.decodeLyricsFile(
        data: utf8.encode('[00:00.00]未知文本歌词'),
        path: r'D:\lyrics\demo.txt',
      ),
      contains('未知文本歌词'),
    );
  });

  test('打开歌词 reader 在读取前按文件大小拒绝异常输入', () async {
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'lddc_open_lyrics_reader_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final File file = File('${tempDir.path}${Platform.pathSeparator}huge.lrc');
    file.writeAsBytesSync(Uint8List(9));

    final OpenLyricsFileReader reader = const OpenLyricsFileReaderImpl(
      maxBytes: 8,
    );

    Object? caught;
    try {
      await reader.readLocalPath(file.path);
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<OpenLyricsFileTooLargeException>());
  });
}

class _RecordingAppFilePicker implements AppFilePicker {
  List<String>? lastAllowedExtensions;
  String? lastInitialDirectory;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => null;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    lastAllowedExtensions = allowedExtensions;
    lastInitialDirectory = initialDirectory;
    return null;
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return const <PickedFileHandle>[];
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
    return null;
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {}

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    return null;
  }
}
