import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'integration_report_status.dart';

typedef IntegrationFailureArtifactWriter = Future<String?> Function();

class IntegrationCapabilityState {
  const IntegrationCapabilityState({
    required this.mode,
    required this.required,
    required this.applicable,
    required this.reason,
  });

  final String mode;
  final bool required;
  final bool applicable;
  final String reason;

  factory IntegrationCapabilityState.fromJson(
    String name,
    Map<String, Object?> json,
  ) {
    if (json.keys.toSet().difference(<String>{
      'mode',
      'required',
      'applicable',
      'reason',
    }).isNotEmpty) {
      throw StateError('capability=$name 包含未知字段');
    }
    final Object? mode = json['mode'];
    final Object? required = json['required'];
    final Object? applicable = json['applicable'];
    final Object? reason = json['reason'];
    if (mode is! String || mode.trim().isEmpty) {
      throw StateError('capability=$name 缺少有效 mode');
    }
    if (required is! bool || applicable is! bool) {
      throw StateError('capability=$name 缺少 required/applicable 布尔值');
    }
    if (reason is! String || reason.trim().isEmpty) {
      throw StateError('capability=$name 缺少原因说明');
    }
    if (required && !applicable) {
      throw StateError('capability=$name 不适用时不能设为 required');
    }
    if (!applicable && mode != 'notApplicable') {
      throw StateError('capability=$name 不适用时 mode 必须为 notApplicable');
    }
    if (applicable && mode == 'notApplicable') {
      throw StateError('capability=$name 适用时不能使用 notApplicable');
    }
    return IntegrationCapabilityState(
      mode: mode,
      required: required,
      applicable: applicable,
      reason: reason,
    );
  }

  Map<String, Object?> toJson({
    List<Map<String, Object?>> evidence = const <Map<String, Object?>>[],
  }) => <String, Object?>{
    'mode': mode,
    'required': required,
    'applicable': applicable,
    'reason': reason,
    'evidence': evidence,
  };
}

/// runner 从版本化矩阵解析出的“当前平台 + profile + 场景”能力契约。
///
/// 能力名称是动态的，新增原生场景时只需扩展矩阵和 verifier，不需要再修改
/// Dart 数据结构。应用进程只负责证明自己实际执行的动作，不能在运行时把
/// `real` 自动降级成 Fake，也不能给不适用能力补一条伪证据。
class IntegrationCapabilityContract {
  IntegrationCapabilityContract(Map<String, IntegrationCapabilityState> states)
    : _states = Map<String, IntegrationCapabilityState>.unmodifiable(states) {
    if (_states.isEmpty) {
      throw StateError('integration capability 契约不能为空');
    }
  }

  final Map<String, IntegrationCapabilityState> _states;

  factory IntegrationCapabilityContract.fromEnvironment({
    required Map<String, String> environment,
    required String profile,
  }) {
    final String encoded =
        environment['LDDC_IT_CAPABILITIES_B64']?.trim() ?? '';
    if (encoded.isEmpty) {
      throw StateError('profile=$profile 必须显式设置 LDDC_IT_CAPABILITIES_B64');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
    } on Object catch (error) {
      throw StateError('LDDC_IT_CAPABILITIES_B64 不是有效契约：$error');
    }
    if (decoded is! Map) {
      throw StateError('LDDC_IT_CAPABILITIES_B64 顶层必须为对象');
    }
    final Map<String, IntegrationCapabilityState> states =
        <String, IntegrationCapabilityState>{};
    for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
      final String name = entry.key.toString().trim();
      if (name.isEmpty || entry.value is! Map) {
        throw StateError('LDDC_IT_CAPABILITIES_B64 包含无效能力项');
      }
      states[name] = IntegrationCapabilityState.fromJson(
        name,
        Map<String, Object?>.from(entry.value as Map<dynamic, dynamic>),
      );
    }
    return IntegrationCapabilityContract(states);
  }

  Iterable<String> get names => _states.keys;

  bool contains(String name) => _states.containsKey(name);

  IntegrationCapabilityState state(String name) {
    final IntegrationCapabilityState? value = _states[name];
    if (value == null) {
      throw StateError('当前场景没有声明 capability=$name');
    }
    return value;
  }

  String mode(String name) => state(name).mode;

  String get network => mode('network');
  String get translation => mode('translation');
  String get filePicker => mode('filePicker');
  String get pathOpener => mode('pathOpener');
  String get media => mode('media');
  String get nativeChannels => mode('nativeChannels');
  String get desktopProcess => mode('desktopProcess');
  String get windowHost => mode('windowHost');

  Map<String, Object?> toJson({
    Map<String, List<Map<String, Object?>>> evidence =
        const <String, List<Map<String, Object?>>>{},
  }) => <String, Object?>{
    for (final MapEntry<String, IntegrationCapabilityState> entry
        in _states.entries)
      entry.key: entry.value.toJson(
        evidence: evidence[entry.key] ?? const <Map<String, Object?>>[],
      ),
  };
}

