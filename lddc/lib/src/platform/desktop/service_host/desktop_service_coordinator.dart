import 'dart:async';
import 'dart:typed_data';
import '../../../core/config/config.dart';
import '../../../core/logging/logging.dart';
import '../ipc/desktop_ipc.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import '../window/desktop_playback_control_host_mapper.dart';
import 'desktop_selector_context_builder.dart';
import 'desktop_floating_effect_executor.dart';
import 'desktop_exit_guard.dart';
import 'desktop_main_window_navigation.dart';
import 'desktop_pending_effect_executor.dart';
import 'desktop_panel_effect_executor.dart';
import 'desktop_selector_effect_executor.dart';
import 'desktop_session_reducer.dart';
import 'desktop_session_state.dart';
import 'desktop_window_reconciler.dart';

final AppLogger _serviceCoordinatorLogger = AppLogger.scope(
  'service-coordinator',
);

/// 主机侧待继续处理的桌面 effect 批次。
///
/// 说明：
/// - 窗口相关 effect 已由 coordinator 直接下发；
/// - 其余 effect 继续暴露给上层，用于后续接自动搜索、远端歌词保存、
///   关联库写回等 IO 主线。
final class DesktopPendingEffectBatch {
  const DesktopPendingEffectBatch({
    required this.instanceId,
    required this.state,
    required this.effects,
    this.sourceIntent,
  });

  final int instanceId;
  final DesktopSessionState state;
  final List<DesktopSessionEffect> effects;
  final DesktopSelectorWindowIntent? sourceIntent;
}

/// 主机侧一次 reducer 应用结果。
final class DesktopCoordinatorApplyResult {
  const DesktopCoordinatorApplyResult({
    required this.instanceId,
    required this.state,
    required this.effects,
    required this.pendingEffects,
    this.sourceIntent,
  });

  final int instanceId;
  final DesktopSessionState state;
  final List<DesktopSessionEffect> effects;
  final List<DesktopSessionEffect> pendingEffects;
  final DesktopSelectorWindowIntent? sourceIntent;
}

/// 桌面服务向主窗口发布的一次性提示事件。
sealed class DesktopServiceNotice {
  const DesktopServiceNotice();
}

final class DesktopClientDisconnectedNotice extends DesktopServiceNotice {
  const DesktopClientDisconnectedNotice({required this.instanceIds});

  final List<int> instanceIds;
}

/// 面板宿主生命周期销毁口。
abstract interface class DesktopPanelLifecycleDisposer {
  Future<void> destroyPanelsForInstance({
    required int instanceId,
    required Iterable<int> panelIds,
  });
}

/// 桌面主机最小协调层。
///
/// 当前职责：
/// - 维护 `instanceId -> DesktopSessionState`；
/// - 订阅选择器意图流并回灌 reducer；
/// - 直接下发 panel/selector 窗口 effect；
/// - 将非窗口 effect 作为待处理批次继续抛给上层。
final class DesktopServiceCoordinator {
  DesktopServiceCoordinator({
    required DesktopSessionReducer reducer,
    required DesktopSceneStorePort sceneStore,
    required DesktopFloatingEffectExecutor floatingEffectExecutor,
    required DesktopPanelEffectExecutor panelEffectExecutor,
    required DesktopSelectorEffectExecutor selectorEffectExecutor,
    DesktopMainWindowNavigationPort mainWindowNavigationPort =
        const DesktopNoopMainWindowNavigationPort(),
    DesktopPendingEffectExecutor? pendingEffectExecutor,
    DesktopExitGuardPort exitGuard = const DesktopNoopExitGuard(),
    DesktopWindowLifecycleRegistry? lifecycleRegistry,
  }) : _reducer = reducer,
       _sceneStore = sceneStore,
       _floatingEffectExecutor = floatingEffectExecutor,
       _panelEffectExecutor = panelEffectExecutor,
       _selectorEffectExecutor = selectorEffectExecutor,
       _mainWindowNavigationPort = mainWindowNavigationPort,
       _pendingEffectExecutor = pendingEffectExecutor,
       _exitGuard = exitGuard,
       _sceneCodec = const DesktopLyricsSceneCodec(),
       _windowReconciler = DesktopWindowReconciler(
         lifecycleRegistry:
             lifecycleRegistry ??
             DesktopWindowLifecycleRegistryController.instance,
         floatingEffectExecutor: floatingEffectExecutor,
         selectorEffectExecutor: selectorEffectExecutor,
       );

