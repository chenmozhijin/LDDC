import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/accessibility/app_action_semantics.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_dependencies.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_file_reader.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_input_picker.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_controller.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_state.dart';
import 'package:lddc/src/features/open_lyrics/presentation/open_lyrics_page.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:lddc/src/shared/ui/components/desktop_page_interaction_scope.dart';

void main() {
  group('OpenLyricsPageController', () {
    test('打开歌词文件后先显示原始文本，转换后可切换格式与偏移', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      );
      final _FakeLyricsApi lyricsApi = _FakeLyricsApi(lyrics: _buildLyrics());
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: lyricsApi,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.previewState, OpenLyricsPreviewState.rawLoaded);
      expect(state.previewText, contains('[00:00.00]原文'));

      await controller.convert();
      state = container.read(openLyricsPageControllerProvider);
      expect(state.previewState, OpenLyricsPreviewState.converted);
      expect(state.previewText, contains('原文'));
      expect(lyricsApi.lastPath, r'D:\demo.lrc');

      controller.updateLyricsFormat(LyricsFormat.srt);
      state = container.read(openLyricsPageControllerProvider);
      expect(state.previewText, contains('-->'));

      controller.updateOffsetMs(1000);
      state = container.read(openLyricsPageControllerProvider);
      expect(state.previewText, contains('00:00:01,000'));
    });

    test('打开歌曲文件后以 path:null 走无扩展名回退链路', () async {
      final PickedAudioFileHandle pickedAudio = const PickedAudioFileHandle(
        name: 'demo.mp3',
        path: r'D:\demo.mp3',
      );
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedAudioFile: pickedAudio,
      );
      final _FakeLyricsApi lyricsApi = _FakeLyricsApi(lyrics: _buildLyrics());
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()..readLyricsText = '[00:00.00]内嵌歌词';
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: lyricsApi,
        mediaGateway: mediaGateway,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openSongFile();
      await controller.convert();

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.inputType, OpenLyricsInputType.songFile);
      expect(state.previewText, contains('原文'));
      expect(lyricsApi.lastPath, isNull);
      expect(lyricsApi.lastData, isA<Uint8List>());
    });

    test('toggleTranslation 首次添加 LDDC_ts，再次点击移除', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        translateApi: _FakeTranslateApi(),
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      await controller.convert();
      await controller.toggleTranslation();

      OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isTrue);

      await controller.toggleTranslation();
      state = container.read(openLyricsPageControllerProvider);
      expect(state.currentLyrics?.data.containsKey('LDDC_ts'), isFalse);
    });

    test('未选择任何语言时显示 noLanguage 空态', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      await controller.convert();
      controller.updateSelectedLangs(<String>{});

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.previewText, isEmpty);
      expect(state.emptyReason, OpenLyricsEmptyReason.noLanguage);
    });

    test('saveToTag 在非 LRC 格式下给出明确提示', () async {
      final PickedAudioFileHandle pickedAudio = const PickedAudioFileHandle(
        name: 'demo.mp3',
        path: r'D:\demo.mp3',
      );
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedAudioFile: pickedAudio,
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        mediaGateway: _FakeLocalMatchMediaGateway()
          ..readLyricsText = '[00:00.00]内嵌歌词',
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openSongFile();
      await controller.convert();
      controller.updateLyricsFormat(LyricsFormat.srt);
      await controller.saveToTag();

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.notice?.code, OpenLyricsNoticeCode.audioTagRequiresLrc);
    });

    test('切换输入后旧翻译请求不会覆盖新状态，disposeSession 会释放音频句柄', () async {
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..completer = Completer<LyricsData>();
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'first.lrc',
          path: r'D:\first.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
        pickedAudioFile: const PickedAudioFileHandle(
          name: 'demo.mp3',
          path: r'D:\demo.mp3',
        ),
      );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()..readLyricsText = '[00:00.00]内嵌歌词';
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        translateApi: translateApi,
        mediaGateway: mediaGateway,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      await controller.convert();
      unawaited(controller.toggleTranslation());

      await controller.openSongFile();
      translateApi.completer?.complete(_translationLines());
      await Future<void>.delayed(Duration.zero);

      OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.inputType, OpenLyricsInputType.songFile);
      expect(state.currentLyrics, isNull);

      await controller.disposeSession();
      state = container.read(openLyricsPageControllerProvider);
      expect(state.inputType, isNull);
      expect(picker.releasedAudioFiles, hasLength(1));
    });

    test('切换输入后旧翻译失败不会显示到当前页面', () async {
      final _FakeTranslateApi translateApi = _FakeTranslateApi()
        ..failureCompleter = Completer<void>()
        ..failure = Exception('old translate failed');
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'first.lrc',
          path: r'D:\first.lrc',
          bytes: _lyricsFileBytes('[00:00.00]第一首'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        translateApi: translateApi,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      await controller.convert();
      final Future<void> oldTranslation = controller.toggleTranslation();
      await Future<void>.delayed(Duration.zero);
      picker.pickedLyricsFile = _MemoryPickedFileHandle(
        name: 'second.lrc',
        path: r'D:\second.lrc',
        bytes: _lyricsFileBytes('[00:00.00]第二首'),
      );
      await controller.openLyricsFile();
      translateApi.failureCompleter?.complete();
      await oldTranslation;

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.inputName, 'second.lrc');
      expect(state.isTranslating, isFalse);
      expect(state.notice?.detail, isNot(contains('old translate failed')));
      expect(state.previewText, contains('第二首'));
    });

    test('切换输入后旧转换请求不会覆盖新输入', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'first.lrc',
          path: r'D:\first.lrc',
          bytes: _lyricsFileBytes('[00:00.00]第一首'),
        ),
      );
      final _FakeLyricsApi lyricsApi = _FakeLyricsApi(lyrics: _buildLyrics())
        ..completer = Completer<Lyrics>();
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: lyricsApi,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      final Future<void> oldConvert = controller.convert();
      picker.pickedLyricsFile = _MemoryPickedFileHandle(
        name: 'second.lrc',
        path: r'D:\second.lrc',
        bytes: _lyricsFileBytes('[00:00.00]第二首'),
      );
      await controller.openLyricsFile();
      lyricsApi.completer?.complete(_buildLyrics());
      await oldConvert;

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.inputName, 'second.lrc');
      expect(state.previewState, OpenLyricsPreviewState.rawLoaded);
      expect(state.currentLyrics, isNull);
      expect(state.previewText, contains('第二首'));
    });

    test('预览变化后旧保存完成不会回写成功提示', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      )..saveCompleter = Completer<SavedTextFileResult?>();
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openLyricsFile();
      await controller.convert();
      final Future<void> oldSave = controller.saveToFile();
      controller.updateLyricsFormat(LyricsFormat.srt);
      picker.saveCompleter?.complete(
        SavedTextFileResult.localPath(r'D:\old-output.lrc'),
      );
      await oldSave;

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.isSaving, isFalse);
      expect(state.notice?.detail, isNot(contains('old-output')));
      expect(state.previewText, contains('-->'));
      expect(picker.lastSavedText, isNot(contains('-->')));
    });

    test('预览变化后旧标签写入完成不会回写成功提示', () async {
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedAudioFile: const PickedAudioFileHandle(
          name: 'demo.mp3',
          path: r'D:\demo.mp3',
        ),
      );
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()
            ..readLyricsText = '[00:00.00]内嵌歌词'
            ..writeCompleter = Completer<void>();
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        mediaGateway: mediaGateway,
      );
      addTearDown(container.dispose);
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );

      await controller.openSongFile();
      await controller.convert();
      final Future<void> oldSave = controller.saveToTag();
      controller.updateLyricsFormat(LyricsFormat.srt);
      mediaGateway.writeCompleter?.complete();
      await oldSave;

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      expect(state.isSaving, isFalse);
      expect(state.notice?.code, isNot(OpenLyricsNoticeCode.saveTagSucceeded));
      expect(state.previewText, contains('-->'));
      expect(mediaGateway.lastWrittenLyricsText, isNot(contains('-->')));
    });
  });

  group('OpenLyricsPage', () {
    testWidgets('页面展示主流程控件且控制区收口为无标题卡片', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));

      expect(find.text('预览'), findsOneWidget);
      expect(find.text('输入文件'), findsNothing);
      expect(find.text('转换控制'), findsNothing);
      expect(find.text('操作'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_open_lyrics_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_open_song_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_language_segments')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_format_dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_offset_stepper')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_translate_button')),
        findsOneWidget,
      );
      expect(find.text('Open Lyrics Baseline'), findsNothing);
    });

    testWidgets('大窗口预览消费剩余高度且中小窗口保持滚动回退', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 768));
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildTestApp(container));
      await tester.pump();

      final Finder previewCard = find.byKey(
        const ValueKey<String>('open_lyrics_preview_card'),
      );
      final double shortWindowHeight = tester.getSize(previewCard).height;
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1366, 1024);
      await tester.pump();
      final double tallWindowHeight = tester.getSize(previewCard).height;
      expect(tallWindowHeight, greaterThan(shortWindowHeight + 200));
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.byType(ListView), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_action_bar')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      expect(find.byType(ListView), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Windows 默认窗口在系统缩放后初始预览仍随可用高度伸展', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1280, 720), devicePixelRatio: 1.25);
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _buildTestApp(container, simulateDesktopShell: true),
      );
      await tester.pump();

      expect(
        find.byKey(
          const ValueKey<String>('open_lyrics_adaptive_height_layout'),
        ),
        findsOneWidget,
      );
      final Finder previewCard = find.byKey(
        const ValueKey<String>('open_lyrics_preview_card'),
      );
      final double initialHeight = tester.getSize(previewCard).height;

      tester.view.physicalSize = const Size(1280, 900);
      await tester.pump();
      expect(
        tester.getSize(previewCard).height,
        greaterThan(initialHeight + 100),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('紧凑布局下主流程控件可滚动到操作区', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_open_lyrics_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('open_lyrics_open_song_button')),
        findsOneWidget,
      );
      final Finder mainListView = find.byType(ListView).first;
      await tester.dragUntilVisible(
        find.byKey(const ValueKey<String>('open_lyrics_action_bar')),
        mainListView,
        const Offset(0, -300),
      );

      expect(
        find.byKey(const ValueKey<String>('open_lyrics_action_bar')),
        findsOneWidget,
      );
    });

    testWidgets('打开歌词文件按钮直接触发歌词文件选择', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.tap(
        find.byKey(const ValueKey<String>('open_lyrics_open_lyrics_button')),
      );
      await tester.pumpAndSettle();

      expect(picker.lyricsFilePickCount, 1);
      expect(find.text(r'D:\demo.lrc'), findsOneWidget);
    });

    testWidgets('打开歌曲文件按钮直接触发歌曲文件选择', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedAudioFile: const PickedAudioFileHandle(
          name: 'demo.mp3',
          path: r'D:\demo.mp3',
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        mediaGateway: _FakeLocalMatchMediaGateway()
          ..readLyricsText = '[00:00.00]内嵌歌词',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.tap(
        find.byKey(const ValueKey<String>('open_lyrics_open_song_button')),
      );
      await tester.pumpAndSettle();

      expect(picker.audioFilePickCount, 1);
      expect(find.text(r'D:\demo.mp3'), findsOneWidget);
    });

    testWidgets('notice 由页面按当前 locale 渲染', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(390, 844));
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildTestApp(container, locale: const Locale('en')),
      );
      await container.read(openLyricsPageControllerProvider.notifier).convert();
      await tester.pumpAndSettle();

      expect(find.text('Lyrics content cannot be empty'), findsOneWidget);
    });

    testWidgets('标签写入成功 notice 暴露稳定原生结果 identifier', (
      WidgetTester tester,
    ) async {
      _setTestViewport(tester, const Size(390, 844));
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedAudioFile: const PickedAudioFileHandle(
          name: 'demo.mp3',
          path: r'D:\demo.mp3',
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        mediaGateway: _FakeLocalMatchMediaGateway()
          ..readLyricsText = '[00:00.00]内嵌歌词',
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );
      await controller.openSongFile();
      await controller.convert();
      await tester.pump();
      await controller.saveToTag();
      expect(
        container.read(openLyricsPageControllerProvider).notice?.code,
        OpenLyricsNoticeCode.saveTagSucceeded,
      );
      // Riverpod listener 先调度 SnackBar，再由下一帧建立 live-region 语义节点。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.bySemanticsIdentifier(
          AppSemanticsIdentifiers.openLyricsSaveTagSucceeded,
        ),
        findsOneWidget,
      );
    });

    testWidgets('标签写入失败 notice 暴露稳定原生结果 identifier', (
      WidgetTester tester,
    ) async {
      _setTestViewport(tester, const Size(390, 844));
      final _FakeLocalMatchMediaGateway mediaGateway =
          _FakeLocalMatchMediaGateway()
            ..readLyricsText = '[00:00.00]内嵌歌词'
            ..writeError = Exception('受控写入失败');
      final ProviderContainer container = _createContainer(
        picker: _FakeOpenLyricsInputPicker(
          pickedAudioFile: const PickedAudioFileHandle(
            name: 'demo.mp3',
            path: r'D:\demo.mp3',
          ),
        ),
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
        mediaGateway: mediaGateway,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      final OpenLyricsPageController controller = container.read(
        openLyricsPageControllerProvider.notifier,
      );
      await controller.openSongFile();
      await controller.convert();
      await controller.saveToTag();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.bySemanticsIdentifier(
          AppSemanticsIdentifiers.openLyricsSaveTagFailed,
        ),
        findsOneWidget,
      );
    });

    testWidgets('选择文件后预览卡内仅显示单行路径摘要', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]原文'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.tap(
        find.byKey(const ValueKey<String>('open_lyrics_open_lyrics_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'D:\demo.lrc'), findsOneWidget);
      expect(find.text('输入文件'), findsNothing);
      expect(find.text('demo.lrc'), findsNothing);
    });

    testWidgets('桌面快捷键 Ctrl+O 走默认歌词文件打开链路', (WidgetTester tester) async {
      _setTestViewport(tester, const Size(1366, 1024));
      final _FakeOpenLyricsInputPicker picker = _FakeOpenLyricsInputPicker(
        pickedLyricsFile: _MemoryPickedFileHandle(
          name: 'demo.lrc',
          path: r'D:\demo.lrc',
          bytes: _lyricsFileBytes('[00:00.00]快捷键原文'),
        ),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        lyricsApi: _FakeLyricsApi(lyrics: _buildLyrics()),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true),
      );
      await tester.pumpAndSettle();
      expect(picker.lyricsFilePickCount, 1);
      expect(
        container.read(openLyricsPageControllerProvider).previewState,
        OpenLyricsPreviewState.rawLoaded,
      );

      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.enter),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(openLyricsPageControllerProvider).previewState,
        OpenLyricsPreviewState.converted,
      );

      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.escape),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(openLyricsPageControllerProvider).inputType,
        isNull,
      );

      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true),
      );
      await tester.pumpAndSettle();
      expect(picker.lyricsFilePickCount, 2);
      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.delete),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(openLyricsPageControllerProvider).inputType,
        isNull,
      );
    });
  });
}

