// 单实例控制文件、info.json 和 Unix socket 都位于用户目录，可能落在漫游配置、
// 网络主目录或慢磁盘。这里刻意使用异步文件 API，避免服务发现阶段阻塞 Flutter
// 主 isolate；该性能边界优先于要求改用同步 IO 的通用 lint 建议。
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../../core/app_metadata.dart';
import '../../../core/logging/logging.dart';
import '../../../core/storage/app_storage_paths_port.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'desktop_service_launch_arguments.dart';

typedef DesktopServiceLineWriter = void Function(String line);
typedef DesktopServiceExitHandler = void Function(int exitCode);
typedef DesktopServiceSingletonRequestHandler =
    FutureOr<String?> Function(String message);
typedef DesktopShowRequestHandler = Future<void> Function();

final AppLogger _bootstrapLogger = AppLogger.scope('service-bootstrap');
const int _maxControlRequestBytes = 4096;
const Duration _controlRequestTimeout = Duration(seconds: 2);

void _defaultStdoutWriter(String line) {
  if (_writeWindowsStdHandleLine(STD_OUTPUT_HANDLE, line)) {
    return;
  }
  stdout.writeln(line);
}

void _defaultStderrWriter(String line) {
  if (_writeWindowsStdHandleLine(STD_ERROR_HANDLE, line)) {
    return;
  }
  stderr.writeln(line);
}

void _defaultExitHandler(int exitCode) {
  if (Platform.isWindows) {
    ExitProcess(exitCode);
  }
  exit(exitCode);
}

bool _writeWindowsStdHandleLine(STD_HANDLE handleKind, String line) {
  if (!Platform.isWindows) {
    return false;
  }
  final Win32Result<HANDLE> handleResult = GetStdHandle(handleKind);
  final HANDLE handle = handleResult.value;
  if (_isInvalidHandle(handle)) {
    return false;
  }
  final List<int> bytes = utf8.encode('$line\r\n');
  final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
  final Pointer<Uint32> bytesWritten = calloc<Uint32>();
  try {
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    final Win32Result<bool> result = WriteFile(
      handle,
      buffer,
      bytes.length,
      bytesWritten,
      nullptr,
    );
    return result.value && bytesWritten.value == bytes.length;
  } finally {
    calloc.free(bytesWritten);
    calloc.free(buffer);
  }
}

DynamicLibrary? _kernel32BootstrapLibrary;
Pointer Function(Pointer<SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)?
_createMutexFunction;

