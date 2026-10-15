import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/app_feature_scopes.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'package:lddc/src/app/bootstrap/app_runtime_providers.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_dependencies.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_input_picker.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_controller.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_page_state.dart';
import 'package:lddc/src/features/batch_convert/presentation/batch_convert_page.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

/// 批量转换在安卓端使用的授权树与树内文档（形态与 DocumentsUI 返回一致）。
const String _musicTreeUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic';
const String _downloadTreeUri =
    'content://com.android.externalstorage.documents/tree/primary%3ADownload';
const String _musicLyricsUri =
    'content://com.android.externalstorage.documents/tree/primary%3AMusic/document/primary%3AMusic%2Fa.lrc';

void main() {
  group('batchConvertFileIoProvider', () {
    test('安卓能力下产出 SAF 文件 IO，并复用注入的树端口与内容端口', () {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort();
      final _FakeAndroidSafContentPort contentPort =
          _FakeAndroidSafContentPort();
      final ProviderContainer container = _createWiringContainer(
        capability: _androidCapability(),
        treePort: treePort,
        contentPort: contentPort,
      );
      addTearDown(container.dispose);

      final BatchConvertFileIo fileIo = container.read(
        batchConvertFileIoProvider,
      );

      expect(fileIo, isA<SafBatchConvertFileIo>());
      final SafBatchConvertFileIo safFileIo = fileIo as SafBatchConvertFileIo;
      // SAF 文档源/目标不能交给 dart:io：必须由注入的端口读写，测试里也不能退回
      // 真实 MethodChannel。
      expect(safFileIo.treePort, same(treePort));
      expect(safFileIo.contentPort, same(contentPort));
    });

    test('非安卓能力下沿用默认本地文件 IO', () {
      final ProviderContainer container = _createWiringContainer(
        capability: _desktopCapability(),
      );
      addTearDown(container.dispose);

      expect(
        container.read(batchConvertFileIoProvider),
        isA<DefaultBatchConvertFileIo>(),
      );
    });

    test('批量转换 use case 与 SAF 扫描用例都从 Provider 树取依赖', () {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort();
      final ProviderContainer container = _createWiringContainer(
        capability: _androidCapability(),
        treePort: treePort,
      );
      addTearDown(container.dispose);

      // use case 与页面覆盖预检必须共用 batchConvertFileIoProvider，避免
      // "写入用 SAF、预检用本地"这种分叉。
      expect(
        container.read(batchConvertUseCaseProvider),
        isA<BatchConvertUseCase>(),
      );
      final AndroidSafLyricsScanUseCase scanUseCase = container.read(
        androidSafLyricsScanUseCaseProvider,
      );
      // 保存树选择（选择器）与导入扫描必须共用同一棵授权树的实现。
      expect(scanUseCase.treePort, same(treePort));
    });
  });

  group('BatchConvertInputPickerImpl', () {
    test('pickImportTree 返回树 URI 与显示名并完成持久授权', () async {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickTreeResult: const AndroidSafTreeToken(
          uri: _musicTreeUri,
          displayName: ' 内部存储 ',
        ),
      );

      final PickedBatchConvertImportTree? picked = await _createPicker(
        treePort,
      ).pickImportTree(initialUri: _downloadTreeUri);

      expect(picked?.treeUri, _musicTreeUri);
      // 显示名两侧空白要去掉：标签会直接展示在落点预览里。
      expect(picked?.treeLabel, '内部存储');
      // 未持久授权的树在应用重启或系统回收权限后会失效，进入队列前必须授权。
      expect(treePort.persistedUris, <String>[_musicTreeUri]);
      expect(treePort.pickedInitialUris, <String?>[_downloadTreeUri]);
    });

    test('目录选择器不给显示名时标签退回树 URI', () async {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickTreeResult: const AndroidSafTreeToken(
          uri: _musicTreeUri,
          displayName: '   ',
        ),
      );

      final PickedBatchConvertSaveTree? picked = await _createPicker(
        treePort,
      ).pickSaveTree();

      expect(picked?.treeUri, _musicTreeUri);
      expect(picked?.treeLabel, _musicTreeUri);
      expect(treePort.persistedUris, <String>[_musicTreeUri]);
    });

    test('用户在系统目录选择器里取消时返回 null', () async {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickError: PlatformException(code: 'cancelled'),
      );
      final BatchConvertInputPicker picker = _createPicker(treePort);

      // 取消是正常操作：返回 null 让控制器静默返回，而不是弹出错误提示。
      expect(await picker.pickImportTree(), isNull);
      expect(await picker.pickSaveTree(), isNull);
      expect(treePort.persistedUris, isEmpty);
    });

    test('非取消类平台异常继续抛出', () async {
      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickError: PlatformException(code: 'boom'),
      );

      await expectLater(
        _createPicker(treePort).pickImportTree(),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('BatchConvertSaveRoot', () {
    test('相同的 SAF 保存根相等且哈希一致，树名不同则不相等', () {
      const BatchConvertSaveRoot left = BatchConvertSaveRoot.saf(
        treeUri: _musicTreeUri,
        treeLabel: '内部存储',
      );
      const BatchConvertSaveRoot right = BatchConvertSaveRoot.saf(
        treeUri: _musicTreeUri,
        treeLabel: '内部存储',
      );
      const BatchConvertSaveRoot otherLabel = BatchConvertSaveRoot.saf(
        treeUri: _musicTreeUri,
        treeLabel: '下载',
      );

      expect(left, right);
      expect(left.hashCode, right.hashCode);
      expect(left == otherLabel, isFalse);
      expect(left.hashCode == otherLabel.hashCode, isFalse);
    });

    test('本地保存根与 SAF 保存根互不相等', () {
      const BatchConvertSaveRoot local = BatchConvertSaveRoot.local(
        r'D:\exports',
      );
      const BatchConvertSaveRoot localCopy = BatchConvertSaveRoot.local(
        r'D:\exports',
      );
      const BatchConvertSaveRoot saf = BatchConvertSaveRoot.saf(
        treeUri: _musicTreeUri,
        treeLabel: '内部存储',
      );

      expect(local, localCopy);
      expect(local.hashCode, localCopy.hashCode);
      expect(local == saf, isFalse);
      // 两种形态互斥（本地目录 / 授权树），哈希也必须区分开。
      expect(local.hashCode == saf.hashCode, isFalse);
      expect(local.localPath, r'D:\exports');
      expect(local.treeUri, isNull);
      expect(local.displayLabel, r'D:\exports');
    });
  });

  group('AppBatchConvertPageScope', () {
    testWidgets('安卓能力下把 SAF 端口、扫描用例与文件 IO 注入批量转换依赖', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1366, 1024));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final _FakeAndroidSafTreePort treePort = _FakeAndroidSafTreePort(
        pickTreeResult: const AndroidSafTreeToken(
          uri: _musicTreeUri,
          displayName: '内部存储',
        ),
        childrenByUri: <String, List<AndroidSafTreeEntry>>{
          _musicTreeUri: const <AndroidSafTreeEntry>[
            AndroidSafTreeEntry(
              uri: _musicLyricsUri,
              displayName: 'a.lrc',
              mimeType: 'application/octet-stream',
              isDirectory: false,
              isFile: true,
            ),
          ],
        },
      );
      final ProviderContainer container = _createWiringContainer(
        capability: _androidCapability(),
        treePort: treePort,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildScopeApp(container));
      await tester.pumpAndSettle();
      expect(find.byType(BatchConvertPage), findsOneWidget);

      // scope 内部会再开一层 ProviderScope，页面依赖只在那层容器里。
      final ProviderContainer pageContainer = ProviderScope.containerOf(
        tester.element(find.byType(BatchConvertPage)),
        listen: false,
      );
      expect(
        pageContainer.read(batchConvertDependenciesProvider).fileIo,
        isA<SafBatchConvertFileIo>(),
      );

      final BatchConvertPageController controller = pageContainer.read(
        batchConvertPageControllerProvider.notifier,
      );
      await controller.selectSaveRootDirectory();
      await controller.addDirectories();
      await tester.pumpAndSettle();

      final BatchConvertPageState state = pageContainer.read(
        batchConvertPageControllerProvider,
      );
      expect(state.saveRoot?.treeUri, _musicTreeUri);
      expect(state.saveRoot?.displayLabel, '内部存储');
      expect(state.queueItems.single.source, isA<SafDocumentSource>());
      expect(state.queueItems.single.targetDisplayPath, '内部存储/a.lrc');
      // 保存树与导入树各自选一次，两次都要完成持久授权（选树走 scope 注入的端口）。
      expect(treePort.pickCalls, 2);
      expect(treePort.persistedUris, <String>[_musicTreeUri, _musicTreeUri]);
    });
  });
}