  final DesktopSessionReducer _reducer;
  final DesktopSceneStorePort _sceneStore;
  final DesktopFloatingEffectExecutor _floatingEffectExecutor;
  final DesktopPanelEffectExecutor _panelEffectExecutor;
  final DesktopSelectorEffectExecutor _selectorEffectExecutor;
  final DesktopMainWindowNavigationPort _mainWindowNavigationPort;
  final DesktopPendingEffectExecutor? _pendingEffectExecutor;
  final DesktopExitGuardPort _exitGuard;
  final DesktopLyricsSceneCodec _sceneCodec;
  final DesktopWindowReconciler _windowReconciler;
  final Map<int, DesktopSessionState> _sessions = <int, DesktopSessionState>{};
  final Map<int, Future<void>> _sessionQueues = <int, Future<void>>{};
  final Set<int> _removingInstanceIds = <int>{};
  final Map<int, String> _publishedSceneIds = <int, String>{};
  final Map<int, int> _selectorRefreshTokens = <int, int>{};
  int _selectorConfigRevision = 0;
  final StreamController<DesktopPendingEffectBatch> _pendingEffectsController =
      StreamController<DesktopPendingEffectBatch>.broadcast(sync: true);
  final StreamController<Map<int, DesktopSessionState>>
  _sessionSnapshotsController =
      StreamController<Map<int, DesktopSessionState>>.broadcast(sync: true);
  final StreamController<DesktopServiceNotice> _noticesController =
      StreamController<DesktopServiceNotice>.broadcast(sync: true);

  StreamSubscription<DesktopPendingEffectBatch>? _pendingEffectSubscription;
  StreamSubscription<AppConfig>? _configSubscription;
  final Set<Future<void>> _pendingEffectTasks = <Future<void>>{};
  Future<void>? _configQueue;
  Future<void>? _disposeFuture;
  bool _selectorIntentsBound = false;
  bool _floatingIntentsBound = false;
  bool _panelIntentsBound = false;
  bool _pendingEffectsBound = false;
  bool _configWatchBound = false;
  bool _disposing = false;
  DesktopControlCommandSender? _controlCommandSender;

  Stream<DesktopPendingEffectBatch> get pendingEffects =>
      _pendingEffectsController.stream;

  Stream<Map<int, DesktopSessionState>> get sessionSnapshots =>
      _sessionSnapshotsController.stream;

  Stream<DesktopServiceNotice> get notices => _noticesController.stream;

  Map<int, DesktopSessionState> get sessions =>
      Map<int, DesktopSessionState>.unmodifiable(_sessions);

  void bindSelectorIntents() {
    if (_selectorIntentsBound) {
      return;
    }
    _selectorIntentsBound = true;
    _selectorEffectExecutor.setIntentHandler((
      DesktopSelectorWindowIntent intent,
    ) async {
      return await handleSelectorIntent(intent) != null;
    });
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposing = true;
    await _configSubscription?.cancel();
    _configSubscription = null;
    await _pendingEffectSubscription?.cancel();
    _pendingEffectSubscription = null;
    _floatingEffectExecutor.setIntentHandler(null);
    _selectorEffectExecutor.setIntentHandler(null);
    _panelEffectExecutor.setIntentHandler(null);
    _pendingEffectExecutor?.dispose();
    final Future<void>? configQueue = _configQueue;
    if (configQueue != null) {
      await configQueue;
    }
    await _waitForSessionTransactions();
    _pendingEffectTasks.clear();
    _controlCommandSender = null;
    _windowReconciler.destroyPanelsForInstance = null;
    _releasePublishedScenes();
    _sessions.clear();
    _selectorRefreshTokens.clear();
    _removingInstanceIds.clear();
    await _noticesController.close();
    await _sessionSnapshotsController.close();
    await _pendingEffectsController.close();
  }

  DesktopSessionState? sessionFor(int instanceId) => _sessions[instanceId];

  Future<bool> flushFloatingGeometryForApplicationExit() async {
    bool allConfirmed = true;
    for (final int instanceId in _sessions.keys.toList(growable: false)) {
      if (_removingInstanceIds.contains(instanceId)) {
        continue;
      }
      final bool confirmed = await _floatingEffectExecutor.flushGeometry(
        instanceId,
      );
      allConfirmed = allConfirmed && confirmed;
    }
    return allConfirmed;
  }

  void reportUnexpectedClientDisconnect(Iterable<int> instanceIds) {
    if (_noticesController.isClosed) {
      return;
    }
    final List<int> ids = instanceIds.toSet().toList(growable: false)..sort();
    if (ids.isEmpty) {
      return;
    }
    _noticesController.add(DesktopClientDisconnectedNotice(instanceIds: ids));
  }

  void registerPanelHost({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
  }) {
    final DesktopSessionState? state = _sessions[instanceId];
    if (state == null) {
      return;
    }
    final DesktopPanelState? current = state.panels[panelId];
    final DesktopPanelState nextPanel = DesktopPanelState(
      panelId: panelId,
      hostWindowId: hostWindowId,
      width: current?.width,
      height: current?.height,
      visible: current?.visible ?? true,
    );
    _sessions[instanceId] = state.upsertPanel(nextPanel);
    _emitSessionSnapshots();
  }