HANDLE _createNamedMutex(Pointer<Utf16> name) {
  final DynamicLibrary kernel32 = _kernel32BootstrapLibrary ??=
      DynamicLibrary.open('kernel32.dll');
  final Pointer Function(Pointer<SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
  createMutex = _createMutexFunction ??= kernel32
      .lookupFunction<
        Pointer Function(
          Pointer<SECURITY_ATTRIBUTES> lpMutexAttributes,
          Int32 bInitialOwner,
          Pointer<Utf16> lpName,
        ),
        Pointer Function(
          Pointer<SECURITY_ATTRIBUTES> lpMutexAttributes,
          int bInitialOwner,
          Pointer<Utf16> lpName,
        )
      >('CreateMutexW');
  return HANDLE(createMutex(nullptr, FALSE, name));
}

bool _isInvalidHandle(HANDLE handle) {
  // win32 6.x 将 HANDLE 改为强类型后，不能再用 int 0/-1 判断无效句柄。
  // 这里集中判断 NULL 与 INVALID_HANDLE_VALUE，避免管道和互斥体释放路径遗漏。
  return handle == INVALID_HANDLE_VALUE || handle.address == NULL;
}

/// 当前进程的可执行命令描述。
final class DesktopServiceLaunchCommand {
  const DesktopServiceLaunchCommand({
    required this.executable,
    this.arguments = const <String>[],
  });

  final String executable;
  final List<String> arguments;

  DesktopServiceLaunchCommand append(List<String> extraArguments) {
    return DesktopServiceLaunchCommand(
      executable: executable,
      arguments: <String>[...arguments, ...extraArguments],
    );
  }

  String toCommandLine() {
    return <String>[_quote(executable), ...arguments.map(_quote)].join(' ');
  }

  static String _quote(String value) {
    final String escaped = value.replaceAll('"', r'\"');
    return '"$escaped"';
  }
}

typedef DesktopServiceLaunchCommandProvider =
    DesktopServiceLaunchCommand Function();

/// 桌面服务入口处理结果。
final class DesktopServiceEntrypointResult {
  const DesktopServiceEntrypointResult._({
    required this.shouldRunApp,
    required this.exitCode,
    this.stdoutLine,
    this.stderrLine,
  });

  const DesktopServiceEntrypointResult.continueApp()
    : this._(shouldRunApp: true, exitCode: 0);

  const DesktopServiceEntrypointResult.exit({
    required int exitCode,
    String? stdoutLine,
    String? stderrLine,
  }) : this._(
         shouldRunApp: false,
         exitCode: exitCode,
         stdoutLine: stdoutLine,
         stderrLine: stderrLine,
       );

  final bool shouldRunApp;
  final int exitCode;
  final String? stdoutLine;
  final String? stderrLine;
}

/// Python版 `info.json` 写入器。
final class DesktopServiceInfoWriter {
  DesktopServiceInfoWriter({
    AppStoragePathsPort? paths,
    DesktopServiceLaunchCommandProvider? commandProvider,
  }) : _paths = paths,
       _commandProvider = commandProvider ?? _defaultCommand;

  final AppStoragePathsPort? _paths;
  final DesktopServiceLaunchCommandProvider _commandProvider;
  static final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  DesktopServiceLaunchCommand buildLaunchCommand() => _commandProvider();

  Future<File> writeInfo() async {
    // 默认端口延迟到首次写入时解析，避免只进行参数解析或单元测试的
    // DesktopServiceBootstrap 在尚未注册 app 组合根时提前触碰文件系统。
    final File infoFile = await (_paths ?? AppStoragePathsRegistry.current)
        .resolveInfoFile();
    final String normalizedPath = p.normalize(infoFile.absolute.path);
    final String queueKey = Platform.isWindows
        ? normalizedPath.toLowerCase()
        : normalizedPath;
    final Future<void> previous = _writeTails[queueKey] ?? Future<void>.value();
    final Completer<void> completion = Completer<void>();
    final Future<void> current = completion.future;
    _writeTails[queueKey] = current;
    await previous;
    try {
      return await _writeResolvedInfo(infoFile);
    } finally {
      completion.complete();
      if (identical(_writeTails[queueKey], current)) {
        // POSIX 文件锁按进程生效，不能阻止同一 Dart 进程内的并发 Future。
        // 队尾完成后立即移除键，既补齐进程内串行边界，也不让路径长期驻留内存。
        _writeTails.remove(queueKey);
      }
    }
  }

  Future<File> _writeResolvedInfo(File infoFile) async {
    final Directory parent = infoFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final DesktopServiceLaunchCommand command = buildLaunchCommand();
    final Map<String, Object?> payload = <String, Object?>{
      'schema': 'lddc.desktop_service.info',
      'version': kLddcVersion,
      'executable': command.executable,
      'arguments': command.arguments,
      // Python版桌面歌词插件读取这个历史字段启动服务，wire 兼容边界必须保留。
      'Command Line': command.toCommandLine(),
    };
    final String infoFileName = p.basename(infoFile.path);
    final Directory stagingDirectory = await parent.createTemp(
      '.$infoFileName.write-${pid.toString()}-',
    );
    final File tempFile = File(p.join(stagingDirectory.path, infoFileName));
    final File lockFile = File('${infoFile.path}.lock');
    RandomAccessFile? lockHandle;
    try {
      await tempFile.writeAsString(jsonEncode(payload), flush: true);
      lockHandle = await lockFile.open(mode: FileMode.append);
      // 主进程、端口 CLI 和第二实例可能同时刷新 info.json。固定的 lock 文件
      // 提供跨进程排他区；每个写入者使用独立临时目录，避免共享 `.tmp` 被另一
      // 个进程先重命名。锁内删除再重命名兼容 Windows 不覆盖目标文件的语义。
      await lockHandle.lock(FileLock.blockingExclusive);
      if (await infoFile.exists()) {
        await infoFile.delete();
      }
      await tempFile.rename(infoFile.path);
    } finally {
      if (lockHandle != null) {
        try {
          await lockHandle.unlock();
        } on Object {
          // 写入结果由主异常或目标文件校验决定；释放锁失败时 close 仍会让操作
          // 系统回收进程级锁，不能因此跳过临时目录清理。
        }
        await lockHandle.close();
      }
      if (await stagingDirectory.exists()) {
        await stagingDirectory.delete(recursive: true);
      }
    }
    return infoFile;
  }

  static DesktopServiceLaunchCommand _defaultCommand() {
    final String executable = Platform.resolvedExecutable;
    final String executableName = executable
        .split(Platform.pathSeparator)
        .last
        .toLowerCase();
    final bool isDartVm =
        executableName == 'dart' || executableName == 'dart.exe';
    if (isDartVm && Platform.script.isScheme('file')) {
      return DesktopServiceLaunchCommand(
        executable: executable,
        arguments: <String>[Platform.script.toFilePath()],
      );
    }
    return DesktopServiceLaunchCommand(executable: executable);
  }
}

/// 后台拉起当前桌面服务进程。
abstract interface class DesktopServiceProcessLauncher {
  Future<void> launchBackgroundService(DesktopServiceLaunchCommand command);
}

final class DesktopLocalProcessLauncher
    implements DesktopServiceProcessLauncher {
  const DesktopLocalProcessLauncher();

  @override
  Future<void> launchBackgroundService(DesktopServiceLaunchCommand command) {
    final DesktopServiceLaunchCommand backgroundCommand = command.append(
      const <String>['--not-show'],
    );
    return Process.start(
      backgroundCommand.executable,
      backgroundCommand.arguments,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }
}

/// 单服务发现/控制通道抽象。
abstract interface class DesktopSingletonBootstrapPort {
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  });

  Future<bool> hasPrimaryInstance();

  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  });

  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  });

  Future<void> setServicePort(int port);

  Future<void> close();
}

enum DesktopPrimaryClaimResult { primary, existingPrimary }

