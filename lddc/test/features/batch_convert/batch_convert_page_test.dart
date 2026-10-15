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

/// 安卓端批量转换使用的授权树与树内文档（形态与 DocumentsUI 返回一致）。
const String _safTreeUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic';
const String _safLyricsUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fa.lrc';

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
      expect(
        _localTargetPathOf(state.queueItems.first),
        p.join(saveRoot, 'a.ass'),
      );
      expect(
        _localTargetPathOf(state.queueItems.last),
        p.join(saveRoot, 'b.ass'),
      );
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
      // 确认清单必须完整：这里断言清单与队列条目的落点文本一一对应（不依赖平台
      // 路径分隔符），旧实现只给最多 5 条"示例路径"，第一个条目之后就可能被截断。
      final BatchConvertQueueItem queuedItem = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .single;
      expect(capturedSummary?.overwritePaths, <String>[
        queuedItem.targetDisplayPath,
      ]);
      expect(capturedSummary?.overwritePaths.single, endsWith('same.lrc'));
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

    test('超过 5 个覆盖目标时确认清单一条不漏', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc_batch_convert_overwrite_',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final List<PickedFileHandle> pickedFiles = <PickedFileHandle>[];
      for (int index = 1; index <= 8; index += 1) {
        final String source = p.join(dir.path, 's$index.lrc');
        await File(source).writeAsString('[00:00.00]覆盖清单');
        // 目标格式改成 srt 后，同名 .srt 已经存在：每条都走"覆盖已存在目标"分支。
        await File(
          p.join(dir.path, 's$index.srt'),
        ).writeAsString('1\n00:00:00,000 --> 00:00:01,000\n覆盖清单');
        pickedFiles.add(
          PickedFileHandle(name: p.basename(source), path: source),
        );
      }

      BatchConvertOverwriteSummary? capturedSummary;
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(files: pickedFiles),
        confirmOverwrite: (BatchConvertOverwriteSummary summary) async {
          capturedSummary = summary;
          return false;
        },
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      controller.updateTargetFormat(LyricsFormat.srt);
      await controller.startOrCancel();

      final BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );
      // 旧实现最多只取 5 条示例路径；现在 8 条都要在清单里，顺序与队列一致。
      expect(capturedSummary?.existingTargetCount, 8);
      expect(state.queueItems, hasLength(8));
      expect(capturedSummary?.overwritePaths, <String>[
        for (final BatchConvertQueueItem item in state.queueItems)
          item.targetDisplayPath,
      ]);
      expect(capturedSummary?.overwritePaths.last, endsWith('s8.srt'));
    });

    test('多条条目写同一目标时清单按目标去重', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc_batch_convert_duplicate_target_',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String saveRoot = p.join(dir.path, 'out');
      final List<PickedFileHandle> pickedFiles = <PickedFileHandle>[];
      for (final String folder in <String>['left', 'right']) {
        final String source = p.join(dir.path, folder, 'song.lrc');
        // 先建子目录：两个源分处不同目录、却会规划到同一个目标，本用例要的就是这种重复。
        await Directory(p.dirname(source)).create(recursive: true);
        await File(source).writeAsString('[00:00.00]$folder');
        pickedFiles.add(PickedFileHandle(name: 'song.lrc', path: source));
      }

      BatchConvertOverwriteSummary? capturedSummary;
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(
          files: pickedFiles,
          saveRootDirectory: saveRoot,
        ),
        confirmOverwrite: (BatchConvertOverwriteSummary summary) async {
          capturedSummary = summary;
          return false;
        },
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.selectSaveRootDirectory();
      controller.updateTargetFormat(LyricsFormat.srt);
      await controller.startOrCancel();

      // 两个条目落到同一个目标：算一组重复目标，清单里只占一行（目标是同一个文件，
      // 展示两行完全相同的路径只会让用户误以为会有两次写入）。
      expect(capturedSummary?.duplicateTargetGroupCount, 1);
      expect(capturedSummary?.existingTargetCount, 0);
      expect(capturedSummary?.sourceOverwriteCount, 0);
      final BatchConvertQueueItem firstItem = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .first;
      expect(capturedSummary?.overwritePaths, <String>[
        firstItem.targetDisplayPath,
      ]);
      expect(capturedSummary?.overwritePaths.single, endsWith('song.srt'));
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

      expect(
        openedLyricsPath,
        _localTargetPathOf(batchState.queueItems.single),
      );
    });

    test('安卓端取消 SAF 保存树选择时保持原保存根', () async {
      final _FakeBatchConvertInputPicker picker =
          _FakeBatchConvertInputPicker();
      final ProviderContainer container = _createContainer(
        picker: picker,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      // `saveTree` 为 null 表示用户在系统选择器里取消：既不能写入保存根，也不能
      // 当成失败弹出错误提示。
      await controller.selectSaveRootDirectory();

      final BatchConvertPageState state = _readState(container);
      expect(state.saveRoot, isNull);
      expect(state.notice, isNull);
      // 安卓端不会回落到本地目录选择器：SAF 保存树入口必须被走到。
      expect(picker.saveRootPickCount, 1);
    });

    test('安卓端选定 SAF 保存树后整条队列的落点重算到该树', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(
            name: 'demo.lrc',
            path: '/data/user/0/com.cmzj.lddc/cache/picked/demo.lrc',
          ),
        ],
        saveTree: (treeUri: _safTreeUri, treeLabel: '内部存储'),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      await controller.selectSaveRootDirectory();

      final BatchConvertPageState state = _readState(container);
      expect(state.saveRoot?.treeUri, _safTreeUri);
      expect(state.saveRoot?.displayLabel, '内部存储');
      // 插件缓存副本没有树内层级：平铺写到授权树根，落点是可读文本而不是缓存路径。
      expect(state.queueItems.single.target, isA<SafDocumentTarget>());
      expect(state.queueItems.single.targetDisplayPath, '内部存储/demo.lrc');
      expect(picker.saveRootPickCount, 1);
    });

    test('保存根为空时清空保存目录不产生任何副作用', () async {
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      controller.clearSaveRootDirectory();

      final BatchConvertPageState state = _readState(container);
      expect(state.saveRoot, isNull);
      expect(state.notice, isNull);
    });

    test('队列中存在 SAF 文档源时拒绝清空保存目录并给出提示', () async {
      final _SafFixture fixture = _createSafImportedContainer();
      addTearDown(fixture.container.dispose);
      final BatchConvertPageController controller = fixture.container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addDirectories();
      controller.clearSaveRootDirectory();

      final BatchConvertPageState state = _readState(fixture.container);
      // 树内源不存在"源文件旁边的本地目录"：保存根一清空，落点规划会直接抛
      // ArgumentError，这里必须提前拒绝并保留保存根。
      expect(state.saveRoot?.treeUri, _safTreeUri);
      expect(state.notice?.code, BatchConvertNoticeCode.unsupportedOperation);
      expect(state.notice?.detail, '队列中存在 SAF 文档源，必须保留保存目录');
      expect(state.queueItems, hasLength(1));
    });

    test('SAF 源与 SAF 目标不会交给本地路径打开与文件管理器', () async {
      String? openedLyricsPath;
      final _SafFixture fixture = _createSafImportedContainer(
        openInOpenLyrics: (String lyricsPath) async {
          openedLyricsPath = lyricsPath;
        },
      );
      addTearDown(fixture.container.dispose);
      final BatchConvertPageController controller = fixture.container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addDirectories();
      final String itemId = _readState(fixture.container).queueItems.single.id;

      await controller.openSourceDirectory(itemId);
      expect(
        _readState(fixture.container).notice?.detail,
        'SAF 文档源暂时无法在文件管理器中定位',
      );

      await controller.openSaveDirectory(itemId);
      expect(
        _readState(fixture.container).notice?.detail,
        'SAF 保存位置暂时无法在文件管理器中打开',
      );

      await controller.openOutputFile(itemId);
      expect(_readState(fixture.container).notice?.detail, 'SAF 文档暂时无法用外部应用打开');

      await controller.openInOpenLyrics(itemId);
      expect(
        _readState(fixture.container).notice?.detail,
        'SAF 文档暂时无法在打开歌词页载入',
      );

      // `content://` 既不能交给 dart:io，也不能交给路径打开器。
      expect(fixture.pathOpener.openedDirectories, isEmpty);
      expect(fixture.pathOpener.openedFiles, isEmpty);
      expect(openedLyricsPath, isNull);
    });

    test('本地目标已存在时用系统默认应用打开输出文件', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc_batch_convert_open_output_',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });
      final String source = '${dir.path}${Platform.pathSeparator}demo.lrc';
      await File(source).writeAsString('[00:00.00]打开输出文件');
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: <PickedFileHandle>[
          PickedFileHandle(name: 'demo.lrc', path: source),
        ],
      );
      final _FakePathOpener pathOpener = _FakePathOpener();
      final ProviderContainer container = _createContainer(
        picker: picker,
        pathOpener: pathOpener,
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addFiles();
      // 未选保存根时目标就是源文件旁边的新文件；源码里写入后它确实存在，
      // 因此这里必须走到路径打开器（而不是"文件不存在"提示）。
      final BatchConvertQueueItem item = _readState(
        container,
      ).queueItems.single;
      await controller.openOutputFile(item.id);

      expect(pathOpener.openedFiles, <String>[_localTargetPathOf(item)]);
      // 导入本身会留下"已导入"提示，成功打开不会再改写它；这里只要求不是
      // "输出文件不可用"——那才是走了失败分支的证据。
      expect(
        _readState(container).notice?.code,
        isNot(BatchConvertNoticeCode.outputFileUnavailable),
      );
    });

    test('打开已不存在的条目时静默返回，不打开任何路径', () async {
      final _FakePathOpener pathOpener = _FakePathOpener();
      final ProviderContainer container = _createContainer(
        picker: _FakeBatchConvertInputPicker(),
        pathOpener: pathOpener,
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      // 条目可能已被删除：`_findItem` 找不到时必须直接返回，不能抛异常。
      await controller.openSourceDirectory('missing-item');
      await controller.openSaveDirectory('missing-item');
      await controller.openOutputFile('missing-item');
      await controller.openInOpenLyrics('missing-item');

      expect(_readState(container).notice, isNull);
      expect(pathOpener.openedDirectories, isEmpty);
      expect(pathOpener.openedFiles, isEmpty);
    });

    test('SAF 扫描过程中的进度映射到页面扫描状态', () async {
      final _PausedPagingAndroidSafTreePort treePort =
          _PausedPagingAndroidSafTreePort(
            childrenByUri: <String, List<AndroidSafTreeEntry>>{
              _safTreeUri: const <AndroidSafTreeEntry>[
                AndroidSafTreeEntry(
                  uri: _safLyricsUri,
                  displayName: 'a.lrc',
                  mimeType: 'application/octet-stream',
                  isDirectory: false,
                  isFile: true,
                ),
              ],
            },
          );
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        importTree: (treeUri: _safTreeUri, treeLabel: '内部存储'),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        safTreePort: treePort,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      final Future<void> pendingScan = controller.addDirectories();
      // 续页被挂起：此时第一页已经交付过进度，页面必须停在 scanning 状态。
      await treePort.secondPageStarted.future;

      BatchConvertPageState state = _readState(container);
      expect(state.taskPhase, BatchConvertTaskPhase.scanning);
      expect(state.progressCurrent, 1);
      // SAF 枚举前不知道总数，固定用 0 表示"进度不确定"。
      expect(state.progressTotal, 0);
      expect(
        state.progressMessage.code,
        BatchConvertProgressMessageCode.scanningDirectory,
      );
      expect(state.progressMessage.detail, '内部存储');

      treePort.releaseSecondPage.complete();
      await pendingScan;

      state = _readState(container);
      expect(state.taskPhase, BatchConvertTaskPhase.completed);
      expect(
        state.progressMessage.code,
        BatchConvertProgressMessageCode.scanCompleted,
      );
      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.id, _safLyricsUri);
    });

    test('SAF 扫描遇到无法推导落点的文档时给出页面错误', () async {
      // 端口返回了别的授权树里的文档（异常 provider）：落点无法推导属于"会写错位置"，
      // 必须变成可解释的页面错误，而不是把 ArgumentError 泄漏到按钮回调。
      const String foreignLyricsUri =
          'content://com.android.externalstorage.documents/tree/primary%3ADownload/document/primary%3ADownload%2Fb.lrc';
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          _safTreeUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: foreignLyricsUri,
              displayName: 'b.lrc',
              mimeType: 'application/octet-stream',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
      );
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        importTree: (treeUri: _safTreeUri, treeLabel: '内部存储'),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        safTreePort: treePort,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      await controller.addDirectories();

      final BatchConvertPageState state = _readState(container);
      expect(state.errorMessage, startsWith('导入 SAF 目录失败'));
      expect(state.notice?.code, BatchConvertNoticeCode.pageError);
      expect(state.queueItems, isEmpty);
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

      // 壳层 AppBar 已经渲染路由标题，页面体内不再重复渲染第二个「批量转换」。
      expect(find.text('批量转换'), findsNothing);
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
      final BatchConvertQueueItem item = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .single;
      final String targetPath = item.targetDisplayPath;

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

    testWidgets('移动端队列行展示可读落点而不是缓存路径或 SAF 树 URI', (WidgetTester tester) async {
      await _setViewport(tester, const Size(420, 900));
      const String treeUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic';
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        files: const <PickedFileHandle>[
          PickedFileHandle(
            name: 'demo.lrc',
            path: '/data/user/0/com.cmzj.lddc/cache/picked/demo.lrc',
          ),
        ],
        saveTree: (treeUri: treeUri, treeLabel: '内部存储'),
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .addFiles();
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .selectSaveRootDirectory();
      final BatchConvertQueueItem item = container
          .read(batchConvertPageControllerProvider)
          .queueItems
          .single;

      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      // 落点由运行时规划器给出可读文本：SAF 目标是"树名 / 文件名"，既不是插件缓存
      // 全路径，也不是 `content://` 树 URI；保存根同样只暴露树显示名。
      expect(item.targetDisplayPath, '内部存储/demo.lrc');
      expect(
        container
            .read(batchConvertPageControllerProvider)
            .saveRoot
            ?.displayLabel,
        '内部存储',
      );
      expect(find.text('输出路径'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Tooltip && widget.message == item.targetDisplayPath,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('content://'), findsNothing);
      expect(find.textContaining('/data/user/0/'), findsNothing);
    });

    test('安卓端不支持目录选择时给出提示而不是泄漏异常', () async {
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        unsupportedDirectoryPick: true,
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      final BatchConvertPageController controller = container.read(
        batchConvertPageControllerProvider.notifier,
      );

      // UnsupportedError 属于 Error，此前只声明了 `on Exception`：安卓端
      // "导入文件夹"与"选择保存目录"两个入口的异常都会直接泄漏，表现为按钮无反应。
      await controller.addDirectories();
      expect(
        container.read(batchConvertPageControllerProvider).notice?.code,
        BatchConvertNoticeCode.unsupportedOperation,
      );

      await controller.selectSaveRootDirectory();
      expect(
        container.read(batchConvertPageControllerProvider).notice?.code,
        BatchConvertNoticeCode.unsupportedOperation,
      );
    });

    testWidgets('安卓端导入文件夹读取 SAF 树并复用同一棵树作为保存根', (WidgetTester tester) async {
      const String treeUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic';
      const String albumUri = 'content://doc/album-dir';
      const String topLyricsUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fa.lrc';
      const String nestedLyricsUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2Fb.lrc';
      const String nestedAudioUri =
          'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2Fb.flac';
      final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
        importTree: (treeUri: treeUri, treeLabel: '内部存储'),
      );
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          treeUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: topLyricsUri,
              displayName: 'a.lrc',
              mimeType: 'application/octet-stream',
              isDirectory: false,
              isFile: true,
            ),
            AndroidSafTreeEntry(
              uri: albumUri,
              displayName: 'Album',
              mimeType: 'vnd.android.document/directory',
              isDirectory: true,
              isFile: false,
            ),
          ],
          albumUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: nestedLyricsUri,
              displayName: 'b.lrc',
              mimeType: 'application/octet-stream',
              isDirectory: false,
              isFile: true,
            ),
            AndroidSafTreeEntry(
              uri: nestedAudioUri,
              displayName: 'b.flac',
              mimeType: 'audio/flac',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
      );
      final ProviderContainer container = _createContainer(
        picker: picker,
        safTreePort: treePort,
        capability: _mobileCapability(),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_buildTestApp(container));
      await tester.pumpAndSettle();

      // 默认非递归：只导入树根的直接子项（音频与子目录被过滤）。
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .addDirectories();
      // 导入后需要重建组件树，否则下面按落点文本做的 widget 断言仍看旧状态。
      await tester.pumpAndSettle();
      BatchConvertPageState state = container.read(
        batchConvertPageControllerProvider,
      );

      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.source, isA<SafDocumentSource>());
      expect(state.queueItems.single.id, topLyricsUri);
      expect(state.queueItems.single.fileName, 'a.lrc');
      // 导入树顺手成为保存根：SAF 源必须有树内落点，否则落点规划会直接抛异常。
      expect(state.saveRoot?.treeUri, treeUri);
      expect(state.saveRoot?.displayLabel, '内部存储');
      // 落点必须是可读文本：既不是缓存路径，也不是 `content://` URI。
      expect(state.queueItems.single.targetDisplayPath, '内部存储/a.lrc');
      // 行内文本会被中间省略，完整落点以 Tooltip 呈现（与既有输出路径用例同款断言）。
      expect(
        find.byWidgetPredicate(
          (Widget widget) =>
              widget is Tooltip && widget.message == '内部存储/a.lrc',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('content://'), findsNothing);

      // 递归模式：子目录里的歌词按相对层级镜像落点。
      container
          .read(batchConvertPageControllerProvider.notifier)
          .toggleRecursive(true);
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .addDirectories();
      state = container.read(batchConvertPageControllerProvider);
      expect(state.queueItems, hasLength(2));
      expect(state.queueItems.last.id, nestedLyricsUri);
      // 目标落点由保存目标模型（`AndroidSafSaveTarget.displayPathFor`）拼出：树名与
      // 每一级目录都用 `/` 连接，所以子目录里的条目是 `内部存储/Album/b.lrc`。
      expect(state.queueItems.last.targetDisplayPath, '内部存储/Album/b.lrc');

      // 再次导入同一棵树：按文档 URI 去重，不会重复入队。
      await container
          .read(batchConvertPageControllerProvider.notifier)
          .addDirectories();
      expect(
        container.read(batchConvertPageControllerProvider).queueItems,
        hasLength(2),
      );
      // 安卓端不会回落到本地目录选择器，导入只走 SAF 树端口。
      expect(picker.directoryPickCount, 0);
      expect(picker.importTreePickCount, 3);
      expect(treePort.listChildrenPageCalls, greaterThan(0));
      expect(
        state.progressMessage.code,
        BatchConvertProgressMessageCode.scanCompleted,
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
  AndroidSafTreePort? safTreePort,
  BatchConvertUseCase? useCase,
  AppPathOpener? pathOpener,
  AppCapability? capability,
  Future<void> Function(String lyricsPath)? openInOpenLyrics,
  Future<bool> Function(BatchConvertOverwriteSummary summary)? confirmOverwrite,
}) {
  final _FixedConfigRepository repository = _FixedConfigRepository(
    ConfigDefaults.current,
  );
  final AppCapability resolvedCapability = capability ?? _desktopCapability();
  final _FakeBatchConvertInputPicker resolvedPicker =
      picker ?? _FakeBatchConvertInputPicker();
  final BatchConvertUseCase resolvedUseCase =
      useCase ?? BatchConvertUseCase(localProvider: _FakeLocalLyricsProvider());
  final AppPathOpener resolvedPathOpener = pathOpener ?? _FakePathOpener();
  // 安卓端"导入文件夹"走真实扫描用例 + 内存 fake 树端口：这样可以断言用法与
  // MethodChannel 完全解耦，测试环境永远不会弹出系统目录选择器。
  final AndroidSafTreePort resolvedSafTreePort =
      safTreePort ?? _ThrowingAndroidSafTreePort();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => resolvedCapability),
      configRepositoryProvider.overrideWithValue(repository),
      batchConvertDependenciesProvider.overrideWithValue(
        BatchConvertDependencies(
          capability: resolvedCapability,
          configRepository: repository,
          inputPicker: resolvedPicker,
          useCase: resolvedUseCase,
          androidLyricsScanUseCase: AndroidSafLyricsScanUseCase(
            treePort: resolvedSafTreePort,
          ),
          // 单测全部走本地源与本地目标，直接用默认本地 IO 即可。
          fileIo: const DefaultBatchConvertFileIo(),
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

/// 取出本地目标的实际写入路径。
///
/// 队列条目持有的是类型化目标（本地或 SAF），断言本地落点时统一走这里，
/// 避免测试直接依赖可读文本。
String _localTargetPathOf(BatchConvertQueueItem item) =>
    (item.target as LocalFileTarget).path;

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

/// 安卓手机形态：桌面专属能力关闭，线程/SAF 能力开启。
AppCapability _mobileCapability() {
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
    this.saveTree,
    this.importTree,
    this.unsupportedDirectoryPick = false,
  }) : _files = files ?? const <PickedFileHandle>[],
       _directories = directories ?? const <String>[];

  final List<PickedFileHandle> _files;
  final List<String> _directories;
  final String? saveRootDirectory;

  /// 模拟安卓端 SAF 保存树选择结果；为 null 表示用户取消。
  final PickedBatchConvertSaveTree? saveTree;

  /// 模拟安卓端 SAF 导入树选择结果；为 null 表示用户取消。
  final PickedBatchConvertImportTree? importTree;

  /// 模拟安卓端 `AppFilePicker.pickDirectory` 的能力缺失（抛 `UnsupportedError`）。
  final bool unsupportedDirectoryPick;
  int filePickCount = 0;
  int directoryPickCount = 0;
  int saveRootPickCount = 0;
  int importTreePickCount = 0;

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
    if (unsupportedDirectoryPick) {
      throw UnsupportedError('当前平台不支持目录选择');
    }
    return _directories;
  }

  @override
  Future<String?> pickSaveRootDirectory({String? initialDirectory}) async {
    saveRootPickCount += 1;
    if (unsupportedDirectoryPick) {
      throw UnsupportedError('当前平台不支持目录选择');
    }
    return saveRootDirectory;
  }

  @override
  Future<PickedBatchConvertSaveTree?> pickSaveTree({String? initialUri}) async {
    saveRootPickCount += 1;
    if (unsupportedDirectoryPick) {
      throw UnsupportedError('当前平台不支持目录选择');
    }
    return saveTree;
  }

  @override
  Future<PickedBatchConvertImportTree?> pickImportTree({
    String? initialUri,
  }) async {
    importTreePickCount += 1;
    if (unsupportedDirectoryPick) {
      throw UnsupportedError('当前平台不支持目录选择');
    }
    return importTree;
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

/// 内存 SAF 目录树：只按 `listChildrenPage` 的契约分页返回，不触碰平台通道。
class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  _FakeAndroidSafTreePort({required this.childrenByUri});

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;

  /// 每次分页只返回 1 条：强制走 `nextOffset` 续页分支。
  ///
  /// 真实端口对同一 limit 每次返回一致页大小，所以这里固定 1 条，不按 limit 收缩；
  /// 否则续页会把剩余条目一次性返回，扫描的分页分支就验证不到。
  static const int _pageSize = 1;
  int listChildrenPageCalls = 0;

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    listChildrenPageCalls += 1;
    final List<AndroidSafTreeEntry> entries =
        childrenByUri[uri] ?? const <AndroidSafTreeEntry>[];
    if (offset >= entries.length) {
      return AndroidSafTreePage(
        entries: const <AndroidSafTreeEntry>[],
        nextOffset: null,
      );
    }
    final int end = offset + _pageSize < entries.length
        ? offset + _pageSize
        : entries.length;
    return AndroidSafTreePage(
      entries: entries.sublist(offset, end),
      nextOffset: end < entries.length ? end : null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    // 目录选择必须由 picker 的替身完成：走到这里说明测试触碰了真实平台通道。
    throw StateError('测试不允许调用真实目录选择');
  }

  @override
  Future<void> persistTreePermission(String uri) async {}

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw StateError('批量转换单测不写 SAF 文档');
  }
}

