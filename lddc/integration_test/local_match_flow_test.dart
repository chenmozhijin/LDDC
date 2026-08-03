import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_controller.dart'
    show localMatchPageControllerProvider;
import 'package:lddc/src/features/local_match/application/local_match_page_state.dart';
import 'package:lddc/src/features/local_match/presentation/local_match_page.dart';

import 'support/audio_fixture_factory.dart';
import 'support/audio_fixture_probe.dart';
import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/sample_pool.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('local match integration: 扫描、匹配、写文件、写标签、跳过已有歌词', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'local_match_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'local_match_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'local_match_flow',
        runtimeConfig: runtime,
        reporter: reporter,
        config: buildIntegrationConfig(
          searchSources: const <String>['QM', 'NE'],
        ),
      );
      addTearDown(app.dispose);

      final Directory songsDir = Directory(
        '${app.workspace.artifactsDir.path}${Platform.pathSeparator}songs',
      );
      await songsDir.create(recursive: true);
      final IntegrationAudioFixtureFactory audioFactory =
          IntegrationAudioFixtureFactory(
            ffmpegExecutable: runtime.ffmpegExecutable,
            mediaGateway: app.mediaGateway,
          );
      final List<IntegrationGeneratedAudioFixture> fixtures = await audioFactory
          .createAudioFixtureBatch(
            rootDirectory: songsDir,
            specs: kIntegrationLocalMatchSongs.map(
              (IntegrationAudioFixtureSpec spec) => IntegrationAudioFixtureSpec(
                pathSegments: spec.pathSegments,
                format: spec.format,
                durationMs: spec.durationMs,
                title: spec.title,
                artists: spec.artists,
                album: spec.album,
                track: spec.track,
                date: spec.date,
                embeddedLyricsText: spec.embeddedLyricsText,
              ),
            ),
          );
      for (final IntegrationGeneratedAudioFixture fixture in fixtures) {
        final IntegrationAudioProbeResult probe = await probeAudioFixture(
          mediaGateway: app.mediaGateway,
          songPath: fixture.path,
        );
        expectProbeDurationWithin(
          expectedDurationMs: fixture.spec.durationMs,
          actualDurationMs: probe.durationMs,
        );
        expect(probe.songInfos, isNotEmpty);
        expect(probe.songInfos.first.title, fixture.spec.title);
        expect(
          probe.songInfos.first.artist?.join(),
          fixture.spec.artists.join('/'),
        );
      }
      app.filePicker.directory = songsDir.path;

      final AppShellDriver shell = AppShellDriver(tester);
      final LocalMatchDriver localMatch = LocalMatchDriver(tester);
      await shell.openRoute(AppShellRoute.localMatch);
      final localMatchContainer = scopedProviderContainer(
        tester,
        find.byType(LocalMatchPage),
      );
      localMatchContainer
          .read(localMatchPageControllerProvider.notifier)
          .updateMinScore(0);

      await reporter.runStep('scan_directory', () async {
        await runStepWithTimeout(
          () async {
            await localMatch.pickDirectory();
            await pumpUntil(
              tester,
              () {
                final LocalMatchPageState state = localMatchContainer.read(
                  localMatchPageControllerProvider,
                );
                return state.queueItems.length == fixtures.length;
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待目录扫描完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'scan_directory',
        );
      });

      await reporter.runStep('run_match_and_write', () async {
        await runStepWithTimeout(
          () async {
            await localMatch.selectSaveToTagMode(LocalMatchSaveToTagMode.both);
            await pumpUntil(
              tester,
              () =>
                  localMatchContainer
                      .read(localMatchPageControllerProvider)
                      .saveToTagMode ==
                  LocalMatchSaveToTagMode.both,
              timeout: runtime.defaultStepTimeout,
              reason: '等待输出策略切换为文件与标签',
            );
            await localMatch.tapStartOrCancel();
            await pumpUntil(
              tester,
              () {
                final LocalMatchPageState state = localMatchContainer.read(
                  localMatchPageControllerProvider,
                );
                return !state.isBusy &&
                    state.successCount + state.skipCount + state.failCount ==
                        fixtures.length;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待本地匹配执行完成',
            );
          },
          timeout: runtime.longStepTimeout,
          label: 'run_match_and_write',
        );
        final LocalMatchPageState state = localMatchContainer.read(
          localMatchPageControllerProvider,
        );
        final String statusSummary = state.queueItems
            .map(
              (LocalMatchQueueItem item) =>
                  '${item.lastStatus?.type.name}:${item.lastStatus?.text}',
            )
            .join(' | ');
        expect(
          state.successCount,
          fixtures.length,
          reason:
              'success=${state.successCount}, skip=${state.skipCount}, '
              'fail=${state.failCount}, statuses=$statusSummary, '
              'queries=${app.mediaGateway.searchKeywords}',
        );
        expect(state.skipCount, 0);
        expect(state.failCount, 0);
        expect(app.mediaGateway.writes.length, fixtures.length);
        for (final IntegrationGeneratedAudioFixture fixture in fixtures) {
          final String? lyricsText = await app.mediaGateway.readAudioLyricsText(
            songPath: fixture.path,
          );
          expect(lyricsText, isNotNull);
          expect(lyricsText, contains('['));
        }
        expect(
          localMatchContainer
              .read(localMatchPageControllerProvider)
              .queueItems
              .every(
                (LocalMatchQueueItem item) =>
                    (item.outputPath ?? item.savePlan.targetPath ?? '')
                        .trim()
                        .isNotEmpty ||
                    item.savePlan.kind == LocalMatchSavePlanKind.tagOnly ||
                    item.savePlan.waitsForLyricsFileName,
              ),
          isTrue,
        );
        final bool hasGeneratedLyricsFile = songsDir
            .listSync(recursive: true)
            .whereType<File>()
            .any((File file) => !file.path.endsWith('.flac'));
        expect(
          hasGeneratedLyricsFile ||
              app.workspace.exportsDir
                  .listSync(recursive: true)
                  .whereType<File>()
                  .isNotEmpty,
          isTrue,
        );
      });

      await reporter.runStep('skip_existing_lyrics', () async {
        final int writesBeforeSkip = app.mediaGateway.writes.length;
        final Map<String, String> filesBeforeSkip = _fileSignatures(songsDir);
        await runStepWithTimeout(
          () async {
            await localMatch.toggleSkipExisting();
            await pumpUntil(
              tester,
              () => localMatchContainer
                  .read(localMatchPageControllerProvider)
                  .skipExistingLyrics,
              timeout: runtime.defaultStepTimeout,
              reason: '等待跳过已有歌词设置生效',
            );
            await localMatch.tapStartOrCancel();
            await pumpUntil(
              tester,
              () => !localMatchContainer
                  .read(localMatchPageControllerProvider)
                  .isBusy,
              timeout: runtime.longStepTimeout,
              reason: '等待跳过已有歌词流程完成',
            );
          },
          timeout: runtime.longStepTimeout,
          label: 'skip_existing_lyrics',
        );
        expect(
          localMatchContainer.read(localMatchPageControllerProvider).isBusy,
          isFalse,
        );
        final LocalMatchPageState state = localMatchContainer.read(
          localMatchPageControllerProvider,
        );
        expect(state.successCount, 0);
        expect(state.skipCount, fixtures.length);
        expect(state.failCount, 0);
        expect(app.mediaGateway.writes.length, writesBeforeSkip);
        expect(_fileSignatures(songsDir), filesBeforeSkip);
      });

      await reporter.writeSummary(
        extra: <String, Object?>{
          'songsDir': songsDir.path,
          'tagWrites': app.mediaGateway.writes.length,
          'searchQueries': app.mediaGateway.searchKeywords,
          'generatedSongs': fixtures
              .map((IntegrationGeneratedAudioFixture item) => item.path)
              .toList(growable: false),
        },
      );
    });
  });
}

Map<String, String> _fileSignatures(Directory root) {
  final Map<String, String> signatures = <String, String>{};
  for (final File file in root.listSync(recursive: true).whereType<File>()) {
    final FileStat stat = file.statSync();
    // 仅比较大小和修改时间会漏掉同尺寸覆写；加入内容摘要后，跳过策略只要
    // 改写了音频或歌词中的任意字节就会使集成测试失败。
    final String digest = sha256.convert(file.readAsBytesSync()).toString();
    signatures[file.path] =
        '$digest:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  }
  return signatures;
}
