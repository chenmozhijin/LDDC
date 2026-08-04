import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('真实桌面进程完成单实例、IPC 创建更新删除和自动退出', () async {
    final _ProcessE2eEnvironment environment =
        _ProcessE2eEnvironment.fromPlatform();
    final _ProcessEvidence evidence = _ProcessEvidence(environment);
    final List<Process> primaryProcesses = <Process>[];
    final List<Future<void>> logDrains = <Future<void>>[];
    Socket? socket;
    _SocketFrameReader? reader;
    Object? failure;
    StackTrace? failureStack;
    int finalChildProcessCount = 0;
    try {
      final Process hiddenPrimary = await Process.start(
        environment.executable,
        const <String>['--not-show'],
        workingDirectory: environment.workingDirectory,
        environment: environment.appEnvironment,
        runInShell: false,
      );
      primaryProcesses.add(hiddenPrimary);
      await environment.pidFile.writeAsString('${hiddenPrimary.pid}');
      logDrains
        ..add(
          _drainBounded(
            hiddenPrimary.stdout,
            environment.logDirectory.file('hidden-primary-stdout.log'),
          ),
        )
        ..add(
          _drainBounded(
            hiddenPrimary.stderr,
            environment.logDirectory.file('hidden-primary-stderr.log'),
          ),
        );
      evidence.add('desktopProcess', 'hidden_production_process_started');

      // info.json 在 claim mutex/Unix socket 之前写入。先等待生产 bootstrap
      // 到达该明确里程碑，再留出一个短轮询周期完成 claim；若直接启动端口 CLI，
      // CLI 会把“首进程尚未 claim”误判为无服务并额外拉起后台主进程。
      await _waitForPrimaryBootstrap(
        hiddenPrimary,
        environment.infoFile,
        controlFile: environment.controlFile,
      );

      int? directlyProbedPort;
      final File? controlFile = environment.controlFile;
      if (controlFile != null) {
        final bool primaryAlive = await _isProcessAlive(hiddenPrimary);
        evidence
          ..diagnostic('controlFileObserved', await controlFile.exists())
          ..diagnostic('primaryAliveAtControlProbe', primaryAlive)
          ..diagnostic('directControlProbeSucceeded', false);
        if (!primaryAlive) {
          throw StateError('macOS 隐藏主进程在 control endpoint 探测前退出');
        }
        directlyProbedPort = await _probeMacOsControlEndpoint(controlFile);
        evidence
          ..diagnostic('directControlProbeSucceeded', true)
          ..add(
            'desktopProcess',
            'macos_control_endpoint_direct_probe_completed',
          );
      }

      final _ProcessResult portResult = await _runBoundedProcess(
        environment.executable,
        const <String>['--get-service-port'],
        workingDirectory: environment.workingDirectory,
        environment: environment.appEnvironment,
        timeout: const Duration(seconds: 25),
      );
      expect(portResult.exitCode, 0, reason: portResult.stderr);
      final int port = _parseServicePort(portResult);
      expect(port, inInclusiveRange(1, 65535));
      if (directlyProbedPort != null) {
        expect(
          port,
          directlyProbedPort,
          reason: 'macOS CLI 与 control.json 直接探针必须解析到同一业务端口',
        );
      }
      evidence.add('desktopProcess', 'service_port_cli_resolved_primary');

      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 5),
      );
      reader = _SocketFrameReader(socket);
      const DesktopIpcFramer framer = DesktopIpcFramer();
      socket.add(
        framer.encodeJson(
          DesktopHelloMessage(
            pid: pid,
            availableTaskNames: const <String>['play', 'pause', 'stop'],
            clientInfo: const DesktopClientInfo(
              name: 'lddc-process-e2e',
              version: '1.0',
            ),
          ).toJson(),
        ),
      );
      await socket.flush();
      final DesktopInstanceAckMessage ack = const DesktopIpcMessageCodec()
          .decodeInstanceAck(
            await reader.nextFrame().timeout(const Duration(seconds: 5)),
          );
      expect(ack.instanceId, greaterThan(0));
      evidence.add('nativeChannels', 'loopback_hello_acknowledged');

      socket
        ..add(
          framer.encodeJson(
            DesktopChangMusicMessage(
              instanceId: ack.instanceId,
              title: 'Synthetic title',
              artist: 'Synthetic artist',
              album: 'Synthetic album',
              durationMs: 120000,
              path: null,
              track: 1,
              playbackTimeMs: 2500,
            ).toJson(),
          ),
        )
        ..add(
          framer.encodeJson(
            DesktopSimpleTaskMessage(
              task: DesktopIpcTask.start,
              instanceId: ack.instanceId,
              playbackTimeMs: 2500,
            ).toJson(),
          ),
        );
      await socket.flush();
      evidence.add('nativeChannels', 'instance_music_and_playback_updated');

      socket.add(
        framer.encodeJson(
          DesktopSimpleTaskMessage(
            task: DesktopIpcTask.delInstance,
            instanceId: ack.instanceId,
          ).toJson(),
        ),
      );
      await socket.flush();
      await reader.dispose();
      reader = null;
      socket = null;

      final int hiddenPrimaryExitCode = await hiddenPrimary.exitCode.timeout(
        const Duration(seconds: 15),
      );
      expect(hiddenPrimaryExitCode, 0);
      evidence.add('nativeChannels', 'instance_deleted');
      evidence.add(
        'desktopProcess',
        'hidden_service_exited_after_last_instance',
      );

      // 普通第二实例会把隐藏主窗口显示出来，因此不能再期待它在删除歌词实例后
      // 自动退出。使用新的隐藏主进程单独验证 show 转发，避免把互相冲突的窗口
      // 所有权和隐藏服务退出语义塞进同一个生命周期。
      if (await environment.infoFile.exists()) {
        await environment.infoFile.delete();
      }
      final Process forwardingPrimary = await Process.start(
        environment.executable,
        const <String>['--not-show'],
        workingDirectory: environment.workingDirectory,
        environment: environment.appEnvironment,
        runInShell: false,
      );
      primaryProcesses.add(forwardingPrimary);
      await environment.pidFile.writeAsString('${forwardingPrimary.pid}');
      logDrains
        ..add(
          _drainBounded(
            forwardingPrimary.stdout,
            environment.logDirectory.file('forwarding-primary-stdout.log'),
          ),
        )
        ..add(
          _drainBounded(
            forwardingPrimary.stderr,
            environment.logDirectory.file('forwarding-primary-stderr.log'),
          ),
        );
      await _waitForPrimaryBootstrap(
        forwardingPrimary,
        environment.infoFile,
        controlFile: environment.controlFile,
      );

      final _ProcessResult secondaryResult = await _runBoundedProcess(
        environment.executable,
        const <String>[],
        workingDirectory: environment.workingDirectory,
        environment: environment.appEnvironment,
        timeout: const Duration(seconds: 10),
      );
      expect(secondaryResult.exitCode, 0, reason: secondaryResult.stderr);
      expect(
        await _isProcessAlive(forwardingPrimary),
        isTrue,
        reason: '普通第二实例转发 show 后，持有可见主窗口的生产进程应继续运行',
      );
      evidence.add('desktopProcess', 'second_instance_forwarded_and_exited');
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
      final Process? hiddenPrimary = primaryProcesses.isEmpty
          ? null
          : primaryProcesses.first;
      if (hiddenPrimary != null) {
        final bool isAlive = await _isProcessAlive(hiddenPrimary);
        evidence.diagnostic('primaryAliveAtFailure', isAlive);
        if (!isAlive) {
          evidence.diagnostic(
            'primaryExitCodeAtFailure',
            await hiddenPrimary.exitCode,
          );
        }
      }
      final File? controlFile = environment.controlFile;
      if (controlFile != null) {
        evidence.diagnostic(
          'controlFileExistsAtFailure',
          await controlFile.exists(),
        );
      }
    } finally {
      await reader?.dispose();
      socket?.destroy();
      for (final Process process in primaryProcesses) {
        if (await _isProcessAlive(process)) {
          process.kill();
          await process.exitCode.timeout(const Duration(seconds: 5));
        }
      }
      try {
        await Future.wait(logDrains).timeout(const Duration(seconds: 5));
      } on Object catch (error, stackTrace) {
        // 日志管道异常也必须进入同一份失败 evidence，不能阻断后续 PID 文件清理。
        failure ??= error;
        failureStack ??= stackTrace;
      }
      finalChildProcessCount = 0;
      for (final Process process in primaryProcesses) {
        if (await _isProcessAlive(process)) {
          finalChildProcessCount += 1;
        }
      }
      if (finalChildProcessCount == 0) {
        evidence.add('resourceCleanup', 'process_socket_and_instance_released');
      } else {
        failure ??= StateError('桌面进程 E2E 清理后仍有子进程存活');
        failureStack ??= StackTrace.current;
      }
      if (environment.pidFile.existsSync()) {
        environment.pidFile.deleteSync();
      }
      final File? controlFile = environment.controlFile;
      if (controlFile != null) {
        evidence.diagnostic(
          'controlFileExistsAfterProcessCleanup',
          await controlFile.exists(),
        );
      }
      await evidence.write(failure, finalChildProcessCount);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }, timeout: const Timeout(Duration(seconds: 80)));
}

