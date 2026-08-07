import 'dart:io';

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart'
    show searchWorkflowControllerProvider;
import 'package:lddc/src/features/search/presentation/search_page.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';

import 'support/audio_fixture_factory.dart';
import 'support/audio_fixture_probe.dart';
import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/sample_pool.dart';
import 'support/search_preview_save_strategy.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('search integration: 单曲、songId、预览、翻译、目录与标签保存', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'search_song_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'search_song_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'search_song_flow',
        runtimeConfig: runtime,
        reporter: reporter,
        config: buildIntegrationConfig(
          searchSources: const <String>['QM', 'NE'],
        ),
      );
      addTearDown(app.dispose);

      final IntegrationAudioFixtureFactory audioFactory =
          IntegrationAudioFixtureFactory(
            ffmpegExecutable: runtime.ffmpegExecutable,
            mediaGateway: app.mediaGateway,
          );
      final List<IntegrationGeneratedAudioFixture> tagTargets =
          await audioFactory.createAudioFixtureBatch(
            rootDirectory: app.workspace.artifactsDir,
            specs: kIntegrationSearchTagTargets,
          );
      for (final IntegrationGeneratedAudioFixture fixture in tagTargets) {
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
      }
      if (runtime.capabilities.media == 'real') {
        reporter.recordCapabilityEvidence(
          'media',
          'read_real_audio_metadata',
          details: <String, Object?>{'fixtureCount': tagTargets.length},
        );
      }
      final IntegrationGeneratedAudioFixture firstTagTarget = tagTargets.first;
      app.filePicker.audioFile = PickedAudioFileHandle(
        name: firstTagTarget.file.uri.pathSegments.last,
        path: firstTagTarget.path,
      );
      // 移动端离线场景使用脚本化文件选择器，但仍必须写出并回读真实文件。旧测试只
      // 配置了标签目标，没有为 saveTextFile 提供路径，选择器按“用户取消”返回 null，
      // 测试随后只能等待到超时，且无法证明保存产物正确。
      app.filePicker.saveFilePath = File(
        '${app.workspace.exportsDir.path}${Platform.pathSeparator}search-preview.lrc',
      ).path;

      final AppShellDriver shell = AppShellDriver(tester);
      await shell.openRoute(AppShellRoute.search);
      final searchContainer = scopedProviderContainer(
        tester,
        find.byType(SearchPage),
      );
      final SearchDriver search = SearchDriver(
        tester,
        readState: () => searchContainer.read(searchWorkflowControllerProvider),
      );

      await reporter.runStep('search_song', () async {
        await runStepWithTimeout(
          () async {
            await search.enterKeyword('');
            await search.selectSource(kIntegrationSearchSongCase.source);
            await search.selectSearchType(SearchType.song);
            await search.enterKeyword(kIntegrationSearchSongCase.keyword);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.selectedSource ==
                        kIntegrationSearchSongCase.source &&
                    state.selectedSearchType == SearchType.song &&
                    state.keyword == kIntegrationSearchSongCase.keyword;
              },
              timeout: const Duration(seconds: 5),
              reason: '等待搜索条件同步到状态',
            );
            await search.submitSearch();
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                final Object? info = state.currentPathResult?.info;
                return find
                        .byKey(const ValueKey<String>('search_result_row_0'))
                        .evaluate()
                        .isNotEmpty &&
                    state.currentPathResult != null &&
                    state.currentPathResult!.isNotEmpty &&
                    info is SearchInfo &&
                    info.keyword == kIntegrationSearchSongCase.keyword &&
                    info.searchType == SearchType.song;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待单曲搜索结果',
            );
          },
          timeout: runtime.longStepTimeout,
          label: 'search_song',
        );
      });
      if (runtime.capabilities.network == 'real') {
        reporter.recordCapabilityEvidence('network', 'search_song');
      }

      await reporter.runStep('open_first_preview', () async {
        await runStepWithTimeout(
          () async {
            await search.openResultAt(0);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.previewPhase == SearchPreviewPhase.ready &&
                    state.previewText.trim().isNotEmpty;
              },
              timeout: runtime.defaultStepTimeout,
              reason: '等待歌词预览完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'open_first_preview',
        );
      });

      await reporter.runStep('toggle_translation', () async {
        await runStepWithTimeout(
          () async {
            await search.tapTranslate();
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
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
      if (runtime.capabilities.translation == 'real') {
        reporter.recordCapabilityEvidence('translation', 'translate_lyrics');
      }

      final IntegrationSearchPreviewSaveAction previewSaveAction =
          searchPreviewSaveActionForPlatform(runtime.deviceName);
      final bool usesFileSave =
          previewSaveAction == IntegrationSearchPreviewSaveAction.file;
      await reporter.runStep<Map<String, Object?>>(
        usesFileSave ? 'save_preview_to_file' : 'save_preview_to_directory',
        () async {
          late final ExportArtifactSnapshot artifact;
          await runStepWithTimeout(
            () async {
              // 移动端通过系统保存文件界面选择最终文件，桌面端则选择目录并由
              // LDDC 生成文件名。旧测试在 Android/iOS 上寻找不存在的“保存目录”
              // 按钮，误报为预览弹层未建立；这里按生产能力执行真实用户动作。
              if (usesFileSave) {
                await search.tapSaveFile();
              } else {
                await search.tapSaveDirectory();
              }
              await pumpUntil(
                tester,
                () => app.workspace.exportsDir
                    .listSync(recursive: true)
                    .whereType<File>()
                    .isNotEmpty,
                timeout: runtime.defaultStepTimeout,
                reason: '等待歌词保存产物写入隔离工作区',
              );
              final File exported = app.workspace.exportsDir
                  .listSync(recursive: true)
                  .whereType<File>()
                  .first;
              artifact = await assertExportArtifact(
                file: exported,
                expectedExtension: '.lrc',
                requiredTextFragments: const <String>['[', ']'],
              );
            },
            timeout: runtime.defaultStepTimeout,
            label: usesFileSave
                ? 'save_preview_to_file'
                : 'save_preview_to_directory',
          );
          expect(
            searchContainer
                .read(searchWorkflowControllerProvider)
                .lastSavedPath,
            isNotEmpty,
          );
          return artifact.toJson();
        },
        details: (Map<String, Object?> value) => value,
      );

      await reporter.runStep('save_preview_to_tag', () async {
        await runStepWithTimeout(
          () async {
            await search.tapSaveTag();
            await pumpUntil(
              tester,
              () => app.mediaGateway.writes.isNotEmpty,
              timeout: runtime.defaultStepTimeout,
              reason: '等待标签写回完成',
            );
          },
          timeout: runtime.defaultStepTimeout,
          label: 'save_preview_to_tag',
        );
        final String? embeddedLyricsText = await app.mediaGateway
            .readAudioLyricsText(songPath: firstTagTarget.path);
        expect(embeddedLyricsText, contains('['));
        expect(app.mediaGateway.writes.last.songPath, firstTagTarget.path);
      });

      await search.dismissPreviewSheetIfOpen();

      await reporter.runStep('search_song_id', () async {
        await runStepWithTimeout(
          () async {
            await search.enterKeyword('');
            await search.selectSource(kIntegrationSearchSongIdCase.source);
            await search.selectSearchType(SearchType.songId);
            await search.enterKeyword(kIntegrationSearchSongIdCase.keyword);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.selectedSource ==
                        kIntegrationSearchSongIdCase.source &&
                    state.selectedSearchType == SearchType.songId &&
                    state.keyword == kIntegrationSearchSongIdCase.keyword;
              },
              timeout: const Duration(seconds: 5),
              reason: '等待 songId 搜索条件同步到状态',
            );
            await search.submitSearch();
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                final Object? info = state.currentPathResult?.info;
                return find
                        .byKey(const ValueKey<String>('search_result_row_0'))
                        .evaluate()
                        .isNotEmpty &&
                    state.currentPathResult != null &&
                    state.currentPathResult!.isNotEmpty &&
                    info is SearchInfo &&
                    info.keyword == kIntegrationSearchSongIdCase.keyword &&
                    info.searchType == SearchType.songId;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待 songId 搜索结果',
            );
          },
          timeout: runtime.longStepTimeout,
          label: 'search_song_id',
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
