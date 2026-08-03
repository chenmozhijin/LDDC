import 'package:flutter_test/flutter_test.dart';

import 'support/desktop_lyrics_diagnostic_harness.dart';

void main() {
  test('desktop lyrics diagnostic harness 会过滤 panel 相关日志并解析字段', () {
    const String logText = '''
[2026-03-29T12:00:00.000][level=INFO][role=panel][pid=100][scope=panel-host-bridge][instance=1][panel=2][seq=1] update_panel_surface requested_size=970x1114
[2026-03-29T12:00:00.010][level=INFO][role=panel][pid=100][scope=panel-shell][instance=1][panel=2][seq=2] reason=surface display=painter mode=painter geometryEpoch=34 renderGeneration=lyrics|scene=1
[2026-03-29T12:00:00.020][level=INFO][role=main][pid=100][scope=main-window][instance=-][panel=-][seq=3] ignored
[2026-03-29T12:00:00.030][level=INFO][role=panel][pid=100][scope=panel-render][instance=1][panel=2][seq=4] phase=paintRasterResolved geometryEpoch=34 paintFrameId=7 visibleCacheMissCount=0
''';

    final List<DesktopLyricsDiagnosticEvent> events =
        DesktopLyricsDiagnosticHarness.parse(logText);

    expect(
      events.map((DesktopLyricsDiagnosticEvent item) => item.scope),
      <String>['panel-host-bridge', 'panel-shell', 'panel-render'],
    );
    expect(events[1].field('reason'), 'surface');
    expect(events[1].intField('geometryEpoch'), 34);
    expect(events[2].intField('paintFrameId'), 7);
  });

  test('desktop lyrics diagnostic harness 能解析包含空格的 native 字段', () {
    const String logText = '''
[2026-03-29T12:00:00.000][level=INFO][role=panel][pid=100][scope=panel-host-native][instance=1][panel=2][seq=1] [desktop-panel-host] event=update_surface_after_apply host_parent_rect=1657,1333 948x569 host_client=946x536 view_client=946x536
''';

    final List<DesktopLyricsDiagnosticEvent> events =
        DesktopLyricsDiagnosticHarness.parse(logText);

    expect(events, hasLength(1));
    expect(events.first.kind, 'update_surface_after_apply');
    expect(events.first.field('host_parent_rect'), '1657,1333 948x569');
    expect(events.first.field('host_client'), '946x536');
  });

  test('desktop lyrics diagnostic harness 支持阶段切分和 generation 提取', () {
    const String logText = '''
[2026-03-29T12:00:00.000][level=INFO][role=panel][pid=100][scope=panel-shell][instance=1][panel=2][seq=1] reason=surface display=empty geometryEpoch=31 bindGeneration=1 geometryGeneration=2 visibilityGeneration=3 surfaceReadyGeneration=4
[2026-03-29T12:00:01.000][level=INFO][role=panel][pid=100][scope=panel-render][instance=1][panel=2][seq=2] phase=paintGeometryResolved geometryEpoch=31 paintFrameId=8 renderGeneration=lyrics|scene=1
[2026-03-29T12:00:02.000][level=INFO][role=panel][pid=100][scope=panel-shell][instance=1][panel=2][seq=3] reason=surface display=painter geometryEpoch=32 bindGeneration=1 geometryGeneration=3 visibilityGeneration=4 surfaceReadyGeneration=5
''';
    final List<DesktopLyricsDiagnosticEvent> events =
        DesktopLyricsDiagnosticHarness.parse(logText);
    final List<DesktopLyricsDiagnosticPhase> phases =
        DesktopLyricsDiagnosticHarness.sliceByCheckpoints(
          events,
          <DesktopLyricsDiagnosticCheckpoint>[
            DesktopLyricsDiagnosticCheckpoint(
              name: 'initial_show',
              timestamp: DateTime.parse('2026-03-29T12:00:01.500'),
            ),
            DesktopLyricsDiagnosticCheckpoint(
              name: 'reshow',
              timestamp: DateTime.parse('2026-03-29T12:00:02.500'),
            ),
          ],
        );
    final List<DesktopPanelGenerationSample> samples =
        DesktopLyricsDiagnosticHarness.extractGenerationSamples(events);

    expect(phases, hasLength(2));
    expect(phases.first.name, 'initial_show');
    expect(phases.first.events, hasLength(2));
    expect(phases.last.events, hasLength(1));
    expect(samples, hasLength(3));
    expect(samples.first.geometryEpoch, 31);
    expect(samples.last.geometryGeneration, 3);
    expect(samples[1].paintFrameId, 8);
  });
}