final class DesktopNoopSingletonBootstrapPort
    implements DesktopSingletonBootstrapPort {
  const DesktopNoopSingletonBootstrapPort();

  @override
  Future<void> close() async {}

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return null;
  }

  @override
  Future<void> setServicePort(int port) async {}

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async => DesktopPrimaryClaimResult.primary;

  @override
  Future<bool> hasPrimaryInstance() async => true;

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    return true;
  }
}

/// Windows 单服务发现适配器：命名互斥体 + 命名管道。
final class DesktopWindowsSingletonBootstrapPort
    implements DesktopSingletonBootstrapPort {
  DesktopWindowsSingletonBootstrapPort({
    String mutexName = 'LDDCLOCK',
    String pipeName = 'LDDCService',
    Duration serverPollInterval = const Duration(milliseconds: 50),
  }) : _mutexName = mutexName,
       _pipeName = pipeName,
       _serverPollInterval = serverPollInterval {
    if (serverPollInterval <= Duration.zero) {
      throw ArgumentError.value(
        serverPollInterval,
        'serverPollInterval',
        '必须大于零',
      );
    }
  }

  final String _mutexName;
  final String _pipeName;
  final Duration _serverPollInterval;
  HANDLE? _mutexHandle;
  HANDLE? _serverPipeHandle;
  bool _clientConnected = false;
  Timer? _serverPumpTimer;
  Future<void>? _serverPumpFuture;
  Future<void>? _closeFuture;
  DesktopServiceSingletonRequestHandler? _onRequest;
  final List<int> _serverReadBuffer = <int>[];
  bool _closed = false;

  String get _pipePath => '\\\\.\\pipe\\$_pipeName';

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    _serverPumpTimer?.cancel();
    _serverPumpTimer = null;
    await _serverPumpFuture;
    _closeServerPipe();
    _onRequest = null;
    final HANDLE? mutexHandle = _mutexHandle;
    _mutexHandle = null;
    if (mutexHandle != null) {
      CloseHandle(mutexHandle);
    }
  }

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    return _requestThroughPipe(message, timeout: timeout);
  }

  @override
  Future<void> setServicePort(int port) async {}

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async {
    if (_closed) {
      throw StateError('DesktopWindowsSingletonBootstrapPort 已关闭');
    }
    _onRequest = onRequest;
    if (_mutexHandle != null && _serverPumpTimer != null) {
      return DesktopPrimaryClaimResult.primary;
    }
    final Pointer<Utf16> mutexName = _mutexName.toNativeUtf16();
    try {
      final HANDLE handle = _createNamedMutex(mutexName);
      if (_isInvalidHandle(handle)) {
        throw StateError('创建 Windows 单服务互斥体失败: ${GetLastError()}');
      }
      if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(handle);
        return DesktopPrimaryClaimResult.existingPrimary;
      }
      _mutexHandle = handle;
      final _DesktopPipeCreateResult pipeResult = _createServerPipe();
      if (pipeResult.isExistingPrimary) {
        _releaseMutex();
        return DesktopPrimaryClaimResult.existingPrimary;
      }
      if (pipeResult.error != null) {
        _releaseMutex();
        throw StateError('创建 Windows 单服务命名管道失败: ${pipeResult.error}');
      }
      _serverPipeHandle = pipeResult.handle;
      _serverPumpTimer = Timer.periodic(_serverPollInterval, (_) {
        _scheduleServerPump();
      });
      return DesktopPrimaryClaimResult.primary;
    } finally {
      calloc.free(mutexName);
    }
  }

  @override
  Future<bool> hasPrimaryInstance() async {
    if (_mutexHandle != null) {
      return true;
    }
    final Pointer<Utf16> mutexName = _mutexName.toNativeUtf16();
    try {
      final HANDLE handle = _createNamedMutex(mutexName);
      if (_isInvalidHandle(handle)) {
        return false;
      }
      final bool exists = GetLastError() == ERROR_ALREADY_EXISTS;
      CloseHandle(handle);
      return exists;
    } finally {
      calloc.free(mutexName);
    }
  }

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final String? response = await request(
          'get_service_port',
          timeout: pollInterval,
        );
        if (response != null) {
          return true;
        }
      } on Object {
        // 服务进程可能刚启动但控制通道尚未就绪，轮询阶段吞掉单次失败后继续等待。
      }
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }

  void _scheduleServerPump() {
    if (_closed || _serverPumpFuture != null) {
      return;
    }
    late final Future<void> pumpFuture;
    pumpFuture = _pumpServerPipe()
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _bootstrapLogger.error(
              'windows singleton pipe pump failed'
              ' error=$error stack=$stackTrace',
            );
          },
        )
        .whenComplete(() {
          if (identical(_serverPumpFuture, pumpFuture)) {
            _serverPumpFuture = null;
          }
        });
    _serverPumpFuture = pumpFuture;
  }

  Future<void> _pumpServerPipe() async {
    if (_closed || !_ensureServerPipe()) {
      return;
    }
    final HANDLE? serverPipeHandle = _serverPipeHandle;
    if (serverPipeHandle == null) {
      return;
    }
    if (!_clientConnected) {
      final Win32Result<bool> connectResult = ConnectNamedPipe(
        serverPipeHandle,
        nullptr,
      );
      if (connectResult.value) {
        _clientConnected = true;
      } else {
        final WIN32_ERROR error = connectResult.error;
        if (error == ERROR_PIPE_CONNECTED) {
          _clientConnected = true;
        } else if (error == ERROR_PIPE_LISTENING || error == ERROR_NO_DATA) {
          return;
        } else {
          _bootstrapLogger.warning(
            'windows singleton pipe connect failed',
            fields: <String, Object?>{'error': error.toString()},
          );
          _recreateServerPipe();
          return;
        }
      }
    }

    final List<int>? chunk = _readAvailableBytes(serverPipeHandle);
    if (chunk == null) {
      return;
    }
    _serverReadBuffer.addAll(chunk);
    if (_serverReadBuffer.length > _maxControlRequestBytes) {
      _bootstrapLogger.warning(
        'windows singleton request exceeds $_maxControlRequestBytes bytes',
      );
      _disconnectServerPipe();
      return;
    }
    final int newlineIndex = _serverReadBuffer.indexOf(0x0A);
    if (newlineIndex < 0) {
      return;
    }
    final String requestMessage = utf8
        .decode(_serverReadBuffer.sublist(0, newlineIndex))
        .trim();
    final DesktopServiceSingletonRequestHandler? handler = _onRequest;
    final String response = handler == null
        ? ''
        : (await handler(requestMessage) ?? '');
    if (_closed) {
      return;
    }
    _writeResponse(serverPipeHandle, response);
    _disconnectServerPipe();
  }

  Future<String?> _requestThroughPipe(
    String message, {
    required Duration timeout,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final String? response = _tryRequestThroughPipeOnce(
        message,
        deadline: deadline,
      );
      if (response != null) {
        return response;
      }

      final Duration left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        return null;
      }
      final int sleepMs = left.inMilliseconds < 50 ? left.inMilliseconds : 50;
      await Future<void>.delayed(Duration(milliseconds: sleepMs));
    }
    return null;
  }

  String? _tryRequestThroughPipeOnce(
    String message, {
    required DateTime deadline,
  }) {
    final Pointer<Utf16> pipePath = _pipePath.toNativeUtf16();
    final Win32Result<HANDLE> pipeResult = CreateFile(
      PCWSTR(pipePath),
      GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_NONE,
      null,
      OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL,
      null,
    );
    calloc.free(pipePath);
    final HANDLE pipeHandle = pipeResult.value;
    if (_isInvalidHandle(pipeHandle)) {
      final WIN32_ERROR error = pipeResult.error;
      if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PIPE_BUSY) {
        return null;
      }
      return null;
    }

    final List<int> payload = utf8.encode('$message\n');
    final Pointer<Uint8> writeBuffer = calloc<Uint8>(payload.length);
    final Pointer<Uint32> bytesWritten = calloc<Uint32>();
    final Pointer<Uint32> bytesAvailable = calloc<Uint32>();
    final Pointer<Uint8> readBuffer = calloc<Uint8>(1024);
    final Pointer<Uint32> bytesRead = calloc<Uint32>();
    final List<int> responseBuffer = <int>[];
    try {
      writeBuffer.asTypedList(payload.length).setAll(0, payload);
      final Win32Result<bool> writeResult = WriteFile(
        pipeHandle,
        writeBuffer,
        payload.length,
        bytesWritten,
        nullptr,
      );
      if (!writeResult.value) {
        return null;
      }

      while (DateTime.now().isBefore(deadline)) {
        final Win32Result<bool> peekResult = PeekNamedPipe(
          pipeHandle,
          nullptr,
          0,
          nullptr,
          bytesAvailable,
          nullptr,
        );
        if (!peekResult.value) {
          final WIN32_ERROR error = peekResult.error;
          if (error == ERROR_NO_DATA || error == ERROR_BROKEN_PIPE) {
            return null;
          }
          return null;
        }
        final int available = bytesAvailable.value;
        if (available <= 0) {
          final Duration remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) {
            break;
          }
          final int sleepMs = remaining.inMilliseconds < 20
              ? remaining.inMilliseconds
              : 20;
          Sleep(sleepMs);
          continue;
        }
        final int readSize = available > 1024 ? 1024 : available;
        final Win32Result<bool> readResult = ReadFile(
          pipeHandle,
          readBuffer,
          readSize,
          bytesRead,
          nullptr,
        );
        if (!readResult.value) {
          final WIN32_ERROR error = readResult.error;
          if (error == ERROR_NO_DATA || error == ERROR_BROKEN_PIPE) {
            return _decodePipeResponseLine(responseBuffer);
          }
          return null;
        }
        responseBuffer.addAll(readBuffer.asTypedList(bytesRead.value));
        final String? line = _decodePipeResponseLine(responseBuffer);
        if (line != null) {
          return line;
        }
      }
      return null;
    } finally {
      calloc.free(bytesRead);
      calloc.free(readBuffer);
      calloc.free(bytesAvailable);
      calloc.free(bytesWritten);
      calloc.free(writeBuffer);
      CloseHandle(pipeHandle);
    }
  }

  String? _decodePipeResponseLine(List<int> buffer) {
    final int newlineIndex = buffer.indexOf(0x0A);
    if (newlineIndex < 0) {
      return null;
    }
    int end = newlineIndex;
    if (end > 0 && buffer[end - 1] == 0x0D) {
      end -= 1;
    }
    return utf8.decode(buffer.sublist(0, end));
  }

  bool _ensureServerPipe() {
    if (_closed) {
      return false;
    }
    if (_serverPipeHandle != null) {
      return true;
    }
    final _DesktopPipeCreateResult result = _createServerPipe();
    if (result.handle != null) {
      _serverPipeHandle = result.handle;
      return true;
    }
    if (result.isExistingPrimary) {
      return false;
    }
    throw StateError('创建 Windows 单服务命名管道失败: ${result.error}');
  }

  List<int>? _readAvailableBytes(HANDLE handle) {
    final Pointer<Uint8> buffer = calloc<Uint8>(1024);
    final Pointer<Uint32> bytesRead = calloc<Uint32>();
    try {
      final Win32Result<bool> readResult = ReadFile(
        handle,
        buffer,
        1024,
        bytesRead,
        nullptr,
      );
      if (!readResult.value) {
        final WIN32_ERROR error = readResult.error;
        // PIPE_NOWAIT 下，客户端刚连接但尚未提交首字节时，不同 Windows
        // 版本可能返回 NO_DATA 或 PIPE_LISTENING。两者都不是管道损坏；保持
        // 当前连接并让下一次有界 pump 继续读取，避免端口发现偶发断开客户端。
        if (error == ERROR_NO_DATA || error == ERROR_PIPE_LISTENING) {
          return null;
        }
        if (error == ERROR_BROKEN_PIPE) {
          _disconnectServerPipe();
          return null;
        }
        _recreateServerPipe();
        return null;
      }
      return buffer.asTypedList(bytesRead.value).toList(growable: false);
    } finally {
      calloc.free(bytesRead);
      calloc.free(buffer);
    }
  }

  void _writeResponse(HANDLE handle, String response) {
    _writeBytes(handle, utf8.encode('$response\n'));
    FlushFileBuffers(handle);
  }

  void _writeBytes(HANDLE handle, List<int> bytes) {
    if (bytes.isEmpty) {
      return;
    }
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    final Pointer<Uint32> bytesWritten = calloc<Uint32>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      final Win32Result<bool> writeResult = WriteFile(
        handle,
        buffer,
        bytes.length,
        bytesWritten,
        nullptr,
      );
      if (!writeResult.value) {
        throw StateError('写入 Windows 命名管道失败: ${writeResult.error}');
      }
    } finally {
      calloc.free(bytesWritten);
      calloc.free(buffer);
    }
  }

  void _disconnectServerPipe() {
    final HANDLE? handle = _serverPipeHandle;
    if (handle == null) {
      return;
    }
    _clientConnected = false;
    _serverReadBuffer.clear();
    DisconnectNamedPipe(handle);
  }

  void _recreateServerPipe() {
    _closeServerPipe();
    if (!_closed) {
      _ensureServerPipe();
    }
  }

  void _closeServerPipe() {
    final HANDLE? handle = _serverPipeHandle;
    _serverPipeHandle = null;
    _clientConnected = false;
    _serverReadBuffer.clear();
    if (handle != null) {
      DisconnectNamedPipe(handle);
      CloseHandle(handle);
    }
  }

  void _releaseMutex() {
    final HANDLE? mutexHandle = _mutexHandle;
    _mutexHandle = null;
    if (mutexHandle != null) {
      CloseHandle(mutexHandle);
    }
  }

  _DesktopPipeCreateResult _createServerPipe() {
    final Pointer<Utf16> pipePath = _pipePath.toNativeUtf16();
    try {
      final HANDLE handle = CreateNamedPipe(
        PCWSTR(pipePath),
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_NOWAIT,
        1,
        4096,
        4096,
        0,
        nullptr,
      );
      if (_isInvalidHandle(handle)) {
        final WIN32_ERROR error = GetLastError();
        if (error == ERROR_PIPE_BUSY || error == ERROR_ACCESS_DENIED) {
          return _DesktopPipeCreateResult.existingPrimary(error);
        }
        return _DesktopPipeCreateResult.failed(error);
      }
      return _DesktopPipeCreateResult.created(handle);
    } finally {
      calloc.free(pipePath);
    }
  }
}

