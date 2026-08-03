import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/capability/capability.dart';
import 'package:window_manager/window_manager.dart';

import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';
import 'support/integration_viewport.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('platform capability smoke: 真实插件注册与错误路径', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'platform_capability_smoke',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'platform_capability_smoke',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      expect(
        runtime.profile,
        anyOf('platform', 'live'),
        reason: '真实平台通道 smoke 不能在 offline profile 中运行',
      );
      runtime.verifyCurrentDevice();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('LDDC'))),
      );
      await tester.pump(kIntegrationInteractionPump);
      final IntegrationViewportSnapshot viewport =
          await captureIntegrationViewport(tester);
      debugPrint(
        'integration[platform_capability_smoke] viewport ${viewport.summary}',
      );
      reporter.recordContext('viewport', viewport.toJson());

      final AppCapability capability = AppCapabilityResolver.resolveCurrent();
      debugPrint(
        'integration[platform_capability_smoke] capabilities=${capability.toMap()}',
      );
      await reporter.runStep('capability_matrix', () async {
        _expectCurrentCapability(capability);
        return capability.toMap();
      }, details: (Map<String, bool> value) => <String, Object?>{...value});

      final Map<String, Object?> nativeChannelEvidence = await reporter.runStep(
        'native_channel_probe',
        _probeNativeChannel,
        details: (Map<String, Object?> value) => value,
      );
      reporter.recordCapabilityEvidence(
        'nativeChannels',
        'native_channel_probe',
        details: nativeChannelEvidence,
      );
      await reporter.runStep('native_viewport_contract', () async {
        _expectViewportContract(viewport);
        return viewport.toJson();
      }, details: (Map<String, Object?> value) => value);
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // viewport 尺寸本身只能证明 Flutter 正在渲染，不能证明桌面窗口插件
        // 工作。这里复用上面已经成功返回的真实 window_manager 调用结果；
        // 移动端不会再伪造 windowHost，更不会把应用自身 PID 说成桌面子进程。
        reporter.recordCapabilityEvidence(
          'windowHost',
          'window_manager_state_read',
          details: nativeChannelEvidence,
        );
      }
    }, extra: <String, Object?>{'capabilities': capabilityMap()});
  });
}

void _expectViewportContract(IntegrationViewportSnapshot viewport) {
  if (!viewport.isDesktop) {
    // Actions 的 Android/iOS 使用手机模拟器。此断言可直接阻止 harness
    // 再把移动端伪装成 1440 宽的桌面 viewport。平板响应式尺寸由
    // 独立 Widget 矩阵覆盖，不与这两个手机 E2E job 混用。
    expect(viewport.logicalSize.width, lessThan(980));
    expect(viewport.logicalSize.height, greaterThan(0));
    return;
  }

  final Size expected = viewport.expectedDesktopContentSize;
  expect(
    viewport.logicalSize.width,
    closeTo(expected.width, 2),
    reason: '桌面 Flutter 内容宽度必须符合统一原生窗口契约',
  );
  expect(
    viewport.logicalSize.height,
    closeTo(expected.height, 2),
    reason: '桌面 Flutter 内容高度必须符合统一原生窗口契约',
  );
  expect(
    viewport.logicalSize.aspectRatio,
    closeTo(16 / 9, 0.02),
    reason: '工作区不足时必须等比缩小，不能单独压缩宽或高',
  );

  final Rect? windowBounds = viewport.windowBounds;
  final Rect? visibleBounds = viewport.displayVisibleBounds;
  final bool isWayland =
      Platform.isLinux &&
      Platform.environment['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland';
  if (windowBounds != null && visibleBounds != null && !isWayland) {
    final Rect toleratedVisibleBounds = visibleBounds.inflate(2);
    expect(toleratedVisibleBounds.contains(windowBounds.topLeft), isTrue);
    expect(toleratedVisibleBounds.contains(windowBounds.bottomRight), isTrue);
  }
}

Map<String, bool> capabilityMap() {
  return AppCapabilityResolver.resolveCurrent().toMap();
}

void _expectCurrentCapability(AppCapability capability) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    expect(capability.multiWindow, isTrue);
    expect(capability.systemTray, isTrue);
    expect(capability.audioTagWrite, isTrue);
    expect(capability.desktopPanelEmbedded, Platform.isWindows);
    return;
  }
  if (Platform.isAndroid) {
    expect(capability.androidSafTreeAccess, isTrue);
    expect(capability.androidCueTrackResolve, isTrue);
    expect(capability.directoryRecursiveScan, isTrue);
    expect(capability.audioTagWrite, isTrue);
    return;
  }
  if (Platform.isIOS) {
    expect(capability.androidSafTreeAccess, isFalse);
    expect(capability.directoryRecursiveScan, isFalse);
    expect(capability.audioTagWrite, isTrue);
    return;
  }
  fail('不支持的平台');
}

Future<Map<String, Object?>> _probeNativeChannel() async {
  if (Platform.isAndroid) {
    const MethodChannel fdChannel = MethodChannel('lddc/android_saf_fd');
    const MethodChannel treeChannel = MethodChannel('lddc/android_saf_tree');
    final List<Object?>? persistedTrees = await treeChannel
        .invokeListMethod<Object?>('listPersistedTrees');
    expect(persistedTrees, isNotNull);
    try {
      await fdChannel.invokeMethod<void>('closeFd', <String, Object?>{
        'fd': -1,
      });
    } on PlatformException catch (error) {
      expect(error.code, 'invalid_argument');
      return <String, Object?>{
        'channels': <String>['lddc/android_saf_fd', 'lddc/android_saf_tree'],
        'persistedTreeCount': persistedTrees!.length,
        'validatedError': error.code,
      };
    }
    fail('Android SAF 必须拒绝负数 fd');
  }
  if (Platform.isIOS) {
    const MethodChannel channel = MethodChannel('lddc/ios_search_audio_tag');
    await channel.invokeMethod<void>('closeAllOpenedFiles');
    return <String, Object?>{
      'channel': 'lddc/ios_search_audio_tag',
      'resourceCleanup': true,
    };
  }

  // 桌面 smoke 使用真实 window_manager 通道读取窗口状态；如果插件未注册，
  // invokeMethod 会直接抛出 MissingPluginException，报告不会被标记为通过。
  await windowManager.ensureInitialized();
  final bool visible = await windowManager.isVisible();
  return <String, Object?>{
    'channel': 'window_manager',
    'windowVisible': visible,
  };
}
