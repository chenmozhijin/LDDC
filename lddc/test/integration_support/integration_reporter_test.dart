import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/integration_reporter.dart';

void main() {
  group('IntegrationReporter', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'lddc_integration_reporter_test_',
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('空步骤默认写为基础设施失败，不能算通过', () async {
      final IntegrationReporter reporter = _createReporter(tempDir, 'empty');

      await reporter.writeSummary();

      final Map<String, Object?> payload = _readReport(tempDir, 'empty');
      expect(payload['status'], 'infrastructureFailed');
      expect(payload['coverageStatus'], 'executed');
      expect(payload['success'], isFalse);
    });

    test('blocked 和 skipped 空报告不会伪装成 passed', () async {
      final IntegrationReporter blocked = _createReporter(tempDir, 'blocked');
      final IntegrationReporter skipped = _createReporter(tempDir, 'skipped');

      await blocked.writeSummary(extra: <String, Object?>{'blocked': true});
      await skipped.writeSummary(extra: <String, Object?>{'skipped': true});

      expect(_readReport(tempDir, 'blocked')['status'], 'blocked');
      expect(_readReport(tempDir, 'blocked')['success'], isFalse);
      expect(_readReport(tempDir, 'blocked')['coverageStatus'], 'blocked');
      expect(_readReport(tempDir, 'skipped')['status'], 'skipped');
      expect(_readReport(tempDir, 'skipped')['success'], isFalse);
      expect(_readReport(tempDir, 'skipped')['coverageStatus'], 'skipped');
    });

    test('失败步骤会落盘并让 summary 失败', () async {
      final IntegrationReporter reporter = _createReporter(tempDir, 'failed');

      await expectLater(
        reporter.runStep('boom', () async {
          throw StateError('broken');
        }),
        throwsStateError,
      );
      await reporter.writeSummary();

      final Map<String, Object?> payload = _readReport(tempDir, 'failed');
      expect(payload['status'], 'failed');
      expect(payload['success'], isFalse);
      final List<Object?> steps = payload['steps']! as List<Object?>;
      expect(steps, hasLength(1));
      expect((steps.single! as Map<String, Object?>)['success'], isFalse);
    });

    test('writeSummary 幂等，避免 tearDown 重复覆盖失败报告', () async {
      final IntegrationReporter reporter = _createReporter(
        tempDir,
        'idempotent',
      );

      await reporter.writeSummary(extra: <String, Object?>{'blocked': true});
      await reporter.writeSummary();

      final Map<String, Object?> payload = _readReport(tempDir, 'idempotent');
      expect(payload['status'], 'blocked');
    });

    test('运行时上下文会写入场景报告', () async {
      final IntegrationReporter reporter = _createReporter(
        tempDir,
        'runtime-context',
      );
      reporter.recordContext('viewport', <String, Object?>{
        'logicalWidth': 1280,
        'logicalHeight': 720,
      });

      await reporter.runStep<void>('pass', () async {});
      await reporter.writeSummary();

      final Map<String, Object?> payload = _readReport(
        tempDir,
        'runtime-context',
      );
      final Map<String, Object?> extra = Map<String, Object?>.from(
        payload['extra']! as Map<dynamic, dynamic>,
      );
      expect(extra['viewport'], <String, Object?>{
        'logicalWidth': 1280,
        'logicalHeight': 720,
      });
    });

    test('能力模式与真实动作证据会写入场景报告', () async {
      final IntegrationReporter reporter = _createReporter(
        tempDir,
        'capability-evidence',
        profile: 'platform',
        capabilities: _platformCapabilities(),
      );

      reporter.recordCapabilityEvidence(
        'nativeChannels',
        'invokeMethod',
        details: const <String, Object?>{'channel': 'lddc/test'},
      );
      await reporter.runStep<void>('pass', () async {});
      await reporter.writeSummary();

      final Map<String, Object?> payload = _readReport(
        tempDir,
        'capability-evidence',
      );
      expect(
        ((payload['capabilities']! as Map<String, Object?>)['nativeChannels']!
            as Map<String, Object?>)['mode'],
        'real',
      );
      final Map<String, Object?> nativeChannels = Map<String, Object?>.from(
        (payload['capabilities']! as Map<String, Object?>)['nativeChannels']!
            as Map<dynamic, dynamic>,
      );
      expect(nativeChannels['evidence'], isNotEmpty);
      expect(payload['schemaVersion'], 2);
      expect(payload['runId'], 'unit-test-run');
      expect(payload['framework'], 'integration_test');
      expect(payload['platform'], 'test');
    });

    test('场景失败会写入截图诊断且不吞掉原始异常', () async {
      final IntegrationReporter reporter = _createReporter(
        tempDir,
        'failure-artifact',
      );
      int artifactCalls = 0;
      reporter.registerFailureArtifactWriter(() async {
        artifactCalls += 1;
        return '${tempDir.path}${Platform.pathSeparator}failure.png';
      });

      await expectLater(
        reporter.runScenario<void>(() async {
          await reporter.runStep<void>('fail', () async {
            throw StateError('original failure');
          });
        }),
        throwsStateError,
      );

      final Map<String, Object?> payload = _readReport(
        tempDir,
        'failure-artifact',
      );
      final Map<String, Object?> extra = Map<String, Object?>.from(
        payload['extra']! as Map<dynamic, dynamic>,
      );
      expect(artifactCalls, 1);
      expect(extra['failureScreenshot'], contains('failure.png'));
      expect(extra['error'], contains('original failure'));
      expect(payload['status'], 'failed');
    });

    test('profile 明确区分离线、平台和真实网络能力', () {
      final IntegrationRuntimeConfig offline =
          IntegrationRuntimeConfig.fromEnvironment(
            scenarioName: 'offline',
            environment: _runtimeEnvironment('offline'),
          );
      final IntegrationRuntimeConfig platform =
          IntegrationRuntimeConfig.fromEnvironment(
            scenarioName: 'platform',
            environment: _runtimeEnvironment('platform'),
          );
      final IntegrationRuntimeConfig live =
          IntegrationRuntimeConfig.fromEnvironment(
            scenarioName: 'live',
            environment: _runtimeEnvironment('live'),
          );

      expect(offline.realNetworkEnabled, isFalse);
      expect(offline.realMediaEnabled, isFalse);
      expect(offline.deviceName, 'windows');
      expect(offline.requestRetryCount, 0);
      expect(platform.realNetworkEnabled, isFalse);
      expect(platform.realMediaEnabled, isFalse);
      expect(platform.capabilities.filePicker, 'notApplicable');
      expect(platform.capabilities.nativeChannels, 'real');
      expect(platform.capabilities.windowHost, 'real');
      expect(live.realNetworkEnabled, isTrue);
      expect(live.realMediaEnabled, isTrue);
      expect(live.capabilities.filePicker, 'scripted');
    });

    test('废弃或未知 profile 会立即失败', () {
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'legacy',
          environment: <String, String>{
            ..._runtimeEnvironment('offline'),
            'LDDC_IT_SKIP_REAL_NETWORK': '0',
          },
        ),
        throwsStateError,
      );
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'unknown',
          environment: const <String, String>{'LDDC_IT_PROFILE': 'full'},
        ),
        throwsStateError,
      );
    });

    test('缺少显式 profile/device/runId 或损坏能力契约会立即失败', () {
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'missing-profile',
          environment: const <String, String>{'LDDC_IT_DEVICE': 'windows'},
        ),
        throwsStateError,
      );
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'missing-device',
          environment: <String, String>{..._runtimeEnvironment('offline')}
            ..remove('LDDC_IT_DEVICE'),
        ),
        throwsStateError,
      );
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'missing-run-id',
          environment: <String, String>{..._runtimeEnvironment('live')}
            ..remove('LDDC_IT_RUN_ID'),
        ),
        throwsStateError,
      );
      expect(
        () => IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'broken-capability',
          environment: <String, String>{
            ..._runtimeEnvironment('offline'),
            'LDDC_IT_CAPABILITIES_B64': 'not-base64',
          },
        ),
        throwsStateError,
      );
    });

    test('同一场景的多次运行使用不同报告文件', () {
      final Map<String, String> firstEnvironment = _runtimeEnvironment(
        'offline',
        runId: 'repeated-first',
      );
      final Map<String, String> secondEnvironment = _runtimeEnvironment(
        'offline',
        runId: 'repeated-second',
      );
      final IntegrationRuntimeConfig first =
          IntegrationRuntimeConfig.fromEnvironment(
            scenarioName: 'repeated',
            environment: firstEnvironment,
          );
      final IntegrationRuntimeConfig second =
          IntegrationRuntimeConfig.fromEnvironment(
            scenarioName: 'repeated',
            environment: secondEnvironment,
          );

      expect(first.reportPath.path, isNot(second.reportPath.path));
    });
  });
}