final class _ProcessE2eEnvironment {
  const _ProcessE2eEnvironment({
    required this.executable,
    required this.workingDirectory,
    required this.runId,
    required this.platform,
    required this.evidenceFile,
    required this.infoFile,
    required this.controlFile,
    required this.pidFile,
    required this.logDirectory,
    required this.appEnvironment,
  });

  final String executable;
  final String workingDirectory;
  final String runId;
  final String platform;
  final File evidenceFile;
  final File infoFile;
  final File? controlFile;
  final File pidFile;
  final Directory logDirectory;
  final Map<String, String> appEnvironment;

  factory _ProcessE2eEnvironment.fromPlatform() {
    final String executable = _requiredEnvironment('LDDC_PROCESS_E2E_APP_EXE');
    final File executableFile = File(executable).absolute;
    if (!executableFile.existsSync()) {
      throw StateError('桌面 E2E 应用不存在');
    }
    final Directory evidenceDirectory = Directory(
      _requiredEnvironment('LDDC_NATIVE_EVIDENCE_DIR'),
    )..createSync(recursive: true);
    final Directory logDirectory = Directory(
      _requiredEnvironment('LDDC_NATIVE_LOG_DIR'),
    )..createSync(recursive: true);
    final String platform = _requiredEnvironment('LDDC_IT_PLATFORM');
    return _ProcessE2eEnvironment(
      executable: executableFile.path,
      workingDirectory: executableFile.parent.path,
      runId: _requiredEnvironment('LDDC_IT_RUN_ID'),
      platform: platform,
      evidenceFile: File(
        '${evidenceDirectory.path}${Platform.pathSeparator}desktop_real_process.json',
      ),
      infoFile: File(_requiredEnvironment('LDDC_PROCESS_E2E_INFO_FILE')),
      controlFile: platform == 'macos'
          ? File(_requiredEnvironment('LDDC_PROCESS_E2E_CONTROL_FILE'))
          : null,
      pidFile: File(_requiredEnvironment('LDDC_PROCESS_E2E_PID_FILE')),
      logDirectory: logDirectory,
      appEnvironment: <String, String>{
        ...Platform.environment,
        'APPDATA': _requiredEnvironment('LDDC_PROCESS_E2E_APPDATA'),
        'LOCALAPPDATA': _requiredEnvironment('LDDC_PROCESS_E2E_LOCALAPPDATA'),
        'HOME': _requiredEnvironment('LDDC_PROCESS_E2E_HOME'),
        'XDG_CONFIG_HOME': _requiredEnvironment(
          'LDDC_PROCESS_E2E_XDG_CONFIG_HOME',
        ),
        'XDG_CACHE_HOME': _requiredEnvironment(
          'LDDC_PROCESS_E2E_XDG_CACHE_HOME',
        ),
        'XDG_DATA_HOME': _requiredEnvironment('LDDC_PROCESS_E2E_XDG_DATA_HOME'),
        'TMPDIR': _requiredEnvironment('LDDC_PROCESS_E2E_TMPDIR'),
      },
    );
  }
}