  void updatePanelHostSurface({
    required int instanceId,
    required int panelId,
    required int hostWindowId,
    required int width,
    required int height,
    required bool visible,
  }) {
    final DesktopSessionState? state = _sessions[instanceId];
    if (state == null) {
      return;
    }
    final DesktopPanelState nextPanel = DesktopPanelState(
      panelId: panelId,
      hostWindowId: hostWindowId,
      width: width,
      height: height,
      visible: visible,
    );
    _sessions[instanceId] = state.upsertPanel(nextPanel);
    _emitSessionSnapshots();
  }

  void unregisterPanelHost({required int instanceId, required int panelId}) {
    final DesktopSessionState? state = _sessions[instanceId];
    if (state == null) {
      return;
    }
    _sessions[instanceId] = state.removePanel(panelId);
    _emitSessionSnapshots();
  }

  Future<bool> runWindowAction({
    required int instanceId,
    required DesktopWindowActionType action,
    DesktopPlaybackControlTask? controlTask,
  }) async {
    switch (action) {
      case DesktopWindowActionType.showMainWindow:
        try {
          return await _mainWindowNavigationPort.showMainWindow();
        } on Object catch (error, stackTrace) {
          _serviceCoordinatorLogger.error(
            'show main window failed error=$error stack=$stackTrace',
          );
          return false;
        }
      case DesktopWindowActionType.openAssociationManager:
        try {
          return await _mainWindowNavigationPort.openAssociationManager();
        } on Object catch (error, stackTrace) {
          _serviceCoordinatorLogger.error(
            'open association manager failed error=$error stack=$stackTrace',
          );
          return false;
        }
      case DesktopWindowActionType.openSelector:
      case DesktopWindowActionType.toggleInstrumental:
      case DesktopWindowActionType.toggleAutoSearchDisabled:
      case DesktopWindowActionType.unlinkLyrics:
      case DesktopWindowActionType.toggleClickThrough:
      case DesktopWindowActionType.toggleFloatingVisibility:
      case DesktopWindowActionType.controlCommand:
        final DesktopSessionState? state = _sessions[instanceId];
        if (state == null) {
          return false;
        }
        try {
          return await _handleWindowAction(
            state: state,
            action: action,
            controlTask: controlTask,
          );
        } on Object catch (error, stackTrace) {
          _serviceCoordinatorLogger.error(
            'window action failed instance=$instanceId'
            ' action=${action.value}'
            ' error=$error stack=$stackTrace',
          );
          return false;
        }
    }
  }

  Future<void> removeSession(int instanceId) async {
    await _runSessionTransaction(instanceId, () async {
      final DesktopSessionState? state = _sessions[instanceId];
      if (state == null) {
        return;
      }
      _removingInstanceIds.add(instanceId);
      try {
        final bool flushed = await _floatingEffectExecutor.flushGeometry(
          instanceId,
        );
        if (!flushed) {
          _serviceCoordinatorLogger.warning(
            'floating geometry flush was not confirmed instance=$instanceId',
          );
        }
        await _windowReconciler.reconcileSessionRemoval(
          instanceId: instanceId,
          panelIds: state.panels.keys,
        );
        _sessions.remove(instanceId);
        _pendingEffectExecutor?.clearInstance(instanceId);
        _selectorRefreshTokens.remove(instanceId);
        final String? previousSceneId = _publishedSceneIds.remove(instanceId);
        if (previousSceneId != null) {
          _sceneStore.releaseScene(previousSceneId);
        }
        _sceneStore.evictScenes(instanceId);
        _emitSessionSnapshots();
      } finally {
        _removingInstanceIds.remove(instanceId);
      }
      await _exitGuard.handleInstanceLifecycleChanged();
    });
  }

  void upsertSession(DesktopSessionState state) {
    final int instanceId =
        state.instanceId ??
        (throw StateError(
          'DesktopServiceCoordinator 不能注册缺少 instanceId 的 session',
        ));
    final DesktopSessionState? previousState = _sessions[instanceId];
    _sessions[instanceId] = state;
    _emitSessionSnapshots();
    _publishSceneDocument(previousState: previousState, nextState: state);
    _dispatchWindowEffects(
      instanceId: instanceId,
      state: state,
      effects: const <DesktopSessionEffect>[],
    );
  }

  void bindConfigWatch({required ConfigRepository repository}) {
    if (_configWatchBound || _disposing) {
      return;
    }
    _configWatchBound = true;
    _configSubscription = repository.watch().listen((AppConfig config) {
      _enqueueAppConfigChanged(config);
    }, onError: _logConfigWatchError);
  }