IntegrationReporter _createReporter(
  Directory tempDir,
  String scenarioName, {
  String profile = 'offline',
  IntegrationCapabilityContract? capabilities,
}) {
  return IntegrationReporter(
    scenarioName: scenarioName,
    runtimeConfig: IntegrationRuntimeConfig(
      runId: 'unit-test-run',
      framework: 'integration_test',
      profile: profile,
      deviceName: 'test',
      capabilities: capabilities ?? _offlineCapabilities(),
      reportRoot: tempDir,
      reportPath: File(
        '${tempDir.path}${Platform.pathSeparator}$scenarioName.json',
      ),
      ffmpegExecutable: 'ffmpeg',
      requestTimeout: const Duration(seconds: 1),
      requestRetryCount: 0,
      defaultStepTimeout: const Duration(seconds: 1),
      longStepTimeout: const Duration(seconds: 1),
      desktopStepTimeout: const Duration(seconds: 1),
    ),
  );
}

Map<String, String> _runtimeEnvironment(
  String profile, {
  String runId = 'runtime-test',
}) {
  final IntegrationCapabilityContract capabilities = switch (profile) {
    'offline' => _offlineCapabilities(),
    'platform' => _platformCapabilities(),
    'live' => _liveCapabilities(),
    _ => _offlineCapabilities(),
  };
  final String encoded = base64Encode(
    utf8.encode(jsonEncode(_contractPayload(capabilities))),
  );
  return <String, String>{
    'LDDC_IT_PROFILE': profile,
    'LDDC_IT_DEVICE': 'windows',
    'LDDC_IT_RUN_ID': runId,
    'LDDC_IT_FRAMEWORK': 'integration_test',
    'LDDC_IT_CAPABILITIES_B64': encoded,
  };
}

