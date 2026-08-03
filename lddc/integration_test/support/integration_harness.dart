import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lddc/src/app/bootstrap/app_providers.dart';
import 'app_test_launcher.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:lddc/src/core/config/config.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc/src/platform/desktop/service_host/desktop_service_bootstrap.dart';
import 'package:path/path.dart' as p;

import 'integration_reporter.dart';
import 'integration_viewport.dart';
import 'integration_workspace.dart';

void ensureIntegrationBinding() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // 集成测试必须把“调用了 tap 但用户实际点不到”视为失败。业务断言可能稍后
  // 因其他状态变化而偶然通过，若只打印 warning 会形成假绿。
  WidgetController.hitTestWarningShouldBeFatal = true;
}

class IntegrationAppHandle {
  IntegrationAppHandle({
    required this.launchHandle,
    required this.workspace,
    required this.filePicker,
    required this.pathOpener,
    required this.mediaGateway,
    required this.runtimeConfig,
    required this.tester,
    required this.screenshotBoundaryKey,
    required this.surfaceSizeOverridden,
  });

  final LddcIntegrationLaunchHandle launchHandle;
  final IntegrationWorkspace workspace;
  final IntegrationFilePicker filePicker;
  final IntegrationPathOpener pathOpener;
  final IntegrationHybridMediaGateway mediaGateway;
  final IntegrationRuntimeConfig runtimeConfig;
  final WidgetTester tester;
  final GlobalKey screenshotBoundaryKey;
  final bool surfaceSizeOverridden;

  ProviderContainer get container => launchHandle.container;

  Future<String?> captureFailureScreenshot() =>
      captureIntegrationFailureScreenshot(
        tester: tester,
        screenshotBoundaryKey: screenshotBoundaryKey,
        runtimeConfig: runtimeConfig,
      );

  Future<void> dispose() async {
    // 先把应用 Widget 从 RenderView 卸载，再关闭 Provider/数据库，避免
    // 已失效的 controller 在下一帧仍被访问。任何一步失败时也要继续
    // 恢复测试 viewport 并关闭工作区，不把尺寸或 SQLite 句柄泄漏给后续场景。
    try {
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      try {
        await launchHandle.dispose();
      } finally {
        try {
          await workspace.dispose();
        } finally {
          if (surfaceSizeOverridden) {
            await tester.binding.setSurfaceSize(null);
          }
        }
      }
    }
  }
}

Future<String> captureIntegrationFailureScreenshot({
  required WidgetTester tester,
  required GlobalKey screenshotBoundaryKey,
  required IntegrationRuntimeConfig runtimeConfig,
}) async {
  await tester.pump();
  // 截图只是失败诊断，不能无限阻塞原始错误报告。Flutter 的移动端
  // integration_test 提供原生截图通道，桌面端则没有对应插件，因此使用
  // 已由真实宿主引擎绘制的 RepaintBoundary。硬超时保证即使 raster 线程或
  // 原生通道异常，reporter 仍能写入原始失败与截图错误。
  final Uint8List pngBytes =
      await _captureIntegrationPngBytes(
        tester: tester,
        screenshotBoundaryKey: screenshotBoundaryKey,
        screenshotName: p.basenameWithoutExtension(
          runtimeConfig.reportPath.path,
        ),
      ).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('集成测试失败截图超时'),
      );
  final Directory screenshotDirectory = Directory(
    p.join(runtimeConfig.reportRoot.parent.path, 'screenshots'),
  );
  await screenshotDirectory.create(recursive: true);
  final File screenshot = File(
    p.join(
      screenshotDirectory.path,
      p.setExtension(p.basename(runtimeConfig.reportPath.path), '.png'),
    ),
  );
  await screenshot.writeAsBytes(pngBytes, flush: true);
  return screenshot.path;
}

Future<Uint8List> _captureIntegrationPngBytes({
  required WidgetTester tester,
  required GlobalKey screenshotBoundaryKey,
  required String screenshotName,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final IntegrationTestWidgetsFlutterBinding binding =
        IntegrationTestWidgetsFlutterBinding.instance;
    if (Platform.isAndroid) {
      // Android 的 integration_test 只能从 FlutterImageView 读取像素。转换会在
      // 当前测试的 tearDown 中由 Flutter 自动恢复，不另外保留常驻表面。
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    return Uint8List.fromList(await binding.takeScreenshot(screenshotName));
  }

  final RenderObject? renderObject = screenshotBoundaryKey.currentContext
      ?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('集成测试截图边界尚未挂载');
  }
  final Uint8List? pngBytes = await tester.runAsync<Uint8List>(() async {
    final ui.Image image = await renderObject.toImage(pixelRatio: 1);
    try {
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError('Flutter 渲染层未返回 PNG 字节');
      }
      return Uint8List.fromList(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
    } finally {
      // ui.Image 持有原生像素缓冲；字节复制完成后立即释放，避免连续
      // 失败场景在同一 runner 进程内积累 GPU 或原生内存。
      image.dispose();
    }
  });
  if (pngBytes == null) {
    throw StateError('Flutter 截图异步任务未返回 PNG 字节');
  }
  return pngBytes;
}

