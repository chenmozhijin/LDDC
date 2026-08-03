import 'dart:io';

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_controller.dart'
    show openLyricsPageControllerProvider;
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_state.dart';
import 'package:lddc/src/features/open_lyrics/presentation/open_lyrics_page.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';
import 'package:path/path.dart' as p;

import 'support/audio_fixture_factory.dart';
import 'support/audio_fixture_probe.dart';
import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/sample_pool.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('open lyrics integration: 打开、转换、翻译、导出与标签写回', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'open_lyrics_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'open_lyrics_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'open_lyrics_flow',
        runtimeConfig: runtime,
        reporter: reporter,
      );
      addTearDown(app.dispose);

      final IntegrationAudioFixtureFactory audioFactory =
          IntegrationAudioFixtureFactory(
            ffmpegExecutable: runtime.ffmpegExecutable,
            mediaGateway: app.mediaGateway,
          );
      final IntegrationGeneratedAudioFixture songFixture = await audioFactory
          .createAudioFixture(
            rootDirectory: app.workspace.artifactsDir,
            spec: kIntegrationOpenLyricsSong,
          );
      final IntegrationAudioProbeResult openLyricsProbe =
          await probeAudioFixture(
            mediaGateway: app.mediaGateway,
            songPath: songFixture.path,
          );
      expectProbeDurationWithin(
        expectedDurationMs: kIntegrationOpenLyricsSong.durationMs,
        actualDurationMs: openLyricsProbe.durationMs,
      );
      expect(openLyricsProbe.embeddedLyricsText, contains('内嵌歌词'));

      app.filePicker
        ..file = MemoryPickedFileHandle(
          name: 'open_lyrics_sample.qrc',
          path: p.join(app.workspace.root.path, 'open_lyrics_sample.qrc'),
          bytes: utf8Bytes(
            '<Lyric_1 LyricType="1" '
            'LyricContent="[ar:集成测试]\n'
            '[0,5000]打开(0,1200)歌词(1200,1800)样本(3000,2000)\n"/>',
          ),
        )
        ..saveFilePath =
            '${app.workspace.exportsDir.path}${Platform.pathSeparator}open_lyrics_export.lrc'
        ..audioFile = PickedAudioFileHandle(
          name: p.basename(songFixture.path),
          path: songFixture.path,
        );

      final AppShellDriver shell = AppShellDriver(tester);
      final OpenLyricsDriver openLyrics = OpenLyricsDriver(tester);
      await shell.openRoute(AppShellRoute.openLyrics);
      final openLyricsContainer = scopedProviderContainer(
        tester,
        find.byType(OpenLyricsPage),
      );

      await reporter.runStep('open_qrc_and_convert', () async {
        await runStepWithTimeout(
          () async {
            await openLyrics.openLyricsFile();
            // 文件按钮的测试驱动只负责完成点击；真实文件读取和 controller 状态更新
            // 仍在异步执行。若未等到 rawLoaded 就点击转换，按钮会因为 isOpening=true
            // 保持禁用，旧测试随后只能以超时结束，无法说明到底是读取还是解析失败。
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = openLyricsContainer.read(
                  openLyricsPageControllerProvider,
                );
                return !state.isOpening &&
                    state.previewState == OpenLyricsPreviewState.rawLoaded &&
                    state.rawText.contains('<Lyric_1');
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待 QRC 原文读取完成',
            );
            await openLyrics.tapConvert();
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = openLyricsContainer.read(
                  openLyricsPageControllerProvider,
                );
                return !state.isConverting &&
                    (state.previewState == OpenLyricsPreviewState.converted ||
                        state.notice != null);
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待歌词文件转换完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'open_qrc_and_convert',
        );
        final OpenLyricsPageState state = openLyricsContainer.read(
          openLyricsPageControllerProvider,
        );
        expect(state.inputName, 'open_lyrics_sample.qrc');
        expect(
          state.notice,
          isNull,
          reason: state.notice?.detail ?? state.notice?.code.name,
        );
        expect(state.previewState, OpenLyricsPreviewState.converted);
        expect(state.currentLyrics?.tags['ar'], '集成测试');
        final LyricsData original = state.currentLyrics!.data['orig']!;
        expect(original, hasLength(1));
        expect(original.single.text, '打开歌词样本');
        expect(
          original.single.words
              .map((LyricsWord word) => (word.startMs, word.endMs))
              .toList(growable: false),
          <(int?, int?)>[(0, 1200), (1200, 3000), (3000, 5000)],
        );
        expect(state.previewText, contains('[00:00.000]打开'));
        expect(state.previewText, contains('[00:01.200]歌词'));
      });

      await reporter.runStep('switch_formats', () async {
        await openLyrics.selectLyricsFormat(LyricsFormat.ass);
        await pumpUntil(
          tester,
          () => openLyricsContainer
              .read(openLyricsPageControllerProvider)
              .previewText
              .contains('[Script Info]'),
          timeout: runtime.defaultStepTimeout,
          reason: '等待 ASS 预览刷新',
        );
        expect(
          openLyricsContainer
              .read(openLyricsPageControllerProvider)
              .previewText,
          contains('[Script Info]'),
        );
        await openLyrics.selectLyricsFormat(LyricsFormat.srt);
        await pumpUntil(
          tester,
          () => openLyricsContainer
              .read(openLyricsPageControllerProvider)
              .previewText
              .contains('-->'),
          timeout: runtime.defaultStepTimeout,
          reason: '等待 SRT 预览刷新',
        );
        expect(
          openLyricsContainer
              .read(openLyricsPageControllerProvider)
              .previewText,
          contains('-->'),
        );
        await openLyrics.selectLyricsFormat(LyricsFormat.lineByLineLrc);
        await pumpUntil(
          tester,
          () => openLyricsContainer
              .read(openLyricsPageControllerProvider)
              .previewText
              .contains('['),
          timeout: runtime.defaultStepTimeout,
          reason: '等待 LRC 预览刷新',
        );
      });

      await reporter.runStep('toggle_translation', () async {
        await runStepWithTimeout(
          () async {
            await openLyrics.tapTranslate();
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = openLyricsContainer.read(
                  openLyricsPageControllerProvider,
                );
                return state.currentLyrics?.data.containsKey('LDDC_ts') ??
                    false;
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待翻译完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'toggle_translation',
        );
      });

      await reporter.runStep<Map<String, Object?>>('export_to_file', () async {
        late final ExportArtifactSnapshot artifact;
        await runStepWithTimeout(
          () async {
            await openLyrics.tapSaveFile();
            await pumpUntil(
              tester,
              () => File(app.filePicker.saveFilePath!).existsSync(),
              timeout: runtime.defaultStepTimeout,
              reason: '等待导出文件完成',
            );
            artifact = await assertExportArtifact(
              file: File(app.filePicker.saveFilePath!),
              expectedExtension: '.lrc',
              requiredTextFragments: const <String>['[', ']'],
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'export_to_file',
        );
        return artifact.toJson();
      }, details: (Map<String, Object?> value) => value);

      await reporter.runStep('open_song_and_read_embedded_lyrics', () async {
        await runStepWithTimeout(
          () async {
            await openLyrics.selectLyricsFormat(LyricsFormat.lineByLineLrc);
            await openLyrics.openSongFile();
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = openLyricsContainer.read(
                  openLyricsPageControllerProvider,
                );
                return !state.isOpening &&
                    state.inputType == OpenLyricsInputType.songFile &&
                    state.rawText.contains('内嵌歌词');
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待歌曲内嵌歌词原文读取完成',
            );
            await openLyrics.tapConvert();
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = openLyricsContainer.read(
                  openLyricsPageControllerProvider,
                );
                return state.previewState == OpenLyricsPreviewState.converted &&
                    !state.isConverting &&
                    state.previewText.contains('内嵌歌词');
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待歌曲内嵌歌词读取完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'open_song_and_read_embedded_lyrics',
        );
      });

      await reporter.runStep('save_to_tag', () async {
        await runStepWithTimeout(
          () async {
            await openLyrics.selectLyricsFormat(LyricsFormat.lineByLineLrc);
            await openLyrics.tapSaveTag();
            await pumpUntil(
              tester,
              () => app.mediaGateway.writes.isNotEmpty,
              timeout: runtime.defaultStepTimeout,
              reason: '等待歌词写回标签完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'save_to_tag',
        );
        final String? lyricsText = await app.mediaGateway.readAudioLyricsText(
          songPath: songFixture.path,
        );
        expect(lyricsText, contains('内嵌歌词'));
      });

      await reporter.runStep('reject_non_lrc_tag_write', () async {
        await openLyrics.selectLyricsFormat(LyricsFormat.srt);
        await openLyrics.tapSaveTag();
        await pumpUntilVisible(
          tester,
          find.byKey(
            const ValueKey<String>('open_lyrics_notice_audioTagRequiresLrc'),
          ),
          timeout: runtime.defaultStepTimeout,
          reason: '等待非 LRC 标签写回提示出现',
        );
        expect(
          find.byKey(
            const ValueKey<String>('open_lyrics_notice_audioTagRequiresLrc'),
          ),
          findsOneWidget,
        );
      });

      await reporter.writeSummary(
        extra: <String, Object?>{
          'exportsDir': app.workspace.exportsDir.path,
          'tagWrites': app.mediaGateway.writes.length,
        },
      );
    });
  });
}