class IntegrationRuntimeConfig {
  const IntegrationRuntimeConfig({
    required this.runId,
    required this.framework,
    required this.profile,
    required this.deviceName,
    required this.capabilities,
    required this.reportRoot,
    required this.reportPath,
    required this.ffmpegExecutable,
    required this.requestTimeout,
    required this.requestRetryCount,
    required this.defaultStepTimeout,
    required this.longStepTimeout,
    required this.desktopStepTimeout,
  });

  final String runId;
  final String framework;
  final String profile;
  final String deviceName;
  final IntegrationCapabilityContract capabilities;
  final Directory reportRoot;
  final File reportPath;
  final String ffmpegExecutable;
  final Duration requestTimeout;
  final int requestRetryCount;
  final Duration defaultStepTimeout;
  final Duration longStepTimeout;
  final Duration desktopStepTimeout;

  bool get realNetworkEnabled => capabilities.network == 'real';
  bool get realMediaEnabled => capabilities.media == 'real';

  static int _reportSequence = 0;

  static IntegrationRuntimeConfig fromEnvironment({
    required String scenarioName,
    Map<String, String>? environment,
  }) {
    final Map<String, String> env = environment ?? _runtimeEnvironment();
    final String profile = (env['LDDC_IT_PROFILE'] ?? '').trim().toLowerCase();
    if (profile.isEmpty) {
      throw StateError('必须显式设置 LDDC_IT_PROFILE');
    }
    if (!<String>{'offline', 'platform', 'live'}.contains(profile)) {
      throw StateError(
        '未知 LDDC_IT_PROFILE=$profile；只允许 offline、platform 或 live',
      );
    }
    if (env.containsKey('LDDC_IT_SKIP_REAL_NETWORK')) {
      throw StateError('LDDC_IT_SKIP_REAL_NETWORK 已废弃，请使用 LDDC_IT_PROFILE');
    }
    final IntegrationCapabilityContract capabilities =
        IntegrationCapabilityContract.fromEnvironment(
          environment: env,
          profile: profile,
        );
    final String runId = (env['LDDC_IT_RUN_ID'] ?? '').trim();
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(runId)) {
      throw StateError('必须显式设置仅含安全字符的 LDDC_IT_RUN_ID');
    }
    final String framework = (env['LDDC_IT_FRAMEWORK'] ?? '').trim();
    if (framework.isEmpty) {
      throw StateError('必须显式设置 LDDC_IT_FRAMEWORK');
    }
    final String deviceName = (env['LDDC_IT_DEVICE'] ?? '')
        .trim()
        .toLowerCase();
    if (!<String>{
      'windows',
      'macos',
      'linux',
      'android',
      'ios',
    }.contains(deviceName)) {
      throw StateError('必须显式设置有效 LDDC_IT_DEVICE；只允许五个正式平台');
    }
    final String configuredRoot = env['LDDC_IT_REPORT_DIR']?.trim() ?? '';
    final int requestTimeoutMs =
        int.tryParse(env['LDDC_IT_REQUEST_TIMEOUT_MS'] ?? '') ?? 10000;
    final int requestRetryCount =
        int.tryParse(env['LDDC_IT_REQUEST_RETRY_COUNT'] ?? '') ?? 0;
    final int stepTimeoutMs =
        int.tryParse(env['LDDC_IT_STEP_TIMEOUT_MS'] ?? '') ?? 20000;
    final String ffmpegExecutable =
        env['LDDC_IT_FFMPEG_PATH']?.trim().isNotEmpty == true
        ? env['LDDC_IT_FFMPEG_PATH']!.trim()
        : 'ffmpeg';
    final Directory root = configuredRoot.isEmpty
        ? _createDefaultReportRoot(runId)
        : Directory(
            _resolveReportRoot(configuredRoot: configuredRoot, runId: runId),
          );
    final int sequence = _reportSequence++;
    final String safeScenarioName = scenarioName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final String reportFileName = configuredRoot.isNotEmpty
        ? '$safeScenarioName.json'
        : '$safeScenarioName-$pid-'
              '${DateTime.now().microsecondsSinceEpoch}-$sequence.json';
    return IntegrationRuntimeConfig(
      runId: runId,
      framework: framework,
      profile: profile,
      deviceName: deviceName,
      capabilities: capabilities,
      reportRoot: root,
      reportPath: File('${root.path}${Platform.pathSeparator}$reportFileName'),
      ffmpegExecutable: ffmpegExecutable,
      requestTimeout: Duration(milliseconds: requestTimeoutMs),
      requestRetryCount: requestRetryCount,
      defaultStepTimeout: Duration(milliseconds: stepTimeoutMs),
      longStepTimeout: const Duration(seconds: 45),
      desktopStepTimeout: const Duration(seconds: 15),
    );
  }

  /// 确认 runner 声明的平台与真实设备一致，避免设备选择错误后仍生成有效报告。
  void verifyCurrentDevice() {
    final String actual = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isLinux
        ? 'linux'
        : Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : 'unsupported';
    if (deviceName != actual) {
      throw StateError('集成测试设备不匹配：声明=$deviceName，实际=$actual');
    }
  }

  static Directory _createDefaultReportRoot(String runId) {
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'lddc_integration_reports${Platform.pathSeparator}$runId',
    );
  }

  static String _resolveReportRoot({
    required String configuredRoot,
    required String runId,
  }) {
    if (File(configuredRoot).isAbsolute) {
      return configuredRoot;
    }
    // Android/iOS 应用进程不能写宿主 runner 的绝对目录。runner 为移动端
    // 传入相对于应用临时目录的稳定位置，测试结束后再从应用容器拉回。
    // 禁止接受 `..`，避免测试配置越出应用沙箱内约定的报告根目录。
    final List<String> segments = configuredRoot
        .split(RegExp(r'[/\\]+'))
        .where((String segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.contains('..')) {
      throw StateError('LDDC_IT_REPORT_DIR 不能包含 ..');
    }
    if (segments.isEmpty) {
      return _createDefaultReportRoot(runId).path;
    }
    return <String>[
      Directory.systemTemp.path,
      ...segments,
    ].join(Platform.pathSeparator);
  }

  static Map<String, String> _runtimeEnvironment() {
    final Map<String, String> values = <String, String>{
      ...Platform.environment,
    };
    const Map<String, String> dartDefines = <String, String>{
      'LDDC_IT_PROFILE': String.fromEnvironment('LDDC_IT_PROFILE'),
      'LDDC_IT_DEVICE': String.fromEnvironment('LDDC_IT_DEVICE'),
      'LDDC_IT_RUN_ID': String.fromEnvironment('LDDC_IT_RUN_ID'),
      'LDDC_IT_FRAMEWORK': String.fromEnvironment('LDDC_IT_FRAMEWORK'),
      'LDDC_IT_CAPABILITIES_B64': String.fromEnvironment(
        'LDDC_IT_CAPABILITIES_B64',
      ),
      'LDDC_IT_REPORT_DIR': String.fromEnvironment('LDDC_IT_REPORT_DIR'),
      'LDDC_IT_REQUEST_TIMEOUT_MS': String.fromEnvironment(
        'LDDC_IT_REQUEST_TIMEOUT_MS',
      ),
      'LDDC_IT_REQUEST_RETRY_COUNT': String.fromEnvironment(
        'LDDC_IT_REQUEST_RETRY_COUNT',
      ),
      'LDDC_IT_STEP_TIMEOUT_MS': String.fromEnvironment(
        'LDDC_IT_STEP_TIMEOUT_MS',
      ),
      'LDDC_IT_FFMPEG_PATH': String.fromEnvironment('LDDC_IT_FFMPEG_PATH'),
    };
    for (final MapEntry<String, String> entry in dartDefines.entries) {
      if (entry.value.isNotEmpty) {
        values[entry.key] = entry.value;
      }
    }
    return values;
  }
}

