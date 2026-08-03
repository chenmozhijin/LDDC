import 'dart:io';

import 'package:flutter/material.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/features/search/application/search_workflow_providers.dart'
    show searchWorkflowControllerProvider;
import 'package:lddc/src/features/search/presentation/search_page.dart';
import 'package:path/path.dart' as p;

import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/sample_pool.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('search integration: 专辑、歌单、批量保存与空关键词校验', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'search_collection_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'search_collection_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'search_collection_flow',
        runtimeConfig: runtime,
        reporter: reporter,
        config: buildIntegrationConfig(searchSources: const <String>['QM']),
      );
      addTearDown(app.dispose);

      final AppShellDriver shell = AppShellDriver(tester);
      final SearchDriver search = SearchDriver(tester);
      await shell.openRoute(AppShellRoute.search);
      final searchContainer = scopedProviderContainer(
        tester,
        find.byType(SearchPage),
      );
      expect(await _readExportedLyrics(app.workspace.exportsDir), isEmpty);
      // 移动端列表批量保存依赖真实 SAF tree。offline profile 明确使用
      // scripted picker，不应调用真实 Android MethodChannel；这里继续覆盖
      // 专辑/歌单导航并断言动作不暴露。Android SAF 保存由 platform/UI
      // Automator 场景形成真实证据，桌面离线流程仍验证最终文件产物。
      final bool supportsListBatchSave =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
      Map<String, String> albumArtifacts = <String, String>{};
      // 专辑和歌单步骤各自串行等待搜索结果、曲目列表与批量保存完成。
      // 外层总预算必须覆盖三个长等待，否则慢设备会先抛出笼统的组合步骤超时，
      // 掩盖内部已经准备好的具体失败原因。额外的默认步骤预算用于菜单动画、
      // 双击进入曲目页和文件写入等交互，不放宽任何单个业务等待的上限。
      final Duration collectionStepTimeout =
          runtime.longStepTimeout * 3 + runtime.defaultStepTimeout;

      await reporter.runStep('search_album_and_batch_save', () async {
        await runStepWithTimeout(
          () async {
            await search.enterKeyword('');
            await search.selectSource(kIntegrationSearchAlbumCase.source);
            await search.selectSearchType(SearchType.album);
            await search.enterKeyword(kIntegrationSearchAlbumCase.keyword);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.selectedSource ==
                        kIntegrationSearchAlbumCase.source &&
                    state.selectedSearchType == SearchType.album &&
                    state.keyword == kIntegrationSearchAlbumCase.keyword;
              },
              timeout: const Duration(seconds: 5),
              reason: '等待专辑搜索条件同步到状态',
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
                    info.keyword == kIntegrationSearchAlbumCase.keyword &&
                    info.searchType == SearchType.album;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待专辑搜索结果',
            );
            await search.openResultAt(0);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.currentPathResult != null &&
                    state.currentPathResult!.isNotEmpty &&
                    state.currentPathResult!.info is SongListInfo;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待专辑歌曲列表',
            );
            if (supportsListBatchSave) {
              await search.tapBatchSave();
              await pumpUntil(
                tester,
                () => !searchContainer
                    .read(searchWorkflowControllerProvider)
                    .isBatchSaving,
                timeout: runtime.longStepTimeout,
                reason: '等待专辑批量保存完成',
              );
            } else {
              expect(
                find.byKey(
                  const ValueKey<String>('search_result_batch_save_button'),
                ),
                findsNothing,
              );
            }
          },
          timeout: collectionStepTimeout,
          label: 'search_album_and_batch_save',
        );
        albumArtifacts = await _readExportedLyrics(app.workspace.exportsDir);
        if (supportsListBatchSave) {
          expect(albumArtifacts, isNotEmpty);
          expect(
            albumArtifacts.keys.every(
              (String path) => p.extension(path) == '.lrc',
            ),
            isTrue,
          );
          expect(
            albumArtifacts.values.every(
              (String content) => content.contains('['),
            ),
            isTrue,
          );
        } else {
          expect(albumArtifacts, isEmpty);
        }
      });
      if (runtime.capabilities.network == 'real') {
        reporter.recordCapabilityEvidence(
          'network',
          'search_album_and_fetch_lyrics',
        );
      }

      await reporter.runStep('search_songlist_and_batch_save', () async {
        await runStepWithTimeout(
          () async {
            await search.enterKeyword('');
            await search.selectSource(kIntegrationSearchSongListCase.source);
            await search.selectSearchType(SearchType.songlist);
            await search.enterKeyword(kIntegrationSearchSongListCase.keyword);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.selectedSource ==
                        kIntegrationSearchSongListCase.source &&
                    state.selectedSearchType == SearchType.songlist &&
                    state.keyword == kIntegrationSearchSongListCase.keyword;
              },
              timeout: const Duration(seconds: 5),
              reason: '等待歌单搜索条件同步到状态',
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
                    info.keyword == kIntegrationSearchSongListCase.keyword &&
                    info.searchType == SearchType.songlist;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待歌单搜索结果',
            );
            await search.openResultAt(0);
            await pumpUntil(
              tester,
              () {
                final SearchWorkflowState state = searchContainer.read(
                  searchWorkflowControllerProvider,
                );
                return state.currentPathResult != null &&
                    state.currentPathResult!.isNotEmpty &&
                    state.currentPathResult!.info is SongListInfo;
              },
              timeout: runtime.longStepTimeout,
              reason: '等待歌单歌曲列表',
            );
            if (supportsListBatchSave) {
              await search.tapBatchSave();
              await pumpUntil(
                tester,
                () => !searchContainer
                    .read(searchWorkflowControllerProvider)
                    .isBatchSaving,
                timeout: runtime.longStepTimeout,
                reason: '等待歌单批量保存完成',
              );
            } else {
              expect(
                find.byKey(
                  const ValueKey<String>('search_result_batch_save_button'),
                ),
                findsNothing,
              );
            }
          },
          timeout: collectionStepTimeout,
          label: 'search_songlist_and_batch_save',
        );
        final Map<String, String> allArtifacts = await _readExportedLyrics(
          app.workspace.exportsDir,
        );
        final Set<String> playlistFiles = allArtifacts.keys.toSet().difference(
          albumArtifacts.keys.toSet(),
        );
        if (supportsListBatchSave) {
          expect(playlistFiles, isNotEmpty, reason: '歌单保存必须生成专辑保存步骤之外的新文件');
          for (final String fileName in playlistFiles) {
            expect(p.extension(fileName), '.lrc');
            expect(allArtifacts[fileName], contains('['));
          }
        } else {
          expect(playlistFiles, isEmpty);
        }
      });

      await reporter.runStep('empty_keyword_notice', () async {
        await runStepWithTimeout(
          () async {
            await search.enterKeyword('');
            await search.submitSearch();
            await pumpUntilVisible(
              tester,
              find.byKey(const ValueKey<String>('search_notice_emptyKeyword')),
              timeout: runtime.defaultStepTimeout,
              reason: '等待空关键词提示出现',
            );
          },
          // 内部可见性等待会在 defaultStepTimeout 给出具体失败原因；外层预算
          // 必须略大，避免两个相同计时器同时触发后遗留仍在 pump 的 Future，
          // 进而让失败截图和 teardown 与它发生 guarded function conflict。
          timeout: runtime.defaultStepTimeout + const Duration(seconds: 2),
          label: 'empty_keyword_notice',
        );
        expect(
          find.byKey(const ValueKey<String>('search_notice_emptyKeyword')),
          findsOneWidget,
        );
      });

      await reporter.writeSummary(
        extra: <String, Object?>{'exportsDir': app.workspace.exportsDir.path},
      );
    });
  });
}

Future<Map<String, String>> _readExportedLyrics(Directory root) async {
  final Map<String, String> artifacts = <String, String>{};
  await for (final FileSystemEntity entity in root.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final String relativePath = p.relative(entity.path, from: root.path);
    artifacts[relativePath] = await entity.readAsString();
  }
  return artifacts;
}
