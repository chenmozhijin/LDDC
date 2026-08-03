import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('SavedTextFileResult', () {
    test('区分本地路径、Android content URI 与外部 URI', () {
      final SavedTextFileResult local = SavedTextFileResult.localPath(
        '  C:\\Music\\demo.lrc  ',
      );
      final SavedTextFileResult content = SavedTextFileResult.uri(
        ' content://documents/demo ',
      );
      final SavedTextFileResult external = SavedTextFileResult.uri(
        'https://provider.invalid/demo',
      );

      expect(local.kind, SavedTextFileResultKind.localPath);
      expect(local.localPath, r'C:\Music\demo.lrc');
      expect(local.uri, isNull);
      expect(content.kind, SavedTextFileResultKind.contentUri);
      expect(content.uri, 'content://documents/demo');
      expect(external.kind, SavedTextFileResultKind.externalUri);
      expect(external.localPath, isNull);
    });

    test('拒绝空保存目标', () {
      expect(() => SavedTextFileResult.localPath('  '), throwsArgumentError);
      expect(() => SavedTextFileResult.uri(''), throwsArgumentError);
    });
  });

  group('PickedFileHandle', () {
    test('基础句柄不虚构长度或字节读取能力', () async {
      const PickedFileHandle handle = PickedFileHandle(name: 'demo.lrc');

      expect(await handle.length(), isNull);
      expect(handle.readAsBytes, throwsUnsupportedError);
    });
  });

  group('PickedAudioFileHandle Android', () {
    test('解析 content URI 并使用显示名或 URI 末段作为名称', () {
      final PickedAudioFileHandle named = PickedAudioFileHandle.fromAndroidMap(
        <Object?, Object?>{
          'identifier': 'content://media/audio/42',
          'name': ' demo.flac ',
        },
      );
      final PickedAudioFileHandle fallback =
          PickedAudioFileHandle.fromAndroidMap(<Object?, Object?>{
            'identifier': 'content://media/audio/fallback.mp3',
          });

      expect(named.name, 'demo.flac');
      expect(named.targetPath, 'content://media/audio/42');
      expect(named.canRead, isTrue);
      expect(named.canWrite, isTrue);
      expect(fallback.name, 'fallback.mp3');
    });

    test('拒绝缺失、空白和非 content URI identifier', () {
      for (final Map<Object?, Object?> payload in <Map<Object?, Object?>>[
        <Object?, Object?>{},
        <Object?, Object?>{'identifier': '  '},
        <Object?, Object?>{'identifier': 'file:///tmp/demo.mp3'},
      ]) {
        expect(
          () => PickedAudioFileHandle.fromAndroidMap(payload),
          throwsFormatException,
          reason: payload.toString(),
        );
      }
    });
  });

  group('PickedAudioFileHandle iOS', () {
    test('接受 fd/nameHint 别名、权限标志和本地 file URI', () {
      final PickedAudioFileHandle handle =
          PickedAudioFileHandle.fromIosMap(<Object?, Object?>{
            'fd': 7,
            'nameHint': ' imported.m4a ',
            'path': 'file:///tmp/imported.m4a',
            'identifier': 'file:///tmp/preferred.m4a',
            'canRead': false,
            'canWrite': true,
          });

      expect(handle.fileDescriptor, 7);
      expect(handle.fileDescriptorNameHint, 'imported.m4a');
      expect(handle.name, 'imported.m4a');
      expect(handle.canRead, isFalse);
      expect(handle.canWrite, isTrue);
      expect(handle.targetPath, endsWith('preferred.m4a'));
    });

    test('仅有 path 时可回退名称，identifier 普通值回退本地 path', () {
      final PickedAudioFileHandle handle =
          PickedAudioFileHandle.fromIosMap(<Object?, Object?>{
            'fileDescriptor': 9,
            'path': r'C:\Music\fallback.wav',
            'identifier': 'security-scope-token',
          });

      expect(handle.name, 'fallback.wav');
      expect(handle.targetPath, r'C:\Music\fallback.wav');
      expect(handle.canRead, isTrue);
      expect(handle.canWrite, isFalse);
    });

    test('拒绝非法 fd、缺失名称上下文和非 bool 权限字段', () {
      for (final Map<Object?, Object?> payload in <Map<Object?, Object?>>[
        <Object?, Object?>{'fileDescriptor': -1, 'nameHint': 'demo.mp3'},
        <Object?, Object?>{'fileDescriptor': 1},
        <Object?, Object?>{
          'fileDescriptor': 1,
          'nameHint': 'demo.mp3',
          'canRead': 'yes',
        },
      ]) {
        expect(
          () => PickedAudioFileHandle.fromIosMap(payload),
          throwsFormatException,
          reason: payload.toString(),
        );
      }
    });
  });

  test('normalizePickedLocalFilePath 处理空值、普通路径和 file URI', () {
    expect(normalizePickedLocalFilePath(null), isNull);
    expect(normalizePickedLocalFilePath('  '), isNull);
    expect(
      normalizePickedLocalFilePath(r' C:\Music\demo.mp3 '),
      r'C:\Music\demo.mp3',
    );
    expect(
      normalizePickedLocalFilePath('file:///tmp/demo.mp3'),
      endsWith('demo.mp3'),
    );
  });
}