final class DesktopServiceRuntimePaths {
  const DesktopServiceRuntimePaths();

  Future<File> resolveControlSocketFile() async {
    final Directory baseDirectory = await _resolveBaseDirectory();
    return File(p.join(baseDirectory.path, 'LDDC', 'service.sock'));
  }

  Future<Directory> _resolveBaseDirectory() async {
    if (Platform.isLinux) {
      final String? runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
      if (runtimeDir != null && runtimeDir.trim().isNotEmpty) {
        return Directory(runtimeDir);
      }
    }
    if (Platform.isMacOS) {
      final String? tmpDir = Platform.environment['TMPDIR'];
      if (tmpDir != null && tmpDir.trim().isNotEmpty) {
        return Directory(tmpDir);
      }
    }
    return Directory.systemTemp;
  }
}

/// Unix 桌面平台单服务发现适配器：本地控制 socket。
final class DesktopUnixSingletonBootstrapPort
    implements DesktopSingletonBootstrapPort {
  DesktopUnixSingletonBootstrapPort({DesktopServiceRuntimePaths? runtimePaths})
    : _runtimePaths = runtimePaths ?? const DesktopServiceRuntimePaths();

  final DesktopServiceRuntimePaths _runtimePaths;
  ServerSocket? _server;
  File? _socketFile;
  StreamSubscription<Socket>? _serverSubscription;
  DesktopServiceSingletonRequestHandler? _onRequest;
  final Set<Socket> _clientSockets = <Socket>{};
  final Set<Future<void>> _clientTasks = <Future<void>>{};
  Future<void>? _closeFuture;
  bool _closed = false;

  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _serverSubscription?.cancel();
    await _server?.close();
    _serverSubscription = null;
    _server = null;
    for (final Socket socket in _clientSockets.toList(growable: false)) {
      socket.destroy();
    }
    if (_clientTasks.isNotEmpty) {
      await Future.wait(_clientTasks.toList(growable: false));
    }
    _clientSockets.clear();
    _clientTasks.clear();
    _onRequest = null;
    final File? socketFile = _socketFile;
    _socketFile = null;
    if (socketFile != null && await socketFile.exists()) {
      await socketFile.delete();
    }
  }

  @override
  Future<String?> request(
    String message, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final File socketFile = await _runtimePaths.resolveControlSocketFile();
    final InternetAddress address = InternetAddress(
      socketFile.path,
      type: InternetAddressType.unix,
    );
    final Socket socket = await Socket.connect(address, 0, timeout: timeout);
    try {
      socket.write('$message\n');
      await socket.flush();
      final String response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(timeout);
      return response;
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<void> setServicePort(int port) async {}

  @override
  Future<DesktopPrimaryClaimResult> claimPrimary({
    required DesktopServiceSingletonRequestHandler onRequest,
  }) async {
    if (_closed) {
      throw StateError('DesktopUnixSingletonBootstrapPort 已关闭');
    }
    final ServerSocket? server = _server;
    if (server != null) {
      _onRequest = onRequest;
      _serverSubscription ??= server.listen(_handleClientConnected);
      return DesktopPrimaryClaimResult.primary;
    }
    final File socketFile = await _runtimePaths.resolveControlSocketFile();
    final Directory parent = socketFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    if (await socketFile.exists()) {
      final bool alive = await _canReachExistingSocket(socketFile);
      if (alive) {
        return DesktopPrimaryClaimResult.existingPrimary;
      }
      await socketFile.delete();
    }
    final InternetAddress address = InternetAddress(
      socketFile.path,
      type: InternetAddressType.unix,
    );
    try {
      _server = await ServerSocket.bind(address, 0, shared: false);
      _socketFile = socketFile;
      _onRequest = onRequest;
      _serverSubscription = _server!.listen(_handleClientConnected);
      return DesktopPrimaryClaimResult.primary;
    } on SocketException {
      final bool alive = await _canReachExistingSocket(socketFile);
      if (alive) {
        return DesktopPrimaryClaimResult.existingPrimary;
      }
      if (await socketFile.exists()) {
        await socketFile.delete();
      }
      _server = await ServerSocket.bind(address, 0, shared: false);
      _socketFile = socketFile;
      _onRequest = onRequest;
      _serverSubscription = _server!.listen(_handleClientConnected);
      return DesktopPrimaryClaimResult.primary;
    }
  }

  @override
  Future<bool> hasPrimaryInstance() async {
    if (_server != null) {
      return true;
    }
    final File socketFile = await _runtimePaths.resolveControlSocketFile();
    if (!await socketFile.exists()) {
      return false;
    }
    return _canReachExistingSocket(socketFile);
  }

  @override
  Future<bool> waitUntilPrimaryAvailable({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        await request('get_service_port', timeout: pollInterval);
        return true;
      } on Object {
        await Future<void>.delayed(pollInterval);
      }
    }
    return false;
  }

  void _handleClientConnected(Socket socket) {
    if (_closed) {
      socket.destroy();
      return;
    }
    _clientSockets.add(socket);
    late final Future<void> clientTask;
    clientTask = _handleClient(socket)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _bootstrapLogger.info(
              'unix singleton client failed'
              ' error=$error stack=$stackTrace',
            );
          },
        )
        .whenComplete(() {
          _clientSockets.remove(socket);
          _clientTasks.remove(clientTask);
        });
    _clientTasks.add(clientTask);
  }

  Future<void> _handleClient(Socket socket) async {
    try {
      final String requestMessage = (await _readBoundedControlLine(
        socket,
      )).trim();
      final DesktopServiceSingletonRequestHandler? handler = _onRequest;
      final String response = handler == null
          ? ''
          : (await handler(requestMessage) ?? '');
      socket.write(response);
      await socket.flush();
    } finally {
      socket.destroy();
    }
  }

  Future<String> _readBoundedControlLine(Socket socket) async {
    final StreamIterator<List<int>> iterator = StreamIterator<List<int>>(
      socket,
    );
    final List<int> bytes = <int>[];
    final DateTime deadline = DateTime.now().add(_controlRequestTimeout);
    try {
      while (true) {
        final Duration remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero ||
            !await iterator.moveNext().timeout(remaining)) {
          throw TimeoutException('桌面单实例控制请求未完整到达');
        }
        for (final int byte in iterator.current) {
          if (byte == 0x0A) {
            if (bytes.isNotEmpty && bytes.last == 0x0D) {
              bytes.removeLast();
            }
            return utf8.decode(bytes);
          }
          bytes.add(byte);
          if (bytes.length > _maxControlRequestBytes) {
            throw const FormatException('桌面单实例控制请求超过 4096 bytes');
          }
        }
      }
    } finally {
      await iterator.cancel();
    }
  }

  Future<bool> _canReachExistingSocket(File socketFile) async {
    try {
      final String? response = await request(
        'get_service_port',
        timeout: const Duration(milliseconds: 200),
      );
      return response != null;
    } on Object {
      return false;
    }
  }
}