const Duration kIntegrationFramePump = Duration(milliseconds: 16);
const Duration kIntegrationInteractionPump = Duration(milliseconds: 120);
const Duration kIntegrationMenuPump = Duration(milliseconds: 200);

Future<IntegrationAppHandle> launchIntegrationApp(
  WidgetTester tester, {
  required String scenarioName,
  required IntegrationRuntimeConfig runtimeConfig,
  required IntegrationReporter reporter,
  List<Object> overrides = const [],
  AppConfig? config,
  AppCapability? capability,
  DesktopServiceBootstrap? serviceBootstrap,
  bool startDesktopServiceHost = false,
  bool useRealFilePicker = false,
  Directory? workspaceParent,
  Size? size,
}) async {
  runtimeConfig.verifyCurrentDevice();
  final bool surfaceSizeOverridden = size != null;
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
  }

  final IntegrationWorkspace workspace = await IntegrationWorkspace.create(
    scenarioName,
    parentDirectory: workspaceParent,
  );
  debugPrint('integration[$scenarioName] workspace=${workspace.root.path}');
  final IntegrationFilePicker filePicker = IntegrationFilePicker();
  final IntegrationPathOpener pathOpener = IntegrationPathOpener();
  final IntegrationHybridMediaGateway mediaGateway =
      IntegrationHybridMediaGateway(
        realMediaEnabled: runtimeConfig.realMediaEnabled,
      );
  final List<Object> resolvedOverrides = <Object>[
    // 每个场景使用临时目录内的独占缓存，避免读取用户缓存或复用上一次测试的
    // 成功/失败结果。workspace 负责在 ProviderContainer 释放后关闭数据库。
    cacheFacadeProvider.overrideWithValue(workspace.cache),
    if (!runtimeConfig.realNetworkEnabled)
      ...buildIntegrationOfflineApiOverrides(
        songInfoResolver: mediaGateway.resolveSearchSongInfo,
      ),
    // 平台系统界面测试必须保留生产 AppFilePickerImpl；其余现有场景默认继续
    // 注入确定性选择器，避免离线回归意外弹出系统对话框。
    if (!useRealFilePicker) appFilePickerProvider.overrideWithValue(filePicker),
    appPathOpenerProvider.overrideWithValue(pathOpener),
    localMatchMediaGatewayProvider.overrideWithValue(mediaGateway),
    localMatchAudioMetadataPortProvider.overrideWithValue(mediaGateway),
    lyricsRequestBudgetProvider.overrideWithValue(
      NetworkRequestBudget(
        timeout: runtimeConfig.requestTimeout,
        retryCount: runtimeConfig.requestRetryCount,
      ),
    ),
    translateRequestBudgetProvider.overrideWithValue(
      NetworkRequestBudget(
        timeout: runtimeConfig.requestTimeout,
        retryCount: runtimeConfig.requestRetryCount,
      ),
    ),
    ...overrides,
  ];
  final AppConfig resolvedConfig = _withDefaultSavePath(
    config ?? buildIntegrationConfig(),
    workspace.exportsDir.path,
  );
  final AppCapability resolvedCapability = _resolveIntegrationCapability(
    runtimeConfig: runtimeConfig,
    explicitCapability: capability,
  );
  await workspace.configRepository.update(
    _ConfigPatchEncoder.encode(resolvedConfig),
  );
  final LddcIntegrationLaunchHandle launchHandle =
      await launchLddcForIntegrationTest(
        options: LddcIntegrationLaunchOptions(
          configRepository: workspace.configRepository,
          capability: resolvedCapability,
          overrides: resolvedOverrides,
          serviceBootstrap: serviceBootstrap,
          startDesktopServiceHost: startDesktopServiceHost,
        ),
      );
  final GlobalKey screenshotBoundaryKey = GlobalKey(
    debugLabel: 'integration_screenshot_$scenarioName',
  );
  await tester.pumpWidget(
    RepaintBoundary(key: screenshotBoundaryKey, child: launchHandle.buildApp()),
  );
  await pumpForMenuOrRoute(tester);
  final IntegrationViewportSnapshot viewport = await captureIntegrationViewport(
    tester,
  );
  debugPrint('integration[$scenarioName] viewport ${viewport.summary}');
  reporter.recordContext('viewport', viewport.toJson());
  final IntegrationAppHandle handle = IntegrationAppHandle(
    launchHandle: launchHandle,
    workspace: workspace,
    filePicker: filePicker,
    pathOpener: pathOpener,
    mediaGateway: mediaGateway,
    runtimeConfig: runtimeConfig,
    tester: tester,
    screenshotBoundaryKey: screenshotBoundaryKey,
    surfaceSizeOverridden: surfaceSizeOverridden,
  );
  reporter.registerFailureArtifactWriter(handle.captureFailureScreenshot);
  return handle;
}