  void bindFloatingIntents({required ConfigRepository repository}) {
    if (_floatingIntentsBound) {
      return;
    }
    _floatingIntentsBound = true;
    _floatingEffectExecutor.setIntentHandler((
      DesktopFloatingWindowIntent intent,
    ) {
      return _handleFloatingIntent(intent, repository: repository);
    });
  }

  void installPanelIntentHandlers() {
    if (_panelIntentsBound) {
      return;
    }
    _panelIntentsBound = true;
    _panelEffectExecutor.setIntentHandler((DesktopPanelWindowIntent intent) {
      return _handlePanelIntent(intent);
    });
  }

  void attachPanelLifecycleDisposer(DesktopPanelLifecycleDisposer disposer) {
    _windowReconciler.destroyPanelsForInstance =
        ({required int instanceId, required Iterable<int> panelIds}) {
          return disposer.destroyPanelsForInstance(
            instanceId: instanceId,
            panelIds: panelIds,
          );
        };
  }

  void attachControlCommandSender(DesktopControlCommandSender sender) {
    _controlCommandSender = sender;
  }

  void bindPendingEffects() {
    if (_pendingEffectsBound || _pendingEffectExecutor == null || _disposing) {
      return;
    }
    _pendingEffectsBound = true;
    _pendingEffectSubscription = pendingEffects.listen((
      DesktopPendingEffectBatch batch,
    ) {
      _startPendingEffectTask(batch);
    }, onError: _logPendingEffectStreamError);
  }

  Future<DesktopCoordinatorApplyResult?> handleSelectorIntent(
    DesktopSelectorWindowIntent intent,
  ) async {
    _serviceCoordinatorLogger.info(
      'selector intent received instance=${intent.instanceId}'
      ' type=${_selectorIntentName(intent)}',
    );
    final DesktopSessionState? state = _sessions[intent.instanceId];
    if (state == null) {
      return null;
    }
    return switch (intent) {
      DesktopSelectorLyricsSelectedIntent() => _applyExistingReducerResult(
        instanceId: intent.instanceId,
        result: _reducer.applySelectedLyrics(
          state,
          DesktopSelectedLyricsPayload(
            lyrics: intent.lyrics,
            path: intent.path,
            langs: intent.langs,
            offsetMs: intent.offsetMs,
            isInstrumental: intent.isInstrumental,
          ),
        ),
        sourceIntent: intent,
      ),
      DesktopSelectorWindowHiddenIntent() => DesktopCoordinatorApplyResult(
        instanceId: intent.instanceId,
        state: state,
        effects: const <DesktopSessionEffect>[],
        pendingEffects: const <DesktopSessionEffect>[],
        sourceIntent: intent,
      ),
    };
  }

  Future<DesktopCoordinatorApplyResult> applyReducerResult({
    required int instanceId,
    required DesktopReducerResult result,
    DesktopSelectorWindowIntent? sourceIntent,
    bool requireExistingSession = false,
  }) async {
    late DesktopCoordinatorApplyResult applyResult;
    await _runSessionTransaction(instanceId, () async {
      final DesktopSessionState? previousState = _sessions[instanceId];
      if (_removingInstanceIds.contains(instanceId) ||
          (requireExistingSession && previousState == null)) {
        applyResult = DesktopCoordinatorApplyResult(
          instanceId: instanceId,
          state: previousState ?? result.state,
          effects: const <DesktopSessionEffect>[],
          pendingEffects: const <DesktopSessionEffect>[],
          sourceIntent: sourceIntent,
        );
        return;
      }
      _sessions[instanceId] = result.state;
      _emitSessionSnapshots();
      _publishSceneDocument(
        previousState: previousState,
        nextState: result.state,
      );
      final List<DesktopSessionEffect> pendingEffects = result.effects
          .where(_isPendingEffect)
          .toList(growable: false);
      _dispatchWindowEffects(
        instanceId: instanceId,
        state: result.state,
        effects: result.effects,
      );
      if (pendingEffects.isNotEmpty && !_pendingEffectsController.isClosed) {
        _pendingEffectsController.add(
          DesktopPendingEffectBatch(
            instanceId: instanceId,
            state: result.state,
            effects: pendingEffects,
            sourceIntent: sourceIntent,
          ),
        );
      }
      applyResult = DesktopCoordinatorApplyResult(
        instanceId: instanceId,
        state: result.state,
        effects: result.effects,
        pendingEffects: pendingEffects,
        sourceIntent: sourceIntent,
      );
    });
    return applyResult;
  }

  Future<void> _runSessionTransaction(
    int instanceId,
    Future<void> Function() task,
  ) {
    final Future<void> previous =
        _sessionQueues[instanceId] ?? Future<void>.value();
    late Future<void> next;
    next = previous.then((_) => task(), onError: (_, _) => task());
    late Future<void> queued;
    queued = next.whenComplete(() {
      if (identical(_sessionQueues[instanceId], queued)) {
        _sessionQueues.remove(instanceId);
      }
    });
    _sessionQueues[instanceId] = queued;
    return next;
  }

