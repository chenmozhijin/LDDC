import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('DesktopLyricsProjectionRuntime', () {
    test('send_time 传输延迟会修正 start_time', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 5000);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1000,
          pluginSendTimeMs: 4800,
          hostReceivedAtMs: 5000,
          isPlaying: true,
          syncRevision: 1,
          task: DesktopPlaybackEventKind.sync,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );

      expect(runtime.currentTimeMs, 800);
      expect(runtime.tick(nowMs: 5100), 900);
    });

    test('pause 后冻结当前时间，不再继续推进', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 6000);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1200,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 6000,
          isPlaying: true,
          syncRevision: 1,
          task: DesktopPlaybackEventKind.start,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );
      expect(runtime.tick(nowMs: 6300), 1500);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1550,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 6350,
          isPlaying: false,
          syncRevision: 2,
          task: DesktopPlaybackEventKind.pause,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 6350,
      );

      expect(runtime.currentTimeMs, 1550);
      expect(runtime.tick(nowMs: 6600), 1550);
    });

    test('编码解码后的静态文案会生成 panel staticText render plan', () {
      const DesktopLyricsSceneCodec codec = DesktopLyricsSceneCodec();
      final DesktopLyricsSceneDocument decoded = codec.decode(
        codec.encode(
          DesktopLyricsSceneDocument(
            mode: DesktopLyricsSceneMode.staticText,
            selectedLangs: <String>['orig'],
            langOrder: <String>['orig'],
            durationMs: 0,
            staticDisplayLines: <String>['欢迎使用LDDC桌面歌词', 'Welcome'],
          ),
        ),
      );
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime()
            ..bindScene(decoded)
            ..updatePanelStyle(DesktopLyricsProjectionStyle());

      final DesktopPanelRenderPlan? panelPlan = runtime.buildPanelRenderPlan(
        currentTimeMs: 0,
      );

      expect(decoded.mode, DesktopLyricsSceneMode.staticText);
      expect(panelPlan, isNotNull);
      expect(panelPlan!.mode, 'staticText');
      expect(panelPlan.blocks.map((block) => block.lines.single.text), <String>[
        '欢迎使用LDDC桌面歌词',
        'Welcome',
      ]);
    });

    test('floating 和 panel 在同一时刻对齐同一 active 行', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 2500);
      final DesktopLyricsSceneDocument scene = _buildScene();
      runtime
        ..bindScene(scene)
        ..updateFloatingStyle(
          DesktopLyricsProjectionStyle(
            enabledLangs: <String>['orig', 'ts'],
            showFurigana: true,
          ),
        )
        ..updatePanelStyle(
          DesktopLyricsProjectionStyle(
            enabledLangs: <String>['orig', 'ts'],
            showFurigana: true,
          ),
        )
        ..syncEvent(
          const DesktopLyricsPlaybackSyncEvent(
            pluginPlaybackTimeMs: 1500,
            pluginSendTimeMs: null,
            hostReceivedAtMs: 2500,
            isPlaying: false,
            syncRevision: 1,
            task: DesktopPlaybackEventKind.sync,
            sceneId: 'scene-1',
            songToken: 'song-1',
          ),
        );

      final DesktopFloatingRenderPlan? floatingPlan = runtime
          .buildFloatingRenderPlan(currentTimeMs: 1500);
      final DesktopPanelRenderPlan? panelPlan = runtime.buildPanelRenderPlan(
        currentTimeMs: 1500,
      );

      expect(floatingPlan, isNotNull);
      expect(panelPlan, isNotNull);
      expect(panelPlan!.activeIndex, 1);
      expect(floatingPlan!.leftTracks.single.focusedOrigIndex, 1);
      expect(
        floatingPlan.leftTracks.single.lines
            .where((DesktopRenderLinePlan line) => line.lang == 'orig')
            .single
            .state,
        DesktopRenderLineState.active,
      );
      expect(
        panelPlan.blocks[1].lines
            .where((DesktopRenderLinePlan line) => line.lang == 'orig')
            .single
            .state,
        DesktopRenderLineState.active,
      );
      expect(
        floatingPlan.leftTracks.single.lines
            .where((DesktopRenderLinePlan line) => line.lang == 'ts')
            .single
            .words
            .single
            .startMs,
        1000,
      );
      expect(
        panelPlan.blocks[1].lines
            .where((DesktopRenderLinePlan line) => line.lang == 'ts')
            .single
            .words
            .single
            .endMs,
        2000,
      );
    });

    test('间奏期间保持上一行完整激活，不提前聚焦下一行', () {
      final LyricsLine previous = LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 500, text: '前'),
          LyricsWord(startMs: 500, endMs: 1000, text: '句'),
        ],
      );
      final LyricsLine next = LyricsLine(
        startMs: 2000,
        endMs: 3000,
        words: <LyricsWord>[
          LyricsWord(startMs: 2000, endMs: 2500, text: '后'),
          LyricsWord(startMs: 2500, endMs: 3000, text: '句'),
        ],
      );
      final DesktopLyricsProjectionRuntime
      runtime = DesktopLyricsProjectionRuntime()
        ..bindScene(
          DesktopLyricsSceneDocument(
            mode: DesktopLyricsSceneMode.lyrics,
            selectedLangs: const <String>['orig'],
            langOrder: const <String>['orig'],
            durationMs: 3600,
            multiLyricsData: <String, LyricsData>{
              'orig': <LyricsLine>[previous, next],
            },
            assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
              (Direction.left, 0): <(int, LyricsLine)>[
                (0, previous),
                (1, next),
              ],
            },
          ),
        )
        ..updatePanelStyle(
          DesktopLyricsProjectionStyle(enabledLangs: const <String>['orig']),
        );

      final DesktopPanelRenderPlan plan = runtime.buildPanelRenderPlan(
        currentTimeMs: 1500,
      )!;
      final DesktopRenderLinePlan line = plan.blocks.first.lines.single;

      expect(plan.activeIndex, 0);
      expect(line.state, DesktopRenderLineState.active);
      expect(line.activeProgress.charIndex, 2);
    });

    test('逐字进度使用 grapheme 索引，不会拆开 emoji 组合字符', () {
      final LyricsLine line = LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 1000, text: '👨‍👩‍👧‍👦A'),
        ],
      );
      final DesktopLyricsProjectionRuntime
      runtime = DesktopLyricsProjectionRuntime()
        ..bindScene(
          DesktopLyricsSceneDocument(
            mode: DesktopLyricsSceneMode.lyrics,
            selectedLangs: const <String>['orig'],
            langOrder: const <String>['orig'],
            durationMs: 1000,
            multiLyricsData: <String, LyricsData>{
              'orig': <LyricsLine>[line],
            },
            assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
              (Direction.left, 0): <(int, LyricsLine)>[(0, line)],
            },
          ),
        )
        ..updatePanelStyle(
          DesktopLyricsProjectionStyle(enabledLangs: const <String>['orig']),
        );

      final DesktopPanelRenderPlan plan = runtime.buildPanelRenderPlan(
        currentTimeMs: 500,
      )!;
      final DesktopRenderLinePlan renderedLine =
          plan.blocks.single.lines.single;

      expect(renderedLine.activeProgress.charIndex, 1);
      expect(renderedLine.activeProgress.charRatio, 0);
    });

    test('旧 revision 的同步包不会覆盖新状态', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 8000);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 2200,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 8000,
          isPlaying: true,
          syncRevision: 3,
          task: DesktopPlaybackEventKind.sync,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );
      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 900,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 7900,
          isPlaying: false,
          syncRevision: 2,
          task: DesktopPlaybackEventKind.pause,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );

      expect(runtime.currentTimeMs, 2200);
      expect(runtime.isPlaying, isTrue);
    });

    test('start/pause/proceed/stop 会按播放任务语义推进并复位时钟', () {
      int nowMs = 1000;
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => nowMs);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 200,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 1000,
          isPlaying: true,
          syncRevision: 1,
          task: DesktopPlaybackEventKind.start,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );
      expect(runtime.currentTimeMs, 200);

      nowMs = 1200;
      expect(runtime.tick(nowMs: nowMs), 400);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 450,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 1250,
          isPlaying: false,
          syncRevision: 2,
          task: DesktopPlaybackEventKind.pause,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 1250,
      );
      expect(runtime.currentTimeMs, 450);
      expect(runtime.tick(nowMs: 1500), 450);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 450,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 1600,
          isPlaying: true,
          syncRevision: 3,
          task: DesktopPlaybackEventKind.resume,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 1600,
      );
      expect(runtime.currentTimeMs, 450);
      expect(runtime.tick(nowMs: 1800), 650);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 700,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 1820,
          isPlaying: false,
          syncRevision: 4,
          task: DesktopPlaybackEventKind.stop,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 1820,
      );
      expect(runtime.currentTimeMs, 0);
      expect(runtime.isPlaying, isFalse);
      expect(runtime.tick(nowMs: 2100), 0);
    });

    test('send_time 缺失时用当前处理时刻起算，存在延迟时扣除传输耗时', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 5000);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1200,
          pluginSendTimeMs: null,
          hostReceivedAtMs: 5000,
          isPlaying: true,
          syncRevision: 1,
          task: DesktopPlaybackEventKind.sync,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 5000,
      );
      expect(runtime.currentTimeMs, 1200);
      expect(runtime.tick(nowMs: 5120), 1320);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1500,
          pluginSendTimeMs: 5200,
          hostReceivedAtMs: 5400,
          isPlaying: true,
          syncRevision: 2,
          task: DesktopPlaybackEventKind.sync,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
        nowMs: 5400,
      );
      expect(runtime.currentTimeMs, 1300);
      expect(runtime.tick(nowMs: 5480), 1380);
    });

    test('子窗口首次晚到时会按首次处理时刻扣总 delay', () {
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => 5200);

      runtime.syncEvent(
        const DesktopLyricsPlaybackSyncEvent(
          pluginPlaybackTimeMs: 1000,
          pluginSendTimeMs: 4800,
          hostReceivedAtMs: 5000,
          isPlaying: true,
          syncRevision: 1,
          task: DesktopPlaybackEventKind.sync,
          sceneId: 'scene-1',
          songToken: 'song-1',
        ),
      );

      expect(runtime.currentTimeMs, 600);
      expect(runtime.tick(nowMs: 5300), 700);
    });

    test('同 revision 的旧 anchor 被重放时不会把经过时间误算成额外延迟', () {
      int nowMs = 5000;
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => nowMs);
      const DesktopLyricsPlaybackSyncEvent event =
          DesktopLyricsPlaybackSyncEvent(
            pluginPlaybackTimeMs: 1000,
            pluginSendTimeMs: 4800,
            hostReceivedAtMs: 5000,
            isPlaying: true,
            syncRevision: 1,
            task: DesktopPlaybackEventKind.sync,
            sceneId: 'scene-1',
            songToken: 'song-1',
          );

      runtime.syncEvent(event);
      expect(runtime.currentTimeMs, 800);

      nowMs = 5600;
      runtime.syncEvent(event, nowMs: nowMs);

      expect(runtime.currentTimeMs, 1400);
      expect(runtime.tick(nowMs: 5700), 1500);
    });

    test('1Hz sync 重同步不会累计跑到 delay 调整基线前面', () {
      int nowMs = 1000;
      const int delayMs = 200;
      const int stepMs = 20;
      final DesktopLyricsProjectionRuntime runtime =
          DesktopLyricsProjectionRuntime(nowMsFactory: () => nowMs);
      final List<int> driftSamples = <int>[];

      for (int revision = 1; revision <= 5; revision += 1) {
        nowMs = revision * 1000;
        runtime.syncEvent(
          DesktopLyricsPlaybackSyncEvent(
            pluginPlaybackTimeMs: revision * 1000,
            pluginSendTimeMs: nowMs - delayMs,
            hostReceivedAtMs: nowMs,
            isPlaying: true,
            syncRevision: revision,
            task: DesktopPlaybackEventKind.sync,
            sceneId: 'scene-1',
            songToken: 'song-1',
          ),
          nowMs: nowMs,
        );
        for (
          int tickNowMs = nowMs;
          tickNowMs < nowMs + 1000;
          tickNowMs += stepMs
        ) {
          final int currentTimeMs = runtime.tick(nowMs: tickNowMs);
          final int expectedTimeMs = tickNowMs - delayMs;
          driftSamples.add(currentTimeMs - expectedTimeMs);
        }
      }

      expect(driftSamples.every((int drift) => drift <= 0), isTrue);
      expect(
        driftSamples
            .map((int drift) => drift.abs())
            .reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(stepMs),
      );
    });
  });
}