AppCapability _resolveIntegrationCapability({
  required IntegrationRuntimeConfig runtimeConfig,
  AppCapability? explicitCapability,
}) {
  final AppCapability resolved =
      explicitCapability ?? AppCapabilityResolver.resolveCurrent();
  if (explicitCapability != null ||
      runtimeConfig.profile != 'offline' ||
      !Platform.isAndroid) {
    return resolved;
  }

  // Android 的生产能力会把本地匹配和列表保存切换到 SAF tree。offline
  // profile 按契约使用 scripted picker 和 mocked native channels，若仍暴露
  // SAF UI，测试会调用未注入的真实 MethodChannel，既不是离线业务测试，
  // 也无法形成真实平台证据。这里只关闭 offline 的 SAF 分支；platform
  // 与 UI Automator 仍使用完整生产能力验证真实目录授权、FD 和生命周期。
  return AppCapability(
    multiWindow: resolved.multiWindow,
    desktopPanelDetached: resolved.desktopPanelDetached,
    desktopPanelEmbedded: resolved.desktopPanelEmbedded,
    systemTray: resolved.systemTray,
    globalHotkey: resolved.globalHotkey,
    audioTagWrite: resolved.audioTagWrite,
    directoryRecursiveScan: resolved.directoryRecursiveScan,
    androidSafTreeAccess: false,
    androidCueTrackResolve: false,
    webFileSystemAccess: resolved.webFileSystemAccess,
    webTaglibWasmReady: resolved.webTaglibWasmReady,
  );
}

List<Object> buildIntegrationOfflineApiOverrides({
  SongInfo? Function(String keyword)? songInfoResolver,
}) {
  final LyricsSourceRegistry lyricsRegistry = LyricsSourceRegistry()
    ..registerCloudProviders(<LyricsCloudSourceProvider>[
      for (final Source source in <Source>[
        Source.qm,
        Source.kg,
        Source.ne,
        Source.lrclib,
      ])
        IntegrationFakeLyricsCloudProvider(
          source: source,
          songInfoResolver: songInfoResolver,
        ),
    ])
    ..registerLocalProvider(createDefaultLocalLyricsProvider());
  return <Object>[
    lyricsSourceRegistryProvider.overrideWithValue(lyricsRegistry),
    translateApiProvider.overrideWithValue(
      const IntegrationFakeTranslationClient(),
    ),
  ];
}

Future<void> pumpOneIntegrationFrame(WidgetTester tester) {
  return tester.pump(kIntegrationFramePump);
}

Future<void> pumpForInteraction(WidgetTester tester) {
  return tester.pump(kIntegrationInteractionPump);
}

Future<void> pumpForMenuOrRoute(WidgetTester tester) {
  return tester.pump(kIntegrationMenuPump);
}

