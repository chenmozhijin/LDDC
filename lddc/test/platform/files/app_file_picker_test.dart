import 'dart:io';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel iosChannel = MethodChannel(
    'lddc/ios_search_audio_tag_test',
  );
  const MethodChannel androidChannel = MethodChannel(
    'lddc/android_search_file_test',
  );

  setUp(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iosChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iosChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('AppFilePickerImpl', () {
    test('桌面端选择目录时只做字符串归一化，不同步 stat 失效路径', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-picker-dir-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final _FakeFileDialog fileDialog = _FakeFileDialog(
        pickDirectoryResult: root.path,
      );
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final String? directory = await picker.pickDirectory(
        initialDirectory:
            '${root.path}${Platform.pathSeparator}missing${Platform.pathSeparator}child',
      );

      expect(directory, root.path);
      expect(
        fileDialog.lastPickDirectoryInitialDirectory,
        '${root.path}${Platform.pathSeparator}missing${Platform.pathSeparator}child',
      );
    });

    test('桌面端选择音频文件时映射为搜索文件对象', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-picker-audio-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final File songFile = File(
        '${root.path}${Platform.pathSeparator}picked.mp3',
      )..writeAsStringSync('demo');
      final _FakeFileDialog fileDialog = _FakeFileDialog(
        pickFileResult: selector.XFile(songFile.path),
      );
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final PickedAudioFileHandle? file = await picker.pickAudioFile(
        initialDirectory: root.path,
      );

      expect(file, isNotNull);
      expect(file?.name, 'picked.mp3');
      expect(file?.path, songFile.path);
      expect(fileDialog.lastPickFileInitialDirectory, root.path);
      expect(fileDialog.lastPickFileAllowedExtensions, audioFileExtensions);
    });

    test('桌面端选择普通文件时返回可读取字节的文件句柄', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-picker-generic-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final File file = File('${root.path}${Platform.pathSeparator}demo.lrc')
        ..writeAsStringSync('[00:00.00]demo');
      final _FakeFileDialog fileDialog = _FakeFileDialog(
        pickFileResult: selector.XFile(file.path),
      );
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final PickedFileHandle? pickedFile = await picker.pickFile(
        allowedExtensions: const <String>['lrc'],
        initialDirectory: root.path,
        label: 'lyrics',
      );

      expect(pickedFile, isNotNull);
      expect(pickedFile?.name, 'demo.lrc');
      expect(await pickedFile?.readAsBytes(), isNotNull);
      expect(fileDialog.lastPickFileAllowedExtensions, const <String>['lrc']);
    });

    test('桌面端选择多个普通文件时返回多个文件句柄', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-picker-generic-multi-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final File firstFile = File('${root.path}${Platform.pathSeparator}a.lrc')
        ..writeAsStringSync('[00:00.00]a');
      final File secondFile = File('${root.path}${Platform.pathSeparator}b.lrc')
        ..writeAsStringSync('[00:00.00]b');
      final _FakeFileDialog fileDialog = _FakeFileDialog(
        pickFilesResult: <selector.XFile>[
          selector.XFile(firstFile.path),
          selector.XFile(secondFile.path),
        ],
      );
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final List<PickedFileHandle> pickedFiles = await picker.pickFiles(
        allowedExtensions: const <String>['lrc'],
        initialDirectory: root.path,
        label: 'lyrics',
      );

      expect(pickedFiles, hasLength(2));
      expect(pickedFiles.first.name, 'a.lrc');
      expect(pickedFiles.last.name, 'b.lrc');
      expect(fileDialog.lastPickFileAllowedExtensions, const <String>['lrc']);
    });

    test('桌面端保存文本时通过 file_selector 写入目标文件', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final Directory root = await Directory.systemTemp.createTemp(
        'lddc-picker-save-',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });
      final File outputFile = File(
        '${root.path}${Platform.pathSeparator}lyrics.lrc',
      );
      final _FakeFileDialog fileDialog = _FakeFileDialog(
        pickSaveLocationResult: selector.FileSaveLocation(outputFile.path),
      );
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final SavedTextFileResult? saveResult = await picker.saveTextFile(
        fileName: 'lyrics.lrc',
        text: '保存到桌面文件',
        initialDirectory: root.path,
        allowedExtensions: const <String>['lrc'],
      );

      expect(saveResult?.kind, SavedTextFileResultKind.localPath);
      expect(saveResult?.localPath, outputFile.path);
      expect(saveResult?.displayPath, outputFile.path);
      expect(outputFile.readAsStringSync(), '保存到桌面文件');
      expect(fileDialog.lastSaveFileName, 'lyrics.lrc');
      expect(fileDialog.lastSaveInitialDirectory, root.path);
      expect(fileDialog.lastSaveAllowedExtensions, const <String>['lrc']);
    });

    test('桌面端取消保存时返回 null 且不创建输出文件', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final _FakeFileDialog fileDialog = _FakeFileDialog();
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      final SavedTextFileResult? result = await picker.saveTextFile(
        fileName: 'cancelled.lrc',
        text: '不会写入的歌词',
        initialDirectory: '  D:/lyrics  ',
        allowedExtensions: const <String>['lrc'],
      );

      expect(result, isNull);
      expect(fileDialog.pickSaveLocationCallCount, 1);
      expect(fileDialog.lastSaveInitialDirectory, 'D:/lyrics');
    });

    test('不支持的平台在打开保存对话框前直接拒绝', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      final _FakeFileDialog fileDialog = _FakeFileDialog();
      final AppFilePickerImpl picker = AppFilePickerImpl(
        fileDialog: fileDialog,
      );

      await expectLater(
        picker.saveTextFile(fileName: 'lyrics.lrc', text: 'demo'),
        throwsUnsupportedError,
      );

      expect(fileDialog.pickSaveLocationCallCount, 0);
    });

    test('Android 通过 MethodChannel 选择音频文件并保留 content uri', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'name': 'picked.mp3',
              'identifier': 'content://media/external/audio/media/42',
            };
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        androidSearchFileChannel: androidChannel,
      );

      final PickedAudioFileHandle? file = await picker.pickAudioFile(
        initialDirectory: 'content://tree/demo',
      );

      expect(receivedCall?.method, 'pickAudioFile');
      expect(receivedCall?.arguments, <String, Object?>{
        'initialDirectory': 'content://tree/demo',
      });
      expect(file?.name, 'picked.mp3');
      expect(file?.identifier, 'content://media/external/audio/media/42');
      expect(file?.targetPath, 'content://media/external/audio/media/42');
    });

    test('Android 保存文本时透传字节和 mimeType', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (MethodCall call) async {
            receivedCall = call;
            return 'content://documents/document/lyrics.json';
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        androidSearchFileChannel: androidChannel,
      );

      final SavedTextFileResult? saveResult = await picker.saveTextFile(
        fileName: 'lyrics.json',
        text: '{"demo":true}',
        initialDirectory: 'content://tree/primary%3ADocuments',
        allowedExtensions: const <String>['json'],
      );

      expect(saveResult?.kind, SavedTextFileResultKind.contentUri);
      expect(saveResult?.uri, 'content://documents/document/lyrics.json');
      expect(
        saveResult?.displayPath,
        'content://documents/document/lyrics.json',
      );
      expect(receivedCall?.method, 'saveTextFile');
      final Map<Object?, Object?> arguments =
          receivedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], 'lyrics.json');
      expect(
        arguments['initialDirectory'],
        'content://tree/primary%3ADocuments',
      );
      expect(arguments['mimeType'], 'application/json');
      expect(arguments['bytes'], isA<Uint8List>());
    });

    test('Android 保存 LRC 时使用专用 MIME 并保留扩展名', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(androidChannel, (MethodCall call) async {
            receivedCall = call;
            return 'content://documents/document/lyrics.lrc';
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        androidSearchFileChannel: androidChannel,
      );

      await picker.saveTextFile(
        fileName: 'lyrics.lrc',
        text: '[00:00.00]Hello LDDC',
        allowedExtensions: const <String>['lrc'],
      );

      final Map<Object?, Object?> arguments =
          receivedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], 'lyrics.lrc');
      expect(arguments['mimeType'], 'application/x-lrc');
    });

    test('iOS 通过 MethodChannel 选择原文件并映射 fd 信息', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'name': 'picked.m4a',
              'path': '/private/var/mobile/demo/picked.m4a',
              'identifier': 'ios-picked-audio',
              'fileDescriptor': 42,
              'fileDescriptorNameHint': 'picked.m4a',
              'canRead': true,
              'canWrite': false,
            };
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      final PickedAudioFileHandle? file = await picker.pickAudioFile(
        initialDirectory: Directory.systemTemp.path,
      );

      expect(receivedCall?.method, 'pickAudioFile');
      expect(receivedCall?.arguments, <String, Object?>{
        'initialDirectory': Directory.systemTemp.path,
      });
      expect(file, isNotNull);
      expect(file?.name, 'picked.m4a');
      expect(file?.path, '/private/var/mobile/demo/picked.m4a');
      expect(file?.identifier, 'ios-picked-audio');
      expect(file?.fileDescriptor, 42);
      expect(file?.fileDescriptorNameHint, 'picked.m4a');
      expect(file?.canRead, isTrue);
      expect(file?.canWrite, isFalse);
    });

    test('iOS 写标签前会显式升级为读写 fd', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'name': 'picked.m4a',
              'path': '/private/var/mobile/demo/picked.m4a',
              'identifier': 'file:///private/var/mobile/demo/picked.m4a',
              'fileDescriptor': 43,
              'fileDescriptorNameHint': 'picked.m4a',
              'canRead': true,
              'canWrite': true,
            };
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      final PickedAudioFileHandle writable = await picker.openAudioFileForWrite(
        const PickedAudioFileHandle(
          name: 'picked.m4a',
          path: '/private/var/mobile/demo/picked.m4a',
          identifier: 'file:///private/var/mobile/demo/picked.m4a',
          fileDescriptor: 42,
          canRead: true,
          canWrite: false,
        ),
      );

      expect(receivedCall?.method, 'openAudioFileForWrite');
      expect(writable.fileDescriptor, 43);
      expect(writable.canWrite, isTrue);
    });

    test('iOS 保存文本时走原生导出通道', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            receivedCall = call;
            return 'file:///private/var/mobile/Containers/Data/lyrics.lrc';
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      final SavedTextFileResult? saveResult = await picker.saveTextFile(
        fileName: 'lyrics.lrc',
        text: 'iOS 导出歌词',
      );

      expect(saveResult?.kind, SavedTextFileResultKind.localPath);
      expect(
        saveResult?.localPath,
        '/private/var/mobile/Containers/Data/lyrics.lrc',
      );
      expect(receivedCall?.method, 'saveTextFile');
      final Map<Object?, Object?> arguments =
          receivedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['fileName'], 'lyrics.lrc');
      expect(arguments['bytes'], isA<Uint8List>());
    });

    test('iOS 取消选择时返回 null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            throw PlatformException(code: 'cancelled');
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      final PickedAudioFileHandle? file = await picker.pickAudioFile();

      expect(file, isNull);
    });

    test('iOS 通道不可用时转换为 UnsupportedError', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            throw PlatformException(
              code: 'unavailable',
              message: '无法获取当前页面上下文',
            );
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      await expectLater(
        picker.pickAudioFile(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('iOS 释放音频文件时透传 fd 参数', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            receivedCall = call;
            return null;
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      await picker.releaseAudioFile(
        const PickedAudioFileHandle(name: 'picked.flac', fileDescriptor: 7),
      );

      expect(receivedCall?.method, 'closeFd');
      expect(receivedCall?.arguments, <String, Object?>{'fd': 7});
    });

    test('没有 fd 时 releaseAudioFile 直接跳过', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (MethodCall call) async {
            callCount += 1;
            return null;
          });
      final AppFilePickerImpl picker = AppFilePickerImpl(
        iosAudioFileChannel: iosChannel,
      );

      await picker.releaseAudioFile(
        const PickedAudioFileHandle(name: 'picked.flac'),
      );

      expect(callCount, 0);
    });
  });
}

