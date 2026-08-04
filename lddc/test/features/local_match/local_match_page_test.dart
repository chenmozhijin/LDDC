import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/local_match/application/local_match_dependencies.dart';
import 'package:lddc/src/features/local_match/application/local_match_input_picker.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_controller.dart';
import 'package:lddc/src/features/local_match/application/local_match_page_state.dart';
import 'package:lddc/src/features/local_match/presentation/local_match_page.dart';
import 'package:lddc/src/features/local_match/presentation/widgets/local_match_rules.dart';
import 'package:lddc/src/platform/android/saf/android_saf_lyrics_save_persistence.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';

void main() {
  group('LocalMatchPageController', () {
    test('Android 初始和清空队列后都保持 SAF 目录模式', () {
      final ProviderContainer container = _createContainer(
        capability: _androidCapability(),
        picker: _FakeLocalMatchInputPicker(),
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      expect(
        controller.currentState.inputMode,
        LocalMatchInputMode.androidTree,
      );
      controller.clearQueue();
      expect(
        controller.currentState.inputMode,
        LocalMatchInputMode.androidTree,
      );
    });

    test('桌面导入后可按 SongInfo 自动获取并跳转到搜索页', () async {
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
        ],
      );
      final SongInfo songInfo = SongInfo(
        source: Source.local,
        path: r'D:\music\demo.mp3',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
      );
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            resultBuilder: (List<String> inputPaths) =>
                LocalMatchGetInfosResult(
                  entries: <LocalMatchSongEntry>[
                    LocalMatchSongEntry(
                      songInfo: songInfo,
                      rootPath: r'D:\music',
                    ),
                  ],
                  errors: const <String>[],
                  cancelled: false,
                ),
          );
      final SongInfo matchedSong = SongInfo(
        source: Source.qm,
        id: 'qm-demo',
        title: 'Demo',
        artist: SongArtist(<String>['Singer']),
        album: 'Album',
      );
      final _FakeAutoFetchUseCase autoFetchUseCase = _FakeAutoFetchUseCase(
        result: AutoFetchResult(
          lyrics: Lyrics(
            songInfo: matchedSong,
            source: matchedSong.source,
            types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
            data: <String, LyricsData>{
              'orig': <LyricsLine>[
                LyricsLine(
                  startMs: 0,
                  endMs: 1000,
                  words: const <LyricsWord>[
                    LyricsWord(startMs: 0, endMs: 1000, text: '自动获取成功'),
                  ],
                ),
              ],
            },
          ),
          matchedSongInfo: matchedSong,
          score: 95,
          searchResults: APIResultList<SongInfo>(
            <SongInfo>[matchedSong],
            info: SearchInfo(
              source: Source.qm,
              keyword: 'Singer - Demo',
              searchType: SearchType.song,
              page: 1,
            ),
            ranges: <Source, SourceRange>{
              Source.qm: const SourceRange(start: 0, end: 0, total: 1),
            },
          ),
        ),
      );
      SongInfo? openedSong;
      List<Source>? openedSources;
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
        autoFetchUseCase: autoFetchUseCase,
        openInSearch: (SongInfo songInfo, List<Source> preferredSources) async {
          openedSong = songInfo;
          openedSources = preferredSources;
        },
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.addSongFiles();
      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );

      expect(desktopGetInfosUseCase.lastInputPaths, <String>[
        r'D:\music\demo.mp3',
      ]);
      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.savePlan.targetPath, contains('.lrc'));
      expect(
        state.progressMessage.code,
        LocalMatchProgressMessageCode.scanCompleted,
      );

      await controller.openInSearch(state.queueItems.single.id);
      expect(openedSong?.artistTitle(), 'Singer - Demo');
      expect(openedSources, <Source>[Source.qm]);
    });

    test('拖入 .cue 轨道描述时只导入目标轨并保留 cue 语义', () async {
      final Directory directory = await Directory.systemTemp.createTemp(
        'local-match-dropped-cue-',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final File audioFile = File(
        '${directory.path}${Platform.pathSeparator}disc.wav',
      );
      await audioFile.writeAsBytes(const <int>[]);
      final File cueFile = File(
        '${directory.path}${Platform.pathSeparator}disc.cue',
      );
      await cueFile.writeAsString(_cueText());
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()..durations[audioFile.path] = 240000;
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(),
        mediaGateway: mediaGateway,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.importExternalDesktopItems(<DragDropItemDescriptor>[
        DragDropItemDescriptor.song(
          DragDropSongDescriptor(path: cueFile.path, index: '1'),
        ),
      ]);

      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.songInfo.fromCue, isTrue);
      expect(state.queueItems.single.songInfo.id, '02');
      expect(state.queueItems.single.songInfo.title, 'Second');
      expect(state.queueItems.single.songInfo.path, audioFile.path);
      expect(mediaGateway.readAudioSongInfosCallCount, 0);
    });

    test('非 LRC 标签写回在启动前被拦截', () async {
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
        ],
      );
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            resultBuilder: (List<String> inputPaths) =>
                LocalMatchGetInfosResult(
                  entries: <LocalMatchSongEntry>[
                    LocalMatchSongEntry(
                      songInfo: const SongInfo(
                        source: Source.local,
                        path: r'D:\music\demo.mp3',
                        title: 'Demo',
                      ),
                      rootPath: r'D:\music',
                    ),
                  ],
                  errors: const <String>[],
                  cancelled: false,
                ),
          );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.addSongFiles();
      controller.updateSaveToTagMode(LocalMatchSaveToTagMode.onlyTag);
      controller.updateLyricsFormat(LyricsFormat.srt);
      await Future<void>.delayed(Duration.zero);
      await controller.startOrCancel();

      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(state.notice?.code, LocalMatchNoticeCode.validationFailed);
      expect(
        state.notice?.validationIssues?.map((issue) => issue.code),
        contains(LocalMatchRunValidationCode.tagRequiresLrc),
      );
    });

    test('桌面扫描取消后迟到进度不会覆盖取消反馈', () async {
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'slow.mp3', path: r'D:\music\slow.mp3'),
        ],
      );
      LocalMatchGetInfosProgressCallback? capturedProgress;
      final Completer<LocalMatchGetInfosResult> completer =
          Completer<LocalMatchGetInfosResult>();
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            runHandler:
                ({
                  required List<String> inputPaths,
                  LocalMatchCancellationToken? cancellationToken,
                  LocalMatchGetInfosProgressCallback? onProgress,
                }) {
                  capturedProgress = onProgress;
                  return completer.future;
                },
          );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      final Future<void> scan = controller.addSongFiles();
      for (
        int attempt = 0;
        attempt < 10 && capturedProgress == null;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(capturedProgress, isNotNull);
      capturedProgress?.call(
        const LocalMatchGetInfosProgress(
          text: '正在解析 slow.mp3',
          value: 1,
          maxValue: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(localMatchPageControllerProvider).progressMessage.detail,
        '正在解析 slow.mp3',
      );

      await controller.startOrCancel();
      capturedProgress?.call(
        const LocalMatchGetInfosProgress(
          text: '取消后的扫描迟到进度',
          value: 1,
          maxValue: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(localMatchPageControllerProvider).progressMessage.code,
        LocalMatchProgressMessageCode.cancelling,
      );

      completer.complete(
        LocalMatchGetInfosResult(
          entries: const <LocalMatchSongEntry>[],
          errors: const <String>[],
          cancelled: true,
        ),
      );
      await scan;
      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(
        state.progressMessage.code,
        LocalMatchProgressMessageCode.scanCancelled,
      );
      expect(state.notice?.code, LocalMatchNoticeCode.scanCancelled);
    });

    test('桌面匹配取消后迟到进度不会覆盖取消反馈', () async {
      final SongInfo songInfo = SongInfo(
        source: Source.local,
        title: 'Slow',
        artist: SongArtist(<String>['Singer']),
        path: r'D:\music\slow.mp3',
      );
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'slow.mp3', path: r'D:\music\slow.mp3'),
        ],
      );
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            resultBuilder: (_) => LocalMatchGetInfosResult(
              entries: <LocalMatchSongEntry>[
                LocalMatchSongEntry(songInfo: songInfo, rootPath: r'D:\music'),
              ],
              errors: const <String>[],
              cancelled: false,
            ),
          );
      LocalMatchProgressCallback? capturedProgress;
      final Completer<LocalMatchResult> completer =
          Completer<LocalMatchResult>();
      final _StubLocalMatchUseCase localMatchUseCase = _StubLocalMatchUseCase(
        runHandler:
            ({
              required List<LocalMatchSongEntry> entries,
              required LocalMatchRunOptions options,
              AppConfig? config,
              LocalMatchCancellationToken? cancellationToken,
              LyricsSavePersistencePort? lyricsPersistencePort,
              LocalMatchProgressCallback? onProgress,
            }) {
              capturedProgress = onProgress;
              return completer.future;
            },
      );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
        localMatchUseCase: localMatchUseCase,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.addSongFiles();
      final Future<void> run = controller.startOrCancel();
      for (
        int attempt = 0;
        attempt < 10 && capturedProgress == null;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(capturedProgress, isNotNull);
      capturedProgress?.call(
        const LocalMatchProgress(text: '正在匹配 slow.mp3', value: 0, maxValue: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(localMatchPageControllerProvider).progressMessage.detail,
        '正在匹配 slow.mp3',
      );

      await controller.startOrCancel();
      capturedProgress?.call(
        const LocalMatchProgress(text: '取消后的迟到进度', value: 0, maxValue: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(localMatchPageControllerProvider).progressMessage.code,
        LocalMatchProgressMessageCode.cancelling,
      );

      completer.complete(
        LocalMatchResult(
          total: 1,
          successCount: 0,
          failCount: 0,
          skipCount: 0,
          cancelled: true,
          statuses: <LocalMatchingStatus>[],
        ),
      );
      await run;
      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(
        state.progressMessage.code,
        LocalMatchProgressMessageCode.matchingCancelled,
      );
      expect(state.notice?.code, LocalMatchNoticeCode.matchCancelled);
    });

    test('桌面扫描 dispose 后迟到进度和结果不会写入已释放状态', () async {
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'slow.mp3', path: r'D:\music\slow.mp3'),
        ],
      );
      LocalMatchGetInfosProgressCallback? capturedProgress;
      final Completer<LocalMatchGetInfosResult> completer =
          Completer<LocalMatchGetInfosResult>();
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            runHandler:
                ({
                  required List<String> inputPaths,
                  LocalMatchCancellationToken? cancellationToken,
                  LocalMatchGetInfosProgressCallback? onProgress,
                }) {
                  capturedProgress = onProgress;
                  return completer.future;
                },
          );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
      );
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      final Future<void> scan = controller.addSongFiles();
      for (
        int attempt = 0;
        attempt < 10 && capturedProgress == null;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(capturedProgress, isNotNull);

      container.dispose();
      capturedProgress?.call(
        const LocalMatchGetInfosProgress(
          text: 'dispose 后扫描迟到进度',
          value: 1,
          maxValue: 1,
        ),
      );
      completer.complete(
        LocalMatchGetInfosResult(
          entries: const <LocalMatchSongEntry>[],
          errors: const <String>[],
          cancelled: true,
        ),
      );

      await scan;
    });

    test('桌面匹配 dispose 后迟到进度和结果不会写入已释放状态', () async {
      final SongInfo songInfo = SongInfo(
        source: Source.local,
        title: 'Slow',
        artist: SongArtist(<String>['Singer']),
        path: r'D:\music\slow.mp3',
      );
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'slow.mp3', path: r'D:\music\slow.mp3'),
        ],
      );
      final _StubLocalMatchGetInfosUseCase desktopGetInfosUseCase =
          _StubLocalMatchGetInfosUseCase(
            resultBuilder: (_) => LocalMatchGetInfosResult(
              entries: <LocalMatchSongEntry>[
                LocalMatchSongEntry(songInfo: songInfo, rootPath: r'D:\music'),
              ],
              errors: const <String>[],
              cancelled: false,
            ),
          );
      LocalMatchProgressCallback? capturedProgress;
      final Completer<LocalMatchResult> completer =
          Completer<LocalMatchResult>();
      final _StubLocalMatchUseCase localMatchUseCase = _StubLocalMatchUseCase(
        runHandler:
            ({
              required List<LocalMatchSongEntry> entries,
              required LocalMatchRunOptions options,
              AppConfig? config,
              LocalMatchCancellationToken? cancellationToken,
              LyricsSavePersistencePort? lyricsPersistencePort,
              LocalMatchProgressCallback? onProgress,
            }) {
              capturedProgress = onProgress;
              return completer.future;
            },
      );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: desktopGetInfosUseCase,
        localMatchUseCase: localMatchUseCase,
      );
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.addSongFiles();
      final Future<void> run = controller.startOrCancel();
      for (
        int attempt = 0;
        attempt < 10 && capturedProgress == null;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(capturedProgress, isNotNull);

      container.dispose();
      capturedProgress?.call(
        const LocalMatchProgress(
          text: 'dispose 后匹配迟到进度',
          value: 1,
          maxValue: 1,
        ),
      );
      completer.complete(
        LocalMatchResult(
          total: 1,
          successCount: 0,
          failCount: 0,
          skipCount: 0,
          cancelled: true,
          statuses: const <LocalMatchingStatus>[],
        ),
      );

      await run;
    });

    test('Android 目录树模式通过 persistence 写入歌词文件', () async {
      const AndroidSafTreeToken tree = AndroidSafTreeToken(
        uri: 'content://tree/root',
        displayName: '根目录',
      );
      final SongInfo songInfo = SongInfo(
        source: Source.local,
        path: 'content://doc/song.mp3',
        title: 'Song',
        artist: SongArtist(<String>['Singer']),
      );
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort();
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        androidTreeToken: tree,
      );
      final _StubAndroidSafLocalMatchGetInfosUseCase androidGetInfosUseCase =
          _StubAndroidSafLocalMatchGetInfosUseCase(
            resultBuilder: (AndroidSafTreeToken rootTree) =>
                AndroidSafLocalMatchGetInfosResult(
                  entries: <LocalMatchSongEntry>[
                    LocalMatchSongEntry(songInfo: songInfo, rootPath: tree.uri),
                  ],
                  errors: const <String>[],
                  cancelled: false,
                  checkpoint: null,
                ),
          );
      final _StubLocalMatchUseCase localMatchUseCase = _StubLocalMatchUseCase(
        runHandler:
            ({
              required List<LocalMatchSongEntry> entries,
              required LocalMatchRunOptions options,
              AppConfig? config,
              LocalMatchCancellationToken? cancellationToken,
              LyricsSavePersistencePort? lyricsPersistencePort,
              LocalMatchProgressCallback? onProgress,
            }) async {
              final String outputPath = await lyricsPersistencePort!.saveText(
                request: LyricsSaveRequest(
                  songInfo: entries.single.songInfo,
                  lyricLangs: options.langs,
                  lyricsFormat: options.lyricsFormat,
                  fileNameFormat:
                      config?.lyrics.fileNameFormat ??
                      ConfigDefaults.current.lyrics.fileNameFormat,
                ),
                text: '[00:00.000]歌词',
              );
              final LocalMatchingStatus status = LocalMatchingStatus(
                type: LocalMatchingStatusType.success,
                index: 0,
                text: '已写入',
                path: outputPath,
              );
              onProgress?.call(
                LocalMatchProgress(
                  text: '正在写入歌词',
                  value: 1,
                  maxValue: 1,
                  status: status,
                ),
              );
              return LocalMatchResult(
                total: 1,
                successCount: 1,
                failCount: 0,
                skipCount: 0,
                cancelled: false,
                statuses: <LocalMatchingStatus>[status],
              );
            },
      );
      final ProviderContainer container = _createContainer(
        capability: _androidCapability(),
        picker: picker,
        androidGetInfosUseCase: androidGetInfosUseCase,
        localMatchUseCase: localMatchUseCase,
        treePort: treePort,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.selectAndroidTree();
      await controller.startOrCancel();

      final LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(state.isAndroidMode, isTrue);
      expect(state.successCount, 1);
      expect(treePort.writeRequests, hasLength(1));
      expect(treePort.writeRequests.single.displayName, endsWith('.lrc'));
      expect(utf8.decode(treePort.writeRequests.single.bytes), '[00:00.000]歌词');
      expect(
        state.queueItems.single.outputPath,
        'content://tree/root/${treePort.writeRequests.single.displayName}',
      );
    });

    test('Android 目录树匹配取消后再次启动会从 batch checkpoint 继续', () async {
      const AndroidSafTreeToken tree = AndroidSafTreeToken(
        uri: 'content://tree/root',
        displayName: '根目录',
      );
      final List<LocalMatchSongEntry> entries = <LocalMatchSongEntry>[
        LocalMatchSongEntry(
          songInfo: SongInfo(
            source: Source.local,
            path: 'content://doc/one.mp3',
            title: 'One',
          ),
          rootPath: tree.uri,
        ),
        LocalMatchSongEntry(
          songInfo: SongInfo(
            source: Source.local,
            path: 'content://doc/two.mp3',
            title: 'Two',
          ),
          rootPath: tree.uri,
        ),
      ];
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        androidTreeToken: tree,
      );
      final _StubAndroidSafLocalMatchGetInfosUseCase androidGetInfosUseCase =
          _StubAndroidSafLocalMatchGetInfosUseCase(
            resultBuilder: (_) => AndroidSafLocalMatchGetInfosResult(
              entries: entries,
              errors: const <String>[],
              cancelled: false,
              checkpoint: null,
            ),
          );
      int runCount = 0;
      final List<String?> processedTitles = <String?>[];
      final _StubLocalMatchUseCase localMatchUseCase = _StubLocalMatchUseCase(
        runHandler:
            ({
              required List<LocalMatchSongEntry> entries,
              required LocalMatchRunOptions options,
              AppConfig? config,
              LocalMatchCancellationToken? cancellationToken,
              LyricsSavePersistencePort? lyricsPersistencePort,
              LocalMatchProgressCallback? onProgress,
            }) async {
              runCount += 1;
              processedTitles.add(entries.single.songInfo.title);
              final LocalMatchingStatus status = LocalMatchingStatus(
                type: LocalMatchingStatusType.success,
                index: 0,
                text: '已写入',
                path: 'content://out/${entries.single.songInfo.title}.lrc',
              );
              onProgress?.call(
                LocalMatchProgress(
                  text: '正在写入歌词',
                  value: 1,
                  maxValue: 1,
                  status: status,
                ),
              );
              if (runCount == 1) {
                cancellationToken?.cancel();
              }
              return LocalMatchResult(
                total: 1,
                successCount: 1,
                failCount: 0,
                skipCount: 0,
                cancelled: cancellationToken?.isCancelled ?? false,
                statuses: <LocalMatchingStatus>[status],
              );
            },
      );
      final ProviderContainer container = _createContainer(
        capability: _androidCapability(),
        picker: picker,
        androidGetInfosUseCase: androidGetInfosUseCase,
        localMatchUseCase: localMatchUseCase,
      );
      addTearDown(container.dispose);
      final LocalMatchPageController controller = container.read(
        localMatchPageControllerProvider.notifier,
      );

      await controller.selectAndroidTree();
      await controller.startOrCancel();

      LocalMatchPageState state = container.read(
        localMatchPageControllerProvider,
      );
      expect(state.successCount, 1);
      expect(
        state.progressMessage.code,
        LocalMatchProgressMessageCode.matchingCancelled,
      );
      expect(processedTitles, <String?>['One']);

      await controller.startOrCancel();

      state = container.read(localMatchPageControllerProvider);
      expect(state.successCount, 2);
      expect(state.failCount, 0);
      expect(
        state.progressMessage.code,
        LocalMatchProgressMessageCode.matchingCompleted,
      );
      expect(processedTitles, <String?>['One', 'Two']);
      expect(state.queueItems[0].lastStatus?.index, 0);
      expect(state.queueItems[1].lastStatus?.index, 1);
    });
  });

  group('LocalMatchPage', () {
    testWidgets('紧凑状态摘要在窄宽和长进度文本下保持可布局', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(360, 800));
      final LocalMatchPageState state =
          LocalMatchPageState.initial(
            defaultSources: const <Source>[Source.qm],
            defaultSaveRootPath: null,
            inputMode: LocalMatchInputMode.androidTree,
          ).copyWith(
            taskPhase: LocalMatchTaskPhase.matching,
            progressCurrent: 123,
            progressTotal: 456,
            progressMessage: const LocalMatchProgressMessage.external(
              '正在写入一个非常长的多语言歌词文件名称 multilingual-progress-message',
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 328,
              child: LocalMatchCompactQueueStatusSummary(state: state),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LocalMatchCompactQueueStatusSummary), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('桌面默认宽度下展示队列优先布局与全显侧栏', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1040, 900));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                  album: 'Album',
                  durationMs: 209000,
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(find.text('任务队列'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local_match_status_strip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_queue_list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_header_start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_min_score_field')),
        findsOneWidget,
      );
      expect(find.text('60'), findsWidgets);
      expect(
        container.read(localMatchPageControllerProvider).skipExistingLyrics,
        isFalse,
      );
      final Finder skipExisting = find.byKey(
        const ValueKey<String>('local_match_skip_existing_checkbox'),
      );
      await tester.tap(skipExisting);
      await tester.pump();
      expect(
        container.read(localMatchPageControllerProvider).skipExistingLyrics,
        isTrue,
        reason: '整行复选控件一次点击只能切换一次，不能被嵌套手势再次反转',
      );
      await tester.tap(skipExisting);
      await tester.pump();
      expect(
        container.read(localMatchPageControllerProvider).skipExistingLyrics,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_sidebar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_mobile_more_settings')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_select_save_root')),
        findsNothing,
      );
      expect(find.text('Singer · Album'), findsOneWidget);
      expect(find.text('03:29'), findsOneWidget);
      expect(find.text('歌词保存路径'), findsOneWidget);
      expect(find.text('保存根目录'), findsNothing);
    });

    testWidgets('Android 实际窄屏下队列优先显示且规则展开不溢出', (WidgetTester tester) async {
      // 与 hosted Android emulator 报告的逻辑 viewport 一致，避免只在整数设计稿
      // 尺寸测试而漏掉 380 px 高度临界点触发的嵌入状态摘要。
      _setTestViewport(tester, const Size(411.428571, 914.285714));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('local_match_start_or_cancel')),
        findsOneWidget,
      );
      expect(find.text('任务队列'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local_match_header_start')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_status_strip')),
        findsNothing,
      );
      expect(find.byType(LocalMatchCompactQueueStatusSummary), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('local_match_rules_card')),
        findsOneWidget,
      );
      expect(find.text('匹配规则'), findsOneWidget);
      await tester.tap(find.text('匹配规则'));
      await tester.pumpAndSettle();
      expect(find.text('保存模式'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local_match_mobile_more_settings')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('切换保存模式后按规则显示保存根目录入口', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('local_match_select_save_root')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('local_match_save_mode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('镜像目录').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('local_match_select_save_root')),
        findsOneWidget,
      );
    });

    testWidgets('中等宽度下回退到窄屏布局且不会出现底部溢出', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(900, 720));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                  album: 'Album',
                  durationMs: 209000,
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('local_match_start_or_cancel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_header_start')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_queue_list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_rules_card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击单一展开按钮后会竖向显示完整路径并展示失败摘要', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final String longPath =
          r'D:\music\very\long\path\with\many\segments\artist\album\disc1\demo_song_that_has_a_very_long_name.mp3';
      final _StubLocalMatchUseCase localMatchUseCase = _StubLocalMatchUseCase(
        runHandler:
            ({
              required List<LocalMatchSongEntry> entries,
              required LocalMatchRunOptions options,
              AppConfig? config,
              LocalMatchCancellationToken? cancellationToken,
              LyricsSavePersistencePort? lyricsPersistencePort,
              LocalMatchProgressCallback? onProgress,
            }) async {
              const LocalMatchingStatus status = LocalMatchingStatus(
                type: LocalMatchingStatusType.saveFail,
                index: 0,
                text: '需要指定保存路径',
              );
              onProgress?.call(
                LocalMatchProgress(
                  text: '写回失败',
                  value: 1,
                  maxValue: 1,
                  status: status,
                ),
              );
              return LocalMatchResult(
                total: entries.length,
                successCount: 0,
                failCount: 1,
                skipCount: 0,
                cancelled: false,
                statuses: const <LocalMatchingStatus>[status],
              );
            },
      );
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: longPath),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: longPath,
                  title: 'Demo Song',
                  artist: SongArtist(<String>['Singer']),
                  album: 'Album Name',
                  durationMs: 209000,
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
        localMatchUseCase: localMatchUseCase,
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      final String itemId = container
          .read(localMatchPageControllerProvider)
          .queueItems
          .single
          .id;
      await container
          .read(localMatchPageControllerProvider.notifier)
          .startOrCancel();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey<String>('local_match_expand_row_$itemId')),
      );
      await tester.pumpAndSettle();

      expect(find.text(longPath), findsOneWidget);
      expect(find.text('歌曲路径'), findsOneWidget);
      expect(find.text('歌词保存路径'), findsOneWidget);
      expect(find.text('Singer · Album Name'), findsOneWidget);
      expect(find.text('03:29'), findsOneWidget);
      expect(find.textContaining('需要指定保存路径'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('local_match_path_lyrics_$itemId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('收起态路径摘要使用最小化中间省略并保留完整 Tooltip', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final String longPath =
          r'D:\music\very\long\path\with\many\segments\artist\album\disc1\demo_song_that_has_a_very_long_name.mp3';
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: longPath),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: longPath,
                  title: 'Demo Song',
                  artist: SongArtist(<String>['Singer']),
                  album: 'Album Name',
                  durationMs: 209000,
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      final String itemId = container
          .read(localMatchPageControllerProvider)
          .queueItems
          .single
          .id;

      expect(find.text(longPath), findsNothing);
      expect(
        find.byKey(ValueKey<String>('local_match_path_song_$itemId')),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Tooltip && widget.message == longPath,
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('批量选择会切换为上下文工具栏', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();
      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('local_match_toggle_selection_mode')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已选 0 项'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local_match_selection_toggle_all')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_selection_delete')),
        findsOneWidget,
      );
    });

    testWidgets('窄屏下支持显式更多按钮与长按呼出行菜单', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: _FakeLocalMatchInputPicker(
          songFiles: const <PickedFileHandle>[
            PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
          ],
        ),
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      final String itemId = container
          .read(localMatchPageControllerProvider)
          .queueItems
          .single
          .id;

      await tester.tap(
        find.byKey(ValueKey<String>('local_match_row_more_$itemId')),
      );
      await tester.pumpAndSettle();

      expect(find.text('在搜索中打开'), findsOneWidget);
      expect(find.text('进入批量选择'), findsOneWidget);
      expect(find.text('打开歌曲目录'), findsOneWidget);

      Navigator.of(tester.element(find.text('在搜索中打开'))).pop();
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(ValueKey<String>('local_match_queue_row_$itemId')),
      );
      await tester.pumpAndSettle();

      expect(find.text('在搜索中打开'), findsOneWidget);
      expect(find.text('打开歌曲目录'), findsOneWidget);
    });

    testWidgets('Android 模式隐藏桌面路径型导入动作', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      const AndroidSafTreeToken tree = AndroidSafTreeToken(
        uri: 'content://tree/root',
        displayName: '根目录',
      );
      final ProviderContainer container = _createContainer(
        capability: _androidCapability(),
        picker: _FakeLocalMatchInputPicker(androidTreeToken: tree),
        androidGetInfosUseCase: _StubAndroidSafLocalMatchGetInfosUseCase(
          resultBuilder: (AndroidSafTreeToken rootTree) =>
              AndroidSafLocalMatchGetInfosResult(
                entries: <LocalMatchSongEntry>[
                  LocalMatchSongEntry(
                    songInfo: const SongInfo(
                      source: Source.local,
                      path: 'content://doc/song.mp3',
                      title: 'Song',
                    ),
                    rootPath: rootTree.uri,
                  ),
                ],
                errors: const <String>[],
                cancelled: false,
                checkpoint: null,
              ),
        ),
      );
      addTearDown(container.dispose);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .selectAndroidTree();

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('local_match_pick_tree')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_pick_files')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_pick_dirs')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('local_match_select_save_root')),
        findsNothing,
      );
    });

    testWidgets('桌面导入与主操作会触发启动、退出选择与删除聚焦项', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final _FakeLocalMatchInputPicker picker = _FakeLocalMatchInputPicker(
        songFiles: const <PickedFileHandle>[
          PickedFileHandle(name: 'demo.mp3', path: r'D:\music\demo.mp3'),
        ],
        directoryPaths: const <String>[r'D:\music'],
      );
      int runCount = 0;
      final ProviderContainer container = _createContainer(
        capability: _desktopCapability(),
        picker: picker,
        desktopGetInfosUseCase: _StubLocalMatchGetInfosUseCase(
          resultBuilder: (List<String> inputPaths) => LocalMatchGetInfosResult(
            entries: <LocalMatchSongEntry>[
              LocalMatchSongEntry(
                songInfo: SongInfo(
                  source: Source.local,
                  path: r'D:\music\demo.mp3',
                  title: 'Demo',
                  artist: SongArtist(<String>['Singer']),
                ),
                rootPath: r'D:\music',
              ),
            ],
            errors: const <String>[],
            cancelled: false,
          ),
        ),
        localMatchUseCase: _StubLocalMatchUseCase(
          runHandler:
              ({
                required List<LocalMatchSongEntry> entries,
                required LocalMatchRunOptions options,
                AppConfig? config,
                LocalMatchCancellationToken? cancellationToken,
                LyricsSavePersistencePort? lyricsPersistencePort,
                LocalMatchProgressCallback? onProgress,
              }) async {
                runCount += 1;
                return LocalMatchResult(
                  total: entries.length,
                  successCount: 0,
                  failCount: 0,
                  skipCount: 0,
                  cancelled: false,
                  statuses: const <LocalMatchingStatus>[],
                );
              },
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongFiles();
      await tester.pumpAndSettle();
      expect(picker.songFilePickCount, 1);
      await container
          .read(localMatchPageControllerProvider.notifier)
          .addSongDirectories();
      await tester.pumpAndSettle();
      expect(picker.songDirectoryPickCount, 1);

      final String itemId = container
          .read(localMatchPageControllerProvider)
          .queueItems
          .single
          .id;

      await container
          .read(localMatchPageControllerProvider.notifier)
          .startOrCancel();
      await tester.pumpAndSettle();
      expect(runCount, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('local_match_toggle_selection_mode')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 0 项'), findsOneWidget);

      container
          .read(localMatchPageControllerProvider.notifier)
          .exitSelectionMode();
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 0 项'), findsNothing);

      await tester.tap(
        find.byKey(ValueKey<String>('local_match_queue_row_$itemId')),
      );
      await tester.pumpAndSettle();
      final LocalMatchPageController actionController = container.read(
        localMatchPageControllerProvider.notifier,
      );
      actionController.enterSelectionMode(itemId);
      await actionController.removeSelectedItems();
      await tester.pumpAndSettle();
      expect(
        container.read(localMatchPageControllerProvider).queueItems,
        isEmpty,
      );
    });
  });
}

