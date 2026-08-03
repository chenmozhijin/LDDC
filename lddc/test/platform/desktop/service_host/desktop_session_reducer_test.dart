import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/platform/desktop/ipc/desktop_ipc.dart';
import '../../../support/desktop_service_host_exports.dart';

void main() {
  group('DesktopSessionReducer', () {
    late DesktopSessionReducer reducer;

    setUp(() {
      reducer = DesktopSessionReducer(nowMsFactory: () => 1234567890);
    });

    test('配置、选择载荷与 effect 列表会冻结调用方集合', () {
      final List<String> defaultLangs = <String>['orig'];
      final DesktopSessionReducerConfig config = DesktopSessionReducerConfig(
        defaultLangs: defaultLangs,
      );
      final List<String> selectedLangs = <String>['orig', 'ts'];
      final DesktopSelectedLyricsPayload payload = DesktopSelectedLyricsPayload(
        lyrics: _buildRemoteLyrics(),
        langs: selectedLangs,
      );
      final List<DesktopSessionEffect> effects = <DesktopSessionEffect>[
        const DesktopClearTaskEffect(taskKey: 'auto_fetch'),
      ];
      final DesktopReducerResult result = DesktopReducerResult(
        state: DesktopSessionState.initial(),
        effects: effects,
      );

      defaultLangs.add('ts');
      selectedLangs.clear();
      effects.clear();

      expect(config.defaultLangs, const <String>['orig']);
      expect(payload.langs, const <String>['orig', 'ts']);
      expect(result.effects, hasLength(1));
      expect(() => config.defaultLangs.add('ts'), throwsUnsupportedError);
      expect(() => payload.langs!.clear(), throwsUnsupportedError);
      expect(() => result.effects.clear(), throwsUnsupportedError);
    });

    test('chang_music 会重置状态并发出查询关联库 effect', () {
      final DesktopSessionState initial = DesktopSessionState.initial();

      final DesktopReducerResult result = reducer.handleChangMusic(
        initial,
        const DesktopChangMusicMessage(
          instanceId: 1,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: r'D:\music\song.flac',
          track: '7',
        ),
      );

      expect(result.state.playbackSync.pluginPlaybackTimeMs, 0);
      expect(result.state.playbackSync.sceneId, isNull);
      expect(result.state.playbackSync.songToken, '7');
      expect(result.state.lyricsRuntime.song?.title, 'Song');
      expect(result.state.lyricsRuntime.song?.artistText, 'Artist');
      expect(result.state.lyricsRuntime.song?.path, r'D:\music\song.flac');
      expect(result.state.lyricsRuntime.song?.id, '7');
      expect(result.state.instanceId, 1);
      expect(result.state.lastTask, DesktopIpcTask.changMusic);
      expect(result.effects, hasLength(4));
      expect(
        result.effects.whereType<DesktopClearTaskEffect>().map(
          (DesktopClearTaskEffect effect) => effect.taskKey,
        ),
        containsAll(<String>['auto_fetch', 'restore_artist_title']),
      );
      expect(result.effects[2], isA<DesktopRefreshSelectorEffect>());
      final DesktopRefreshSelectorEffect refreshEffect =
          result.effects[2] as DesktopRefreshSelectorEffect;
      expect(refreshEffect.instanceId, 1);
      expect(refreshEffect.onlyIfVisible, isTrue);
      expect(refreshEffect.context.keyword, 'Artist - Song');
      expect(refreshEffect.context.langs, <String>['orig', 'ts']);
      expect(result.effects[3], isA<DesktopQueryLibraryLinkEffect>());
    });

    test('chang_music 会立即同步面板以清空上一首歌词场景', () {
      final DesktopSessionState initial = DesktopSessionState.initial()
          .attachHello(
            hello: const DesktopHelloMessage(),
            apiVersion: 1,
            instanceId: 1,
          )
          .upsertPanel(
            const DesktopPanelState(
              panelId: 9,
              hostWindowId: 100,
              width: 320,
              height: 160,
              visible: true,
            ),
          );

      final DesktopReducerResult result = reducer.handleChangMusic(
        initial,
        const DesktopChangMusicMessage(
          instanceId: 1,
          title: 'New Song',
          artist: 'Artist',
          durationMs: 180000,
          path: r'D:\music\new.flac',
          track: '8',
        ),
      );

      final DesktopSyncPanelsEffect syncEffect = result.effects
          .whereType<DesktopSyncPanelsEffect>()
          .single;
      expect(syncEffect.instanceId, 1);
      expect(syncEffect.panelIds, <int>[9]);
      expect(syncEffect.snapshot.sceneRef, isNull);
      expect(syncEffect.snapshot.anchor.sceneId, isNull);
      expect(syncEffect.snapshot.session.songId, '8');
    });

    test('chang_music 会把单层 file URL 规范化为原生路径和单层关联键', () {
      final DesktopReducerResult result = reducer.handleChangMusic(
        DesktopSessionState.initial(),
        const DesktopChangMusicMessage(
          instanceId: 1,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: r'file://D:\music\song.flac',
          track: '7',
        ),
      );

      final SongInfo song = result.state.lyricsRuntime.song!;
      expect(song.path, r'D:\music\song.flac');
      expect(song.url, r'file://D:\music\song.flac');
      final DesktopQueryLibraryLinkEffect queryEffect = result.effects
          .whereType<DesktopQueryLibraryLinkEffect>()
          .single;
      expect(queryEffect.song.path, r'D:\music\song.flac');
      expect(
        LibraryLinkKey.fromSong(queryEffect.song).songPath,
        r'file://D:\music\song.flac',
      );
    });

    test('关联库结果会重排 langs 并触发本地歌词读取', () {
      final DesktopSessionState state = _buildSongState(reducer);
      final SongInfo song = state.lyricsRuntime.song!;
      final LibraryLinkItem item = LibraryLinkItem(
        id: 1,
        song: song,
        key: LibraryLinkKey.fromSong(song),
        lyricsPath: r'D:\lyrics\song.json',
        configSnapshot: <String, Object?>{
          'langs': <String>['ts', 'roma', 'unknown'],
          'offset': 120,
        },
      );

      final DesktopReducerResult result = reducer.applyLibraryLinkResult(
        state,
        libraryLink: item,
      );

      expect(result.state.config.selectedLangs, <String>['roma', 'ts']);
      expect(result.state.config.offsetMs, 120);
      expect(result.effects, hasLength(1));
      expect(result.effects.single, isA<DesktopLoadLinkedLyricsEffect>());
      expect(
        (result.effects.single as DesktopLoadLinkedLyricsEffect).lyricsPath,
        r'D:\lyrics\song.json',
      );
    });

    test('未命中关联库时会显示自动获取状态并发起 auto_fetch', () {
      final DesktopSessionState state = _buildSongState(reducer);

      final DesktopReducerResult result = reducer.applyLibraryLinkResult(
        state,
        libraryLink: null,
      );

      expect(result.state.lyricsRuntime.staticDisplayLines, <String>[
        '自动获取歌词中...',
      ]);
      expect(result.effects, hasLength(1));
      expect(result.effects.single, isA<DesktopStartAutoFetchEffect>());
      final AutoFetchRequest request =
          (result.effects.single as DesktopStartAutoFetchEffect).request;
      expect(request.info.title, 'Song');
      expect(request.sources, <Source>[Source.qm, Source.kg, Source.ne]);
    });

    test('无标题且无路径时不会发起 auto_fetch', () {
      final DesktopSessionState state = reducer
          .handleChangMusic(
            DesktopSessionState.initial(),
            const DesktopChangMusicMessage(
              instanceId: 1,
              durationMs: 180000,
              track: '7',
            ),
          )
          .state;

      final DesktopReducerResult result = reducer.applyLibraryLinkResult(
        state,
        libraryLink: null,
      );

      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        '? - ?',
        '没有获取到标题或文件名信息, 无法自动获取歌词',
      ]);
      expect(result.effects, isEmpty);
    });

    test('关联库歌词读取失败后会继续走自动获取主线', () {
      final DesktopSessionState state = _buildSongState(reducer).copyWith(
        config: DesktopSessionConfigState(
          defaultLangs: <String>['orig', 'ts'],
          songConfig: <String, Object?>{
            'langs': <String>['orig'],
          },
        ),
      );

      final DesktopReducerResult result = reducer.applyLibraryLinkResult(
        state,
        libraryLink: null,
        skipLinkedLyricsLoad: true,
      );

      expect(result.state.config.selectedLangs, const <String>['orig']);
      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        '自动获取歌词中...',
      ]);
      expect(result.effects.single, isA<DesktopStartAutoFetchEffect>());
    });

    test('禁用自动搜索时未命中关联库只显示歌手标题', () {
      final DesktopSessionState state = _buildSongState(reducer).copyWith(
        config: DesktopSessionConfigState(
          defaultLangs: <String>['orig', 'ts'],
          songConfig: <String, Object?>{'disable_auto_search': true},
        ),
      );

      final DesktopReducerResult result = reducer.applyLibraryLinkResult(
        state,
        libraryLink: null,
      );

      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        'Artist - Song',
      ]);
      expect(result.effects, isEmpty);
    });

    test('auto_fetch 成功会复用 select_lyrics 主线', () {
      final DesktopSessionState state = _buildSongState(reducer);

      final DesktopReducerResult result = reducer.applyAutoFetchResult(
        state,
        result: AutoFetchResult(
          lyrics: _buildRemoteLyrics(),
          matchedSongInfo: state.lyricsRuntime.song!,
          score: 92,
        ),
      );

      expect(result.state.lyricsRuntime.lyrics?.source, Source.qm);
      expect(
        result.effects.any(
          (DesktopSessionEffect effect) =>
              effect is DesktopSaveRemoteLyricsEffect,
        ),
        isTrue,
      );
    });

    test('auto_fetch 纯文本结果会显示失败文案而不落歌词', () {
      final DesktopSessionState state = _buildSongState(reducer);

      final DesktopReducerResult result = reducer.applyAutoFetchResult(
        state,
        result: AutoFetchResult(
          lyrics: _buildPlainTextLyrics(),
          matchedSongInfo: state.lyricsRuntime.song!,
          score: 70,
        ),
      );

      expect(result.state.lyricsRuntime.lyrics, isNull);
      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        'Artist - Song',
        '自动获取的歌词为纯文本，无法显示',
      ]);
      expect(result.effects, hasLength(2));
      expect(
        result.effects.whereType<DesktopClearTaskEffect>().map(
          (DesktopClearTaskEffect effect) => effect.taskKey,
        ),
        contains('restore_artist_title'),
      );
      expect(
        result.effects.any(
          (DesktopSessionEffect effect) =>
              effect is DesktopRestoreArtistTitleEffect,
        ),
        isTrue,
      );
    });

    test('auto_fetch 失败且标题命中伴奏关键词时会切纯音乐', () {
      final DesktopSessionState state = reducer
          .handleChangMusic(
            DesktopSessionState.initial(),
            const DesktopChangMusicMessage(
              instanceId: 1,
              title: 'Song (伴奏)',
              artist: 'Artist',
              album: 'Album',
              durationMs: 180000,
              path: r'D:\music\song.flac',
              track: '7',
            ),
          )
          .state;

      final DesktopReducerResult result = reducer.applyAutoFetchFailure(
        state,
        message: '网络错误',
        treatAsInstrumental: true,
      );

      expect(result.state.config.isInstrumental, isTrue);
      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        'Artist - Song (伴奏)',
        '纯音乐，请欣赏',
      ]);
    });

    test('auto_fetch 失败会显示失败文案', () {
      final DesktopSessionState state = _buildSongState(reducer);

      final DesktopReducerResult result = reducer.applyAutoFetchFailure(
        state,
        message: '网络错误',
        treatAsInstrumental: false,
      );

      expect(result.state.lyricsRuntime.staticDisplayLines, const <String>[
        'Artist - Song',
        '网络错误',
      ]);
      expect(result.effects, hasLength(2));
      expect(
        result.effects.any(
          (DesktopSessionEffect effect) =>
              effect is DesktopRestoreArtistTitleEffect,
        ),
        isTrue,
      );
    });

    test('select_lyrics 远端歌词会清任务、建映射并触发 JSON 保存', () {
      final DesktopSessionState state = _buildSongState(reducer);
      final DesktopSelectedLyricsPayload payload = DesktopSelectedLyricsPayload(
        lyrics: _buildRemoteLyrics(),
        langs: const <String>['orig', 'ts'],
        offsetMs: 250,
      );

      final DesktopReducerResult result = reducer.applySelectedLyrics(
        state,
        payload,
      );

      expect(result.state.config.offsetMs, 250);
      expect(result.state.config.selectedLangs, <String>['orig', 'ts']);
      expect(result.state.lyricsRuntime.hasRenderedLyricsData, isTrue);
      expect(
        result.state.lyricsRuntime.multiLyricsData['orig']!.first.startMs,
        1250,
      );
      expect(
        result.state.lyricsRuntime.multiLyricsData['orig']!.first.endMs,
        2250,
      );
      expect(result.state.lyricsRuntime.lyricsMapping['ts']?[0]?.text, '你好');
      expect(result.state.lyricsRuntime.assignedLyricsSlots, isNotEmpty);
      expect(result.state.lyricsRuntime.sceneDocument, isNotNull);
      expect(result.state.lyricsRuntime.sceneRef, isNotNull);
      expect(
        result.state.playbackSync.sceneId,
        result.state.lyricsRuntime.sceneRef?.sceneId,
      );
      expect(result.effects, hasLength(4));
      expect(
        result.effects.whereType<DesktopClearTaskEffect>().map(
          (DesktopClearTaskEffect effect) => effect.taskKey,
        ),
        containsAll(<String>['auto_fetch', 'restore_artist_title']),
      );
      expect(result.effects[2], isA<DesktopRefreshSelectorEffect>());
      expect(result.effects[3], isA<DesktopSaveRemoteLyricsEffect>());
      final DesktopSaveRemoteLyricsEffect saveEffect =
          result.effects[3] as DesktopSaveRemoteLyricsEffect;
      expect(saveEffect.suggestedFileName, 'Artist - Song｜QM(42).json');
    });

    test('select_lyrics 普通逐行 LRC 会先补齐整行与单词时间轴', () {
      final DesktopSessionState state = _buildSongState(reducer);
      final DesktopReducerResult result = reducer.applySelectedLyrics(
        state,
        DesktopSelectedLyricsPayload(
          lyrics: _buildLineOnlyLyrics(),
          langs: const <String>['orig'],
        ),
      );

      final LyricsData orig =
          result.state.lyricsRuntime.multiLyricsData['orig']!;
      expect(orig[0].startMs, 1000);
      expect(orig[0].endMs, 3000);
      expect(orig[0].words.single.startMs, 1000);
      expect(orig[0].words.single.endMs, 3000);
      expect(orig[1].startMs, 3000);
      expect(orig[1].endMs, 180000);
      expect(orig[1].words.single.endMs, 180000);
    });

    test('远端歌词建议文件名会复用共享非法字符转义规则', () {
      final DesktopSessionState state = _buildSongState(reducer);
      final DesktopSelectedLyricsPayload payload = DesktopSelectedLyricsPayload(
        lyrics: _buildRemoteLyrics(title: 'So/ng', artist: 'Ar:tist'),
        langs: const <String>['orig', 'ts'],
      );

      final DesktopReducerResult result = reducer.applySelectedLyrics(
        state,
        payload,
      );

      final DesktopSaveRemoteLyricsEffect saveEffect =
          result.effects[3] as DesktopSaveRemoteLyricsEffect;
      expect(saveEffect.suggestedFileName, 'Ar：tist - So／ng｜QM(42).json');
    });

    test('远端歌词保存成功后会回写关联库快照', () {
      final DesktopSessionState state = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
              offsetMs: 250,
            ),
          )
          .state;

      final DesktopReducerResult result = reducer.applyRemoteLyricsSaved(
        state,
        lyricsPath: r'D:\auto\Artist - Song｜QM(42).json',
      );

      expect(
        result.state.lyricsRuntime.lyricsPath,
        r'D:\auto\Artist - Song｜QM(42).json',
      );
      expect(result.effects, hasLength(1));
      expect(result.effects.single, isA<DesktopPersistLibraryLinkEffect>());
      final DesktopPersistLibraryLinkEffect persistEffect =
          result.effects.single as DesktopPersistLibraryLinkEffect;
      expect(persistEffect.configSnapshot, <String, Object?>{'offset': 250});
    });

    test('set_inst 会清除歌词关联但保留 disable_auto_search', () {
      final DesktopSessionState state = _buildSongState(reducer).copyWith(
        config: DesktopSessionConfigState(
          defaultLangs: <String>['orig', 'ts'],
          songConfig: <String, Object?>{
            'offset': 100,
            'langs': <String>['roma'],
            'disable_auto_search': true,
          },
        ),
      );

      final DesktopReducerResult result = reducer.setInstrumental(
        state,
        enable: true,
      );

      expect(result.state.config.isInstrumental, isTrue);
      expect(result.state.config.isAutoSearchDisabled, isTrue);
      expect(result.state.config.offsetMs, 0);
      expect(result.state.config.selectedLangs, <String>['orig', 'ts']);
      expect(result.state.lyricsRuntime.lyrics, isNull);
      expect(result.state.lyricsRuntime.lyricsPath, isNull);
      expect(result.state.lyricsRuntime.staticDisplayLines, <String>[
        'Artist - Song',
        '纯音乐，请欣赏',
      ]);
      expect(result.effects, hasLength(3));
      expect(
        result.effects.whereType<DesktopClearTaskEffect>().map(
          (DesktopClearTaskEffect effect) => effect.taskKey,
        ),
        containsAll(<String>['auto_fetch', 'restore_artist_title']),
      );
      expect(result.effects[2], isA<DesktopPersistLibraryLinkEffect>());
      final DesktopPersistLibraryLinkEffect persistEffect =
          result.effects[2] as DesktopPersistLibraryLinkEffect;
      expect(persistEffect.configSnapshot, <String, Object?>{
        'inst': true,
        'disable_auto_search': true,
      });
    });

    test('stop 会完整清空当前歌曲上下文并生成递增 stop 锚点', () {
      final DesktopSessionState state = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
            ),
          )
          .state
          .copyWith(
            config: DesktopSessionConfigState(
              defaultLangs: <String>['orig', 'ts'],
              songConfig: <String, Object?>{
                'offset': 120,
                'disable_auto_search': true,
              },
            ),
            playbackSync: const DesktopPlaybackSyncState(
              pluginPlaybackTimeMs: 3200,
              pluginSendTimeMs: 3000,
              hostReceivedAtMs: 3100,
              isPlaying: true,
              syncRevision: 7,
              task: DesktopIpcTask.sync,
              sceneId: '1:9',
              songToken: 'song-7',
            ),
          )
          .upsertPanel(
            const DesktopPanelState(
              panelId: 3,
              hostWindowId: 55,
              visible: true,
            ),
          );

      final DesktopReducerResult result = reducer.applyStop(state);

      expect(result.state.isPlaying, isFalse);
      expect(result.state.lastTask, DesktopIpcTask.stop);
      expect(result.state.lyricsRuntime.song, isNull);
      expect(result.state.lyricsRuntime.lyrics, isNull);
      expect(result.state.lyricsRuntime.lyricsPath, isNull);
      expect(result.state.lyricsRuntime.sceneDocument, isNull);
      expect(result.state.lyricsRuntime.sceneRef, isNull);
      expect(result.state.lyricsRuntime.staticDisplayLines, isEmpty);
      expect(result.state.config.songConfig, isEmpty);
      expect(result.state.playbackSync.pluginPlaybackTimeMs, 0);
      expect(result.state.playbackSync.pluginSendTimeMs, isNull);
      expect(result.state.playbackSync.isPlaying, isFalse);
      expect(result.state.playbackSync.syncRevision, 8);
      expect(result.state.playbackSync.task, DesktopIpcTask.stop);
      expect(result.state.playbackSync.sceneId, isNull);
      expect(result.state.playbackSync.songToken, isNull);
      expect(result.state.playbackSync.hostReceivedAtMs, 1234567890);
      expect(result.effects, hasLength(4));
      expect(
        result.effects.whereType<DesktopClearTaskEffect>().map(
          (DesktopClearTaskEffect effect) => effect.taskKey,
        ),
        containsAll(<String>['auto_fetch', 'restore_artist_title']),
      );
      final DesktopSyncPanelsEffect panelEffect =
          result.effects[2] as DesktopSyncPanelsEffect;
      expect(panelEffect.panelIds, const <int>[3]);
      expect(panelEffect.snapshot.sceneRef, isNull);
      expect(panelEffect.snapshot.anchor.syncRevision, 8);
      expect(
        panelEffect.snapshot.anchor.eventKind,
        DesktopPlaybackEventKind.stop,
      );
      expect(panelEffect.snapshot.session.actions.canUnlinkLyrics, isFalse);
      expect(result.effects[3], isA<DesktopRefreshSelectorEffect>());
    });

    test('applyPlaybackSync 不回写主机进度，只广播已有同步锚点', () {
      final DesktopSessionState state = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
              offsetMs: 250,
            ),
          )
          .state
          .copyWith(
            playbackSync: const DesktopPlaybackSyncState(
              pluginPlaybackTimeMs: 1500,
              hostReceivedAtMs: 1500,
              isPlaying: true,
              syncRevision: 3,
              sceneId: '1:1',
              songToken: '7',
            ),
          );

      final DesktopReducerResult result = reducer.applyPlaybackSync(state);

      expect(identical(result.state, state), isTrue);
      expect(result.state.playbackSync.pluginPlaybackTimeMs, 1500);
      expect(result.state.lyricsRuntime.sceneDocument, isNotNull);
      expect(result.state.lyricsRuntime.sceneRef, isNotNull);
      expect(
        identical(
          result.state.lyricsRuntime.multiLyricsData,
          state.lyricsRuntime.multiLyricsData,
        ),
        isTrue,
      );
      expect(
        identical(
          result.state.lyricsRuntime.lyricsMapping,
          state.lyricsRuntime.lyricsMapping,
        ),
        isTrue,
      );
      expect(
        identical(
          result.state.lyricsRuntime.assignedLyricsSlots,
          state.lyricsRuntime.assignedLyricsSlots,
        ),
        isTrue,
      );
      expect(
        identical(
          result.state.lyricsRuntime.rubyMapping,
          state.lyricsRuntime.rubyMapping,
        ),
        isTrue,
      );
      expect(
        identical(
          result.state.lyricsRuntime.sceneDocument,
          state.lyricsRuntime.sceneDocument,
        ),
        isTrue,
      );
      expect(result.effects, isEmpty);
    });

    test('现存面板会在静态文本与进度刷新时收到同步快照', () {
      final DesktopSessionState panelState = DesktopSessionState.initial()
          .copyWith(instanceId: 1)
          .upsertPanel(
            const DesktopPanelState(
              panelId: 3,
              hostWindowId: 55,
              visible: true,
            ),
          );

      final DesktopReducerResult staticResult = reducer.setDisplayText(
        panelState,
        const <String>['自动获取歌词中...'],
      );
      expect(staticResult.effects, hasLength(1));
      expect(staticResult.effects.single, isA<DesktopSyncPanelsEffect>());
      final DesktopSyncPanelsEffect staticEffect =
          staticResult.effects.single as DesktopSyncPanelsEffect;
      expect(staticEffect.instanceId, 1);
      expect(staticEffect.panelIds, const <int>[3]);
      expect(staticEffect.snapshot.sceneRef, isNotNull);

      final DesktopSessionState lyricsState = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
            ),
          )
          .state
          .copyWith(instanceId: 1)
          .upsertPanel(
            const DesktopPanelState(
              panelId: 3,
              hostWindowId: 55,
              visible: true,
            ),
          )
          .copyWith(
            playbackSync: const DesktopPlaybackSyncState(
              pluginPlaybackTimeMs: 1500,
              hostReceivedAtMs: 1500,
              isPlaying: true,
              syncRevision: 5,
              sceneId: '1:1',
              songToken: '7',
            ),
          );
      final DesktopReducerResult progressResult = reducer.applyPlaybackSync(
        lyricsState,
      );
      expect(progressResult.effects, hasLength(1));
      expect(progressResult.effects.single, isA<DesktopSyncPanelsEffect>());
      final DesktopSyncPanelsEffect progressEffect =
          progressResult.effects.single as DesktopSyncPanelsEffect;
      expect(progressEffect.instanceId, 1);
      expect(progressEffect.snapshot.sceneRef, isNotNull);
      expect(progressEffect.snapshot.anchor.pluginPlaybackTimeMs, 1500);
      expect(progressEffect.snapshot.anchor.syncRevision, 5);
      expect(
        progressEffect.snapshot.anchor.sceneId,
        progressEffect.snapshot.sceneRef?.sceneId,
      );
    });

    test('桌面配置热更新会重建默认 langs 与 ruby 映射', () {
      final DesktopSessionState state = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
            ),
          )
          .state;

      final DesktopSessionReducerConfigDiff diff = reducer
          .reconfigureFromAppConfig(
            AppConfig(
              schemaVersion: ConfigDefaults.current.schemaVersion,
              search: ConfigDefaults.current.search,
              lyrics: ConfigDefaults.current.lyrics,
              match: ConfigDefaults.current.match,
              translate: ConfigDefaults.current.translate,
              desktop: DesktopConfig(
                playedColors: const <RgbColor>[
                  RgbColor(11, 22, 33),
                  RgbColor(44, 55, 66),
                ],
                unplayedColors: const <RgbColor>[
                  RgbColor(77, 88, 99),
                  RgbColor(111, 122, 133),
                ],
                defaultLangs: const <String>['orig'],
                langOrder: const <String>['orig', 'ts'],
                sources: const <String>['QM'],
                fontFamily: 'Noto Sans CJK SC',
                refreshRate: 120,
                windowRect: const WindowRect(
                  left: 42,
                  top: 84,
                  width: 640,
                  height: 240,
                ),
                fontSize: 36,
                showFurigana: false,
                panelFontSize: ConfigDefaults.current.desktop.panelFontSize,
              ),
              app: ConfigDefaults.current.app,
              storage: ConfigDefaults.current.storage,
            ),
          );

      final DesktopReducerResult result = reducer.applyConfigDiff(state, diff);

      expect(result.state.config.defaultLangs, const <String>['orig']);
      expect(result.state.config.selectedLangs, const <String>['orig']);
      expect(result.state.config.playedColors, const <RgbColor>[
        RgbColor(11, 22, 33),
        RgbColor(44, 55, 66),
      ]);
      expect(result.state.config.unplayedColors, const <RgbColor>[
        RgbColor(77, 88, 99),
        RgbColor(111, 122, 133),
      ]);
      expect(result.state.config.fontFamily, 'Noto Sans CJK SC');
      expect(result.state.config.fontSize, 36);
      expect(result.state.config.showFurigana, isFalse);
      expect(result.state.config.refreshRate, 120);
      expect(result.state.config.windowRect, state.config.windowRect);
      expect(result.state.lyricsRuntime.rubyMapping, isEmpty);
      expect(result.state.lyricsRuntime.sceneDocument, isNotNull);
      expect(result.state.lyricsRuntime.sceneRef, isNotNull);
      expect(
        result.effects.any(
          (DesktopSessionEffect effect) =>
              effect is DesktopRefreshSelectorEffect,
        ),
        isTrue,
      );
    });

    test('panelFontSize 热更新只更新面板快照并保留浮窗字号', () {
      final DesktopSessionState baseState = reducer
          .applySelectedLyrics(
            _buildSongState(reducer),
            DesktopSelectedLyricsPayload(
              lyrics: _buildRemoteLyrics(),
              langs: const <String>['orig', 'ts'],
            ),
          )
          .state
          .copyWith(
            panels: const <int, DesktopPanelState>{
              7: DesktopPanelState(panelId: 7, visible: true),
            },
          );

      final DesktopSessionReducerConfigDiff diff = reducer
          .reconfigureFromAppConfig(
            AppConfig(
              schemaVersion: ConfigDefaults.current.schemaVersion,
              search: ConfigDefaults.current.search,
              lyrics: ConfigDefaults.current.lyrics,
              match: ConfigDefaults.current.match,
              translate: ConfigDefaults.current.translate,
              desktop: DesktopConfig(
                playedColors: ConfigDefaults.current.desktop.playedColors,
                unplayedColors: ConfigDefaults.current.desktop.unplayedColors,
                defaultLangs: ConfigDefaults.current.desktop.defaultLangs,
                langOrder: ConfigDefaults.current.desktop.langOrder,
                sources: ConfigDefaults.current.desktop.sources,
                fontFamily: ConfigDefaults.current.desktop.fontFamily,
                refreshRate: ConfigDefaults.current.desktop.refreshRate,
                windowRect: ConfigDefaults.current.desktop.windowRect,
                fontSize: 38,
                panelFontSize: 16,
                showFurigana: ConfigDefaults.current.desktop.showFurigana,
              ),
              app: ConfigDefaults.current.app,
              storage: ConfigDefaults.current.storage,
            ),
          );

      final DesktopReducerResult result = reducer.applyConfigDiff(
        baseState,
        diff,
      );

      expect(result.state.config.fontSize, 38);
      expect(result.state.config.panelFontSize, 16);
      expect(
        result.effects
            .whereType<DesktopSyncPanelsEffect>()
            .single
            .snapshot
            .session
            .fontSize,
        16,
      );
    });
  });
}