Widget _buildTestApp(
  ProviderContainer container, {
  Locale locale = const Locale('zh'),
  bool simulateDesktopShell = false,
}) {
  final Widget page = simulateDesktopShell
      ? Row(
          children: const <Widget>[
            SizedBox(width: 80),
            VerticalDivider(width: 1),
            Expanded(child: OpenLyricsPage()),
          ],
        )
      : const OpenLyricsPage();
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: simulateDesktopShell ? AppBar(title: const Text('打开歌词')) : null,
        body: page,
      ),
    ),
  );
}

ProviderContainer _createContainer({
  required _FakeOpenLyricsInputPicker picker,
  required _FakeLyricsApi lyricsApi,
  _FakeTranslateApi? translateApi,
  _FakeLocalMatchMediaGateway? mediaGateway,
  OpenLyricsFileReader? fileReader,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(_config());
  final _FakeTranslateApi resolvedTranslateApi =
      translateApi ?? _FakeTranslateApi();
  final _FakeLocalMatchMediaGateway resolvedMediaGateway =
      mediaGateway ?? _FakeLocalMatchMediaGateway();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => _capability()),
      openLyricsDependenciesProvider.overrideWithValue(
        OpenLyricsDependencies(
          configRepository: repository,
          capability: _capability(),
          lyricsApi: lyricsApi,
          translateApi: resolvedTranslateApi,
          mediaGateway: resolvedMediaGateway,
          inputPicker: picker,
          fileReader: fileReader ?? const OpenLyricsFileReaderImpl(),
          dragDropPort: const DragDropPortImpl(),
        ),
      ),
      configRepositoryProvider.overrideWithValue(repository),
      lyricsApiProvider.overrideWithValue(lyricsApi),
      translateApiProvider.overrideWithValue(resolvedTranslateApi),
      localMatchMediaGatewayProvider.overrideWithValue(resolvedMediaGateway),
    ],
  );
}