Widget _buildTestApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: LocalMatchPage()),
    ),
  );
}

ProviderContainer _createContainer({
  required AppCapability capability,
  required _FakeLocalMatchInputPicker picker,
  _StubLocalMatchGetInfosUseCase? desktopGetInfosUseCase,
  _StubAndroidSafLocalMatchGetInfosUseCase? androidGetInfosUseCase,
  _StubLocalMatchUseCase? localMatchUseCase,
  _FakeAndroidSafTreePort? treePort,
  _FakeAndroidSafContentPort? contentPort,
  AutoFetchUseCase? autoFetchUseCase,
  _FakeLocalMatchMediaGateway? mediaGateway,
  OpenLocalMatchSongInSearch? openInSearch,
}) {
  final _FakeAndroidSafTreePort resolvedTreePort =
      treePort ?? _FakeAndroidSafTreePort();
  final _FakeAndroidSafContentPort resolvedContentPort =
      contentPort ?? _FakeAndroidSafContentPort();
  final _FixedConfigRepository configRepository = _FixedConfigRepository(
    _config(),
  );
  final _FakeLocalMatchMediaGateway resolvedMediaGateway =
      mediaGateway ?? _FakeLocalMatchMediaGateway();
  final _StubLocalMatchGetInfosUseCase resolvedDesktopGetInfosUseCase =
      desktopGetInfosUseCase ?? _StubLocalMatchGetInfosUseCase();
  final _StubAndroidSafLocalMatchGetInfosUseCase
  resolvedAndroidGetInfosUseCase =
      androidGetInfosUseCase ?? _StubAndroidSafLocalMatchGetInfosUseCase();
  final _StubLocalMatchUseCase resolvedLocalMatchUseCase =
      localMatchUseCase ?? _StubLocalMatchUseCase();
  final AndroidSafLocalMatchBatchUseCase resolvedAndroidBatchUseCase =
      AndroidSafLocalMatchBatchUseCase(
        getInfosUseCase: resolvedAndroidGetInfosUseCase,
        localMatchUseCase: resolvedLocalMatchUseCase,
      );
  final _FakeAndroidSafFdPort resolvedFdPort = _FakeAndroidSafFdPort();
  final _FakePathOpener pathOpener = _FakePathOpener();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => capability),
      configRepositoryProvider.overrideWithValue(configRepository),
      lyricsApiProvider.overrideWithValue(_FakeLyricsApi()),
      appFilePickerProvider.overrideWithValue(_FakeAppFilePicker()),
      localMatchMediaGatewayProvider.overrideWithValue(resolvedMediaGateway),
      if (autoFetchUseCase != null)
        autoFetchUseCaseProvider.overrideWithValue(autoFetchUseCase),
      localMatchDependenciesProvider.overrideWithValue(
        LocalMatchDependencies(
          configRepository: configRepository,
          capability: capability,
          inputPicker: picker,
          desktopGetInfosUseCase: resolvedDesktopGetInfosUseCase,
          androidGetInfosUseCase: resolvedAndroidGetInfosUseCase,
          androidBatchUseCase: resolvedAndroidBatchUseCase,
          localMatchUseCase: resolvedLocalMatchUseCase,
          androidTreePort: resolvedTreePort,
          androidFdPort: resolvedFdPort,
          androidContentPort: resolvedContentPort,
          pathOpener: pathOpener,
          mediaGateway: resolvedMediaGateway,
          dragDropPort: const DragDropPortImpl(),
          androidLyricsPersistenceFactory: (AndroidSafTreeToken tree) =>
              AndroidSafLyricsSavePersistence(
                treePort: resolvedTreePort,
                treeUri: tree.uri,
              ),
          openInSearch: openInSearch ?? (_, _) async {},
        ),
      ),
      appPathOpenerProvider.overrideWithValue(pathOpener),
    ],
  );
}