class IntegrationStepResult {
  const IntegrationStepResult({
    required this.step,
    required this.success,
    required this.elapsedMs,
    this.details,
    this.error,
  });

  final String step;
  final bool success;
  final int elapsedMs;
  final Map<String, Object?>? details;
  final String? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'step': step,
      'success': success,
      'elapsedMs': elapsedMs,
      'details': details,
      'error': error,
    };
  }
}

class IntegrationReporter {
  IntegrationReporter({
    required this.scenarioName,
    required this.runtimeConfig,
  });

  final String scenarioName;
  final IntegrationRuntimeConfig runtimeConfig;
  final List<IntegrationStepResult> _steps = <IntegrationStepResult>[];
  final Map<String, Object?> _context = <String, Object?>{};
  final Map<String, List<Map<String, Object?>>> _capabilityEvidence =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Object?> _resourceBaseline = <String, Object?>{};
  final Map<String, Object?> _resourceFinal = <String, Object?>{};
  final Map<String, Object?> _resourceThresholds = <String, Object?>{};
  final List<Map<String, Object?>> _artifacts = <Map<String, Object?>>[];
  bool _summaryWritten = false;
  IntegrationFailureArtifactWriter? _failureArtifactWriter;

  void registerFailureArtifactWriter(
    IntegrationFailureArtifactWriter artifactWriter,
  ) {
    _failureArtifactWriter = artifactWriter;
  }

