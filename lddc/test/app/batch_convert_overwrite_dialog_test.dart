import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/app_feature_scopes.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/i18n.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_controller.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_state.dart';
import 'package:lddc/src/features/batch_convert/presentation/batch_convert_page.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;

/// 覆盖确认对话框的界面行为测试。
///
/// 对话框属于 app 层（`app_feature_scopes.dart`），只能通过 [AppBatchConvertPageScope]
/// 注入的 `confirmOverwrite` 触达，因此这里走"页面 scope + 控制器"的真实链路：
/// 文件选择和目标存在性预检替换成内存替身（不碰真实磁盘），其余装配与线上一致。
void main() {
  group('批量转换覆盖确认对话框', () {
    testWidgets('8 个覆盖目标全部列出且最后一条可见', (WidgetTester tester) async {
      final _OverwriteDialogHarness harness = await _pumpOverwriteDialog(
        tester,
        targetCount: 8,
      );
      final l10n = tester.element(find.byType(AlertDialog)).l10n;

      expect(find.text(l10n.batchConvertOverwriteDialogTitle), findsOneWidget);
      expect(find.text(l10n.batchConvertOverwritePathsLabel), findsOneWidget);
      expect(
        find.text(l10n.batchConvertOverwriteExistingTargetCount(8)),
        findsOneWidget,
      );
      expect(harness.targetPaths, hasLength(8));
      expect(harness.targetPaths.last, endsWith('s8.srt'));

      // 旧实现最多只展示 5 条示例路径：这里要求 8 条都能在对话框里看到。
      expect(_inDialog(find.text(harness.targetPaths.first)), findsOneWidget);
      for (final String path in harness.targetPaths) {
        await tester.scrollUntilVisible(
          _inDialog(find.text(path)),
          48,
          scrollable: _pathListScrollable(),
        );
        expect(_inDialog(find.text(path)), findsOneWidget);
      }
      expect(_inDialog(find.text(harness.targetPaths.last)), findsOneWidget);

      // 清单变长不能顶掉按钮：取消与继续都还在对话框内。
      expect(
        find.widgetWithText(FilledButton, l10n.batchConvertOverwriteContinue),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, l10n.actionCancel),
        findsOneWidget,
      );

      await _cancelOverwriteDialog(tester, l10n);
      await harness.pending;
    });

    testWidgets('200 个覆盖目标时惰性构建、首末条目可达且按钮仍可见', (WidgetTester tester) async {
      final _OverwriteDialogHarness harness = await _pumpOverwriteDialog(
        tester,
        targetCount: 200,
      );
      final l10n = tester.element(find.byType(AlertDialog)).l10n;

      expect(
        find.text(l10n.batchConvertOverwriteExistingTargetCount(200)),
        findsOneWidget,
      );
      expect(_inDialog(find.text(harness.targetPaths.first)), findsOneWidget);
      // 惰性构建：只允许构建视口（含缓存区）附近的行，一次性构建 200 行会在这里失败。
      final int builtRows = _builtPathRowCount(harness.targetPaths);
      expect(builtRows, greaterThan(0));
      expect(builtRows, lessThan(harness.targetPaths.length ~/ 2));
      // 限高列表不能产生溢出/无界高度异常。
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        _inDialog(find.text(harness.targetPaths.last)),
        400,
        maxScrolls: 200,
        scrollable: _pathListScrollable(),
      );
      expect(_inDialog(find.text(harness.targetPaths.last)), findsOneWidget);

      // 按钮必须留在屏幕内：清单再长也不能把操作区挤出可视范围。
      final Size logicalSurface =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final Rect dialogRect = tester.getRect(find.byType(AlertDialog));
      expect(dialogRect.bottom, lessThanOrEqualTo(logicalSurface.height));
      final Rect continueRect = tester.getRect(
        find.widgetWithText(FilledButton, l10n.batchConvertOverwriteContinue),
      );
      expect(continueRect.bottom, lessThanOrEqualTo(dialogRect.bottom));

      await _cancelOverwriteDialog(tester, l10n);
      await harness.pending;
    });
  });
}

/// 覆盖确认对话框的测试夹具。
class _OverwriteDialogHarness {
  const _OverwriteDialogHarness({
    required this.pending,
    required this.targetPaths,
  });

  /// 挂起的"开始转换"调用：对话框点掉之后才会返回。
  final Future<void> pending;

  /// 队列里每条条目规划出的覆盖目标展示路径（与对话框展示的内容同源）。
  final List<String> targetPaths;
}