Future<void> tapVisible(
  WidgetTester tester,
  Finder target, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final String description = reason ?? '等待目标可点击';
  await pumpUntil(
    tester,
    () => target.evaluate().length == 1,
    timeout: timeout,
    reason: '$description：目标不存在或不唯一',
  );
  await Scrollable.ensureVisible(
    tester.element(target),
    alignment: 0.5,
    duration: Duration.zero,
  );
  await pumpForInteraction(tester);
  if (target.hitTestable().evaluate().length != 1) {
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
    if (resolvedScrollable != null) {
      final Finder scrollable = find.byElementPredicate(
        (Element element) => identical(element, resolvedScrollable),
      );
      for (int attempt = 0; attempt < 20; attempt += 1) {
        if (target.hitTestable().evaluate().length == 1) {
          break;
        }
        final Rect targetRect = tester.getRect(target);
        final Rect viewportRect = tester.getRect(scrollable);
        final ScrollPosition position = tester
            .state<ScrollableState>(scrollable)
            .position;
        // 横向操作条与纵向页面都复用该辅助方法。旧实现始终使用 dy，
        // 导致横向 SingleChildScrollView 即使目标在右侧也计算出零位移，
        // 最终在真实手机 viewport 上等待到超时。按实际滚动轴选择中心坐标，
        // 不改变严格 hit test，也不使用坐标点击或忽略未命中。
        final double targetCenter = position.axis == Axis.horizontal
            ? targetRect.center.dx
            : targetRect.center.dy;
        final double viewportCenter = position.axis == Axis.horizontal
            ? viewportRect.center.dx
            : viewportRect.center.dy;
        final double nextOffset =
            (position.pixels + targetCenter - viewportCenter).clamp(
              position.minScrollExtent,
              position.maxScrollExtent,
            );
        if ((nextOffset - position.pixels).abs() < 0.5) {
          break;
        }
        position.jumpTo(nextOffset);
        await pumpForInteraction(tester);
      }
    }
  }
  await pumpUntil(
    tester,
    () => target.hitTestable().evaluate().length == 1,
    timeout: timeout,
    reason: '$description：目标未进入可命中区域',
  );
  await tester.tap(target);
  await pumpForInteraction(tester);
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
  String? reason,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(step);
  }
  throw TimeoutException(reason ?? '等待条件超时', timeout);
}

Future<void> pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
  String? reason,
}) {
  return pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    step: step,
    reason: reason,
  );
}

Future<void> pumpUntilVisibleAny(
  WidgetTester tester,
  List<Finder> finders, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
  String? reason,
}) {
  return pumpUntil(
    tester,
    () => finders.any((Finder finder) => finder.evaluate().isNotEmpty),
    timeout: timeout,
    step: step,
    reason: reason,
  );
}

Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  Duration step = const Duration(milliseconds: 100),
  String? reason,
}) {
  return pumpUntil(
    tester,
    () => finder.evaluate().isEmpty,
    timeout: timeout,
    step: step,
    reason: reason,
  );
}

ProviderContainer scopedProviderContainer(
  WidgetTester tester,
  Finder pageFinder,
) {
  final Element element = tester.element(pageFinder);
  return ProviderScope.containerOf(element, listen: false);
}

Future<T> runStepWithTimeout<T>(
  Future<T> Function() action, {
  required Duration timeout,
  required String label,
}) {
  return action().timeout(
    timeout,
    onTimeout: () {
      throw TimeoutException('$label 超时', timeout);
    },
  );
}

class IntegrationFilePicker implements AppFilePicker {
  String? directory;
  PickedFileHandle? file;
  List<PickedFileHandle> files = const <PickedFileHandle>[];
  PickedAudioFileHandle? audioFile;
  String? saveFilePath;
  String? expectedInitialDirectory;
  String? expectedSuggestedFileName;
  List<String>? expectedAllowedExtensions;
  final List<PickedAudioFileHandle> releasedAudioFiles =
      <PickedAudioFileHandle>[];
  final List<IntegrationFilePickerCall> calls = <IntegrationFilePickerCall>[];

  @override
  Future<String?> pickDirectory({String? initialDirectory}) async {
    _record(
      IntegrationFilePickerCall(
        kind: 'pickDirectory',
        initialDirectory: initialDirectory,
      ),
    );
    return directory;
  }

  @override
  Future<PickedAudioFileHandle?> pickAudioFile({
    String? initialDirectory,
  }) async {
    _record(
      IntegrationFilePickerCall(
        kind: 'pickAudioFile',
        initialDirectory: initialDirectory,
      ),
    );
    return audioFile;
  }