DesktopSingletonBootstrapPort _createDefaultSingletonBootstrapPort() {
  if (Platform.isWindows) {
    return DesktopWindowsSingletonBootstrapPort();
  }
  if (Platform.isLinux || Platform.isMacOS) {
    return DesktopUnixSingletonBootstrapPort();
  }
  return const DesktopNoopSingletonBootstrapPort();
}

/// 桌面服务引导协调器。
///
/// 说明：
/// - 负责 `info.json/"Command Line"`、CLI、单服务发现与后台拉起；
/// - 正式链路不再依赖 `service_port.json`；
/// - `show` 只作为内部控制消息存在，不暴露成 public CLI。
class DesktopServiceBootstrap {
  DesktopServiceBootstrap({
    DesktopServiceInfoWriter? infoWriter,
    DesktopSingletonBootstrapPort? singletonPort,
    DesktopServiceProcessLauncher? processLauncher,
    DesktopServiceLineWriter? stdoutWriter,
    DesktopServiceLineWriter? stderrWriter,
    DesktopServiceExitHandler? exitHandler,
  }) : _infoWriter = infoWriter ?? DesktopServiceInfoWriter(),
       _singletonPort = singletonPort ?? _createDefaultSingletonBootstrapPort(),
       _processLauncher =
           processLauncher ?? const DesktopLocalProcessLauncher(),
       _stdoutWriter = stdoutWriter ?? _defaultStdoutWriter,
       _stderrWriter = stderrWriter ?? _defaultStderrWriter,
       _exitHandler = exitHandler ?? _defaultExitHandler;

