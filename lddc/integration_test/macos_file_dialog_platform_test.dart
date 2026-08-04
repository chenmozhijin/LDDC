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
        await _writePickerRequestedMarker(
          runId: runtime.runId,
          scenario: scenarioName,
        );
        await openLyrics.openSongFile();
        await pumpUntil(
          tester,
          () => !container.read(openLyricsPageControllerProvider).isOpening,
          timeout: runtime.longStepTimeout,
          reason: '等待 XCUITest 操作真实 NSOpenPanel 并返回 Flutter',
        );
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

Future<void> _writePickerRequestedMarker({
  required String runId,
  required String scenario,
}) async {
  final Directory directory = Directory(_nativeSyncRoot);
  await directory.create(recursive: true);
  final File target = File(p.join(directory.path, '$scenario.picker.json'));
  final File staging = File('${target.path}.tmp');
  await staging.writeAsString(
    jsonEncode(<String, Object?>{
      'runId': runId,
      'scenario': scenario,
      'pid': pid,
      'state': 'picker_requested',
    }),
    flush: true,
  );
  await staging.rename(target.path);
}