/// 任何调用都视为"碰到了真实 MethodChannel"的树端口。
///
/// 未显式注入 SAF 树端口的用例（例如保存树 `pickTree` 分支）用它兜底：一旦有代码
/// 绕过注入直接调用平台能力，测试会立刻失败而不是弹出系统目录选择器。
class _ThrowingAndroidSafTreePort implements AndroidSafTreePort {
  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) {
    throw StateError('测试环境不允许访问真实 SAF 目录树');
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() {
    throw StateError('测试环境不允许访问真实 SAF 目录树');
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    throw StateError('测试环境不允许访问真实 SAF 目录树');
  }

  @override
  Future<void> persistTreePermission(String uri) {
    throw StateError('测试环境不允许访问真实 SAF 目录树');
  }

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw StateError('测试环境不允许访问真实 SAF 目录树');
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

/// 读取最新页面状态：一次测试里会有多个动作，状态会被后续动作改写。
BatchConvertPageState _readState(ProviderContainer container) {
  return container.read(batchConvertPageControllerProvider);
}

/// "安卓端已导入 SAF 目录"的测试环境。
///
/// 导入树会顺手成为保存根（生产行为：SAF 源必须有树内落点），后续 SAF 分支都依赖
/// 这个状态；树端口与容器都注入内存替身，不会触碰平台通道。
_SafFixture _createSafImportedContainer({
  Future<void> Function(String lyricsPath)? openInOpenLyrics,
}) {
  final _FakeBatchConvertInputPicker picker = _FakeBatchConvertInputPicker(
    importTree: (treeUri: _safTreeUri, treeLabel: '内部存储'),
  );
  final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
    childrenByUri: <String, List<AndroidSafTreeEntry>>{
      _safTreeUri: const <AndroidSafTreeEntry>[
        AndroidSafTreeEntry(
          uri: _safLyricsUri,
          displayName: 'a.lrc',
          mimeType: 'application/octet-stream',
          isDirectory: false,
          isFile: true,
        ),
      ],
    },
  );
  final _FakePathOpener pathOpener = _FakePathOpener();
  return (
    container: _createContainer(
      picker: picker,
      safTreePort: treePort,
      capability: _mobileCapability(),
      pathOpener: pathOpener,
      openInOpenLyrics: openInOpenLyrics,
    ),
    pathOpener: pathOpener,
  );
}