final class _ProcessEvidence {
  _ProcessEvidence(this.environment);

  final _ProcessE2eEnvironment environment;
  final Map<String, List<Map<String, Object?>>> _actions =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Object?> _diagnostics = <String, Object?>{};

  void add(
    String capability,
    String action, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    _actions.putIfAbsent(capability, () => <Map<String, Object?>>[]).add(
      <String, Object?>{'action': action, ...details},
    );
  }

  void diagnostic(String name, Object? value) {
    _diagnostics[name] = value;
  }

  Future<void> write(Object? failure, int finalChildProcessCount) async {
    final Map<String, Object?> payload = <String, Object?>{
      'runId': environment.runId,
      'scenario': 'desktop_real_process',
      'profile': 'platform',
      'platform': environment.platform,
      'framework': 'dart-process-e2e',
      'steps': <Map<String, Object?>>[
        <String, Object?>{
          'step': 'desktop_real_process',
          'success': failure == null,
          'error': failure == null ? null : '${failure.runtimeType}: $failure',
        },
      ],
      'capabilityEvidence': _actions,
      'resources': <String, Object?>{
        'baseline': <String, Object?>{'childProcessCount': 0},
        'final': <String, Object?>{'childProcessCount': finalChildProcessCount},
        'thresholds': <String, Object?>{'childProcessCount': 0},
      },
      'artifacts': <Object?>[],
      // 诊断只保存结果级布尔值、退出码和端口；绝不复制 endpoint 路径或 token。
      'extra': Map<String, Object?>.unmodifiable(_diagnostics),
    };
    final File temporary = File('${environment.evidenceFile.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      flush: true,
    );
    if (environment.evidenceFile.existsSync()) {
      environment.evidenceFile.deleteSync();
    }
    await temporary.rename(environment.evidenceFile.path);
  }
}