ProviderContainer _createWiringContainer({
  required AppCapability capability,
  AndroidSafTreePort? treePort,
  AndroidSafContentPort? contentPort,
}) {
  final AndroidSafTreePort resolvedTreePort =
      treePort ?? _FakeAndroidSafTreePort();
  final AndroidSafContentPort resolvedContentPort =
      contentPort ?? _FakeAndroidSafContentPort();
  return ProviderContainer(
    overrides: [
      appCapabilityProvider.overrideWith((Ref ref) => capability),
      configRepositoryProvider.overrideWithValue(
        _FixedConfigRepository(ConfigDefaults.current),
      ),
      // 平台端口全部替换成内存替身：真实适配器会打到 MethodChannel。
      androidSafTreePortProvider.overrideWith((Ref ref) => resolvedTreePort),
      androidSafContentPortProvider.overrideWith(
        (Ref ref) => resolvedContentPort,
      ),
    ],
  );
}

BatchConvertInputPicker _createPicker(AndroidSafTreePort treePort) {
  return BatchConvertInputPickerImpl(
    filePicker: _ThrowingAppFilePicker(),
    treePort: treePort,
  );
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

/// 安卓手机形态：SAF 授权树能力开启，桌面专属能力关闭。
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

/// 桌面形态：没有 SAF 授权树能力。
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

/// 内存 SAF 授权树端口：选树结果可配置，目录枚举不触碰平台通道。
class _FakeAndroidSafTreePort implements AndroidSafTreePort {
  _FakeAndroidSafTreePort({
    this.pickTreeResult,
    this.pickError,
    Map<String, List<AndroidSafTreeEntry>>? childrenByUri,
  }) : childrenByUri =
           childrenByUri ?? const <String, List<AndroidSafTreeEntry>>{};

  /// `pickTree` 的返回结果；为 null 表示测试没有配置选树成功。
  final AndroidSafTreeToken? pickTreeResult;

  /// 非空时 `pickTree` 直接抛出它，用来模拟"用户取消"等平台异常。
  final Object? pickError;

  final Map<String, List<AndroidSafTreeEntry>> childrenByUri;
  final List<String?> pickedInitialUris = <String?>[];
  final List<String> persistedUris = <String>[];
  int pickCalls = 0;

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) async {
    pickCalls += 1;
    pickedInitialUris.add(initialUri);
    final Object? error = pickError;
    if (error != null) {
      throw error;
    }
    final AndroidSafTreeToken? tree = pickTreeResult;
    if (tree == null) {
      throw StateError('测试未配置选树结果');
    }
    return tree;
  }

  @override
  Future<void> persistTreePermission(String uri) async {
    persistedUris.add(uri);
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    return const <AndroidSafPersistedTree>[];
  }

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    if (offset != 0) {
      return AndroidSafTreePage(
        entries: const <AndroidSafTreeEntry>[],
        nextOffset: null,
      );
    }
    return AndroidSafTreePage(
      entries: childrenByUri[uri] ?? const <AndroidSafTreeEntry>[],
      nextOffset: null,
    );
  }

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required List<String> directorySegments,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw StateError('批量转换单元测试不写入真实 SAF 文档');
  }
}

/// SAF 内容端口替身：这些用例只关心预检与落点规划，不读取文档内容。
class _FakeAndroidSafContentPort implements AndroidSafContentPort {
  @override
  Future<Uint8List> readBytes(String uri, {int? maxBytes}) {
    throw StateError('批量转换单元测试不读取真实 SAF 文档内容');
  }
}

/// 只用于装配选择器的文件端口：SAF 选树路径不允许触碰真实文件对话框。
class _ThrowingAppFilePicker implements AppFilePicker {
  @override
  Future<String?> pickDirectory({String? initialDirectory}) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({String? initialDirectory}) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<PickedAudioFileHandle> openAudioFileForWrite(
    PickedAudioFileHandle file,
  ) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<void> releaseAudioFile(PickedAudioFileHandle file) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }

  @override
  Future<SavedTextFileResult?> saveTextFile({
    required String fileName,
    required String text,
    String? initialDirectory,
    List<String>? allowedExtensions,
  }) {
    throw UnsupportedError('测试场景不调用真实文件选择');
  }
}