/// 打开覆盖确认对话框，返回断言所需的夹具。
Future<_OverwriteDialogHarness> _pumpOverwriteDialog(
  WidgetTester tester, {
  required int targetCount,
}) async {
  final List<PickedFileHandle> pickedFiles = <PickedFileHandle>[
    for (int index = 1; index <= targetCount; index += 1)
      PickedFileHandle(
        name: 's$index.lrc',
        path: p.join('batch_convert', 'overwrite', 's$index.lrc'),
      ),
  ];
  final ProviderContainer container = ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => _desktopCapability()),
      configRepositoryProvider.overrideWithValue(
        _FixedConfigRepository(ConfigDefaults.current),
      ),
      // 只替换"选文件"和"目标是否已存在"：对话框的触发与渲染只依赖这两件事。
      appFilePickerProvider.overrideWith(
        (Ref ref) => _FakeAppFilePicker(pickedFiles),
      ),
      batchConvertFileIoProvider.overrideWith(
        (Ref ref) => const _ExistingTargetFileIo(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(_buildScopeApp(container));
  await tester.pumpAndSettle();

  // scope 内部会再开一层 ProviderScope，页面依赖只在那层容器里。
  final ProviderContainer pageContainer = ProviderScope.containerOf(
    tester.element(find.byType(BatchConvertPage)),
    listen: false,
  );
  final BatchConvertPageController controller = pageContainer.read(
    batchConvertPageControllerProvider.notifier,
  );
  await controller.addFiles();
  // 目标格式改成 srt 后与源文件不同名，从而走"覆盖已存在目标"的预检分支。
  controller.updateTargetFormat(LyricsFormat.srt);
  final List<String> targetPaths = pageContainer
      .read(batchConvertPageControllerProvider)
      .queueItems
      .map((BatchConvertQueueItem item) => item.targetDisplayPath)
      .toList(growable: false);

  // startOrCancel 会一直等对话框返回，这里先拿到挂起的 Future，断言完再关掉对话框。
  final Future<void> pending = controller.startOrCancel();
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  return _OverwriteDialogHarness(pending: pending, targetPaths: targetPaths);
}

/// 覆盖清单所在的可滚动区域。
///
/// 必须限定在对话框内：页面背后的队列本身也是 `ListView`，不限定就会匹配到两个
/// `Scrollable`，`scrollUntilVisible` 会因此抛错。
Finder _pathListScrollable() {
  return find.descendant(
    of: find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ListView),
    ),
    matching: find.byType(Scrollable),
  );
}

/// 已经被构建出来的路径行数量：用于证明列表是惰性构建的。
int _builtPathRowCount(List<String> paths) {
  final Set<String> expected = paths.toSet();
  return find
      .byType(Text)
      .evaluate()
      .map((Element element) => element.widget)
      .whereType<Text>()
      .where((Text text) => expected.contains(text.data))
      .length;
}

Future<void> _cancelOverwriteDialog(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  await tester.tap(find.widgetWithText(TextButton, l10n.actionCancel));
  await tester.pumpAndSettle();
}

Widget _buildScopeApp(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: AppBatchConvertPageScope()),
    ),
  );
}

/// 桌面形态：没有 SAF 授权树能力，落点是本地路径。
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

/// 只实现"选歌词文件"的文件端口替身。
class _FakeAppFilePicker implements AppFilePicker {
  const _FakeAppFilePicker(this.files);

  final List<PickedFileHandle> files;

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    return files;
  }

  @override
  Future<String?> pickDirectory({String? initialDirectory}) {
    throw UnsupportedError('覆盖确认测试不选目录');
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) {
    throw UnsupportedError('覆盖确认测试不选单个文件');
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory}) {
    throw UnsupportedError('覆盖确认测试不选音频文件');
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) {
    throw UnsupportedError('覆盖确认测试不写音频标签');
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) {
    throw UnsupportedError('覆盖确认测试不持有音频文件句柄');
  }

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) {
    throw UnsupportedError('覆盖确认测试不保存文本文件');
  }
}

/// 目标存在性预检替身：一律视为"目标已存在"，从而稳定触发覆盖确认。
///
/// 走真实文件 IO 需要在 FakeAsync 区里等磁盘，容易让测试挂起；这里只替换端口，
/// 覆盖预检的判定逻辑仍由控制器真实执行。
class _ExistingTargetFileIo implements BatchConvertFileIo {
  const _ExistingTargetFileIo();

  @override
  Future<bool?> targetExists(BatchConvertTarget target) async => true;

  @override
  Future<Uint8List> readBytes(BatchConvertSource source) {
    throw UnsupportedError('覆盖确认测试不读取源内容');
  }

  @override
  Future<void> writeText({
    required BatchConvertSource source,
    required BatchConvertTarget target,
    required String text,
    required bool allowOverwrite,
  }) {
    throw UnsupportedError('覆盖确认测试不写入文件');
  }
}

/// 目标路径同时出现在弹窗清单与背后的队列行里，断言必须限定在弹窗内。
Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);