typedef _SafFixture = ({
  ProviderContainer container,
  _FakePathOpener pathOpener,
});

/// 分页枚举可暂停的 SAF 树端口：首页立即返回并请求续页，续页挂起。
///
/// 扫描进度只在"页与页之间"写入状态，扫描结束后会被收尾逻辑覆盖；挂起续页才能
/// 观察到 `scanningDirectory` 这条中间态映射。
class _PausedPagingAndroidSafTreePort implements AndroidSafTreePort {
  _PausedPagingAndroidSafTreePort({required this.childrenByUri});

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;
  final Completer<void> secondPageStarted = Completer<void>();
  final Completer<void> releaseSecondPage = Completer<void>();

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    if (offset == 0) {
      return AndroidSafTreePage(
        entries: childrenByUri[uri] ?? const <AndroidSafTreeEntry>[],
        nextOffset: 1,
      );
    }
    if (!secondPageStarted.isCompleted) {
      secondPageStarted.complete();
    }
    await releaseSecondPage.future;
    return AndroidSafTreePage(
      entries: const <AndroidSafTreeEntry>[],
      nextOffset: null,
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) {
    // 目录选择必须由 picker 的替身完成：走到这里说明测试触碰了真实平台通道。
    throw StateError('测试不允许调用真实目录选择');
  }

  @override
  Future<void> persistTreePermission(String uri) async {}

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw StateError('批量转换单测不写 SAF 文档');
  }
}
