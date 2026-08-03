import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('DesktopWindowPayloadCodec', () {
    test('非有限数字和坏窗口尺寸会回退安全默认值', () {
      final DesktopFloatingFlagsPayload flags =
          DesktopWindowPayloadCodec.decodeFloatingFlagsPayload(
            <String, Object?>{
              'revision': 3,
              'flags': <String, Object?>{'opacity': double.nan},
            },
          );
      final DesktopFloatingWindowIntent? intent =
          DesktopWindowPayloadCodec.decodeFloatingIntent(
            DesktopWindowMethodNames.floatingMetricsCommittedIntent,
            <String, Object?>{
              'instanceId': 1,
              'windowRect': <Object?>[0, 0, -1, double.infinity],
            },
          );

      expect(flags.flags.opacity, 1.0);
      expect(intent, isNull);
    });

    test('selector 语言列表会过滤并归一化', () {
      final DesktopSelectorWindowContext context =
          DesktopWindowPayloadCodec.decodeSelectorContext(<String, Object?>{
            'langs': <Object?>['orig', '', null, 'unknown', 'LDDC_ts', 'ts'],
          });

      expect(context.langs, <String>['orig', 'ts']);
    });

    test('selector 搜索诊断 round-trip 保留累计启动与完成计数', () {
      const DesktopSelectorRuntimeDiagnostics source =
          DesktopSelectorRuntimeDiagnostics(
            available: true,
            hasActiveBatch: false,
            hasActiveRequest: false,
            hasPendingRequest: false,
            hasDebounceTimer: false,
            isSearching: false,
            isLoadingMore: false,
            searchBatchStartedCount: 3,
            searchBatchSettledCount: 3,
            sourceRequestStartedCount: 6,
            sourceRequestSettledCount: 6,
          );

      final DesktopSelectorRuntimeDiagnostics decoded =
          DesktopWindowPayloadCodec.decodeSelectorRuntimeDiagnostics(
            DesktopWindowPayloadCodec.encodeSelectorRuntimeDiagnostics(source),
          );

      expect(decoded.available, isTrue);
      expect(decoded.isIdle, isTrue);
      expect(decoded.searchBatchStartedCount, 3);
      expect(decoded.searchBatchSettledCount, 3);
      expect(decoded.sourceRequestStartedCount, 6);
      expect(decoded.sourceRequestSettledCount, 6);
    });

    test('Panel 原子内容 round-trip 只读取 ByteData 视图范围', () {
      final Uint8List raw = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]);
      final ByteData view = ByteData.sublistView(raw, 2, 5);
      final DesktopPanelContentPayload decoded =
          DesktopWindowPayloadCodec.decodePanelContentPayload(<String, Object?>{
            'contentRevision': 9,
            'session': <String, Object?>{
              'songId': 'song',
              'enabledLangs': <String>['orig'],
              'fontSize': 18,
            },
            'sceneRef': <String, Object?>{
              'sceneId': '9:1',
              'sceneRevision': 3,
              'checksum': 'abc',
            },
            'sceneBytes': view,
          });

      expect(decoded.contentRevision, 9);
      expect(decoded.session.songId, 'song');
      expect(decoded.session.fontSize, 18);
      expect(decoded.sceneRef?.sceneId, '9:1');
      expect(decoded.sceneBytes, <int>[3, 4, 5]);
    });

    test('窗口 snapshot 构造后不会被外部集合污染', () {
      final List<String> langs = <String>['orig'];
      final List<RgbColor> colors = <RgbColor>[RgbColor(1, 2, 3)];
      final Set<DesktopPlaybackControlTask> tasks =
          <DesktopPlaybackControlTask>{DesktopPlaybackControlTask.play};
      final DesktopWindowActionSnapshot actions = DesktopWindowActionSnapshot(
        availableControlTasks: tasks,
      );
      final DesktopPanelSessionSnapshot panel = DesktopPanelSessionSnapshot(
        enabledLangs: langs,
        playedColors: colors,
        actions: actions,
      );

      langs.add('ts');
      colors.add(RgbColor(9, 9, 9));
      tasks.add(DesktopPlaybackControlTask.next);

      expect(panel.enabledLangs, <String>['orig']);
      expect(panel.playedColors, hasLength(1));
      expect(actions.availableControlTasks, <DesktopPlaybackControlTask>{
        DesktopPlaybackControlTask.play,
      });
      expect(() => panel.enabledLangs.add('roma'), throwsUnsupportedError);
    });

    test('信息标签只传输稳定枚举语义并忽略未知值', () {
      const DesktopLyricsInfoBadgeSnapshot snapshot =
          DesktopLyricsInfoBadgeSnapshot(
            source: Source.ne,
            lyricsType: LyricsType.lineByLine,
          );
      final Map<String, Object?> payload =
          DesktopWindowPayloadCodec.encodeLyricsInfoBadgeSnapshot(snapshot);
      final DesktopLyricsInfoBadgeSnapshot decoded =
          DesktopWindowPayloadCodec.decodeLyricsInfoBadgeSnapshot(payload);
      final DesktopLyricsInfoBadgeSnapshot malformed =
          DesktopWindowPayloadCodec.decodeLyricsInfoBadgeSnapshot(
            <String, Object?>{
              'source': 'unknown',
              'lyricsType': 'legacy_label',
            },
          );

      expect(payload, <String, Object?>{
        'source': 'ne',
        'lyricsType': 'lineByLine',
        'isInstrumental': false,
      });
      expect(decoded.source, Source.ne);
      expect(decoded.lyricsType, LyricsType.lineByLine);
      expect(malformed.source, isNull);
      expect(malformed.lyricsType, isNull);
    });

    test('Panel anchor 与 presentation identity round-trip', () {
      const DesktopPanelAnchorSnapshot anchor = DesktopPanelAnchorSnapshot(
        pluginPlaybackTimeMs: 128000,
        pluginSendTimeMs: 256000,
        hostReceivedAtMs: 256500,
        isPlaying: true,
        syncRevision: 12,
        sceneId: '1:2',
        songToken: 'song-token',
      );
      final DesktopPanelAnchorSnapshot decodedAnchor =
          DesktopWindowPayloadCodec.decodePanelAnchorSnapshot(
            DesktopWindowPayloadCodec.encodePanelAnchorSnapshot(anchor),
          );
      final DesktopPanelPresentationReady decodedReady =
          DesktopWindowPayloadCodec.decodePanelPresentationReady(
            DesktopWindowPayloadCodec.encodePanelPresentationReady(
              const DesktopPanelPresentationReady(
                contentRevision: 7,
                surfaceRevision: 4,
              ),
            ),
          );

      expect(decodedAnchor.syncRevision, 12);
      expect(decodedAnchor.sceneId, '1:2');
      expect(decodedReady.contentRevision, 7);
      expect(decodedReady.surfaceRevision, 4);
    });

    test('精简 surface payload 会钳制坏尺寸和 DPI', () {
      final DesktopPanelSurfaceState? state =
          DesktopPanelSurfaceState.fromPayload(<String, Object?>{
            'surfaceRevision': 5,
            'attached': true,
            'visible': false,
            'clientWidthPx': double.infinity,
            'clientHeightPx': -1,
            'dpi': 5000,
          });

      expect(state, isNotNull);
      expect(state!.surfaceRevision, 5);
      expect(state.clientSizePx, Size.zero);
      expect(state.dpi, 960);
      expect(state.surfaceReady, isFalse);
      expect(
        DesktopPanelSurfaceState.fromPayload(
          const DesktopPanelSurfaceState(
            surfaceRevision: 6,
            attached: true,
            visible: true,
            clientSizePx: Size(800, 600),
            dpi: 144,
          ).toPayload(),
        )?.clientSizePx,
        const Size(800, 600),
      );
    });
  });
}