IntegrationCapabilityContract _offlineCapabilities() =>
    IntegrationCapabilityContract(
      _states(<String, String>{
        'network': 'fake',
        'translation': 'fake',
        'filePicker': 'scripted',
        'pathOpener': 'recording',
        'media': 'memory',
        'nativeChannels': 'mocked',
        'desktopProcess': 'inProcess',
        'windowHost': 'noop',
      }),
    );

IntegrationCapabilityContract _platformCapabilities() =>
    IntegrationCapabilityContract(
      _states(
        <String, String>{
          'network': 'notApplicable',
          'translation': 'notApplicable',
          'filePicker': 'notApplicable',
          'pathOpener': 'notApplicable',
          'media': 'notApplicable',
          'nativeChannels': 'real',
          'desktopProcess': 'notApplicable',
          'windowHost': 'real',
        },
        requiredReal: <String>{'nativeChannels', 'windowHost'},
      ),
    );

IntegrationCapabilityContract _liveCapabilities() =>
    IntegrationCapabilityContract(
      _states(
        <String, String>{
          'network': 'real',
          'translation': 'real',
          'filePicker': 'scripted',
          'pathOpener': 'recording',
          'media': 'real',
          'nativeChannels': 'mocked',
          'desktopProcess': 'inProcess',
          'windowHost': 'noop',
        },
        requiredReal: <String>{'network', 'translation', 'media'},
      ),
    );

Map<String, IntegrationCapabilityState> _states(
  Map<String, String> modes, {
  Set<String> requiredReal = const <String>{},
}) => <String, IntegrationCapabilityState>{
  for (final MapEntry<String, String> entry in modes.entries)
    entry.key: IntegrationCapabilityState(
      mode: entry.value,
      required: requiredReal.contains(entry.key),
      applicable: entry.value != 'notApplicable',
      reason: entry.value == 'notApplicable' ? '当前测试不适用' : '测试契约',
    ),
};

Map<String, Object?> _contractPayload(
  IntegrationCapabilityContract capabilities,
) => <String, Object?>{
  for (final String name in capabilities.names)
    name: <String, Object?>{
      'mode': capabilities.state(name).mode,
      'required': capabilities.state(name).required,
      'applicable': capabilities.state(name).applicable,
      'reason': capabilities.state(name).reason,
    },
};

Map<String, Object?> _readReport(Directory tempDir, String scenarioName) {
  final File file = File(
    '${tempDir.path}${Platform.pathSeparator}$scenarioName.json',
  );
  return (jsonDecode(file.readAsStringSync()) as Map<String, Object?>);
}