DesktopSessionState _buildSongState(DesktopSessionReducer reducer) {
  return reducer
      .handleChangMusic(
        DesktopSessionState.initial(),
        const DesktopChangMusicMessage(
          instanceId: 1,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          durationMs: 180000,
          path: r'D:\music\song.flac',
          track: '7',
        ),
      )
      .state;
}

Lyrics _buildRemoteLyrics({String title = 'Song', String artist = 'Artist'}) {
  final SongInfo songInfo = SongInfo(
    source: Source.qm,
    title: title,
    artist: SongArtist(<String>[artist]),
    album: 'Album',
    durationMs: 180000,
    id: '42',
  );
  return Lyrics(
    songInfo: songInfo,
    source: Source.qm,
    id: '42',
    types: const <String, LyricsType>{
      'orig': LyricsType.lineByLine,
      'ts': LyricsType.lineByLine,
      'roma': LyricsType.lineByLine,
    },
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2500,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 1500, text: 'か'),
            LyricsWord(startMs: 1500, endMs: 2000, text: 'な'),
          ],
        ),
      ],
      'ts': <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2500,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 2500, text: '你好'),
          ],
        ),
      ],
      'roma': <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: 2500,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: 2500, text: 'ka  na'),
          ],
        ),
      ],
    },
  );
}

