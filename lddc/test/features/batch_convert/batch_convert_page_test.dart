import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_directory_scanner.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_dependencies.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_input_picker.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_overwrite_summary.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_controller.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_state.dart';
import 'package:lddc/src/features/batch_convert/presentation/batch_convert_page.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:lddc/src/shared/ui/components/desktop_page_interaction_scope.dart';
import 'package:path/path.dart' as p;

void main() {
  group('BatchConvertDirectoryScannerImpl', () {
    test('大目录扫描按 chunk 刷新进度，避免每个文件都触发 UI 更新', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'lddc_batch_scan_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      for (int index = 0; index < 5; index += 1) {
        File(
          '${tempDir.path}${Platform.pathSeparator}$index.lrc',
        ).writeAsStringSync('[00:00.00]demo');
      }
      // scanner 必须复用本地歌词统一输入扩展能力，避免批量转换能解析却不能选。
      File(
        '${tempDir.path}${Platform.pathSeparator}subtitle.ssa',
      ).writeAsStringSync('[Script Info]');
      File(
        '${tempDir.path}${Platform.pathSeparator}plain.txt',
      ).writeAsStringSync('[00:00.00]text');
      File(
        '${tempDir.path}${Platform.pathSeparator}ignored.md',
      ).writeAsStringSync('ignored');
      final List<List<String>> chunks = <List<String>>[];
      final List<BatchConvertProgressMessage> progressMessages =
          <BatchConvertProgressMessage>[];
      final BatchConvertDirectoryScanner scanner =
          const BatchConvertDirectoryScannerImpl(chunkSize: 2);

      final BatchConvertDirectoryScanResult result = await scanner.scan(
        rootDirectories: <String>[tempDir.path],
        recursive: false,
        onChunk: chunks.add,
        onProgress:
            (BatchConvertProgressMessage message, int value, int maxValue) {
              progressMessages.add(message);
            },
      );

      expect(result.foundCount, 7);
      expect(chunks.map((List<String> chunk) => chunk.length), <int>[
        2,
        2,
        2,
        1,
      ]);
      expect(
        progressMessages
            .where(
              (BatchConvertProgressMessage message) =>
                  message.code ==
                  BatchConvertProgressMessageCode.scannedLyricsFiles,
            )
            .length,
        4,
      );
    });
  });

  group('BatchConvertPageController', () {
    test('文件导入去重并随目标格式和保存目录重算输出路径', () async {
      final String sourceRoot = p.join('batch_convert', 'lyrics');
      final String saveRoot = p.join('batch_convert', 'exports');
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: <PickedFileHandle>[
          PickedFileHandle(name: 'a.lrc', path: p.join(sourceRoot, 'a.lrc')),
          PickedFileHandle(name: 'b.srt', path: p.join(sourceRoot, 'b.srt')),
        ],
        saveRootDirectory: saveRoot,
      );
      final ProviderContainer container = _createContainer(picker: picker);
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.addFiles();
      controller.updateTargetFormat(LyricsFormat.ass);
      await controller.selectSaveRootDirectory();

      final BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );
      expect(state.queueItems, hasLength(2));
      expect(state.queueItems.first.targetPath, p.join(saveRoot, 'a.ass'));
      expect(state.queueItems.last.targetPath, p.join(saveRoot, 'b.ass'));
    });

    test('目录扫描按分片追加并更新扫描进度', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        directories: const <String>[r'D:\lyrics'],
      );
      final _FakeBatchConvertDirectoryScanner scanner =
          _FakeBatchConvertDirectoryScanner(
            chunks: const <List<String>>[
              <String>[r'D:\lyrics\one.lrc'],
              <String>[r'D:\lyrics\two.srt'],
            ],
          );
      final ProviderContainer container = _createContainer(
        picker: picker,
        scanner: scanner,
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addDirectories();
      final BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );

      expect(state.queueItems, hasLength(2));
      expect(
        state.progressMessage.code,
        BatchConvertProgressMessageCode.scanCompleted,
      );
      expect(
        scanner.progressMessages.map(
          (BatchConvertProgressMessage message) => message.code,
        ),
        contains(BatchConvertProgressMessageCode.scanningDirectory),
      );
      expect(scanner.progressMessages.last.count, 2);
    });

    test('目录扫描销毁后迟到回调不会写入已释放的 controller', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        directories: const <String>[r'D:\lyrics'],
      );
      final Completer<BatchConvertDirectoryScanResult> scanCompleter =
          Completer<BatchConvertDirectoryScanResult>();
      final _FakeBatchConvertDirectoryScanner scanner =
          _FakeBatchConvertDirectoryScanner(scanCompleter: scanCompleter);
      final ProviderContainer container = _createContainer(
        picker: picker,
        scanner: scanner,
      );
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      final Future<void> pendingScan = controller.addDirectories();
      await scanner.started.future;
      expect(
        container.read(batchConvertPageControllerProvider).taskPhase,
        BatchConvertTaskPhase.scanning,
      );

      container.dispose();
      scanner.capturedOnChunk?.call(const <String>[r'D:\lyrics\late.lrc']);
      scanner.capturedOnProgress?.call(
        const BatchConvertProgressMessage(
          code: BatchConvertProgressMessageCode.scannedLyricsFiles,
          count: 1,
        ),
        1,
        1,
      );
      scanCompleter.complete(
        const BatchConvertDirectoryScanResult(
          foundCount: 1,
          cancelled: false,
          errors: <String>[],
        ),
      );

      await pendingScan;
    });

    test('进度事件会驱动行状态和汇总结果', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(name: 'ok.lrc', path: r'D:\lyrics\ok.lrc'),
          PickedFileHandle(name: 'bad.lrc', path: r'D:\lyrics\bad.lrc'),
        ],
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        useCase: _StubBatchConvertUseCase(
          handler:
              ({
                required List<BatchConvertItem> items,
                required LyricsFormat targetFormat,
                LyricsConvertOptions? convertOptions,
                bool allowOverwrite = false,
                BatchConvertCancellationToken? cancellationToken,
                BatchConvertProgressCallback? onProgress,
              }) async {
                onProgress?.call(
                  const BatchConvertProgress(
                    message: BatchConvertProgressMessage(
                      code: BatchConvertProgressMessageCode.convertingFile,
                      detail: 'ok.lrc',
                    ),
                    value: 0,
                    maxValue: 2,
                  ),
                );
                onProgress?.call(
                  const BatchConvertProgress(
                    message: BatchConvertProgressMessage(
                      code: BatchConvertProgressMessageCode.convertingFile,
                      detail: 'bad.lrc',
                    ),
                    value: 1,
                    maxValue: 2,
                    status: BatchConvertStatus(
                      type: BatchConvertStatusType.success,
                      index: 0,
                    ),
                  ),
                );
                onProgress?.call(
                  const BatchConvertProgress(
                    message: BatchConvertProgressMessage.empty(),
                    value: 0,
                    maxValue: 0,
                    status: BatchConvertStatus(
                      type: BatchConvertStatusType.failure,
                      index: 1,
                    ),
                  ),
                );
                return BatchConvertResult(
                  successCount: 1,
                  failureCount: 1,
                  cancelled: false,
                  logs: const <BatchConvertLogEntry>[],
                );
              },
        ),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.startOrCancel();
      final BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );

      expect(state.queueItems[0].status, BatchConvertQueueItemStatus.success);
      expect(state.queueItems[1].status, BatchConvertQueueItemStatus.failure);
      expect(
        state.queueItems[0].shortMessage?.code,
        BatchConvertProgressMessageCode.itemSuccess,
      );
      expect(
        state.queueItems[1].shortMessage?.code,
        BatchConvertProgressMessageCode.itemFailure,
      );
      expect(state.runSummary?.successCount, 1);
      expect(state.runSummary?.failureCount, 1);
      expect(state.showPartialSuccess, isTrue);
    });

    test('取消后迟到的转换进度不会覆盖取消反馈', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(name: 'slow.srt', path: r'D:\lyrics\slow.srt'),
        ],
      );
      BatchConvertProgressCallback? capturedProgress;
      final Completer<void> started = Completer<void>();
      final Completer<BatchConvertResult> completer =
          Completer<BatchConvertResult>();
      final ProviderContainer container = _createContainer(
        picker: picker,
        useCase: _StubBatchConvertUseCase(
          handler:
              ({
                required List<BatchConvertItem> items,
                required LyricsFormat targetFormat,
                LyricsConvertOptions? convertOptions,
                bool allowOverwrite = false,
                BatchConvertCancellationToken? cancellationToken,
                BatchConvertProgressCallback? onProgress,
              }) {
                capturedProgress = onProgress;
                if (!started.isCompleted) {
                  started.complete();
                }
                return completer.future;
              },
        ),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      final Future<void> run = controller.startOrCancel();
      await started.future;
      expect(capturedProgress, isNotNull);
      capturedProgress?.call(
        const BatchConvertProgress(
          message: BatchConvertProgressMessage(
            code: BatchConvertProgressMessageCode.convertingFile,
            detail: 'slow.srt',
          ),
          value: 0,
          maxValue: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(batchConvertPageControllerProvider).progressMessage.code,
        BatchConvertProgressMessageCode.convertingFile,
      );

      await controller.startOrCancel();
      capturedProgress?.call(
        const BatchConvertProgress(
          message: BatchConvertProgressMessage(
            code: BatchConvertProgressMessageCode.convertingFile,
            detail: 'late.srt',
          ),
          value: 0,
          maxValue: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(batchConvertPageControllerProvider).progressMessage.code,
        BatchConvertProgressMessageCode.cancellingConversion,
      );

      completer.complete(
        BatchConvertResult(
          successCount: 0,
          failureCount: 0,
          cancelled: true,
          logs: const <BatchConvertLogEntry>[],
        ),
      );
      await run;
      final BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );
      expect(state.runSummary?.cancelled, isTrue);
      expect(
        state.progressMessage.code,
        BatchConvertProgressMessageCode.conversionCancelled,
      );
    });

    test('启动前发现源文件覆盖时先请求确认，拒绝后不运行', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(name: 'same.lrc', path: r'D:\lyrics\same.lrc'),
        ],
      );
      int runCount = 0;
      BatchConvertOverwriteSummary? capturedSummary;
      final ProviderContainer container = _createContainer(
        picker: picker,
        confirmOverwrite: (BatchConvertOverwriteSummary summary) async {
          capturedSummary = summary;
          return false;
        },
        useCase: _StubBatchConvertUseCase(
          handler:
              ({
                required List<BatchConvertItem> items,
                required LyricsFormat targetFormat,
                LyricsConvertOptions? convertOptions,
                bool allowOverwrite = false,
                BatchConvertCancellationToken? cancellationToken,
                BatchConvertProgressCallback? onProgress,
              }) async {
                runCount += 1;
                return BatchConvertResult(
                  successCount: 1,
                  failureCount: 0,
                  cancelled: false,
                  logs: const <BatchConvertLogEntry>[],
                );
              },
        ),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.startOrCancel();

      expect(runCount, 0);
      expect(capturedSummary?.sourceOverwriteCount, 1);
      expect(
        container.read(batchConvertPageControllerProvider).notice?.code,
        BatchConvertNoticeCode.overwriteCancelled,
      );
    });

    test('覆盖确认通过后允许 usecase 覆盖写入', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(name: 'same.lrc', path: r'D:\lyrics\same.lrc'),
        ],
      );
      bool? capturedAllowOverwrite;
      final ProviderContainer container = _createContainer(
        picker: picker,
        confirmOverwrite: (_) async => true,
        useCase: _StubBatchConvertUseCase(
          handler:
              ({
                required List<BatchConvertItem> items,
                required LyricsFormat targetFormat,
                LyricsConvertOptions? convertOptions,
                bool allowOverwrite = false,
                BatchConvertCancellationToken? cancellationToken,
                BatchConvertProgressCallback? onProgress,
              }) async {
                capturedAllowOverwrite = allowOverwrite;
                return BatchConvertResult(
                  successCount: 1,
                  failureCount: 0,
                  cancelled: false,
                  logs: const <BatchConvertLogEntry>[],
                );
              },
        ),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.startOrCancel();

      expect(capturedAllowOverwrite, isTrue);
      expect(
        container.read(batchConvertPageControllerProvider).runSummary,
        isNotNull,
      );
    });

    test('成功后可切到打开歌词页并载入生成文件', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc_batch_convert_page_',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String source = '${dir.path}\\demo.lrc';
      await File(source).writeAsString('[00:00.00]批量转换测试');

      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: <PickedFileHandle>[
          PickedFileHandle(name: 'demo.lrc', path: source),
        ],
      );
      String? openedLyricsPath;
      final ProviderContainer container = _createContainer(
        picker: picker,
        openInOpenLyrics: (String lyricsPath) async {
          openedLyricsPath = lyricsPath;
        },
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.startOrCancel();
      final BatchConvertPageState batchState = container.read(
        batchConvertPageControllerProvider,
      );
      await controller.openInOpenLyrics(batchState.queueItems.single.id);

      expect(openedLyricsPath, batchState.queueItems.single.targetPath);
    });
  });

  group('BatchConvertPage', () {
    testWidgets('桌面端展示双栏工作台而不是占位页', (WidgetTester tester) async {
      await _setViewport(tester, const Size(1366, 1024));
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('导入与设置'), findsOneWidget);
      expect(find.text('转换队列'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('batch_convert_start_or_cancel')),
        findsOneWidget,
      );
      expect(find.text('还没有转换任务'), findsNothing);
      expect(find.textContaining('这里会显示批量转换队列'), findsOneWidget);
      _expectBatchEmptyStateCentered(tester);
    });

    testWidgets('移动端展示单列布局和底部主操作区', (WidgetTester tester) async {
      await _setViewport(tester, const Size(390, 844));
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('批量转换'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('batch_convert_compact_controls')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('batch_convert_compact_start_or_cancel'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('batch_convert_compact_pick_files')),
        findsOneWidget,
      );
      _expectBatchEmptyStateCentered(tester);
    });

    testWidgets('紧凑布局在支持尺寸和文本缩放下可滚动访问全部控件', (WidgetTester tester) async {
      const List<Size> viewports = <Size>[
        Size(360, 800),
        Size(411, 914),
        Size(844, 390),
        Size(960, 540),
        Size(1008, 567),
        Size(1280, 720),
      ];
      const List<double> textScales = <double>[1, 1.5, 2];

      for (final Size viewport in viewports) {
        for (final double textScale in textScales) {
          await _setViewport(tester, viewport);
          final _FakeBatchConvertInputPicker picker =
              _FakeBatchConvertInputPicker(
                files: const <PickedFileHandle>[
                  PickedFileHandle(name: 'one.lrc', path: r'D:\lyrics\one.lrc'),
                  PickedFileHandle(name: 'two.srt', path: r'D:\lyrics\two.srt'),
                ],
                saveRootDirectory: r'D:\exports',
              );
          final ProviderContainer container = _createContainer(picker: picker);
          await container
              .read(batchConvertPageControllerProvider.notifier)
              .addFiles();
          await container
              .read(batchConvertPageControllerProvider.notifier)
              .selectSaveRootDirectory();

          await tester.pumpWidget(
            _buildTestApp(container, textScaleFactor: textScale),
          );
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            tester.takeException(),
            isNull,
            reason: 'viewport=$viewport textScale=$textScale 折叠态发生布局异常',
          );

          if (viewport.width < 1080) {
            final Finder controlsToggle = find.byKey(
              const ValueKey<String>('batch_convert_compact_controls_toggle'),
            );
            await _scrollUntilHitTestable(tester, target: controlsToggle);
            expect(_targetReceivesHit(tester, controlsToggle), isTrue);
            await tester.tapAt(tester.getCenter(controlsToggle));
            await tester.pump(const Duration(milliseconds: 300));
            final Object? expandedException = tester.takeException();
            expect(
              expandedException,
              isNull,
              reason: 'viewport=$viewport textScale=$textScale 展开态发生布局异常',
            );
            final Finder saveRoot = find.byKey(
              const ValueKey<String>('batch_convert_select_save_root'),
            );
            await Scrollable.ensureVisible(
              tester.element(saveRoot),
              alignment: 0.5,
              duration: Duration.zero,
            );
            await _scrollUntilHitTestable(tester, target: saveRoot);
            expect(
              _targetReceivesHit(tester, saveRoot),
              isTrue,
              reason: 'viewport=$viewport textScale=$textScale 保存目录按钮不可点击',
            );
            await tester.tapAt(tester.getCenter(saveRoot));
            await tester.pump(const Duration(milliseconds: 120));
            expect(picker.saveRootPickCount, 2);
          }

          container.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });

    testWidgets('输出路径摘要使用最小化中间省略并保留完整 Tooltip', (WidgetTester tester) async {
      await _setViewport(tester, const Size(1366, 1024));
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(
            name: 'demo_song_that_has_a_very_long_name.lrc',
            path:
                r'D:\lyrics\very\long\source\path\with\many\segments\artist\album\disc1\demo_song_that_has_a_very_long_name.lrc',
          ),
        ],
        saveRootDirectory:
            r'D:\exports\very\long\target\root\with\many\segments\artist\album\disc1',
      );
      final ProviderContainer container = _createContainer(picker: picker);
      addTearDown(container.dispose);
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .addFiles();
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .selectSaveRootDirectory();
      final String targetPath = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .single
          .targetPath;

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      expect(find.text(targetPath), findsNothing);
      expect(find.text('输出路径'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is Tooltip && widget.message == targetPath,
        ),
        findsOneWidget,
      );
    });

    testWidgets('桌面快捷键会触发导入、打开、启动与清空选中', (WidgetTester tester) async {
      await _setViewport(tester, const Size(1366, 1024));
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(name: 'demo.lrc', path: r'D:\lyrics\demo.lrc'),
        ],
        directories: const <String>[r'D:\lyrics'],
      );
      int runCount = 0;
      final ProviderContainer container = _createContainer(
        picker: picker,
        useCase: _StubBatchConvertUseCase(
          handler:
              ({
                required List<BatchConvertItem> items,
                required LyricsFormat targetFormat,
                LyricsConvertOptions? convertOptions,
                bool allowOverwrite = false,
                BatchConvertCancellationToken? cancellationToken,
                BatchConvertProgressCallback? onProgress,
              }) async {
                runCount += 1;
                return BatchConvertResult(
                  successCount: 0,
                  failureCount: 0,
                  cancelled: false,
                  logs: const <BatchConvertLogEntry>[],
                );
              },
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.keyO, control: true),
      );
      expect(picker.filePickCount, 1);
      await _invokeShortcut(
        tester,
        const SingleActivator(
          LogicalKeyboardKey.keyO,
          control: true,
          shift: true,
        ),
      );
      expect(picker.directoryPickCount, 1);

      final String itemId = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .single
          .id;

      await tester.tap(
        find.byKey(ValueKey<String>('batch_convert_queue_row_$itemId')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(batchConvertPageControllerProvider).selectedItemId,
        itemId,
      );
      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.escape),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(batchConvertPageControllerProvider).selectedItemId,
        isNull,
      );
      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.enter),
      );
      await tester.pumpAndSettle();
      expect(runCount, 1);

      await tester.tap(
        find.byKey(ValueKey<String>('batch_convert_queue_row_$itemId')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(batchConvertPageControllerProvider).selectedItemId,
        itemId,
      );
      await _invokeShortcut(
        tester,
        const SingleActivator(LogicalKeyboardKey.delete),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(batchConvertPageControllerProvider).queueItems,
        isEmpty,
      );
      expect(
        container.read(batchConvertPageControllerProvider).selectedItemId,
        isNull,
      );
    });
  });
}