AppConfig _config() {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: base.search,
    lyrics: base.lyrics,
    match: base.match,
    translate: base.translate,
    desktop: base.desktop,
    app: base.app,
    storage: base.storage,
    legacyExtras: base.legacyExtras,
  );
}

AppCapability _capability() {
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

class _FakeOpenLyricsInputPicker implements OpenLyricsInputPicker {
  _FakeOpenLyricsInputPicker({this.pickedLyricsFile, this.pickedAudioFile});

  PickedFileHandle? pickedLyricsFile;
  PickedAudioFileHandle? pickedAudioFile;
  int lyricsFilePickCount = 0;
  int audioFilePickCount = 0;
  String? lastSavedFileName;
  String? lastSavedText;
  List<String>? lastAllowedExtensions;
  Completer<SavedTextFileResult?>? saveCompleter;
  final List<PickedAudioFileHandle> releasedAudioFiles =
      <PickedAudioFileHandle>[];

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
    audioFilePickCount += 1;
    return pickedAudioFile;
  }

  @override
  Future<PickedFileHandle?> pickLyricsFile({String? initialDirectory}) async {
    lyricsFilePickCount += 1;
    return pickedLyricsFile;
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) async {
    releasedAudioFiles.add(file);
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) async => file;

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) async {
    lastSavedFileName = fileName;
    lastSavedText = text;
    lastAllowedExtensions = allowedExtensions;
    final Completer<SavedTextFileResult?>? completer = saveCompleter;
    if (completer != null) {
      return completer.future;
    }
    return SavedTextFileResult.localPath(r'D:\output.lrc');
  }
}