Lyrics _buildLineOnlyLyrics() {
  final SongInfo songInfo = SongInfo(
    source: Source.local,
    title: 'Song',
    artist: SongArtist(<String>['Artist']),
    album: 'Album',
    durationMs: 180000,
    id: '42',
  );
  return Lyrics(
    songInfo: songInfo,
    source: Source.local,
    id: '42',
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 1000,
          endMs: null,
          words: const <LyricsWord>[
            LyricsWord(startMs: 1000, endMs: null, text: '第一行'),
          ],
        ),
        LyricsLine(
          startMs: 3000,
          endMs: null,
          words: const <LyricsWord>[
            LyricsWord(startMs: 3000, endMs: null, text: '第二行'),
          ],
        ),
      ],
    },
  );
}

Lyrics _buildPlainTextLyrics() {
  final SongInfo songInfo = SongInfo(
    source: Source.qm,
    title: 'Song',
    artist: SongArtist(<String>['Artist']),
    album: 'Album',
    durationMs: 180000,
    id: '42',
  );
  return Lyrics(
    songInfo: songInfo,
    source: Source.qm,
    id: '42',
    types: const <String, LyricsType>{'orig': LyricsType.plainText},
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: null,
          endMs: null,
          words: const <LyricsWord>[
            LyricsWord(startMs: null, endMs: null, text: 'Plain text'),
          ],
        ),
      ],
    },
  );
}