ProviderContainer _createContainer({
  _FakeBatchConvertInputPicker? picker,
  _FakeBatchConvertDirectoryScanner? scanner,
  BatchConvertUseCase? useCase,
  AppPathOpener? pathOpener,
  Future<void> Function(String lyricsPath)? openInOpenLyrics,
  Future<bool> Function(BatchConvertOverwriteSummary summary)? confirmOverwrite,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    ConfigDefaults.current,
  );
  final _FakeBatchConvertInputPicker resolvedPicker =
      picker ?? _FakeBatchConvertInputPicker();
  final BatchConvertUseCase resolvedUseCase =
      useCase ?? BatchConvertUseCase(localProvider: _FakeLocalLyricsProvider());
  final AppPathOpener resolvedPathOpener = pathOpener ?? _FakePathOpener();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => _desktopCapability()),
      configRepositoryProvider.overrideWithValue(repository),
      batchConvertDependenciesProvider.overrideWithValue(
        BatchConvertDependencies(
          capability: _desktopCapability(),
          configRepository: repository,
          inputPicker: resolvedPicker,
          useCase: resolvedUseCase,
          pathOpener: resolvedPathOpener,
          dragDropPort: const DragDropPortImpl(),
          openInOpenLyrics: openInOpenLyrics ?? (_) async {},
          confirmOverwrite: confirmOverwrite ?? (_) async => true,
        ),
      ),
      batchConvertDirectoryScannerProvider.overrideWithValue(
        scanner ?? _FakeBatchConvertDirectoryScanner(),
      ),
      batchConvertUseCaseProvider.overrideWithValue(resolvedUseCase),
      appPathOpenerProvider.overrideWithValue(resolvedPathOpener),
    ],
  );
}