final class _SocketFrameReader {
  _SocketFrameReader(this._socket) : _subscription = _socket.listen(null) {
    _subscription
      ..onData(_handleChunk)
      ..onDone(_closePending)
      ..onError((Object _, StackTrace _) => _closePending());
  }

  final DesktopIpcFrameBuffer _buffer = DesktopIpcFrameBuffer();
  final Socket _socket;
  final List<Map<String, Object?>> _pending = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _waiters =
      <Completer<Map<String, Object?>>>[];
  final StreamSubscription<List<int>> _subscription;

  void _handleChunk(List<int> chunk) {
    for (final Uint8List frame in _buffer.addChunk(chunk)) {
      final Map<String, Object?> payload = Map<String, Object?>.from(
        jsonDecode(utf8.decode(frame))! as Map<Object?, Object?>,
      );
      if (_waiters.isEmpty) {
        _pending.add(payload);
      } else {
        _waiters.removeAt(0).complete(payload);
      }
    }
  }

  void _closePending() {
    while (_waiters.isNotEmpty) {
      _waiters.removeAt(0).completeError(StateError('服务在返回 IPC 帧前关闭连接'));
    }
  }

  Future<Map<String, Object?>> nextFrame() {
    if (_pending.isNotEmpty) {
      return Future<Map<String, Object?>>.value(_pending.removeAt(0));
    }
    final Completer<Map<String, Object?>> completer =
        Completer<Map<String, Object?>>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    _socket.destroy();
  }
}

final class _ProcessResult {
  const _ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<_ProcessResult> _runBoundedProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  required Duration timeout,
}) async {
  final Process process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: false,
  );
  final Future<String> stdoutFuture = process.stdout
      .transform(utf8.decoder)
      .join()
      .then(_boundedText);
  final Future<String> stderrFuture = process.stderr
      .transform(utf8.decoder)
      .join()
      .then(_boundedText);
  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill();
    exitCode = await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }
  return _ProcessResult(exitCode, await stdoutFuture, await stderrFuture);
}