class _FakeFileDialog implements AppFileDialog {
  _FakeFileDialog({
    this.pickDirectoryResult,
    this.pickFileResult,
    this.pickFilesResult = const <selector.XFile>[],
    this.pickSaveLocationResult,
  });

  final String? pickDirectoryResult;
  final selector.XFile? pickFileResult;
  final List<selector.XFile> pickFilesResult;
  final selector.FileSaveLocation? pickSaveLocationResult;

  String? lastPickDirectoryInitialDirectory;
  String? lastPickFileInitialDirectory;
  List<String>? lastPickFileAllowedExtensions;
  String? lastSaveFileName;
  List<String>? lastSaveAllowedExtensions;
  String? lastSaveInitialDirectory;
  int pickSaveLocationCallCount = 0;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    lastPickDirectoryInitialDirectory = initialDirectory;
    return pickDirectoryResult;
  }

  @override
  Future<selector.XFile?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    lastPickFileInitialDirectory = initialDirectory;
    lastPickFileAllowedExtensions = allowedExtensions;
    return pickFileResult;
  }

  @override
  Future<List<selector.XFile>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    lastPickFileInitialDirectory = initialDirectory;
    lastPickFileAllowedExtensions = allowedExtensions;
    return pickFilesResult;
  }

  @override
  Future<selector.FileSaveLocation?> pickSaveLocation({
    required String fileName,
    List<String>? allowedExtensions,
    String? initialDirectory,
  }) async {
    pickSaveLocationCallCount += 1;
    lastSaveFileName = fileName;
    lastSaveAllowedExtensions = allowedExtensions;
    lastSaveInitialDirectory = initialDirectory;
    return pickSaveLocationResult;
  }
}