  final DesktopServiceInfoWriter _infoWriter;
  final DesktopSingletonBootstrapPort _singletonPort;
  final DesktopServiceProcessLauncher _processLauncher;
  final DesktopServiceLineWriter _stdoutWriter;
  final DesktopServiceLineWriter _stderrWriter;
  final DesktopServiceExitHandler _exitHandler;

  bool _isPrimaryInstance = false;
  bool _shouldStartHidden = false;
  int? _servicePort;
  bool _pendingShowRequest = false;
  DesktopShowRequestHandler? _showHandler;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  bool get isPrimaryInstance => _isPrimaryInstance;

  bool get shouldStartHidden => _shouldStartHidden;

  Future<void> attachShowHandler(DesktopShowRequestHandler handler) async {
    _ensureNotDisposed();
    _showHandler = handler;
    if (_pendingShowRequest) {
      _pendingShowRequest = false;
      await handler();
    }
  }

  void detachShowHandler() {
    _showHandler = null;
  }

  Future<DesktopServiceEntrypointResult> prepareEntrypoint({
    required DesktopWindowLaunchArguments windowLaunch,
    required DesktopServiceLaunchArguments launchArguments,
  }) async {
    _ensureNotDisposed();
    if (!_supportsDesktopBootstrap() ||
        windowLaunch.role != DesktopWindowRole.main) {
      return const DesktopServiceEntrypointResult.continueApp();
    }

    await _infoWriter.writeInfo();

    if (launchArguments.getServicePort) {
      return _handleGetServicePort();
    }

    final DesktopPrimaryClaimResult claimResult = await _singletonPort
        .claimPrimary(onRequest: _handleSingletonRequest);
    if (claimResult == DesktopPrimaryClaimResult.primary) {
      _isPrimaryInstance = true;
      _shouldStartHidden = launchArguments.notShow;
      return const DesktopServiceEntrypointResult.continueApp();
    }

    if (launchArguments.notShow) {
      return const DesktopServiceEntrypointResult.exit(exitCode: 0);
    }

    final bool ready = await _singletonPort.waitUntilPrimaryAvailable();
    if (!ready) {
      return const DesktopServiceEntrypointResult.exit(
        exitCode: 1,
        stderrLine: 'LDDC service bootstrap unavailable.',
      );
    }
    await _singletonPort.request('show');
    return const DesktopServiceEntrypointResult.exit(exitCode: 0);
  }