  void recordContext(String key, Object? value) {
    _context[key] = value;
  }

  /// 记录一次已经完成的真实能力调用。
  ///
  /// 只接受当前场景矩阵已经声明且 mode=real 的能力。调用方应在系统动作成功并
  /// 完成结果断言后记录；开始调用前记录会把失败动作伪装成有效覆盖。
  void recordCapabilityEvidence(
    String capability,
    String action, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!runtimeConfig.capabilities.contains(capability)) {
      throw ArgumentError.value(capability, 'capability', '未知 capability');
    }
    final IntegrationCapabilityState state = runtimeConfig.capabilities.state(
      capability,
    );
    if (!state.applicable || state.mode != 'real') {
      throw StateError('capability=$capability 当前为 ${state.mode}，不能记录真实动作证据');
    }
    final String normalizedAction = action.trim();
    if (normalizedAction.isEmpty) {
      throw ArgumentError.value(action, 'action', '能力证据动作不能为空');
    }
    _capabilityEvidence
        .putIfAbsent(capability, () => <Map<String, Object?>>[])
        .add(<String, Object?>{'action': normalizedAction, ...details});
  }

  void recordResourceBaseline(Map<String, Object?> values) {
    _resourceBaseline
      ..clear()
      ..addAll(values);
  }

  void recordResourceFinal(Map<String, Object?> values) {
    _resourceFinal
      ..clear()
      ..addAll(values);
  }

  void recordResourceThresholds(Map<String, Object?> values) {
    _resourceThresholds
      ..clear()
      ..addAll(values);
  }

  /// artifact 只保存稳定名称、大小与摘要，绝不把应用沙箱或宿主绝对路径写入报告。
  void recordArtifact({
    required String name,
    required int size,
    required String sha256,
  }) {
    final String normalizedName = name.trim();
    final String normalizedHash = sha256.trim().toLowerCase();
    if (normalizedName.isEmpty ||
        size < 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw ArgumentError('artifact 必须提供名称、非负大小和 SHA-256');
    }
    _artifacts.add(<String, Object?>{
      'name': normalizedName,
      'size': size,
      'sha256': normalizedHash,
    });
  }

  Future<T> runStep<T>(
    String step,
    Future<T> Function() action, {
    Map<String, Object?> Function(T value)? details,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final T value = await action();
      stopwatch.stop();
      _steps.add(
        IntegrationStepResult(
          step: step,
          success: true,
          elapsedMs: stopwatch.elapsedMilliseconds,
          details: details?.call(value),
        ),
      );
      return value;
    } catch (error) {
      stopwatch.stop();
      _steps.add(
        IntegrationStepResult(
          step: step,
          success: false,
          elapsedMs: stopwatch.elapsedMilliseconds,
          error: error.toString(),
        ),
      );
      rethrow;
    }
  }

  Future<T> runScenario<T>(
    Future<T> Function() action, {
    Map<String, Object?>? extra,
  }) async {
    try {
      final T value = await action();
      await writeSummary(extra: extra);
      return value;
    } catch (error, stackTrace) {
      final Map<String, Object?> failureExtra = <String, Object?>{
        ...?extra,
        'failed': true,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      };
      final IntegrationFailureArtifactWriter? artifactWriter =
          _failureArtifactWriter;
      if (artifactWriter != null) {
        try {
          final String? artifactPath = await artifactWriter();
          if (artifactPath != null && artifactPath.trim().isNotEmpty) {
            failureExtra['failureScreenshot'] = artifactPath;
          }
        } catch (artifactError, artifactStackTrace) {
          // 截图属于失败诊断，不能覆盖原始业务异常。将截图错误写入同一报告，
          // CI 仍会按原始失败退出，同时能看出缺少 PNG 是平台能力还是渲染问题。
          failureExtra['failureScreenshotError'] = artifactError.toString();
          failureExtra['failureScreenshotStackTrace'] = artifactStackTrace
              .toString();
        }
      }
      await writeSummary(extra: failureExtra);
      rethrow;
    }
  }

  Future<void> writeSummary({Map<String, Object?>? extra}) async {
    if (_summaryWritten) {
      return;
    }
    _summaryWritten = true;
    if (!runtimeConfig.reportRoot.existsSync()) {
      await runtimeConfig.reportRoot.create(recursive: true);
    }
    final Map<String, Object?> extraPayload = <String, Object?>{
      ..._context,
      ...?extra,
    };
    final bool hasFailedStep = _steps.any(
      (IntegrationStepResult item) => !item.success,
    );
    final IntegrationReportStatus status = resolveIntegrationReportStatus(
      hasSteps: _steps.isNotEmpty,
      hasFailedStep: hasFailedStep,
      extra: extraPayload,
    );
    final IntegrationCoverageStatus coverageStatus =
        resolveIntegrationCoverageStatus(status: status, extra: extraPayload);
    final int nativeActionCount = _capabilityEvidence.entries
        .where(
          (MapEntry<String, List<Map<String, Object?>>> entry) =>
              runtimeConfig.capabilities.state(entry.key).mode == 'real',
        )
        .fold<int>(0, (
          int total,
          MapEntry<String, List<Map<String, Object?>>> entry,
        ) {
          return total + entry.value.length;
        });
    final Map<String, Object?> payload = <String, Object?>{
      'schemaVersion': 2,
      'runId': runtimeConfig.runId,
      'scenario': scenarioName,
      'profile': runtimeConfig.profile,
      'platform': runtimeConfig.deviceName,
      'framework': runtimeConfig.framework,
      'capabilities': _redactMap(
        runtimeConfig.capabilities.toJson(evidence: _capabilityEvidence),
      ),
      'resources': _redactMap(<String, Object?>{
        'baseline': _resourceBaseline,
        'final': _resourceFinal,
        'thresholds': _resourceThresholds,
      }),
      'runner': <String, Object?>{
        'exitCode': null,
        'originalReportType': 'flutter-jsonl',
        'testStarted': true,
        'nativeActionCount': nativeActionCount,
      },
      'artifacts': _artifacts
          .map<Map<String, Object?>>(_redactMap)
          .toList(growable: false),
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'steps': _steps
          .map<Map<String, Object?>>(
            (IntegrationStepResult item) => _redactMap(item.toJson()),
          )
          .toList(growable: false),
      'status': status.wireName,
      'coverageStatus': coverageStatus.wireName,
      'success': status.isSuccess,
      'extra': _redactMap(extraPayload),
    };
    await runtimeConfig.reportPath.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    debugPrint('integration[$scenarioName] report written');
  }

  Map<String, Object?> _redactMap(Map<String, Object?> source) {
    return source.map(
      (String key, Object? value) =>
          MapEntry<String, Object?>(key, _redactValue(value)),
    );
  }

  Object? _redactValue(Object? value) {
    if (value is Map) {
      return _redactMap(
        value.map<String, Object?>(
          (dynamic key, dynamic item) =>
              MapEntry<String, Object?>(key.toString(), item),
        ),
      );
    }
    if (value is Iterable) {
      return value.map<Object?>(_redactValue).toList(growable: false);
    }
    if (value is String) {
      String redacted = value;
      for (final String root in <String>[
        Directory.current.path,
        Directory.systemTemp.path,
        Platform.environment['USERPROFILE'] ?? '',
        Platform.environment['HOME'] ?? '',
      ]) {
        if (root.isNotEmpty) {
          redacted = redacted.replaceAll(root, '<local-path>');
        }
      }
      return redacted;
    }
    return value;
  }
}
