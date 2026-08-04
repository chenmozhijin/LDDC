import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'dart:math' as math;

import '../../../core/logging/logging.dart';
import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'desktop_service_bootstrap_io.dart';
import 'desktop_service_coordinator.dart';
import 'desktop_panel_host_bridge.dart';
import 'desktop_session_reducer.dart';
import 'desktop_session_state.dart';

const int kDesktopServiceApiVersion = 2;
const List<String> kDesktopServiceWelcomeLines = <String>[
  '欢迎使用LDDC桌面歌词',
  '',
  'Welcome to LDDC Desktop Lyrics',
];
const int _maxBadFrameCount = 3;
const Duration _helloTimeout = Duration(seconds: 5);

final AppLogger _serviceHostLogger = AppLogger.scope('service-host');

typedef DesktopServiceServerSocketBinder = Future<ServerSocket> Function();

final class DesktopServiceHost {
  DesktopServiceHost({
    required DesktopServiceCoordinator coordinator,
    required DesktopSessionReducer reducer,
    required DesktopServiceBootstrap bootstrap,
    DesktopPanelHostBridgeController? panelHostBridgeController,
    DesktopServiceServerSocketBinder? serverSocketBinder,
    DesktopIpcMessageCodec? messageCodec,
    DesktopIpcFramer? framer,
    DateTime Function()? clock,
  }) : _coordinator = coordinator,
       _reducer = reducer,
       _bootstrap = bootstrap,
       _panelHostBridgeController =
           panelHostBridgeController ??
           DesktopPanelHostBridgeController(
             panelHost: const DesktopNoopPanelWindowHost(),
             coordinator: coordinator,
           ),
       _serverSocketBinder =
           serverSocketBinder ??
           (() => ServerSocket.bind(InternetAddress.loopbackIPv4, 0)),
       _messageCodec = messageCodec ?? const DesktopIpcMessageCodec(),
       _framer = framer ?? const DesktopIpcFramer(),
       _clock = clock ?? DateTime.now {
    _coordinator.attachPanelLifecycleDisposer(_panelHostBridgeController);
  }

  final DesktopServiceCoordinator _coordinator;
  final DesktopSessionReducer _reducer;
  final DesktopServiceBootstrap _bootstrap;
  final DesktopPanelHostBridgeController _panelHostBridgeController;
  final DesktopServiceServerSocketBinder _serverSocketBinder;
  final DesktopIpcMessageCodec _messageCodec;
  final DesktopIpcFramer _framer;
  final DateTime Function() _clock;

  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  final Map<Socket, _DesktopClientConnection> _connections =
      <Socket, _DesktopClientConnection>{};
  final Map<int, Socket> _instanceOwners = <int, Socket>{};
  int _nextInstanceId = 1024;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  bool _disposing = false;
  bool _disposed = false;

  int? get port => _server?.port;

  bool get isRunning => _server != null;

  Future<bool> sendControlCommand({
    required int instanceId,
    required DesktopControlCommandTask task,
  }) async {
    final DesktopSessionState? state = _coordinator.sessionFor(instanceId);
    if (state == null || !state.supportsControlTask(task)) {
      _serviceHostLogger.info(
        'skip control command task=${task.value} instance=$instanceId'
        ' stateExists=${state != null}',
      );
      return false;
    }
    final Socket? ownerSocket = _instanceOwners[instanceId];
    final _DesktopClientConnection? connection = ownerSocket == null
        ? null
        : _connections[ownerSocket];
    if (connection == null) {
      _serviceHostLogger.info(
        'skip control command task=${task.value} instance=$instanceId'
        ' ownerSocketMissing=true',
      );
      return false;
    }
    try {
      await _sendMessage(connection, DesktopControlCommandMessage(task: task));
      _serviceHostLogger.info(
        'sent control command task=${task.value} instance=$instanceId',
      );
      return true;
    } on Object catch (error, stackTrace) {
      _serviceHostLogger.info(
        'control command failed task=${task.value} instance=$instanceId'
        ' error=$error stack=$stackTrace',
      );
      await _handleSocketClosed(connection);
      return false;
    }
  }