AppConfig _config() {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: SearchConfig(sources: const <String>['QM']),
    lyrics: base.lyrics,
    match: base.match,
    translate: base.translate,
    desktop: base.desktop,
    app: base.app,
    storage: base.storage,
    legacyExtras: base.legacyExtras,
  );
}

String _cueText() {
  return '''
TITLE "Album"
PERFORMER "Singer"
FILE "disc.wav" WAVE
  TRACK 01 AUDIO
    TITLE "First"
    PERFORMER "Singer"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second"
    PERFORMER "Singer"
    INDEX 01 01:00:00
''';
}

AppCapability _desktopCapability() {
  return const AppCapability(
    multiWindow: true,
    desktopPanelDetached: true,
    desktopPanelEmbedded: true,
    systemTray: true,
    globalHotkey: true,
    audioTagWrite: true,
    directoryRecursiveScan: true,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

AppCapability _androidCapability() {
  return const AppCapability(
    multiWindow: false,
    desktopPanelDetached: false,
    desktopPanelEmbedded: false,
    systemTray: false,
    globalHotkey: false,
    audioTagWrite: true,
    directoryRecursiveScan: true,
    androidSafTreeAccess: true,
    androidCueTrackResolve: true,
    webFileSystemAccess: false,
    webTaglibWasmReady: false,
  );
}

class _FixedConfigRepository implements ConfigRepository {
  _FixedConfigRepository(this._config);

  final AppConfig _config;

  @override
  AppConfig get current => _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<AppConfig> refreshFromStorage() async => _config;

  @override
  Future<AppConfig> update(Map<String, Object?> patch) async => _config;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
  }
}

class _FakeLocalMatchInputPicker implements LocalMatchInputPicker {
  _FakeLocalMatchInputPicker({
    this.songFiles = const <PickedFileHandle>[],
    this.androidTreeToken,
    this.directoryPaths = const <String>[],
  });

  final List<PickedFileHandle> songFiles;
  final AndroidSafTreeToken? androidTreeToken;
  final List<String> directoryPaths;
  int songFilePickCount = 0;
  int songDirectoryPickCount = 0;

  @override
  Future<AndroidSafTreeToken?> pickAndroidTree({String? initialUri}) async {
    return androidTreeToken;
  }

  @override
  Future<List<PickedFileHandle>> pickSongFiles({
    String? initialDirectory,
  }) async {
    songFilePickCount += 1;
    return songFiles;
  }

  @override
  Future<List<String>> pickSongDirectories({String? initialDirectory}) async {
    songDirectoryPickCount += 1;
    return directoryPaths;
  }

  @override
  Future<String?> pickSaveRootDirectory({String? initialDirectory}) async {
    return null;
  }
}

class _FakeAppFilePicker implements AppFilePicker {
  @override
  Future<String?> pickDirectory({String? initialDirectory}) async => null;

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async => null;

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async => const <PickedFileHandle>[];

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async => null;

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {}

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async => null;
}

class _FakeLyricsApi implements LyricsClient {
  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    throw UnsupportedError('LocalMatch 测试场景不支持搜索');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw UnsupportedError('LocalMatch 测试场景不支持读取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('LocalMatch 测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    throw UnsupportedError('LocalMatch 测试场景不支持歌词解析');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    throw UnsupportedError('LocalMatch 测试场景不支持读取歌词');
  }
}

class _FakePathOpener implements AppPathOpener {
  @override
  Future<void> openDirectory(String path) async {}

  @override
  Future<void> openFile(String path) async {}
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  final Map<String, List<SongInfo>> songInfosByPath =
      <String, List<SongInfo>>{};
  final Map<String, int?> durations = <String, int?>{};
  int readAudioSongInfosCallCount = 0;

  @override
  Future<bool> hasLyricsTag(String songPath) async => false;

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async => null;

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async {
    readAudioSongInfosCallCount += 1;
    return songInfosByPath[audioPath] ?? <SongInfo>[];
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async =>
      durations[audioPath];

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {}
}

class _FakeAutoFetchUseCase extends AutoFetchUseCase {
  _FakeAutoFetchUseCase({required this.result})
    : super(gateway: _NoopAutoFetchGateway());

  final AutoFetchResult result;
  AutoFetchRequest? lastRequest;

  @override
  Future<AutoFetchResult> execute(AutoFetchRequest request) async {
    lastRequest = request;
    return result;
  }
}

class _StubLocalMatchGetInfosUseCase extends LocalMatchGetInfosUseCase {
  _StubLocalMatchGetInfosUseCase({this.resultBuilder, this.runHandler})
    : super(mediaGateway: _FakeLocalMatchMediaGateway());

  final LocalMatchGetInfosResult Function(List<String> inputPaths)?
  resultBuilder;
  final Future<LocalMatchGetInfosResult> Function({
    required List<String> inputPaths,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
  })?
  runHandler;
  List<String>? lastInputPaths;

  @override
  Future<LocalMatchGetInfosResult> run({
    required List<String> inputPaths,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    lastInputPaths = inputPaths;
    final LocalMatchGetInfosResult result;
    if (runHandler != null) {
      result = await runHandler!(
        inputPaths: inputPaths,
        cancellationToken: cancellationToken,
        onProgress: onProgress,
      );
    } else {
      onProgress?.call(
        const LocalMatchGetInfosProgress(
          text: '解析歌曲文件...',
          value: 1,
          maxValue: 1,
        ),
      );
      onProgress?.call(
        const LocalMatchGetInfosProgress(text: '', value: 0, maxValue: 0),
      );
      result =
          resultBuilder?.call(inputPaths) ??
          LocalMatchGetInfosResult(
            entries: const <LocalMatchSongEntry>[],
            errors: const <String>[],
            cancelled: false,
          );
    }
    await onEntries?.call(result.entries);
    return collectEntries
        ? result
        : LocalMatchGetInfosResult(
            entries: const <LocalMatchSongEntry>[],
            errors: result.errors,
            cancelled: result.cancelled,
          );
  }
}

class _StubAndroidSafLocalMatchGetInfosUseCase
    extends AndroidSafLocalMatchGetInfosUseCase {
  _StubAndroidSafLocalMatchGetInfosUseCase({this.resultBuilder})
    : super(
        treePort: _FakeAndroidSafTreePort(),
        contentPort: _FakeAndroidSafContentPort(),
        audioMetadataPort: _FakeAndroidSafAudioMetadataPort(),
      );

  final AndroidSafLocalMatchGetInfosResult Function(
    AndroidSafTreeToken rootTree,
  )?
  resultBuilder;

  @override
  Future<AndroidSafLocalMatchGetInfosResult> run({
    required AndroidSafTreeToken rootTree,
    AndroidSafScanCheckpoint? checkpoint,
    LocalMatchCancellationToken? cancellationToken,
    LocalMatchGetInfosProgressCallback? onProgress,
    LocalMatchSongEntryBatchCallback? onEntries,
    bool collectEntries = true,
  }) async {
    onProgress?.call(
      const LocalMatchGetInfosProgress(text: '遍历文件...', value: 1, maxValue: 1),
    );
    onProgress?.call(
      const LocalMatchGetInfosProgress(text: '', value: 0, maxValue: 0),
    );
    final AndroidSafLocalMatchGetInfosResult result =
        resultBuilder?.call(rootTree) ??
        AndroidSafLocalMatchGetInfosResult(
          entries: const <LocalMatchSongEntry>[],
          errors: const <String>[],
          cancelled: false,
          checkpoint: null,
        );
    await onEntries?.call(result.entries);
    return collectEntries
        ? result
        : AndroidSafLocalMatchGetInfosResult(
            entries: const <LocalMatchSongEntry>[],
            errors: result.errors,
            cancelled: result.cancelled,
            checkpoint: result.checkpoint,
          );
  }
}

class _StubLocalMatchUseCase extends LocalMatchUseCase {
  _StubLocalMatchUseCase({this.runHandler})
    : super(
        autoFetchExecutor: _defaultAutoFetchExecutor,
        mediaGateway: _FakeLocalMatchMediaGateway(),
      );

  final Future<LocalMatchResult> Function({
    required List<LocalMatchSongEntry> entries,
    required LocalMatchRunOptions options,
    AppConfig? config,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    LocalMatchProgressCallback? onProgress,
  })?
  runHandler;

  @override
  Future<LocalMatchResult> run({
    required List<LocalMatchSongEntry> entries,
    required LocalMatchRunOptions options,
    AppConfig? config,
    LocalMatchCancellationToken? cancellationToken,
    LyricsSavePersistencePort? lyricsPersistencePort,
    LocalMatchProgressCallback? onProgress,
  }) async {
    if (runHandler != null) {
      return runHandler!(
        entries: entries,
        options: options,
        config: config,
        cancellationToken: cancellationToken,
        lyricsPersistencePort: lyricsPersistencePort,
        onProgress: onProgress,
      );
    }
    return LocalMatchResult(
      total: entries.length,
      successCount: 0,
      failCount: 0,
      skipCount: 0,
      cancelled: false,
      statuses: const <LocalMatchingStatus>[],
    );
  }

  static Future<AutoFetchResult> _defaultAutoFetchExecutor(
    AutoFetchRequest request,
  ) async {
    final SongInfo remoteSong = SongInfo(
      source: Source.qm,
      id: 'qm-${request.info.title}',
      title: request.info.title,
      artist: request.info.artist,
    );
    return AutoFetchResult(
      lyrics: Lyrics(
        songInfo: remoteSong,
        source: remoteSong.source,
        data: <String, LyricsData>{
          'orig': <LyricsLine>[
            LyricsLine(
              startMs: 0,
              endMs: 1000,
              words: const <LyricsWord>[
                LyricsWord(startMs: 0, endMs: 1000, text: '歌词'),
              ],
            ),
          ],
        },
        types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      ),
      matchedSongInfo: remoteSong,
      score: 95,
    );
  }
}

class _NoopAutoFetchGateway implements AutoFetchLyricsGateway {
  @override
  Future<Lyrics> getLyrics(SongInfo info) async {
    return Lyrics(
      songInfo: info,
      source: info.source,
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      data: const <String, LyricsData>{'orig': <LyricsLine>[]},
    );
  }

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) async {
    return APIResultList<SongInfo>(
      const <SongInfo>[],
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: 1,
      ),
    );
  }
}

class _FakeAndroidSafContentPort implements AndroidSafContentPort {
  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) {
    return Future<Uint8List>.value(Uint8List(0));
  }
}