Future<void> _drainBounded(Stream<List<int>> input, File target) async {
  const int limit = 64 * 1024;
  final IOSink sink = target.openWrite(mode: FileMode.writeOnly);
  int written = 0;
  try {
    await for (final List<int> chunk in input) {
      if (written >= limit) {
        continue;
      }
      final int accepted = (limit - written).clamp(0, chunk.length);
      sink.add(chunk.take(accepted).toList(growable: false));
      written += accepted;
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
}

Future<bool> _isProcessAlive(Process process) async {
  try {
    await process.exitCode.timeout(const Duration(milliseconds: 1));
    return false;
  } on TimeoutException {
    return true;
  }
}

Future<void> _waitForPrimaryBootstrap(
  Process process,
  File infoFile, {
  File? controlFile,
}) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (!await _isProcessAlive(process)) {
      throw StateError('隐藏主进程在服务 bootstrap 完成前退出');
    }
    final bool infoReady = await infoFile.exists();
    final bool controlReady = controlFile == null || await controlFile.exists();
    if (infoReady && controlReady) {
      if (controlFile == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(
    controlFile == null
        ? '等待隐藏主进程生成 info.json 超时'
        : '等待隐藏主进程生成 info.json/control.json 超时',
  );
}

Future<int> _probeMacOsControlEndpoint(File controlFile) async {
  final Object? decoded = jsonDecode(await controlFile.readAsString());
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('macOS control.json 必须是 JSON 对象');
  }
  final Map<String, Object?> endpoint = <String, Object?>{
    for (final MapEntry<Object?, Object?> entry in decoded.entries)
      entry.key.toString(): entry.value,
  };
  expect(endpoint.keys.toSet(), <String>{
    'schema',
    'port',
    'token',
  }, reason: 'control.json 必须保持现有 v1 三字段契约');
  expect(endpoint['schema'], 'lddc.macos_singleton_control');
  final Object? rawPort = endpoint['port'];
  final Object? rawToken = endpoint['token'];
  if (rawPort is! int || rawPort <= 0 || rawPort > 65535) {
    throw const FormatException('macOS control.json 端口无效');
  }
  if (rawToken is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(rawToken)) {
    throw const FormatException('macOS control.json token 无效');
  }

  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    rawPort,
    timeout: const Duration(seconds: 5),
  );
  final _SocketFrameReader reader = _SocketFrameReader(socket);
  try {
    const DesktopIpcFramer framer = DesktopIpcFramer();
    final Uint8List request = framer.encodeJson(<String, Object?>{
      '_lddcControl': 1,
      'token': rawToken,
      'command': 'get_service_port',
    });
    expect(request.length, lessThanOrEqualTo(4 * 1024 + 4));
    socket.add(request);
    await socket.flush();
    final Map<String, Object?> response = await reader.nextFrame().timeout(
      const Duration(seconds: 5),
    );
    expect(response['_lddcControl'], 1);
    expect(response['ok'], isTrue);
    expect(response['port'], rawPort);
    return rawPort;
  } finally {
    await reader.dispose();
  }
}

String _boundedText(String value) {
  const int limit = 64 * 1024;
  return value.length <= limit ? value : value.substring(0, limit);
}

int _parseServicePort(_ProcessResult result) {
  final List<String> numericLines = LineSplitter.split(result.stdout)
      .map((String line) => line.trim())
      .where((String line) => RegExp(r'^\d{1,5}$').hasMatch(line))
      .toList(growable: false);
  expect(
    numericLines,
    hasLength(1),
    reason:
        '服务端口 CLI 未输出唯一纯数字端口。stdout=${result.stdout}; stderr=${result.stderr}',
  );
  return int.parse(numericLines.single);
}

String _requiredEnvironment(String name) {
  final String value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('缺少环境变量 $name');
  }
  return value;
}

extension on Directory {
  File file(String name) => File('$path${Platform.pathSeparator}$name');
}