  Future<void> ensureStarted() {
    if (_disposed) {
      return Future<void>.error(StateError('DesktopServiceHost 已释放，不能再次启动'));
    }
    if (_server != null) {
      return Future<void>.value();
    }
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    ServerSocket? server;
    StreamSubscription<Socket>? serverSubscription;
    bool servicePortRegistered = false;
    try {
      server = await _serverSocketBinder();
      if (_disposed) {
        throw StateError('DesktopServiceHost 在启动完成前已释放');
      }
      _serviceHostLogger.info(
        'server listening on ${server.address.address}:${server.port}',
      );
      // macOS 的 control.json 会发布这个业务端口。必须先安装连接监听回调，
      // 再让第二实例发现 endpoint，避免客户端连接到尚无人消费的 socket。
      serverSubscription = server.listen(_handleClientConnected);
      await _bootstrap.registerServicePort(server.port);
      servicePortRegistered = true;
      if (_disposed) {
        throw StateError('DesktopServiceHost 在端口注册期间已释放');
      }
      _server = server;
      _serverSubscription = serverSubscription;
    } on Object {
      if (servicePortRegistered) {
        await _bootstrap.unregisterServicePort();
      }
      await serverSubscription?.cancel();
      await server?.close();
      rethrow;
    } finally {
      _startFuture = null;
    }
  }

  void _handleClientConnected(Socket socket) {
    if (_disposing) {
      socket.destroy();
      return;
    }
    _serviceHostLogger.info(
      'client connected remote=${socket.remoteAddress.address}:${socket.remotePort}',
    );
    final _DesktopClientConnection connection = _DesktopClientConnection(
      socket: socket,
    );
    connection.helloTimer = Timer(_helloTimeout, () {
      if (connection.instanceIds.isEmpty) {
        _serviceHostLogger.info(
          'client hello timeout remote=${connection.socket.remotePort}',
        );
        _enqueueConnectionTask(
          connection,
          label: 'hello-timeout',
          task: () => _handleSocketClosed(connection),
          allowWhenClosing: true,
        );
      }
    });
    _connections[socket] = connection;
    connection.subscription = socket.listen(
      (List<int> chunk) {
        _enqueueConnectionTask(
          connection,
          label: 'chunk',
          task: () => _handleSocketChunk(connection, chunk),
        );
      },
      onDone: () {
        _enqueueConnectionTask(
          connection,
          label: 'done',
          task: () => _handleSocketClosed(connection),
          allowWhenClosing: true,
        );
      },
      onError: (_, _) {
        _enqueueConnectionTask(
          connection,
          label: 'error',
          task: () => _handleSocketClosed(connection),
          allowWhenClosing: true,
        );
      },
      cancelOnError: true,
    );
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _disposing = true;
    final Future<void>? startFuture = _startFuture;
    if (startFuture != null) {
      try {
        await startFuture;
      } on Object catch (error, stackTrace) {
        _serviceHostLogger.info(
          'server start stopped during dispose error=$error stack=$stackTrace',
        );
      }
    }
    // 先撤销可发现 endpoint，再停止 listener；文件锁由 bootstrap 在更外层释放。
    await _bootstrap.unregisterServicePort();
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    final ServerSocket? server = _server;
    _server = null;
    for (final _DesktopClientConnection connection
        in _connections.values.toList(growable: false)) {
      await _handleSocketClosed(connection);
    }
    _connections.clear();
    _instanceOwners.clear();
    await _panelHostBridgeController.dispose();
    await server?.close();
  }