DesktopLyricsSceneDocument _buildScene() {
  final LyricsLine line0 = LyricsLine(
    startMs: 0,
    endMs: 1000,
    words: <LyricsWord>[
      LyricsWord(startMs: 0, endMs: 500, text: '你'),
      LyricsWord(startMs: 500, endMs: 1000, text: '好'),
    ],
  );
  final LyricsLine line1 = LyricsLine(
    startMs: 1000,
    endMs: 2000,
    words: <LyricsWord>[
      LyricsWord(startMs: 1000, endMs: 1500, text: '世'),
      LyricsWord(startMs: 1500, endMs: 2000, text: '界'),
    ],
  );
  final LyricsLine ts1 = LyricsLine(
    startMs: 1000,
    endMs: 2000,
    words: <LyricsWord>[LyricsWord(startMs: 1000, endMs: 2000, text: 'world')],
  );
  return DesktopLyricsSceneDocument(
    mode: DesktopLyricsSceneMode.lyrics,
    selectedLangs: const <String>['orig', 'ts'],
    langOrder: const <String>['orig', 'ts'],
    durationMs: 2400,
    multiLyricsData: <String, LyricsData>{
      'orig': <LyricsLine>[line0, line1],
    },
    lyricsMapping: <String, Map<int, LyricsLine>>{
      'ts': <int, LyricsLine>{1: ts1},
    },
    assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
      (Direction.left, 0): <(int, LyricsLine)>[(0, line0), (1, line1)],
    },
    rubyMapping: <int, List<RubySpan>>{},
  );
}