  Future<bool> finalizeEntrypoint(DesktopServiceEntrypointResult result) async {
    if (result.shouldRunApp) {
      return true;
    }
    final String? stdoutLine = result.stdoutLine;
    if (stdoutLine != null && stdoutLine.isNotEmpty) {
      _stdoutWriter(stdoutLine);
    }
    final String? stderrLine = result.stderrLine;
    if (stderrLine != null && stderrLine.isNotEmpty) {
      _stderrWriter(stderrLine);
    }
    _exitHandler(result.exitCode);
    return false;
  }

  Future<void> registerServicePort(int port) async {
    _ensureNotDisposed();
    await _singletonPort.setServicePort(port);
    _ensureNotDisposed();
    _servicePort = port;
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _servicePort = null;
    _pendingShowRequest = false;
    _showHandler = null;
    await _singletonPort.close();
  }

  Future<DesktopServiceEntrypointResult> _handleGetServicePort() async {
    _bootstrapLogger.info('handle get service port request');
    final String? servicePort = await _resolveServicePortOrLaunch(
      timeout: const Duration(seconds: 20),
    );
    if (servicePort == null) {
      _bootstrapLogger.info('service port wait timed out');
      return const DesktopServiceEntrypointResult.exit(
        exitCode: 1,
        stderrLine: 'LDDC service port unavailable.',
      );
    }
    _bootstrapLogger.info(
      'service port resolved',
      fields: <String, Object?>{'port': servicePort},
    );
    return DesktopServiceEntrypointResult.exit(
      exitCode: 0,
      stdoutLine: servicePort,
    );
  }