  Future<void> _handleSocketChunk(
    _DesktopClientConnection connection,
    List<int> chunk,
  ) async {
    if (connection.isClosing) {
      return;
    }
    final List<List<int>> frames;
    try {
      frames = connection.frameBuffer.addChunk(chunk);
    } on Object catch (error, stackTrace) {
      await _handleBadFrame(
        connection,
        error: error,
        stackTrace: stackTrace,
        frameLength: connection.frameBuffer.pendingByteCount,
        reason: 'frame-buffer',
      );
      return;
    }
    for (final List<int> frame in frames) {
      try {
        final String rawFrame = utf8.decode(frame);
        final Object? decoded = jsonDecode(rawFrame);
        if (decoded is! Map<Object?, Object?>) {
          await _handleBadFrame(
            connection,
            error: const FormatException('payload must be JSON object'),
            stackTrace: StackTrace.current,
            frameLength: frame.length,
            reason: 'non-map',
          );
          continue;
        }
        final Map<String, Object?> payload = <String, Object?>{
          for (final MapEntry<Object?, Object?> entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
        final DesktopPrivateControlFrameResult controlResult = await _bootstrap
            .handlePrivateControlFrame(payload, encodedLength: frame.length);
        switch (controlResult.action) {
          case DesktopPrivateControlFrameAction.notControl:
            break;
          case DesktopPrivateControlFrameAction.respond:
            connection.helloTimer?.cancel();
            connection.helloTimer = null;
            connection.socket.add(_framer.encodeJson(controlResult.response!));
            await connection.socket.flush();
            await _handleSocketClosed(connection);
            return;
          case DesktopPrivateControlFrameAction.rejectAndClose:
            await _handleSocketClosed(connection);
            return;
        }
        final DesktopClientMessage message = _messageCodec.decodeClientMessage(
          payload,
        );
        await _handleClientMessage(connection, message);
      } on Object catch (error, stackTrace) {
        await _handleBadFrame(
          connection,
          error: error,
          stackTrace: stackTrace,
          frameLength: frame.length,
          reason: 'decode',
        );
      }
    }
  }

  Future<void> _handleBadFrame(
    _DesktopClientConnection connection, {
    required Object error,
    required StackTrace stackTrace,
    required int frameLength,
    required String reason,
  }) async {
    connection.badFrameCount += 1;
    _serviceHostLogger.info(
      'frame handling failed remote=${connection.socket.remotePort}'
      ' reason=$reason badFrames=${connection.badFrameCount}'
      ' frameLength=$frameLength error=$error stack=$stackTrace',
    );
    if (connection.badFrameCount >= _maxBadFrameCount) {
      _serviceHostLogger.info(
        'close client remote=${connection.socket.remotePort}'
        ' reason=too-many-bad-frames',
      );
      await _handleSocketClosed(connection);
    }
  }

  Future<void> _handleClientMessage(
    _DesktopClientConnection connection,
    DesktopClientMessage message,
  ) async {
    _serviceHostLogger.info(
      'recv task=${message.task.value} instance=${message.instanceId ?? '-'}'
      ' remote=${connection.socket.remotePort}',
    );
    if (message is DesktopHelloMessage) {
      connection.helloTimer?.cancel();
      connection.helloTimer = null;
      final int instanceId = _allocateInstanceId();
      final DesktopSessionState state = _createInitialState(
        hello: message,
        instanceId: instanceId,
      );
      await _coordinator.applyReducerResult(
        instanceId: instanceId,
        result: _reducer.setDisplayText(state, kDesktopServiceWelcomeLines),
      );
      connection.instanceIds.add(instanceId);
      _instanceOwners[instanceId] = connection.socket;
      _serviceHostLogger.info(
        'hello accepted instance=$instanceId pid=${message.pid ?? '-'}'
        ' client=${message.clientInfo.name ?? '-'}'
        ' version=${message.clientInfo.version ?? '-'}'
        ' tasks=${message.availableTaskNames.join(',')}',
      );
      await _sendMessage(
        connection,
        DesktopInstanceAckMessage(
          apiVersion: kDesktopServiceApiVersion,
          instanceId: instanceId,
        ),
      );
      return;
    }

    final int instanceId = message.instanceId!;
    final DesktopSessionState? state = _coordinator.sessionFor(instanceId);
    if (state == null) {
      _serviceHostLogger.info(
        'drop task=${message.task.value} instance=$instanceId reason=session-missing',
      );
      return;
    }
    if (!identical(_instanceOwners[instanceId], connection.socket)) {
      await _handleBadFrame(
        connection,
        error: FormatException('instance $instanceId 不属于当前连接'),
        stackTrace: StackTrace.current,
        frameLength: 0,
        reason: 'instance-owner-mismatch',
      );
      return;
    }

    switch (message) {
      case DesktopHelloMessage():
        return;
      case DesktopChangMusicMessage():
        _serviceHostLogger.info(
          'chang_music instance=$instanceId title=${message.title ?? '-'}'
          ' artist=${message.artist ?? '-'} album=${message.album ?? '-'}'
          ' duration=${message.durationMs} path=${message.path ?? '-'}'
          ' track=${message.normalizedTrack ?? '-'}',
        );
        final int nowMs = _clock().millisecondsSinceEpoch;
        await _coordinator.applyReducerResult(
          instanceId: instanceId,
          requireExistingSession: true,
          result: _reducer.handleChangMusic(
            state.copyWith(
              playbackSync: _nextPlaybackSyncState(
                state: state,
                task: DesktopIpcTask.changMusic,
                playbackTimeMs: message.playbackTimeMs,
                sendTimeSeconds: message.sendTimeSeconds,
                hostReceivedAtMs: nowMs,
                isPlaying: state.isPlaying,
                sceneId: null,
                songToken: message.normalizedTrack ?? message.path,
              ),
            ),
            message,
          ),
        );
        break;
      case DesktopPanelCreateMessage():
        _serviceHostLogger.info(
          'create_panel instance=$instanceId panel=${message.panelId}'
          ' host=${message.hostWindowId}',
        );
        await _panelHostBridgeController.createPanel(
          instanceId: instanceId,
          panelId: message.panelId,
          hostWindowId: message.hostWindowId,
        );
        break;
      case DesktopPanelSurfaceUpdateMessage():
        _serviceHostLogger.info(
          'update_panel_surface instance=$instanceId panel=${message.panelId}'
          ' size=${message.width}x${message.height}'
          ' space=${message.sizeSpace.value}'
          ' visible=${message.visible}',
        );
        await _panelHostBridgeController.updatePanelSurface(
          instanceId: instanceId,
          panelId: message.panelId,
          update: PanelSurfaceUpdate(
            width: message.width,
            height: message.height,
            sizeSpace: _mapPanelSizeSpace(message.sizeSpace),
            visible: message.visible,
          ),
        );
        break;
      case DesktopPanelDestroyMessage():
        _serviceHostLogger.info(
          'destroy_panel instance=$instanceId panel=${message.panelId}',
        );
        await _panelHostBridgeController.destroyPanel(
          instanceId: instanceId,
          panelId: message.panelId,
        );
        break;
      case DesktopSimpleTaskMessage():
        await _handleSimpleTaskMessage(state, message);
        break;
    }
  }

  Future<void> _handleSimpleTaskMessage(
    DesktopSessionState state,
    DesktopSimpleTaskMessage message,
  ) async {
    _serviceHostLogger.info(
      'simple task=${message.task.value} instance=${state.instanceId!}'
      ' playback=${message.playbackTimeMs ?? '-'}',
    );
    switch (message.task) {
      case DesktopIpcTask.start:
      case DesktopIpcTask.proceed:
        await _applyPlaybackState(
          state,
          task: message.task,
          isPlaying: true,
          playbackTimeMs: _resolvePluginPlaybackTimeMs(message, state),
          sendTimeSeconds: message.sendTimeSeconds,
        );
        break;
      case DesktopIpcTask.pause:
        await _applyPlaybackState(
          state,
          task: message.task,
          isPlaying: false,
          playbackTimeMs: _resolvePluginPlaybackTimeMs(message, state),
          sendTimeSeconds: message.sendTimeSeconds,
        );
        break;
      case DesktopIpcTask.sync:
        await _applyPlaybackState(
          state,
          task: message.task,
          isPlaying: state.isPlaying,
          playbackTimeMs: _resolvePluginPlaybackTimeMs(message, state),
          sendTimeSeconds: message.sendTimeSeconds,
        );
        break;
      case DesktopIpcTask.stop:
        await _handleStop(state);
        break;
      case DesktopIpcTask.delInstance:
        final int instanceId = state.instanceId!;
        final Socket? ownerSocket = _instanceOwners[instanceId];
        _serviceHostLogger.info(
          'del_instance instance=$instanceId panels=${state.panels.length}',
        );
        await _coordinator.removeSession(instanceId);
        _instanceOwners.remove(instanceId);
        _connections[ownerSocket]?.instanceIds.remove(instanceId);
        break;
      case DesktopIpcTask.newDesktopLyricsInstance:
      case DesktopIpcTask.changMusic:
      case DesktopIpcTask.createPanel:
      case DesktopIpcTask.updatePanelSurface:
      case DesktopIpcTask.destroyPanel:
        break;
    }
  }

  Future<void> _applyPlaybackState(
    DesktopSessionState state, {
    required DesktopIpcTask task,
    required bool isPlaying,
    required int playbackTimeMs,
    required double? sendTimeSeconds,
  }) async {
    final int nowMs = _clock().millisecondsSinceEpoch;
    final DesktopSessionState syncState = state.copyWith(
      isPlaying: isPlaying,
      lastTask: task,
      playbackSync: _nextPlaybackSyncState(
        state: state,
        task: task,
        playbackTimeMs: playbackTimeMs,
        sendTimeSeconds: sendTimeSeconds,
        hostReceivedAtMs: nowMs,
        isPlaying: isPlaying,
        sceneId: state.lyricsRuntime.sceneRef?.sceneId,
        songToken: _songTokenForState(state),
      ),
    );
    final DesktopReducerResult result = _reducer.applyPlaybackSync(syncState);
    await _coordinator.applyReducerResult(
      instanceId: state.instanceId!,
      requireExistingSession: true,
      result: result,
    );
  }

  Future<void> _handleStop(DesktopSessionState state) async {
    final DesktopReducerResult result = _reducer.applyStop(state);
    await _coordinator.applyReducerResult(
      instanceId: state.instanceId!,
      requireExistingSession: true,
      result: result,
    );
  }

  DesktopSessionState _createInitialState({
    required DesktopHelloMessage hello,
    required int instanceId,
  }) {
    return DesktopSessionState.initial(
      defaultLangs: _reducer.config.defaultLangs,
      langOrder: _reducer.config.langOrder,
      playedColors: _reducer.config.playedColors,
      unplayedColors: _reducer.config.unplayedColors,
      fontFamily: _reducer.config.fontFamily,
      fontSize: _reducer.config.fontSize,
      panelFontSize: _reducer.config.panelFontSize,
      showFurigana: _reducer.config.showFurigana,
      refreshRate: _reducer.config.refreshRate,
      windowRect: _reducer.config.windowRect,
    ).attachHello(
      hello: hello,
      apiVersion: kDesktopServiceApiVersion,
      instanceId: instanceId,
    );
  }

  int _allocateInstanceId() {
    while (_coordinator.sessionFor(_nextInstanceId) != null ||
        _instanceOwners.containsKey(_nextInstanceId)) {
      _nextInstanceId += 1;
    }
    return _nextInstanceId++;
  }

  int _resolvePluginPlaybackTimeMs(
    DesktopSimpleTaskMessage message,
    DesktopSessionState state,
  ) {
    return message.playbackTimeMs ?? state.playbackSync.pluginPlaybackTimeMs;
  }

  DesktopPlaybackSyncState _nextPlaybackSyncState({
    required DesktopSessionState state,
    required DesktopIpcTask task,
    required int? playbackTimeMs,
    required double? sendTimeSeconds,
    required int hostReceivedAtMs,
    required bool isPlaying,
    required String? sceneId,
    required String? songToken,
  }) {
    return state.playbackSync.copyWith(
      pluginPlaybackTimeMs: math.max(
        playbackTimeMs ?? state.playbackSync.pluginPlaybackTimeMs,
        0,
      ),
      pluginSendTimeMs: sendTimeSeconds == null
          ? null
          : (sendTimeSeconds * 1000).round(),
      hostReceivedAtMs: hostReceivedAtMs,
      isPlaying: isPlaying,
      syncRevision: state.playbackSync.syncRevision + 1,
      task: task,
      sceneId: sceneId,
      songToken: songToken,
      clearPluginSendTimeMs: sendTimeSeconds == null,
      clearSceneId: sceneId == null,
      clearSongToken: songToken == null,
    );
  }

  String? _songTokenForState(DesktopSessionState state) {
    final song = state.lyricsRuntime.song;
    return song?.id ?? song?.mid ?? song?.path;
  }

  PanelSizeSpace _mapPanelSizeSpace(DesktopPanelSizeSpace sizeSpace) {
    return switch (sizeSpace) {
      DesktopPanelSizeSpace.hostPhysicalPx => PanelSizeSpace.hostPhysicalPx,
      DesktopPanelSizeSpace.hostLogicalPx => PanelSizeSpace.hostLogicalPx,
      DesktopPanelSizeSpace.flutterLogicalPx => PanelSizeSpace.flutterLogicalPx,
      DesktopPanelSizeSpace.unknownRaw => PanelSizeSpace.unknownRaw,
    };
  }

  Future<void> _sendMessage(
    _DesktopClientConnection connection,
    DesktopIpcMessage message,
  ) {
    Future<void> write() async {
      if (connection.isClosing) {
        throw StateError('桌面 IPC 连接正在关闭，不能继续写入');
      }
      final Map<String, Object?> payload = message.toJson();
      _serviceHostLogger.info(
        'send task=${payload['task'] ?? 'ack'}'
        ' instance=${payload['id'] ?? '-'}'
        ' remote=${connection.socket.remotePort} payload=$payload',
      );
      connection.socket.add(_framer.encodeJson(payload));
      await connection.socket.flush();
    }

    final Future<void> pending = connection.pendingWrite.then(
      (_) => write(),
      onError: (Object error, StackTrace stackTrace) => write(),
    );
    connection.pendingWrite = pending;
    return pending;
  }

  void _enqueueConnectionTask(
    _DesktopClientConnection connection, {
    required String label,
    required Future<void> Function() task,
    bool allowWhenClosing = false,
  }) {
    Future<void> runTask() async {
      if (connection.isClosing && !allowWhenClosing) {
        return;
      }
      try {
        await task();
      } on Object catch (error, stackTrace) {
        _serviceHostLogger.error(
          'connection task failed label=$label'
          ' remote=${connection.socket.remotePort}'
          ' error=$error stack=$stackTrace',
        );
        if (!connection.isClosing) {
          await _handleSocketClosed(connection);
        }
      }
    }

    final Future<void> pending = connection.pendingRead.then(
      (_) => runTask(),
      onError: (Object error, StackTrace stackTrace) async {
        _serviceHostLogger.error(
          'previous connection task failed label=$label'
          ' remote=${connection.socket.remotePort}'
          ' error=$error stack=$stackTrace',
        );
        await runTask();
      },
    );
    connection.pendingRead = pending;
  }

  Future<void> _handleSocketClosed(_DesktopClientConnection connection) {
    return connection.closeFuture ??= _closeConnection(connection);
  }

  Future<void> _closeConnection(_DesktopClientConnection connection) async {
    connection.isClosing = true;
    _serviceHostLogger.info(
      'client closed remote=${connection.socket.remotePort}'
      ' instances=${connection.instanceIds.join(',')}',
    );
    final List<int> disconnectedInstanceIds = connection.instanceIds.toList(
      growable: false,
    );
    if (!_disposing && disconnectedInstanceIds.isNotEmpty) {
      _coordinator.reportUnexpectedClientDisconnect(disconnectedInstanceIds);
    }
    connection.helloTimer?.cancel();
    connection.helloTimer = null;
    await connection.subscription?.cancel();
    _connections.remove(connection.socket);
    for (final int instanceId in connection.instanceIds.toList(
      growable: false,
    )) {
      _instanceOwners.remove(instanceId);
      try {
        await _coordinator.removeSession(instanceId);
      } on Object catch (error, stackTrace) {
        _serviceHostLogger.error(
          'remove session failed instance=$instanceId'
          ' error=$error stack=$stackTrace',
        );
      }
    }
    connection.instanceIds.clear();
    connection.socket.destroy();
  }
}

final class _DesktopClientConnection {
  _DesktopClientConnection({required this.socket});

  final Socket socket;
  final DesktopIpcFrameBuffer frameBuffer = DesktopIpcFrameBuffer();
  final Set<int> instanceIds = <int>{};
  StreamSubscription<List<int>>? subscription;
  Future<void> pendingWrite = Future<void>.value();
  Future<void> pendingRead = Future<void>.value();
  Future<void>? closeFuture;
  Timer? helloTimer;
  int badFrameCount = 0;
  bool isClosing = false;
}
