import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;

const String _fixtureBase64 = String.fromEnvironment(
  'LDDC_APPLE_COMPONENT_FIXTURE_BASE64',
);
const String _fixtureSha256 = String.fromEnvironment(
  'LDDC_APPLE_COMPONENT_FIXTURE_SHA256',
);
const int _fixtureSize = int.fromEnvironment(
  'LDDC_APPLE_COMPONENT_FIXTURE_SIZE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS 确定性文件句柄通过生产媒体链路完成往返', (WidgetTester tester) async {
    expect(Platform.isIOS, isTrue, reason: '该 required 场景必须在 iOS Simulator 执行');
    expect(_fixtureBase64, isNotEmpty);
    expect(_fixtureSha256, hasLength(64));
    expect(_fixtureSize, greaterThan(0));

    final List<int> fixtureBytes = base64Decode(_fixtureBase64);
    expect(fixtureBytes, hasLength(_fixtureSize));
    expect(sha256.convert(fixtureBytes).toString(), _fixtureSha256);

    final Directory workspace = await Directory.systemTemp.createTemp(
      'lddc-ios-media-contract-',
    );
    addTearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });
    final File audioFile = File(p.join(workspace.path, 'audio_sample.mp3'));
    await audioFile.writeAsBytes(fixtureBytes, flush: true);

    // Picker 的系统界面与 security-scoped FD 由 XCUITest 和 RunnerTests 分别
    // 验证；这里从已经验证的文件句柄边界继续，专门证明 iOS 产物中的生产
    // TagLib、歌词解析和写回链路，避免把 macOS 主机结果误标成 iOS 证据。
    final PickedAudioFileHandle selected = PickedAudioFileHandle(
      name: 'audio_sample.mp3',
      path: audioFile.path,
      canRead: true,
      canWrite: true,
    );
    final String selectedPath =
        selected.targetPath ?? (throw StateError('确定性 iOS 文件句柄缺少目标路径'));
    final LocalMatchMediaGateway gateway =
        createDefaultLocalMatchMediaGateway();

    final List<SongInfo> infos = await gateway.readAudioSongInfos(selectedPath);
    expect(infos, hasLength(1));
    expect(
      await gateway.readAudioLyricsText(songPath: selectedPath),
      contains('Hello LDDC'),
    );

    final ParsedLyricsPayload parsed = LyricsParser().parseText(
      '[00:00.00]Hello LDDC\n[00:01.00]iOS component round trip\n',
      path: 'component.lrc',
    );
    final Lyrics lyrics = Lyrics(
      songInfo: infos.single,
      source: Source.local,
      data: parsed.lyricsData,
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      tags: parsed.tags,
    );
    final String converted = const LyricsConverter().convert(
      lyrics: lyrics,
      langs: const <String>['orig'],
      format: LyricsFormat.lineByLineLrc,
    );
    expect(converted, contains('[00:01.000]iOS component round trip'));

    await gateway.writeLyricsTag(
      songPath: selectedPath,
      lyricsText: converted,
      lyrics: lyrics,
      id3Version: Id3Version.v24,
    );
    final String? reopenedLyrics = await createDefaultLocalMatchMediaGateway()
        .readAudioLyricsText(songPath: selectedPath);
    expect(reopenedLyrics, contains('iOS component round trip'));
    expect(
      sha256.convert(await audioFile.readAsBytes()).toString(),
      isNot(_fixtureSha256),
    );

    // Unix 允许删除仍被打开的文件，因此这里仅证明临时产物完成清理；原生
    // FD 所有权和幂等关闭由 RunnerTests 的注册表计数单独证明，不能混为一条证据。
    await audioFile.delete();
    expect(audioFile.existsSync(), isFalse);
  });
}