Future<void> _invokeShortcut(
  WidgetTester tester,
  ShortcutActivator activator,
) async {
  for (final Element element
      in find.byType(DesktopPageInteractionScope).evaluate()) {
    final DesktopPageInteractionScope scope =
        element.widget as DesktopPageInteractionScope;
    final VoidCallback? callback = scope.shortcuts[activator];
    if (callback == null) {
      continue;
    }
    callback();
    await tester.pumpAndSettle();
    return;
  }
  fail('未找到快捷键绑定：$activator');
}

class _MemoryPickedFileHandle extends PickedFileHandle {
  _MemoryPickedFileHandle({
    required super.name,
    required this.bytes,
    super.path,
  });

  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

class _FakeLyricsApi implements LyricsClient {
  _FakeLyricsApi({required this.lyrics});

  final Lyrics lyrics;
  Completer<Lyrics>? completer;
  String? lastPath;
  Object? lastData;

  @override
  Future<APIResultList<SourceAware>> search({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    throw UnsupportedError('OpenLyrics 测试场景不支持搜索');
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    throw UnsupportedError('OpenLyrics 测试场景不支持读取歌单');
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    throw UnsupportedError('OpenLyrics 测试场景不支持候选歌词列表');
  }

  @override
  Future<LyricsResolveResult> resolveSongLyrics({
    required SongInfo songInfo,
    required bool autoSelect,
  }) async {
    throw UnsupportedError('OpenLyrics 测试场景不支持云端歌词解析');
  }

  @override
  Future<Lyrics> getLyrics({Object? info, String? path, Object? data}) async {
    lastPath = path;
    lastData = data;
    final Completer<Lyrics>? currentCompleter = completer;
    if (currentCompleter != null) {
      return currentCompleter.future;
    }
    return lyrics;
  }
}

class _FakeTranslateApi implements TranslationClient {
  Completer<LyricsData>? completer;
  Completer<void>? failureCompleter;
  Object? failure;

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    final Completer<void>? currentFailureCompleter = failureCompleter;
    if (currentFailureCompleter != null) {
      await currentFailureCompleter.future;
      throw failure ?? StateError('translate failed');
    }
    final Completer<LyricsData>? currentCompleter = completer;
    if (currentCompleter != null) {
      return currentCompleter.future;
    }
    return _translationLines();
  }
}

class _FakeLocalMatchMediaGateway implements LocalMatchMediaGateway {
  String? readLyricsText;
  String? lastWrittenSongPath;
  String? lastWrittenLyricsText;
  Completer<void>? writeCompleter;
  Exception? writeError;

