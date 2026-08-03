import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/platform/desktop/ipc/desktop_ipc.dart';
import '../../../support/desktop_service_host_exports.dart';

void main() {
  group('DesktopSessionState', () {
    test('initial 保留默认语言并初始化为空面板集', () {
      final DesktopSessionState state = DesktopSessionState.initial(
        defaultLangs: const <String>['orig', 'roma'],
      );

      expect(state.instanceId, isNull);
      expect(state.apiVersion, isNull);
      expect(state.config.defaultLangs, <String>['orig', 'roma']);
      expect(state.panels, isEmpty);
      expect(state.isPlaying, isFalse);
      expect(state.lastTask, isNull);
      expect(state.lyricsRuntime.sceneDocument, isNull);
      expect(state.lyricsRuntime.sceneRef, isNull);
    });

    test('attachHello 合并握手信息且保留默认语言', () {
      const DesktopHelloMessage hello = DesktopHelloMessage(
        pid: 5566,
        availableTaskNames: <String>['play', 'pause', 'next'],
        clientInfo: DesktopClientInfo(
          name: 'foo_lddc',
          version: '0.1.4',
          extra: <String, Object?>{'channel': 'stable'},
        ),
      );
      final DesktopSessionState initial = DesktopSessionState.initial(
        defaultLangs: const <String>['orig', 'ts'],
      );

      final DesktopSessionState state = initial.attachHello(
        hello: hello,
        apiVersion: 2,
        instanceId: 88,
      );

      expect(state.instanceId, 88);
      expect(state.apiVersion, 2);
      expect(state.client.pid, 5566);
      expect(state.client.name, 'foo_lddc');
      expect(state.client.version, '0.1.4');
      expect(state.client.availableTasks, <DesktopControlCommandTask>{
        DesktopControlCommandTask.play,
        DesktopControlCommandTask.pause,
        DesktopControlCommandTask.next,
      });
      expect(state.client.extraInfo, <String, Object?>{'channel': 'stable'});
      expect(state.supportsControlTask(DesktopControlCommandTask.next), isTrue);
      expect(
        state.supportsControlTask(DesktopControlCommandTask.stop),
        isFalse,
      );
      expect(state.config.defaultLangs, <String>['orig', 'ts']);
      expect(state.lastTask, DesktopIpcTask.newDesktopLyricsInstance);
    });

    test('upsertPanel 和 removePanel 保持不可变更新', () {
      final DesktopSessionState initial = DesktopSessionState.initial();
      final DesktopSessionState attached = initial.upsertPanel(
        const DesktopPanelState(
          panelId: 10,
          hostWindowId: 20,
          width: 640,
          height: 240,
          visible: true,
        ),
      );
      final DesktopSessionState updated = attached.upsertPanel(
        const DesktopPanelState(
          panelId: 10,
          hostWindowId: 20,
          width: 800,
          height: 300,
          visible: false,
        ),
      );
      final DesktopSessionState removed = updated.removePanel(10);

      expect(initial.panels, isEmpty);
      expect(attached.panels[10]?.width, 640);
      expect(attached.panels[10]?.visible, isTrue);
      expect(updated.panels[10]?.width, 800);
      expect(updated.panels[10]?.height, 300);
      expect(updated.panels[10]?.visible, isFalse);
      expect(removed.panels, isEmpty);
      expect(updated.removePanel(999), same(updated));
    });

    test('配置与歌词集合会在构造边界完整冻结', () {
      final List<String> selectedLangs = <String>['orig'];
      final Map<String, Object?> songConfig = <String, Object?>{
        'langs': selectedLangs,
      };
      final List<LyricsLine> origLines = <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 2000, text: 'line'),
          ],
        ),
      ];
      final MultiLyricsData multiLyricsData = <String, LyricsData>{
        'orig': origLines,
      };
      final List<String> staticLines = <String>['status'];

      final DesktopSessionConfigState config = DesktopSessionConfigState(
        songConfig: songConfig,
      );
      final DesktopLyricsRuntimeState runtime = DesktopLyricsRuntimeState(
        multiLyricsData: multiLyricsData,
        staticDisplayLines: staticLines,
      );

      selectedLangs.add('ts');
      songConfig['offset'] = 100;
      origLines.clear();
      multiLyricsData['ts'] = const <LyricsLine>[];
      staticLines.add('changed');

      expect(config.selectedLangs, const <String>['orig']);
      expect(config.songConfig.containsKey('offset'), isFalse);
      expect(runtime.multiLyricsData.keys, const <String>['orig']);
      expect(runtime.multiLyricsData['orig'], hasLength(1));
      expect(runtime.staticDisplayLines, const <String>['status']);
      expect(
        () => (config.songConfig['langs']! as List<Object?>).add('ts'),
        throwsUnsupportedError,
      );
      expect(
        () => runtime.multiLyricsData['orig']!.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => runtime.multiLyricsData['ts'] = const <LyricsLine>[],
        throwsUnsupportedError,
      );
    });

    test('offset 只接受可无损读取的整数', () {
      expect(
        DesktopSessionConfigState(
          songConfig: const <String, Object?>{'offset': 120.0},
        ).offsetMs,
        120,
      );
      expect(
        DesktopSessionConfigState(
          songConfig: const <String, Object?>{'offset': '250'},
        ).offsetMs,
        250,
      );
      expect(
        DesktopSessionConfigState(
          songConfig: const <String, Object?>{'offset': 3.8},
        ).offsetMs,
        0,
      );
    });
  });
}