  void _publishSceneDocument({
    required DesktopSessionState? previousState,
    required DesktopSessionState nextState,
  }) {
    final int instanceId =
        nextState.instanceId ??
        (throw StateError('DesktopServiceCoordinator 不能发布缺少 instanceId 的场景'));
    final String? previousSceneId =
        previousState?.lyricsRuntime.sceneRef?.sceneId ??
        _publishedSceneIds[instanceId];
    final DesktopSceneRef? sceneRef = nextState.lyricsRuntime.sceneRef;
    final DesktopLyricsSceneDocument? sceneDocument =
        nextState.lyricsRuntime.sceneDocument;
    if (sceneRef == null || sceneDocument == null) {
      _publishedSceneIds.remove(instanceId);
      if (previousSceneId != null) {
        _sceneStore.releaseScene(previousSceneId);
      }
      return;
    }
    if (previousSceneId == sceneRef.sceneId &&
        _publishedSceneIds[instanceId] == sceneRef.sceneId) {
      return;
    }
    if (previousSceneId != null && previousSceneId != sceneRef.sceneId) {
      _sceneStore.releaseScene(previousSceneId);
    }
    final Uint8List sceneBytes = _sceneCodec.encode(sceneDocument);
    _sceneStore.putScene(
      sceneRef.sceneId,
      sceneBytes,
      revision: sceneRef.sceneRevision,
      checksum: sceneRef.checksum,
    );
    _publishedSceneIds[instanceId] = sceneRef.sceneId;
    DesktopLyricsPerfStats.instance.recordPeak(
      'sceneStoreCurrentSceneCount',
      _sceneStore.stats.sceneCount,
    );
  }

  Future<void> _handlePendingEffectBatch(
    DesktopPendingEffectBatch batch,
  ) async {
    if (_disposing) {
      return;
    }
    final DesktopPendingEffectExecutor? executor = _pendingEffectExecutor;
    if (executor == null) {
      return;
    }
    final DesktopPendingEffectExecutionResult executionResult = await executor
        .executeBatch(batch);
    if (_disposing) {
      return;
    }
    for (final DesktopPendingEffectFollowUp followUp
        in executionResult.followUps) {
      switch (followUp) {
        case DesktopLibraryLinkResolvedFollowUp(
          :final instanceId,
          :final song,
          :final selectionRevision,
          :final libraryLink,
          :final linkedLyrics,
          :final lyricsPath,
          :final skipLinkedLyricsLoad,
        ):
          final DesktopSessionState? state = _sessions[instanceId];
          if (state == null ||
              state.lyricsRuntime.song != song ||
              state.lyricsRuntime.selectionRevision != selectionRevision) {
            continue;
          }
          if (linkedLyrics != null && lyricsPath != null) {
            await _applyExistingReducerResult(
              instanceId: instanceId,
              result: _reducer.applyLinkedLyricsLoaded(
                state,
                lyrics: linkedLyrics,
                lyricsPath: lyricsPath,
              ),
            );
            continue;
          }
          await _applyExistingReducerResult(
            instanceId: instanceId,
            result: _reducer.applyLibraryLinkResult(
              state,
              libraryLink: libraryLink,
              skipLinkedLyricsLoad: skipLinkedLyricsLoad,
            ),
          );
        case DesktopAutoFetchResolvedFollowUp(
          :final instanceId,
          :final song,
          :final selectionRevision,
          :final result,
          :final errorMessage,
          :final treatAsInstrumental,
        ):
          final DesktopSessionState? state = _sessions[instanceId];
          if (state == null ||
              state.lyricsRuntime.song != song ||
              state.lyricsRuntime.selectionRevision != selectionRevision) {
            continue;
          }
          await _applyExistingReducerResult(
            instanceId: instanceId,
            result: result == null
                ? _reducer.applyAutoFetchFailure(
                    state,
                    message: errorMessage ?? '',
                    treatAsInstrumental: treatAsInstrumental,
                  )
                : _reducer.applyAutoFetchResult(state, result: result),
          );
        case DesktopRemoteLyricsSavedFollowUp(
          :final instanceId,
          :final lyricsPath,
          :final lyricsRevision,
        ):
          final DesktopSessionState? state = _sessions[instanceId];
          if (state == null ||
              state.lyricsRuntime.lyricsRevision != lyricsRevision) {
            continue;
          }
          await _applyExistingReducerResult(
            instanceId: instanceId,
            result: _reducer.applyRemoteLyricsSaved(
              state,
              lyricsPath: lyricsPath,
            ),
          );
        case DesktopRestoreArtistTitleFollowUp(
          :final instanceId,
          :final song,
          :final lyricsRevision,
        ):
          final DesktopSessionState? state = _sessions[instanceId];
          if (state == null ||
              state.lyricsRuntime.song != song ||
              state.lyricsRuntime.lyricsRevision != lyricsRevision ||
              state.lyricsRuntime.lyrics != null ||
              state.config.isInstrumental) {
            continue;
          }
          await _applyExistingReducerResult(
            instanceId: instanceId,
            result: _reducer.showArtistTitle(state),
          );
      }
    }
  }