Widget _buildTestApp(
  ProviderContainer container, {
  Locale locale = const Locale('zh'),
  double textScaleFactor = 1,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
        child: child!,
      ),
      home: const Scaffold(body: BatchConvertPage()),
    ),
  );
}

void _expectBatchEmptyStateCentered(WidgetTester tester) {
  final Finder center = find.byKey(
    const ValueKey<String>('batch_convert_queue_empty_center'),
  );
  final Finder emptyCard = find.descendant(
    of: center,
    matching: find.byType(Card),
  );
  expect(center, findsOneWidget);
  expect(emptyCard, findsOneWidget);
  expect(
    (tester.getCenter(center) - tester.getCenter(emptyCard)).distance,
    lessThan(1),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
}

Future<void> _scrollUntilHitTestable(
  WidgetTester tester, {
  required Finder target,
}) async {
  final Element targetElement = tester.element(target);
  Element? scrollableElement;
  targetElement.visitAncestorElements((Element ancestor) {
    if (ancestor.widget is Scrollable) {
      scrollableElement = ancestor;
      return false;
    }
    return true;
  });
  final Element? resolvedScrollable = scrollableElement;
  if (resolvedScrollable == null) {
    return;
  }
  final Finder scrollable = find.byElementPredicate(
    (Element element) => identical(element, resolvedScrollable),
  );
  for (int attempt = 0; attempt < 20; attempt += 1) {
    if (_targetReceivesHit(tester, target)) {
      return;
    }
    final Rect targetRect = tester.getRect(target);
    final Rect viewportRect = tester.getRect(scrollable);
    final ScrollPosition position = tester
        .state<ScrollableState>(scrollable)
        .position;
    final double nextOffset =
        (position.pixels + targetRect.center.dy - viewportRect.center.dy).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    if ((nextOffset - position.pixels).abs() < 0.5) {
      return;
    }
    position.jumpTo(nextOffset);
    await tester.pump(const Duration(milliseconds: 120));
  }
}

bool _targetReceivesHit(WidgetTester tester, Finder target) {
  if (target.evaluate().length != 1) {
    return false;
  }
  final Set<RenderObject> targetRenderObjects = <RenderObject>{};
  void collectRenderObjects(Element element) {
    final RenderObject? renderObject = element.renderObject;
    if (renderObject != null) {
      targetRenderObjects.add(renderObject);
    }
    element.visitChildElements(collectRenderObjects);
  }

  collectRenderObjects(tester.element(target));
  final HitTestResult result = tester.hitTestOnBinding(
    tester.getCenter(target),
  );
  for (final HitTestEntry entry in result.path) {
    final Object hitTarget = entry.target;
    if (hitTarget is! RenderObject) {
      continue;
    }
    if (targetRenderObjects.contains(hitTarget)) {
      return true;
    }
    for (final RenderObject targetRenderObject in targetRenderObjects) {
      RenderObject? current = targetRenderObject.parent;
      while (current != null) {
        if (identical(current, hitTarget)) {
          return true;
        }
        current = current.parent;
      }
    }
  }
  return false;
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
  Future<AppConfig> update(Map<String, Object?> values) async => _config;

  @override
  Stream<AppConfig> watch({bool emitCurrent = true}) async* {
    if (emitCurrent) {
      yield _config;
    }
  }
}

class _FakeBatchConvertInputPicker implements BatchConvertInputPicker {
  _FakeBatchConvertInputPicker({
    List<PickedFileHandle>? files,
    List<String>? directories,
    this.saveRootDirectory,
  }) : _files = files ?? const <PickedFileHandle>[],
       _directories = directories ?? const <String>[];

  final List<PickedFileHandle> _files;
  final List<String> _directories;
  final String? saveRootDirectory;
  int filePickCount = 0;
  int directoryPickCount = 0;
  int saveRootPickCount = 0;

  @override
  Future<List<PickedFileHandle>> pickLyricsFiles({
    String? initialDirectory,
  }) async {
    filePickCount += 1;
    return _files;
  }

  @override
  Future<List<String>> pickLyricsDirectories({String? initialDirectory}) async {
    directoryPickCount += 1;
    return _directories;
  }

  @override
  Future<String?> pickSaveRootDirectory({String? initialDirectory}) async {
    saveRootPickCount += 1;
    return saveRootDirectory;
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

class _FakeBatchConvertDirectoryScanner
    implements BatchConvertDirectoryScanner {
  _FakeBatchConvertDirectoryScanner({
    List<List<String>>? chunks,
    this.scanCompleter,
  }) : _chunks = chunks ?? const <List<String>>[];

  final List<List<String>> _chunks;
  final Completer<BatchConvertDirectoryScanResult>? scanCompleter;
  final List<BatchConvertProgressMessage> progressMessages =
      <BatchConvertProgressMessage>[];
  final Completer<void> started = Completer<void>();
  void Function(List<String> sourcePaths)? capturedOnChunk;
  void Function(BatchConvertProgressMessage message, int value, int maxValue)?
  capturedOnProgress;
  bool Function()? capturedShouldCancel;

  @override
  Future<BatchConvertDirectoryScanResult> scan({
    required List<String> rootDirectories,
    required bool recursive,
    required void Function(List<String> sourcePaths) onChunk,
    required void Function(
      BatchConvertProgressMessage message,
      int value,
      int maxValue,
    )
    onProgress,
    bool Function()? shouldCancel,
  }) async {
    capturedOnChunk = onChunk;
    capturedOnProgress = onProgress;
    capturedShouldCancel = shouldCancel;
    if (!started.isCompleted) {
      started.complete();
    }
    final Completer<BatchConvertDirectoryScanResult>? completer = scanCompleter;
    if (completer != null) {
      return completer.future;
    }
    final BatchConvertProgressMessage initialMessage =
        const BatchConvertProgressMessage(
          code: BatchConvertProgressMessageCode.scanningDirectory,
          detail: 'lyrics',
        );
    progressMessages.add(initialMessage);
    onProgress(initialMessage, 0, 0);
    int count = 0;
    for (final List<String> chunk in _chunks) {
      if (shouldCancel?.call() ?? false) {
        return BatchConvertDirectoryScanResult(
          foundCount: count,
          cancelled: true,
          errors: const <String>[],
        );
      }
      count += chunk.length;
      onChunk(chunk);
      final BatchConvertProgressMessage message = BatchConvertProgressMessage(
        code: BatchConvertProgressMessageCode.scannedLyricsFiles,
        count: count,
      );
      progressMessages.add(message);
      onProgress(message, count, 0);
    }
    return BatchConvertDirectoryScanResult(
      foundCount: count,
      cancelled: false,
      errors: const <String>[],
    );
  }
}

class _FakeLocalLyricsProvider implements LyricsLocalSourceProvider {
  @override
  Future<Lyrics> getLyrics(LocalLyricsRequest request) {
    throw UnsupportedError('测试场景未配置 JSON/QRC/KRC 本地歌词解析');
  }
}

class _StubBatchConvertUseCase extends BatchConvertUseCase {
  _StubBatchConvertUseCase({required this.handler})
    : super(localProvider: _NoopLocalLyricsProvider());

  final Future<BatchConvertResult> Function({
    required List<BatchConvertItem> items,
    required LyricsFormat targetFormat,
    LyricsConvertOptions? convertOptions,
    bool allowOverwrite,
    BatchConvertCancellationToken? cancellationToken,
    BatchConvertProgressCallback? onProgress,
  })
  handler;

  @override
  Future<BatchConvertResult> run({
    required List<BatchConvertItem> items,
    required LyricsFormat targetFormat,
    LyricsConvertOptions? convertOptions,
    bool allowOverwrite = false,
    BatchConvertCancellationToken? cancellationToken,
    BatchConvertProgressCallback? onProgress,
  }) {
    return handler(
      items: items,
      targetFormat: targetFormat,
      convertOptions: convertOptions,
      allowOverwrite: allowOverwrite,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
  }
}

class _NoopLocalLyricsProvider implements LyricsLocalSourceProvider {
  @override
  Future<Lyrics> getLyrics(LocalLyricsRequest request) {
    throw UnsupportedError('测试场景不读取本地歌词');
  }
}

class _FakePathOpener implements AppPathOpener {
  final List<String> openedFiles = <String>[];
  final List<String> openedDirectories = <String>[];

  @override
  Future<void> openDirectory(String path) async {
    openedDirectories.add(path);
  }

  @override
  Future<void> openFile(String path) async {
    openedFiles.add(path);
  }
}
