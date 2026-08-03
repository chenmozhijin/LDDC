import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

void main() {
  group('DesktopLyricsSceneCodec', () {
    test('round-trip 会保留歌词、多语言映射、ruby 与静态文本字段', () {
      final LyricsLine origLine = LyricsLine(
        startMs: 1000,
        endMs: 2000,
        words: <LyricsWord>[
          LyricsWord(startMs: 1000, endMs: 1500, text: 'か'),
          LyricsWord(startMs: 1500, endMs: 2000, text: 'な'),
        ],
      );
      final LyricsLine tsLine = LyricsLine(
        startMs: 1000,
        endMs: 2000,
        words: <LyricsWord>[LyricsWord(startMs: 1000, endMs: 2000, text: '假名')],
      );
      final DesktopLyricsSceneDocument document = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.lyrics,
        selectedLangs: const <String>['orig', 'ts'],
        langOrder: const <String>['orig', 'ts'],
        durationMs: 180000,
        multiLyricsData: <String, LyricsData>{
          'orig': <LyricsLine>[origLine],
          'ts': <LyricsLine>[tsLine],
        },
        lyricsMapping: <String, Map<int, LyricsLine>>{
          'ts': <int, LyricsLine>{0: tsLine},
        },
        assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
          (Direction.left, 0): <(int, LyricsLine)>[(0, origLine)],
        },
        rubyMapping: const <int, List<RubySpan>>{
          0: <RubySpan>[RubySpan(start: 0, end: 1, ruby: 'か')],
        },
        staticDisplayLines: const <String>['欢迎使用', 'Welcome'],
      );
      const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();

      final DesktopLyricsSceneDocument decoded = codec.decode(
        codec.encode(document),
      );

      expect(decoded.mode, DesktopLyricsSceneMode.lyrics);
      expect(decoded.selectedLangs, const <String>['orig', 'ts']);
      expect(decoded.langOrder, const <String>['orig', 'ts']);
      expect(decoded.durationMs, 180000);
      expect(decoded.multiLyricsData['orig']?.single.text, 'かな');
      expect(decoded.lyricsMapping['ts']?[0]?.text, '假名');
      expect(
        decoded.assignedLyricsSlots[(Direction.left, 0)]?.single.$2.text,
        'かな',
      );
      expect(decoded.rubyMapping[0]?.single.ruby, 'か');
      expect(decoded.staticDisplayLines, const <String>['欢迎使用', 'Welcome']);
    });

    test('checksum 对同一份场景字节稳定', () {
      const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();
      final DesktopLyricsSceneDocument document = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.staticText,
        selectedLangs: const <String>['orig'],
        langOrder: const <String>['orig'],
        durationMs: null,
        staticDisplayLines: const <String>['欢迎使用LDDC桌面歌词'],
      );

      final bytes = codec.encode(document);

      expect(codec.checksumForBytes(bytes), codec.checksumForBytes(bytes));
      expect(codec.decode(bytes).mode, DesktopLyricsSceneMode.staticText);
    });

    test('解码时语言 token 会过滤坏值，静态文本显式保留空行', () {
      const StandardMessageCodec messageCodec = StandardMessageCodec();
      final ByteData data = messageCodec.encodeMessage(<String, Object?>{
        'mode': 'staticText',
        'selectedLangs': <Object?>['orig', '', null, 'LDDC_ts', 'bad'],
        'langOrder': <Object?>['roma', ' ', 'LDDC_ts'],
        'staticDisplayLines': <Object?>['欢迎', null, '', '显示'],
      })!;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();

      final DesktopLyricsSceneDocument decoded = codec.decode(bytes);

      expect(decoded.selectedLangs, <String>['orig', 'ts']);
      expect(decoded.langOrder, <String>['roma', 'ts']);
      expect(decoded.staticDisplayLines, <String>['欢迎', '', '', '显示']);
    });
  });

  group('DesktopInMemorySceneStore', () {
    test('put/get/release/evict 会按 sceneId 与 instance 前缀工作', () {
      final DesktopInMemorySceneStore store = DesktopInMemorySceneStore();
      const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();
      final bytesA = codec.encode(
        DesktopLyricsSceneDocument(
          mode: DesktopLyricsSceneMode.staticText,
          selectedLangs: <String>['orig'],
          langOrder: <String>['orig'],
          durationMs: null,
          staticDisplayLines: <String>['A'],
        ),
      );
      final bytesB = codec.encode(
        DesktopLyricsSceneDocument(
          mode: DesktopLyricsSceneMode.staticText,
          selectedLangs: <String>['orig'],
          langOrder: <String>['orig'],
          durationMs: null,
          staticDisplayLines: <String>['B'],
        ),
      );

      store.putScene('1:1', bytesA, revision: 1, checksum: 'a1');
      store.putScene('1:2', bytesB, revision: 2, checksum: 'b2');
      store.putScene('2:1', bytesA, revision: 1, checksum: 'c3');

      expect(store.stats.sceneCount, 2);
      expect(store.stats.totalBytes, bytesA.length + bytesB.length);
      expect(store.getScene('1:1'), isNull);
      expect(store.getScene('1:2'), isNotNull);
      expect(store.getScene('2:1'), isNotNull);

      store.releaseScene('1:1');
      expect(store.getScene('1:2'), isNotNull);

      store.releaseScene('1:2');
      expect(store.stats.sceneCount, 1);
      expect(store.getScene('1:2'), isNull);

      store.evictScenes(1);
      expect(store.stats.sceneCount, 1);
      expect(store.getScene('2:1'), isNotNull);
    });
  });
}