  Future<bool> _handleFloatingIntent(
    DesktopFloatingWindowIntent intent, {
    required ConfigRepository repository,
  }) async {
    try {
      if (!_sessions.containsKey(intent.instanceId)) {
        return false;
      }
      switch (intent) {
        case DesktopFloatingMetricsCommittedIntent():
          final AppConfig current = repository.current;
          final WindowRect? currentRect = current.desktop.windowRect;
          final bool sameRect =
              currentRect != null &&
              _sameFloatingWindowRect(currentRect, intent.windowRect);
          final bool sameFontSize =
              (current.desktop.fontSize - intent.fontSize).abs() < 0.1;
          if (sameRect && sameFontSize) {
            return true;
          }
          await repository.update(<String, Object?>{
            ConfigKey.desktopWindowRect: intent.windowRect.toList(),
            ConfigKey.desktopFontSize: intent.fontSize,
          });
          // 配置 watch 的 session fan-out 是异步的，但下一次窗口创建不能继续
          // 读取旧位置。这里只同步 reducer 的首次创建输入，不更新活动 session。
          _reducer.updateInitialWindowRect(intent.windowRect);
          return true;
        case DesktopFloatingActionWindowIntent():
          if (_removingInstanceIds.contains(intent.instanceId)) {
            return false;
          }
          _serviceCoordinatorLogger.info(
            'floating action received instance=${intent.instanceId}'
            ' action=${intent.action.value}'
            ' control=${intent.controlTask?.value ?? '-'}',
          );
          // 必须在当前 try 内等待窗口动作完成，异步阶段的插件异常才能由下方
          // catch 统一记录并转换为 false，避免异常越过桌面 IPC 的安全边界。
          return await _runIntentWindowAction(
            instanceId: intent.instanceId,
            action: intent.action,
            controlTask: intent.controlTask,
          );
      }
    } on Object catch (error, stackTrace) {
      _serviceCoordinatorLogger.error(
        'floating window action failed instance=${intent.instanceId}'
        ' error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  Future<bool> _handlePanelIntent(DesktopPanelWindowIntent intent) async {
    try {
      if (!_sessions.containsKey(intent.instanceId)) {
        return false;
      }
      switch (intent) {
        case DesktopPanelActionIntent():
          _serviceCoordinatorLogger.info(
            'panel action received instance=${intent.instanceId}'
            ' panel=${intent.panelId}'
            ' action=${intent.action.value}'
            ' control=${intent.controlTask?.value ?? '-'}',
          );
          // Panel 动作同样需要在 try 内等待；否则 Future 后续抛错时，本层的
          // 日志和失败返回值都不会生效，调用方会收到未处理的异步异常。
          return await _runIntentWindowAction(
            instanceId: intent.instanceId,
            action: intent.action,
            controlTask: intent.controlTask,
          );
      }
    } on Object catch (error, stackTrace) {
      _serviceCoordinatorLogger.error(
        'panel window action failed instance=${intent.instanceId}'
        ' panel=${intent.panelId}'
        ' error=$error stack=$stackTrace',
      );
      return false;
    }
  }

  Future<DesktopCoordinatorApplyResult> _applyExistingReducerResult({
    required int instanceId,
    required DesktopReducerResult result,
    DesktopSelectorWindowIntent? sourceIntent,
  }) {
    return applyReducerResult(
      instanceId: instanceId,
      result: result,
      sourceIntent: sourceIntent,
      requireExistingSession: true,
    );
  }

  Future<bool> _runIntentWindowAction({
    required int instanceId,
    required DesktopWindowActionType action,
    DesktopPlaybackControlTask? controlTask,
  }) async {
    return runWindowAction(
      instanceId: instanceId,
      action: action,
      controlTask: controlTask,
    );
  }

  Future<bool> _handleWindowAction({
    required DesktopSessionState state,
    required DesktopWindowActionType action,
    DesktopPlaybackControlTask? controlTask,
  }) async {
    final int instanceId =
        state.instanceId ?? (throw StateError('桌面窗口动作缺少 instanceId'));
    switch (action) {
      case DesktopWindowActionType.openSelector:
        await _selectorEffectExecutor.execute(
          DesktopRefreshSelectorEffect(
            instanceId: instanceId,
            context: _buildSelectorContext(state),
            onlyIfVisible: false,
          ),
        );
        return true;
      case DesktopWindowActionType.toggleInstrumental:
        await _applyExistingReducerResult(
          instanceId: instanceId,
          result: _reducer.setInstrumental(
            state,
            enable: !state.config.isInstrumental,
          ),
        );
        return true;
      case DesktopWindowActionType.toggleAutoSearchDisabled:
        await _applyExistingReducerResult(
          instanceId: instanceId,
          result: _reducer.setAutoSearch(
            state,
            isDisable: !state.config.isAutoSearchDisabled,
          ),
        );
        return true;
      case DesktopWindowActionType.unlinkLyrics:
        await _applyExistingReducerResult(
          instanceId: instanceId,
          result: _reducer.unlinkLyrics(state),
        );
        return true;
      case DesktopWindowActionType.toggleClickThrough:
        await _applyExistingReducerResult(
          instanceId: instanceId,
          result: DesktopReducerResult(
            state: state.copyWith(
              uiState: state.uiState.copyWith(
                clickThrough: !state.uiState.clickThrough,
              ),
            ),
          ),
        );
        return true;
      case DesktopWindowActionType.toggleFloatingVisibility:
        await _applyExistingReducerResult(
          instanceId: instanceId,
          result: DesktopReducerResult(
            state: state.copyWith(
              uiState: state.uiState.copyWith(
                floatingVisibilityMode: _toggleFloatingVisibility(state),
              ),
            ),
          ),
        );
        return true;
      case DesktopWindowActionType.showMainWindow:
      case DesktopWindowActionType.openAssociationManager:
        return false;
      case DesktopWindowActionType.controlCommand:
        if (controlTask == null) {
          return false;
        }
        final DesktopControlCommandSender? sender = _controlCommandSender;
        if (sender == null) {
          return false;
        }
        // 共享窗口动作只在真正写入 foobar IPC 时转换，避免协议枚举泄漏到包 API。
        return sender(
          instanceId: instanceId,
          task: controlTask.toProtocolControlTask(),
        );
    }
  }

  Future<void> _handleAppConfigChanged(AppConfig config) async {
    if (_disposing) {
      return;
    }
    _selectorConfigRevision += 1;
    await _selectorEffectExecutor.publishConfigRevision(
      _selectorConfigRevision,
    );
    final DesktopSessionReducerConfigDiff diff = _reducer
        .reconfigureFromAppConfig(config);
    if (!diff.hasAnyChange || _sessions.isEmpty) {
      return;
    }
    final List<MapEntry<int, DesktopSessionState>> entries = _sessions.entries
        .toList(growable: false);
    for (final MapEntry<int, DesktopSessionState> entry in entries) {
      if (_removingInstanceIds.contains(entry.key)) {
        continue;
      }
      final DesktopReducerResult result = _reducer.applyConfigDiff(
        entry.value,
        diff,
      );
      await _applyExistingReducerResult(instanceId: entry.key, result: result);
    }
  }

  void _enqueueAppConfigChanged(AppConfig config) {
    Future<void> applyConfig() async {
      if (_disposing) {
        return;
      }
      try {
        await _handleAppConfigChanged(config);
      } on Object catch (error, stackTrace) {
        _serviceCoordinatorLogger.error(
          'apply app config failed error=$error stack=$stackTrace',
        );
      }
    }

    final Future<void> previous = _configQueue ?? Future<void>.value();
    _configQueue = previous.then(
      (_) => applyConfig(),
      onError: (Object error, StackTrace stackTrace) async {
        _serviceCoordinatorLogger.error(
          'previous app config task failed error=$error stack=$stackTrace',
        );
        await applyConfig();
      },
    );
  }

  void _startPendingEffectTask(DesktopPendingEffectBatch batch) {
    if (_disposing) {
      return;
    }
    late final Future<void> tracked;
    tracked = _handlePendingEffectBatch(batch)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            _serviceCoordinatorLogger.error(
              'pending effect batch failed instance=${batch.instanceId}'
              ' error=$error stack=$stackTrace',
            );
          },
        )
        .whenComplete(() => _pendingEffectTasks.remove(tracked));
    _pendingEffectTasks.add(tracked);
  }