  @override
  Future<PickedFileHandle?> pickFile({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    _record(
      IntegrationFilePickerCall(
        kind: 'pickFile',
        allowedExtensions: allowedExtensions,
        initialDirectory: initialDirectory,
        label: label,
      ),
    );
    return file;
  }

  @override
  Future<List<PickedFileHandle>> pickFiles({
    required List<String> allowedExtensions,
    String? initialDirectory,
    String? confirmButtonText,
    String label = 'file',
  }) async {
    _record(
      IntegrationFilePickerCall(
        kind: 'pickFiles',
        allowedExtensions: allowedExtensions,
        initialDirectory: initialDirectory,
        label: label,
      ),
    );
    return files;
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
    _record(
      IntegrationFilePickerCall(
        kind: 'saveTextFile',
        fileName: fileName,
        initialDirectory: initialDirectory,
        allowedExtensions: allowedExtensions,
        textHash: text.hashCode,
      ),
    );
    final String? resolved = saveFilePath;
    if (resolved == null) {
      return null;
    }
    _expectIfConfigured(expectedSuggestedFileName, fileName, '保存文件建议名不符合预期');
    _expectIfConfigured(
      expectedInitialDirectory,
      initialDirectory,
      '保存文件初始目录不符合预期',
    );
    if (expectedAllowedExtensions != null) {
      final List<String> actual = allowedExtensions ?? const <String>[];
      if (!_sameStringList(expectedAllowedExtensions!, actual)) {
        throw StateError(
          '保存文件扩展名过滤不符合预期: expected=$expectedAllowedExtensions actual=$actual',
        );
      }
    }
    final File file = File(resolved);
    if (!file.parent.existsSync()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(text);
    return SavedTextFileResult.localPath(file.path);
  }

  void _record(IntegrationFilePickerCall call) {
    calls.add(call);
  }

  void _expectIfConfigured(String? expected, String? actual, String message) {
    if (expected == null) {
      return;
    }
    if (expected != actual) {
      throw StateError('$message: expected=$expected actual=$actual');
    }
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (int index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class IntegrationFilePickerCall {
  const IntegrationFilePickerCall({
    required this.kind,
    this.fileName,
    this.allowedExtensions,
    this.initialDirectory,
    this.label,
    this.textHash,
  });

  final String kind;
  final String? fileName;
  final List<String>? allowedExtensions;
  final String? initialDirectory;
  final String? label;
  final int? textHash;
}

class ExportArtifactSnapshot {
  const ExportArtifactSnapshot({
    required this.path,
    required this.fileName,
    required this.extension,
    required this.size,
    required this.sha256,
    required this.contentPreview,
  });

  final String path;
  final String fileName;
  final String extension;
  final int size;
  final String sha256;
  final String contentPreview;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'fileName': fileName,
      'extension': extension,
      'size': size,
      'sha256': sha256,
      'contentPreview': contentPreview,
    };
  }
}

Future<ExportArtifactSnapshot> assertExportArtifact({
  required File file,
  String? expectedExtension,
  Iterable<String> requiredTextFragments = const <String>[],
}) async {
  if (!file.existsSync()) {
    throw StateError('导出文件不存在: ${file.path}');
  }
  final Uint8List bytes = await file.readAsBytes();
  final String text = utf8.decode(bytes, allowMalformed: true);
  final String extension = file.uri.pathSegments.last.contains('.')
      ? '.${file.uri.pathSegments.last.split('.').last}'
      : '';
  if (expectedExtension != null && extension != expectedExtension) {
    throw StateError(
      '导出文件扩展名不符合预期: expected=$expectedExtension actual=$extension path=${file.path}',
    );
  }
  for (final String fragment in requiredTextFragments) {
    if (!text.contains(fragment)) {
      throw StateError('导出文件缺少预期内容片段: $fragment path=${file.path}');
    }
  }
  return ExportArtifactSnapshot(
    path: file.path,
    fileName: file.uri.pathSegments.last,
    extension: extension,
    size: bytes.length,
    sha256: crypto.sha256.convert(bytes).toString(),
    contentPreview: text.length <= 120 ? text : text.substring(0, 120),
  );
}

class IntegrationPathOpener implements AppPathOpener {
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

class IntegrationHybridMediaGateway
    implements LocalMatchMediaGateway, LocalMatchAudioMetadataPort {
  IntegrationHybridMediaGateway({
    required this.realMediaEnabled,
    LocalMatchMediaGateway? delegate,
  }) : _delegate = realMediaEnabled
           ? (delegate ?? createDefaultLocalMatchMediaGateway())
           : delegate;

  final bool realMediaEnabled;
  final LocalMatchMediaGateway? _delegate;
  final Map<String, _IntegrationMediaFixture> _fixtures =
      <String, _IntegrationMediaFixture>{};
  final List<AudioTagWriteRequest> writes = <AudioTagWriteRequest>[];
  final List<String> searchKeywords = <String>[];

  /// 登记测试音频的稳定元数据。
  ///
  /// 默认离线流程只需要验证页面、控制器和保存链路，不应要求 Android 测试进程
  /// 执行主机上的 ffmpeg 或加载真实 taglib。真实媒体 profile 仍把内嵌歌词写入
  /// 实际文件，离线 profile 则把相同信息保存在有界内存映射中。
  Future<void> registerAudioFixture({
    required String songPath,
    required SongInfo songInfo,
    required int durationMs,
    String? embeddedLyricsText,
    Lyrics? embeddedLyrics,
  }) async {
    if (realMediaEnabled) {
      if (embeddedLyricsText == null) {
        return;
      }
      if (embeddedLyrics == null) {
        throw ArgumentError.value(
          embeddedLyrics,
          'embeddedLyrics',
          '真实媒体夹具写入内嵌歌词时必须提供结构化歌词',
        );
      }
      await _realGateway.writeLyricsTag(
        songPath: songPath,
        lyricsText: embeddedLyricsText,
        lyrics: embeddedLyrics,
        id3Version: Id3Version.v24,
      );
      return;
    }
    _fixtures[songPath] = _IntegrationMediaFixture(
      songInfo: songInfo,
      durationMs: durationMs,
      lyricsText: embeddedLyricsText,
    );
  }

  LocalMatchMediaGateway get _realGateway {
    final LocalMatchMediaGateway? gateway = _delegate;
    if (gateway == null) {
      throw StateError('真实媒体 profile 未配置媒体网关');
    }
    return gateway;
  }

  _IntegrationMediaFixture _fixtureFor(String songPath) {
    final _IntegrationMediaFixture? fixture = _fixtures[songPath];
    if (fixture == null) {
      throw StateError('离线媒体夹具未登记: $songPath');
    }
    return fixture;
  }

  @override
  Future<bool> hasLyricsTag(String songPath) async {
    if (realMediaEnabled) {
      return _realGateway.hasLyricsTag(songPath);
    }
    final String? lyricsText = _fixtures[songPath]?.lyricsText;
    return lyricsText != null && lyricsText.trim().isNotEmpty;
  }

  @override
  Future<int?> readAudioDurationMs(String audioPath) async {
    if (realMediaEnabled) {
      return _realGateway.readAudioDurationMs(audioPath);
    }
    return _fixtureFor(audioPath).durationMs;
  }

  @override
  Future<List<SongInfo>> readAudioSongInfos(String songPath) async {
    if (realMediaEnabled) {
      return _realGateway.readAudioSongInfos(songPath);
    }
    return <SongInfo>[_fixtureFor(songPath).songInfo];
  }

  /// 按自动匹配使用的搜索词查找已登记音频信息。
  ///
  /// 生产 AutoFetch 会同时校验标题、艺术家、版本和四秒时长差。离线歌词源若固定
  /// 伪造另一首 90 秒歌曲，会让真实夹具在歌词获取前被正确过滤，测试只能得到
  /// “匹配失败”。这里让 Fake 的首个结果复用对应夹具已探测过的元数据，不修改
  /// 生产评分规则，也不为普通搜索页凭空注册媒体数据。
  SongInfo? resolveSearchSongInfo(String keyword) {
    if (searchKeywords.length < 32) {
      searchKeywords.add(keyword);
    }
    final String normalizedKeyword = keyword.trim().toLowerCase();
    for (final _IntegrationMediaFixture fixture in _fixtures.values) {
      final SongInfo songInfo = fixture.songInfo;
      final String title = songInfo.title?.trim().toLowerCase() ?? '';
      if (title.isNotEmpty && normalizedKeyword.contains(title)) {
        return songInfo;
      }
    }
    return null;
  }

  @override
  Future<int?> readDurationMs(String songPath) {
    return readAudioDurationMs(songPath);
  }

  @override
  Future<List<SongInfo>> readSongInfos(String songPath) {
    return readAudioSongInfos(songPath);
  }

  @override
  Future<String?> readAudioLyricsText({
    required String songPath,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    if (realMediaEnabled) {
      return _realGateway.readAudioLyricsText(
        songPath: songPath,
        fileDescriptor: fileDescriptor,
        fileDescriptorNameHint: fileDescriptorNameHint,
      );
    }
    return _fixtures[songPath]?.lyricsText;
  }

  @override
  Future<void> writeLyricsTag({
    required String songPath,
    required String lyricsText,
    required Lyrics lyrics,
    required Id3Version id3Version,
    int? fileDescriptor,
    String? fileDescriptorNameHint,
  }) async {
    if (realMediaEnabled) {
      await _realGateway.writeLyricsTag(
        songPath: songPath,
        lyricsText: lyricsText,
        lyrics: lyrics,
        id3Version: id3Version,
        fileDescriptor: fileDescriptor,
        fileDescriptorNameHint: fileDescriptorNameHint,
      );
    } else {
      final _IntegrationMediaFixture? current = _fixtures[songPath];
      _fixtures[songPath] = _IntegrationMediaFixture(
        songInfo:
            current?.songInfo ??
            lyrics.songInfo.copyWith(source: Source.local, path: songPath),
        durationMs:
            current?.durationMs ??
            lyrics.songInfo.durationMs ??
            lyrics.getDurationMs(),
        lyricsText: lyricsText,
      );
    }
    writes.add(
      AudioTagWriteRequest(
        songPath: songPath,
        plainLyricsText: lyricsText,
        lyrics: lyrics,
        id3Version: id3Version,
        fileDescriptor: fileDescriptor,
        fileDescriptorNameHint: fileDescriptorNameHint,
      ),
    );
  }
}

final class _IntegrationMediaFixture {
  const _IntegrationMediaFixture({
    required this.songInfo,
    required this.durationMs,
    required this.lyricsText,
  });

  final SongInfo songInfo;
  final int durationMs;
  final String? lyricsText;
}

/// 离线 integration 使用的云端歌词源。
///
/// 这里不走 HTTP，但仍注册到真实 LyricsApi/AutoFetchUseCase 中，让页面、
/// controller、缓存、批量保存和转换链路继续按生产路径执行。
class IntegrationFakeLyricsCloudProvider implements LyricsCloudSourceProvider {
  const IntegrationFakeLyricsCloudProvider({
    required this.source,
    this.songInfoResolver,
  });

  @override
  final Source source;
  final SongInfo? Function(String keyword)? songInfoResolver;

  @override
  bool get supportsLyricsList => source == Source.kg;

  @override
  Set<SearchType> get supportedSearchTypes => source.supportedSearchTypes;

  @override
  Future<APIResultList<SourceAware>> search({
    required String keyword,
    required SearchType searchType,
    int page = 1,
    RequestCancellationToken? cancellationToken,
  }) async {
    final List<SourceAware> items = switch (searchType) {
      SearchType.album => <SourceAware>[
        _songList(keyword, SongListType.album, page),
      ],
      SearchType.songlist => <SourceAware>[
        _songList(keyword, SongListType.songlist, page),
      ],
      SearchType.songId || SearchType.song => <SourceAware>[
        _song(keyword: keyword, index: 0),
        _song(keyword: keyword, index: 1),
      ],
      _ => <SourceAware>[],
    };
    return APIResultList<SourceAware>(
      items,
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: page,
      ),
      ranges: <Source, SourceRange>{source: _rangeFor(items.length)},
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSonglist(SongListInfo songListInfo) async {
    final List<SongInfo> songs = <SongInfo>[
      _song(keyword: songListInfo.title, index: 0),
      _song(keyword: songListInfo.title, index: 1),
    ];
    return APIResultList<SongInfo>(
      songs,
      info: songListInfo,
      ranges: <Source, SourceRange>{source: _rangeFor(songs.length)},
    );
  }

  @override
  Future<APIResultList<LyricInfo>> getLyricslist(SongInfo songInfo) async {
    final List<LyricInfo> candidates = <LyricInfo>[
      LyricInfo(
        source: source,
        songInfo: songInfo,
        id: 'offline-lyric-${songInfo.id ?? songInfo.title ?? 'song'}',
        durationMs: songInfo.durationMs,
        creator: 'integration-offline',
        score: 100,
      ),
    ];
    return APIResultList<LyricInfo>(
      candidates,
      info: songInfo,
      ranges: <Source, SourceRange>{source: _rangeFor(candidates.length)},
    );
  }

  @override
  Future<Lyrics> getLyrics(Object info) async {
    final SongInfo songInfo = switch (info) {
      LyricInfo lyricInfo => lyricInfo.songInfo,
      SongInfo songInfo => songInfo,
      _ => _song(keyword: info.toString(), index: 0),
    };
    return _lyricsFor(songInfo);
  }

  SongInfo _song({required String keyword, required int index}) {
    final SongInfo? fixture = index == 0
        ? songInfoResolver?.call(keyword)
        : null;
    if (fixture != null) {
      return SongInfo(
        source: source,
        title: fixture.title,
        artist: fixture.artist,
        album: fixture.album,
        durationMs: fixture.durationMs,
        id: 'offline-${source.value.toLowerCase()}-fixture-${fixture.title.hashCode}',
        language: fixture.language,
      );
    }
    final ({String artist, String title}) parsed = _parseArtistTitle(keyword);
    final String title = parsed.title.trim().isEmpty
        ? 'Offline Song ${index + 1}'
        : parsed.title.trim();
    return SongInfo(
      source: source,
      title: index == 0 ? title : '$title ${index + 1}',
      artist: SongArtist(<String>[parsed.artist]),
      album: 'Offline Integration Album',
      durationMs: 90000 + index * 1000,
      id: 'offline-${source.value.toLowerCase()}-$index-${title.hashCode}',
      language: Language.chinese,
    );
  }

  ({String artist, String title}) _parseArtistTitle(String keyword) {
    final String normalized = keyword.trim();
    final int separator = normalized.indexOf(' - ');
    if (separator <= 0 || separator >= normalized.length - 3) {
      return (artist: 'LDDC Integration', title: normalized);
    }
    return (
      artist: normalized.substring(0, separator),
      title: normalized.substring(separator + 3),
    );
  }

  SongListInfo _songList(String keyword, SongListType type, int page) {
    final String title = keyword.trim().isEmpty
        ? 'Offline ${type.value}'
        : keyword.trim();
    return SongListInfo(
      source: source,
      type: type,
      id: 'offline-${source.value.toLowerCase()}-${type.value.toLowerCase()}-$page-${title.hashCode}',
      title: title,
      imgUrl: '',
      songCount: 2,
      publishTimeS: 1767225600,
      author: 'LDDC Integration',
    );
  }

  Lyrics _lyricsFor(SongInfo songInfo) {
    final String title = songInfo.title ?? 'Offline Song';
    final LyricsData orig = <LyricsLine>[
      _line(0, 2500, '$title 第一行'),
      _line(2500, 5200, '$title 第二行'),
    ];
    return Lyrics(
      songInfo: songInfo,
      source: source,
      id: 'offline-lyrics-${songInfo.id ?? title.hashCode}',
      durationMs: songInfo.durationMs,
      creator: 'integration-offline',
      score: 100,
      tags: <String, String>{
        'ti': title,
        'ar': songInfo.artistText,
        if (songInfo.album != null) 'al': songInfo.album!,
      },
      types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
      data: <String, LyricsData>{'orig': orig},
    );
  }

  LyricsLine _line(int startMs, int endMs, String text) {
    return LyricsLine(
      startMs: startMs,
      endMs: endMs,
      words: <LyricsWord>[
        LyricsWord(startMs: startMs, endMs: endMs, text: text),
      ],
    );
  }

  SourceRange _rangeFor(int length) {
    return length == 0
        ? const SourceRange(start: 0, end: -1, total: 0)
        : SourceRange(start: 0, end: length - 1, total: length);
  }
}

/// 离线 integration 翻译 provider，避免默认流程依赖外部翻译服务。
class IntegrationFakeTranslationClient implements TranslationClient {
  const IntegrationFakeTranslationClient();

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  }) async {
    final LyricsData orig = lyrics['orig'] ?? const <LyricsLine>[];
    return orig
        .map(
          (LyricsLine line) => LyricsLine(
            startMs: line.startMs,
            endMs: line.endMs,
            words: <LyricsWord>[
              LyricsWord(
                startMs: line.startMs,
                endMs: line.endMs,
                text: '离线翻译：${line.text}',
              ),
            ],
          ),
        )
        .toList(growable: false);
  }
}

class MemoryPickedFileHandle extends PickedFileHandle {
  const MemoryPickedFileHandle({
    required super.name,
    super.path,
    required Uint8List bytes,
  }) : _bytes = bytes;

  final Uint8List _bytes;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

Uint8List utf8Bytes(String content) => Uint8List.fromList(utf8.encode(content));

AppConfig buildIntegrationConfig({
  List<String>? searchSources,
  String? defaultSavePath,
}) {
  final AppConfig base = ConfigDefaults.current;
  return AppConfig(
    schemaVersion: base.schemaVersion,
    search: SearchConfig(
      sources: searchSources ?? const <String>['QM', 'NE', 'KG', 'LRCLIB'],
    ),
    lyrics: base.lyrics,
    match: base.match,
    translate: base.translate,
    desktop: base.desktop,
    app: base.app,
    storage: StorageConfig(
      defaultSavePath: defaultSavePath ?? base.storage.defaultSavePath,
    ),
    legacyExtras: base.legacyExtras,
  );
}

/// 把强类型配置转换为仓储允许的业务 patch。
///
/// `schemaVersion` 和未知字段只由配置加载/迁移层管理，integration harness 也不能
/// 绕过生产仓储契约直接写入，否则测试会固定一条真实业务代码无法使用的旁路。
class _ConfigPatchEncoder {
  static Map<String, Object?> encode(AppConfig config) {
    return ConfigDefaults.flattenRequired(config);
  }
}

AppConfig _withDefaultSavePath(AppConfig config, String defaultSavePath) {
  return AppConfig(
    schemaVersion: config.schemaVersion,
    search: config.search,
    lyrics: config.lyrics,
    match: config.match,
    translate: config.translate,
    desktop: config.desktop,
    app: config.app,
    storage: StorageConfig(defaultSavePath: defaultSavePath),
    legacyExtras: config.legacyExtras,
  );
}