  @override
  Future<bool> hasLyricsTag(String songPath) async => false;

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    return readLyricsText;
  }

  @override
  Future<List<SongInfo>> readAudioSongInfos(String audioPath) async =>
      <SongInfo>[];

  @override
  Future<int?> readAudioDurationMs(String audioPath) async => null;

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    lastWrittenSongPath = songPath;
    lastWrittenLyricsText = lyricsText;
    final Exception? error = writeError;
    if (error != null) {
      throw error;
    }
    final Completer<void>? completer = writeCompleter;
    if (completer != null) {
      return completer.future;
    }
  }
}

Lyrics _buildLyrics() {
  return Lyrics(
    songInfo: const SongInfo(source: Source.local, title: 'Demo Song'),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 1000,
          words: const <LyricsWord>[
            LyricsWord(startMs: 0, endMs: 1000, text: '原文'),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

LyricsData _translationLines() {
  return <LyricsLine>[
    LyricsLine(
      startMs: 0,
      endMs: 1000,
      words: const <LyricsWord>[
        LyricsWord(startMs: 0, endMs: 1000, text: '译文'),
      ],
    ),
  ];
}

Uint8List _lyricsFileBytes(String text) {
  return Uint8List.fromList(utf8.encode(text));
}

void _setTestViewport(
  WidgetTester tester,
  Size size, {
  double devicePixelRatio = 1,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