  void _logConfigWatchError(Object error, StackTrace stackTrace) {
    _serviceCoordinatorLogger.error(
      'config watch failed error=$error stack=$stackTrace',
    );
  }

  void _logPendingEffectStreamError(Object error, StackTrace stackTrace) {
    _serviceCoordinatorLogger.error(
      'pending effect stream failed error=$error stack=$stackTrace',
    );
  }

  Future<void> _waitForSessionTransactions() async {
    final List<Future<void>> transactions = _sessionQueues.values.toList(
      growable: false,
    );
    if (transactions.isEmpty) {
      return;
    }
    try {
      await Future.wait(transactions);
    } on Object catch (error, stackTrace) {
      _serviceCoordinatorLogger.error(
        'session transaction failed during dispose'
        ' error=$error stack=$stackTrace',
      );
    }
    _sessionQueues.clear();
  }

  void _releasePublishedScenes() {
    for (final String sceneId in _publishedSceneIds.values.toSet()) {
      _sceneStore.releaseScene(sceneId);
    }
    for (final int instanceId in _sessions.keys) {
      _sceneStore.evictScenes(instanceId);
    }
    _publishedSceneIds.clear();
  }

  bool _isPendingEffect(DesktopSessionEffect effect) {
    return switch (effect) {
      DesktopRefreshSelectorEffect() => false,
      DesktopSyncPanelsEffect() => false,
      _ => true,
    };
  }

