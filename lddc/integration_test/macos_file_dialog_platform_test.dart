import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_controller.dart';
import 'package:lddc/src/features/open_lyrics/application/open_lyrics_page_state.dart';
import 'package:lddc/src/features/open_lyrics/presentation/open_lyrics_page.dart';
import 'package:path/path.dart' as p;

import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';

const String _dialogAction = String.fromEnvironment('LDDC_MACOS_DIALOG_ACTION');
const String _workspaceRoot = String.fromEnvironment('LDDC_IT_WORKSPACE_ROOT');
const String _nativeSyncRoot = String.fromEnvironment(
  'LDDC_MACOS_HYBRID_SYNC_DIR',
);
const String _fixtureSha256 = String.fromEnvironment('LDDC_FIXTURE_SHA256');
const int _fixtureSize = int.fromEnvironment('LDDC_FIXTURE_SIZE');

void main() {
  ensureIntegrationBinding();

  final String scenarioName = 'macos_open_panel_$_dialogAction';
  testWidgets('macOS 文件面板由 Flutter 与 XCUITest 协同验证', (
    WidgetTester tester,
  ) async {
    expect(_dialogAction, anyOf('select', 'cancel'));
    expect(_workspaceRoot, isNotEmpty);
    expect(_nativeSyncRoot, isNotEmpty);
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(scenarioName: scenarioName);
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: scenarioName,
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      expect(Platform.isMacOS, isTrue, reason: '该场景只能在 macOS 运行');
      expect(runtime.profile, 'platform');
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
      reporter
        ..recordCapabilityEvidence(
          'desktopProcess',
          'integration_test_real_macos_application',
        )
        ..recordCapabilityEvidence(
          'windowHost',
          'integration_test_operated_flutter_window',
        );

      final AppShellDriver shell = AppShellDriver(tester);
      final OpenLyricsDriver openLyrics = OpenLyricsDriver(tester);
      await shell.openRoute(AppShellRoute.openLyrics);
      final container = scopedProviderContainer(
        tester,
        find.byType(OpenLyricsPage),
      );

      await reporter.runStep('open_production_ns_open_panel', () async {
        try {
          // hybrid 状态位于 LDDC App Sandbox 容器内，只能由
          // Flutter 应用进程写入。XCUITest 只读该状态并操作已经
          // 打开的系统面板，避免跨沙箱写入导致 EPERM。
          await _writeHybridState(
            runId: runtime.runId,
            scenario: scenarioName,
            state: 'picker_requested',
          );
          await openLyrics.openSongFile();
          await pumpUntil(
            tester,
            () {
              final OpenLyricsPageState state = container.read(
                openLyricsPageControllerProvider,
              );
              if (_dialogAction == 'select') {
                return !state.isOpening &&
                    state.inputType == OpenLyricsInputType.songFile &&
                    state.inputName == 'audio_sample.mp3' &&
                    state.inputPath != null &&
                    state.rawText.contains('Hello LDDC');
              }
              return !state.isOpening &&
                  state.inputType == null &&
                  state.inputName.isEmpty &&
                  state.audioFileHandle == null;
            },
            // macOS hybrid 的原生动作预算由 runner 通过 test-only 配置传入。
            // 普通 integration 场景仍保留各自的 30 秒边界；这里只避免 Flutter
            // 在 XCUITest 尚处于系统面板操作时先退出并制造 Lost connection。
            timeout: runtime.defaultStepTimeout,
            reason: _dialogAction == 'select'
                ? '等待 NSOpenPanel 选择结果和嵌入歌词返回 Flutter'
                : '等待 NSOpenPanel 取消且 Flutter 保持空输入',
          );
          // 只有业务结果已经收敛才发布 completed。面板关闭但
          // 没有返回文件的情况会在上方有界等待中失败，并写入
          // flutter_failed，避免 XCUITest 把“关闭”误报为“选择成功”。
          await _writeHybridState(
            runId: runtime.runId,
            scenario: scenarioName,
            state: 'flutter_completed',
            success: true,
          );
        } on Object catch (error, stackTrace) {
          // 失败状态只保留错误类型；完整异常由 Flutter JSONL
          // 记录，避免 hybrid diagnostic 泄露容器或 fixture 绝对路径。
          try {
            await _writeHybridState(
              runId: runtime.runId,
              scenario: scenarioName,
              state: 'flutter_failed',
              success: false,
              error: '${error.runtimeType}: Flutter file picker failed',
            );
          } on Object {
            // 状态记录失败不能覆盖原始业务异常。
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

      final OpenLyricsPageState state = container.read(
        openLyricsPageControllerProvider,
      );
      if (_dialogAction == 'select') {
        expect(state.inputType, OpenLyricsInputType.songFile);
        expect(state.inputName, 'audio_sample.mp3');
        expect(state.rawText, contains('Hello LDDC'));
        expect(state.notice, isNull, reason: state.notice?.detail);
        final String selectedPath = state.inputPath!;
        final File selectedFile = File(selectedPath);
        final List<int> bytes = selectedFile.readAsBytesSync();
        expect(bytes, hasLength(_fixtureSize));
        expect(sha256.convert(bytes).toString(), _fixtureSha256);
        reporter
          ..recordArtifact(
            name: 'audio_sample.mp3',
            size: bytes.length,
            sha256: _fixtureSha256,
          )
          ..recordCapabilityEvidence(
            'nativeChannels',
            'production_file_picker_selection_returned_to_flutter',
          );
        await container
            .read(openLyricsPageControllerProvider.notifier)
            .disposeSession();
        expect(
          container.read(openLyricsPageControllerProvider).audioFileHandle,
          isNull,
        );
        reporter.recordCapabilityEvidence(
          'resourceCleanup',
          'selected_audio_handle_released',
        );
      } else {
        expect(state.inputType, isNull);
        expect(state.inputName, isEmpty);
        expect(state.audioFileHandle, isNull);
        expect(state.notice, isNull);
        reporter
          ..recordCapabilityEvidence(
            'nativeChannels',
            'production_file_picker_cancel_returned_to_flutter',
          )
          ..recordCapabilityEvidence(
            'resourceCleanup',
            'cancel_left_no_audio_handle',
          );
      }
    });
  }, semanticsEnabled: false);
}

Future<void> _writeHybridState({
  required String runId,
  required String scenario,
  required String state,
  bool? success,
  String? error,
}) async {
  final Directory directory = Directory(_nativeSyncRoot);
  await directory.create(recursive: true);
  final File target = _hybridStateFile(scenario);
  final File staging = File('${target.path}.tmp');
  final String executablePath = await File(
    Platform.resolvedExecutable,
  ).resolveSymbolicLinks();
  // macOS 可执行文件固定位于 App.app/Contents/MacOS 下。把实际 bundle 路径交给
  // XCUITest，避免同一 bundle id 的 DerivedData 构建抢占正在运行的 Flutter 应用代理。
  final String appBundlePath = p.dirname(p.dirname(p.dirname(executablePath)));
  if (p.extension(appBundlePath).toLowerCase() != '.app') {
    throw StateError('无法从当前可执行文件解析 macOS app bundle');
  }
  await staging.writeAsString(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'runId': runId,
      'scenario': scenario,
      'state': state,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'appPid': pid,
      'appBundlePath': appBundlePath,
      'action': _dialogAction,
      'success': success,
      'error': error,
    }),
    flush: true,
  );
  await staging.rename(target.path);
}

File _hybridStateFile(String scenario) {
  return File(p.join(_nativeSyncRoot, '$scenario.state.json'));
}
