import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_controller.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_state.dart';
import 'package:lddc/src/features/open_lyrics/presentation/open_lyrics_page.dart';
import 'package:path/path.dart' as p;

import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';

const String _dialogAction = String.fromEnvironment(
  'LDDC_WINDOWS_DIALOG_ACTION',
);
const String _workspaceRoot = String.fromEnvironment('LDDC_IT_WORKSPACE_ROOT');
const String _nativeSyncRoot = String.fromEnvironment(
  'LDDC_WINDOWS_NATIVE_SYNC_DIR',
);

void main() {
  ensureIntegrationBinding();

  final String scenarioName = 'windows_file_dialog_$_dialogAction';
  testWidgets(
    'Windows 文件对话框由 Flutter 与 FlaUI 协同验证',
    (WidgetTester tester) async {
      expect(
        _dialogAction,
        anyOf('select', 'cancel'),
        reason: 'runner 必须显式指定 select 或 cancel',
      );
      final IntegrationRuntimeConfig runtime =
          IntegrationRuntimeConfig.fromEnvironment(scenarioName: scenarioName);
      final IntegrationReporter reporter = IntegrationReporter(
        scenarioName: scenarioName,
        runtimeConfig: runtime,
      );
      addTearDown(reporter.writeSummary);

      await reporter.runScenario(() async {
        expect(Platform.isWindows, isTrue, reason: '该场景只能在 Windows 运行');
        expect(runtime.profile, 'platform');
        expect(
          _workspaceRoot,
          isNotEmpty,
          reason: 'runner 必须提供 D 盘测试 workspace',
        );
        expect(_nativeSyncRoot, isNotEmpty, reason: 'runner 必须提供原生动作同步目录');
        runtime.verifyCurrentDevice();

        final IntegrationAppHandle app = await launchIntegrationApp(
          tester,
          scenarioName: scenarioName,
          runtimeConfig: runtime,
          reporter: reporter,
          useRealFilePicker: true,
          workspaceParent: Directory(_workspaceRoot),
        );
        addTearDown(app.dispose);

        final AppShellDriver shell = AppShellDriver(tester);
        final OpenLyricsDriver openLyrics = OpenLyricsDriver(tester);
        await shell.openRoute(AppShellRoute.openLyrics);
        final container = scopedProviderContainer(
          tester,
          find.byType(OpenLyricsPage),
        );
        reporter.recordCapabilityEvidence(
          'desktopProcess',
          'integration_test_real_windows_application',
        );

        if (_dialogAction == 'select') {
          await reporter.runStep('select_lyrics_file_round_trip', () async {
            await openLyrics.openLyricsFile();
            await pumpUntil(
              tester,
              () {
                final OpenLyricsPageState state = container.read(
                  openLyricsPageControllerProvider,
                );
                return !state.isOpening &&
                    state.inputType == OpenLyricsInputType.lyricsFile &&
                    state.inputName == 'lyrics_sample.lrc' &&
                    state.rawText.contains('Hello LDDC');
              },
              timeout: runtime.longStepTimeout,
              reason: '等待真实 IFileDialog 选择结果返回 Flutter 页面',
            );
            final OpenLyricsPageState state = container.read(
              openLyricsPageControllerProvider,
            );
            expect(state.notice, isNull, reason: state.notice?.detail);
            expect(state.lyricsFileBytes, isNotNull);
            expect(state.lyricsFileBytes, hasLength(165));
          });
          reporter.recordCapabilityEvidence(
            'nativeChannels',
            'file_selector_selection_returned_to_flutter',
          );
        } else {
          await reporter.runStep('cancel_and_reopen_round_trip', () async {
            for (var attempt = 0; attempt < 2; attempt += 1) {
              await openLyrics.openLyricsFile();
              await pumpUntil(
                tester,
                () =>
                    !container.read(openLyricsPageControllerProvider).isOpening,
                timeout: runtime.longStepTimeout,
                reason: '等待第 ${attempt + 1} 次真实 IFileDialog 取消结果返回',
              );
              final OpenLyricsPageState state = container.read(
                openLyricsPageControllerProvider,
              );
              expect(state.inputType, isNull);
              expect(state.inputName, isEmpty);
              expect(state.rawText, isEmpty);
              expect(state.previewState, OpenLyricsPreviewState.idle);
              expect(state.notice, isNull);
              await pumpUntil(
                tester,
                () => File(
                  p.join(_nativeSyncRoot, 'dialog_${attempt + 1}_closed.ready'),
                ).existsSync(),
                timeout: runtime.defaultStepTimeout,
                reason: '等待 FlaUI 确认第 ${attempt + 1} 次原生对话框已经消失',
              );
            }
          });
          reporter.recordCapabilityEvidence(
            'nativeChannels',
            'file_selector_cancel_and_reopen_returned_to_flutter',
          );
        }

        await reporter.runStep('release_native_accessibility_client', () async {
          await pumpUntil(
            tester,
            () => File(
              p.join(_nativeSyncRoot, 'automation_disposed.ready'),
            ).existsSync(),
            timeout: runtime.defaultStepTimeout,
            reason: '等待 FlaUI 释放 UIA3 automation 客户端',
          );
          expect(
            tester.binding.platformDispatcher.semanticsEnabled,
            isTrue,
            reason: 'FlaUI 必须已通过真实 UIA 连接启用 Windows 平台语义',
          );
          // Flutter Windows engine 在 UIA 客户端断开后仍会把本进程的
          // semanticsEnabled 保持为 true。Flutter Test 无法区分该平台持有句柄
          // 与测试自己遗漏的句柄，因此只在已收到 Automation.Dispose 证据后，
          // 通过公开 TestPlatformDispatcher 覆盖触发标准回调释放平台句柄。
          // testWidgets 本身禁用 semantics，随后 outstanding 仍非零就是真泄漏。
          tester.binding.platformDispatcher.semanticsEnabledTestValue = false;
          await tester.pump();
          expect(tester.binding.debugOutstandingSemanticsHandles, 0);
        });
      });
    },
    // FlaUI 只负责真实 IFileDialog，不需要 Flutter 测试框架额外持有
    // semantics 句柄；显式关闭可避免测试结束时把辅助功能句柄误判为泄漏。
    semanticsEnabled: false,
  );
}