  void _dispatchWindowEffects({
    required int instanceId,
    required DesktopSessionState state,
    required Iterable<DesktopSessionEffect> effects,
  }) {
    unawaited(_floatingEffectExecutor.syncState(state));

    final List<DesktopSessionEffect> panelEffects = <DesktopSessionEffect>[];
    final List<DesktopSessionEffect> selectorEffects = <DesktopSessionEffect>[];
    for (final DesktopSessionEffect effect in effects) {
      if (effect is DesktopSyncPanelsEffect) {
        panelEffects.add(effect);
      }
      if (effect case DesktopRefreshSelectorEffect(
        :final instanceId,
        :final onlyIfVisible,
      )) {
        final DesktopSessionState? currentState = _sessions[instanceId];
        if (currentState == null) {
          continue;
        }
        selectorEffects.add(
          DesktopRefreshSelectorEffect(
            instanceId: instanceId,
            context: _buildSelectorContext(currentState),
            onlyIfVisible: onlyIfVisible,
          ),
        );
      }
    }

    if (panelEffects.isNotEmpty) {
      unawaited(_panelEffectExecutor.executeAll(panelEffects));
    }
    if (selectorEffects.isNotEmpty) {
      unawaited(_selectorEffectExecutor.executeAll(selectorEffects));
    }
  }

  DesktopSelectorWindowContext _buildSelectorContext(
    DesktopSessionState state,
  ) {
    return buildDesktopSelectorContext(
      state: state,
      refreshToken: _nextSelectorRefreshToken(
        state.instanceId ??
            (throw StateError('DesktopServiceCoordinator 缺少 instanceId')),
      ),
    );
  }

  int _nextSelectorRefreshToken(int instanceId) {
    final int nextToken = (_selectorRefreshTokens[instanceId] ?? 0) + 1;
    _selectorRefreshTokens[instanceId] = nextToken;
    return nextToken;
  }

  String _selectorIntentName(DesktopSelectorWindowIntent intent) {
    return switch (intent) {
      DesktopSelectorLyricsSelectedIntent() => 'lyrics_selected',
      DesktopSelectorWindowHiddenIntent() => 'hidden',
    };
  }

  DesktopFloatingVisibilityMode _toggleFloatingVisibility(
    DesktopSessionState state,
  ) {
    return switch (state.uiState.floatingVisibilityMode) {
      DesktopFloatingVisibilityMode.forcedHidden =>
        DesktopFloatingVisibilityMode.forcedVisible,
      DesktopFloatingVisibilityMode.forcedVisible =>
        DesktopFloatingVisibilityMode.forcedHidden,
      DesktopFloatingVisibilityMode.auto =>
        _shouldShowAutomatically(state)
            ? DesktopFloatingVisibilityMode.forcedHidden
            : DesktopFloatingVisibilityMode.forcedVisible,
    };
  }

  bool _shouldShowAutomatically(DesktopSessionState state) {
    return state.lyricsRuntime.song != null ||
        state.lyricsRuntime.hasStaticDisplay ||
        state.lyricsRuntime.sceneRef != null ||
        state.lyricsRuntime.hasLyrics;
  }

  bool _sameFloatingWindowRect(WindowRect left, WindowRect right) {
    const double tolerance = 0.5;
    return (left.left - right.left).abs() < tolerance &&
        (left.top - right.top).abs() < tolerance &&
        (left.width - right.width).abs() < tolerance &&
        (left.height - right.height).abs() < tolerance;
  }

  void _emitSessionSnapshots() {
    if (_sessionSnapshotsController.isClosed) {
      return;
    }
    _sessionSnapshotsController.add(
      Map<int, DesktopSessionState>.unmodifiable(
        Map<int, DesktopSessionState>.from(_sessions),
      ),
    );
  }
}

typedef DesktopControlCommandSender =
    Future<bool> Function({
      required int instanceId,
      required DesktopControlCommandTask task,
    });