class _AndroidSafWriteRequest {
  const _AndroidSafWriteRequest({
    required this.treeUri,
    required this.displayName,
    required this.mimeType,
    required this.bytes,
  });

  final String treeUri;
  final String displayName;
  final String mimeType;
  final Uint8List bytes;
}

class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  final List<_AndroidSafWriteRequest> writeRequests =
      <_AndroidSafWriteRequest>[];
  final Map<String, List<AndroidSafTreeEntry>> childrenByUri =
      <String, List<AndroidSafTreeEntry>>{};

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    final List<AndroidSafTreeEntry> entries =
        childrenByUri[uri] ?? const <AndroidSafTreeEntry>[];
    final int end = offset + limit < entries.length
        ? offset + limit
        : entries.length;
    return AndroidSafTreePage(
      entries: offset >= entries.length
          ? const <AndroidSafTreeEntry>[]
          : entries.sublist(offset, end),
      nextOffset: end < entries.length ? end : null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) async {
    return AndroidSafTreeToken(uri: initialUri ?? 'content://tree/root');
  }

  @override
  Future<void> persistTreePermission(String uri) async {}

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    writeRequests.add(
      _AndroidSafWriteRequest(
        treeUri: treeUri,
        displayName: displayName,
        mimeType: mimeType,
        bytes: Uint8List.fromList(bytes),
      ),
    );
    childrenByUri.update(
      treeUri,
      (List<AndroidSafTreeEntry> current) => <AndroidSafTreeEntry>[
        ...current,
        AndroidSafTreeEntry(
          uri: '$treeUri/$displayName',
          displayName: displayName,
          mimeType: mimeType,
          isDirectory: false,
          isFile: true,
        ),
      ],
      ifAbsent: () => <AndroidSafTreeEntry>[
        AndroidSafTreeEntry(
          uri: '$treeUri/$displayName',
          displayName: displayName,
          mimeType: mimeType,
          isDirectory: false,
          isFile: true,
        ),
      ],
    );
    return AndroidSafWriteDocumentResult(
      uri: '$treeUri/$displayName',
      displayName: displayName,
    );
  }
}

class _FakeAndroidSafFdPort implements AndroidSafFdPort {
  @override
  Future<void> closeFd(int fileDescriptor) async {}

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadOnlyFd(String uri) async {
    return AndroidSafOpenedFileDescriptor(fileDescriptor: 1, nameHint: uri);
  }

  @override
  Future<AndroidSafOpenedFileDescriptor> openReadWriteFd(String uri) async {
    return AndroidSafOpenedFileDescriptor(fileDescriptor: 2, nameHint: uri);
  }
}

class _FakeAndroidSafAudioMetadataPort implements AndroidSafAudioMetadataPort {
  @override
  Future<AndroidSafAudioMetadata> readMetadata({
    required String uri,
    required String? nameHint,
  }) async {
    return AndroidSafAudioMetadata(
      nameHint: nameHint ?? uri,
      title: uri,
      artist: null,
      album: null,
      durationMs: null,
      trackNumber: null,
      cuesheet: null,
    );
  }
}

void _setTestViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