  Future<String?> _requestServicePort({
    bool logInvalidResponse = true,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    try {
      final String? response = await _singletonPort.request(
        'get_service_port',
        timeout: timeout,
      );
      final int? parsedPort = int.tryParse(response?.trim() ?? '');
      if (parsedPort == null || parsedPort <= 0 || parsedPort > 65535) {
        if (logInvalidResponse) {
          _bootstrapLogger.info(
            'service port response ignored',
            fields: <String, Object?>{'response': response},
          );
        }
        return null;
      }
      return '$parsedPort';
    } on Object catch (error) {
      _bootstrapLogger.info(
        'service port request failed',
        fields: <String, Object?>{'error': error.toString()},
      );
      return null;
    }
  }

  Future<String?> _resolveServicePortOrLaunch({
    required Duration timeout,
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    bool launchRequested = false;
    bool? lastLoggedHasPrimary;
    bool? lastLoggedLaunchRequested;
    while (DateTime.now().isBefore(deadline)) {
      final bool hasPrimary = await _singletonPort.hasPrimaryInstance();
      if (lastLoggedHasPrimary != hasPrimary ||
          lastLoggedLaunchRequested != launchRequested) {
        // 端口发现会高频轮询，日志只记录状态变化，避免旧主实例退出期间
        // 连续空响应把日志刷屏，同时仍能看清 primary/后台拉起的状态流转。
        _bootstrapLogger.info(
          'primary instance checked',
          fields: <String, Object?>{
            'hasPrimary': hasPrimary,
            'launchRequested': launchRequested,
          },
        );
        lastLoggedHasPrimary = hasPrimary;
        lastLoggedLaunchRequested = launchRequested;
      }

      if (!hasPrimary && !launchRequested) {
        final DesktopServiceLaunchCommand cmd = _infoWriter
            .buildLaunchCommand();
        _bootstrapLogger.info(
          'launch background service',
          fields: <String, Object?>{'command': cmd.toCommandLine()},
        );
        await _processLauncher.launchBackgroundService(cmd);
        launchRequested = true;
      }

      if (hasPrimary || launchRequested) {
        // 旧主实例正在退出时可能仍持有单实例互斥体，但还没有可用 TCP 服务端口。
        // 只有合法端口才算可用；空响应或请求超时都继续轮询，并在旧主实例
        // 释放后立即拉起新的隐藏服务，避免播放器插件长期停在连接中状态。
        final String? port = await _requestServicePort(
          logInvalidResponse: false,
        );
        if (port != null) {
          return port;
        }
      }

      await Future<void>.delayed(pollInterval);
    }
    return null;
  }

  FutureOr<String?> _handleSingletonRequest(String message) async {
    if (_disposed) {
      return '';
    }
    switch (message.trim()) {
      case 'get_service_port':
        final int? servicePort = _servicePort;
        return servicePort == null ? '' : '$servicePort';
      case 'show':
        await _dispatchShowRequest();
        return 'message_received';
      default:
        return '';
    }
  }

  Future<void> _dispatchShowRequest() async {
    final DesktopShowRequestHandler? handler = _showHandler;
    if (handler == null) {
      _pendingShowRequest = true;
      return;
    }
    _pendingShowRequest = false;
    await handler();
  }

  bool _supportsDesktopBootstrap() {
    // `--get-service-port` 需要在三类桌面平台都能拉起隐藏后台服务。
    // 普通启动只有在显式携带内部 `--not-show` 时才隐藏，避免 Linux/macOS 用户正常点击应用时闪窗或不可见。
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('DesktopServiceBootstrap 已释放');
    }
  }
}

final class _DesktopPipeCreateResult {
  const _DesktopPipeCreateResult._({
    required this.handle,
    required this.error,
    required this.isExistingPrimary,
  });

  const _DesktopPipeCreateResult.created(HANDLE handle)
    : this._(handle: handle, error: null, isExistingPrimary: false);

  const _DesktopPipeCreateResult.existingPrimary(WIN32_ERROR error)
    : this._(handle: null, error: error, isExistingPrimary: true);

  const _DesktopPipeCreateResult.failed(WIN32_ERROR error)
    : this._(handle: null, error: error, isExistingPrimary: false);

  final HANDLE? handle;
  final WIN32_ERROR? error;
  final bool isExistingPrimary;
}
