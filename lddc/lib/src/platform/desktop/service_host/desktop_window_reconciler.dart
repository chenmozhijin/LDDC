import '../../../core/logging/logging.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'desktop_floating_effect_executor.dart';
import 'desktop_selector_effect_executor.dart';

final AppLogger _windowReconcilerLogger = AppLogger.scope('window-reconciler');

typedef DesktopDestroyPanelsForInstance =
    Future<void> Function({
      required int instanceId,
      required Iterable<int> panelIds,
    });

class DesktopWindowReconciler {
  DesktopWindowReconciler({
    required DesktopWindowLifecycleRegistry lifecycleRegistry,
    required DesktopFloatingEffectExecutor floatingEffectExecutor,
    required DesktopSelectorEffectExecutor selectorEffectExecutor,
  }) : _lifecycleRegistry = lifecycleRegistry,
       _floatingEffectExecutor = floatingEffectExecutor,
       _selectorEffectExecutor = selectorEffectExecutor;

  final DesktopWindowLifecycleRegistry _lifecycleRegistry;
  final DesktopFloatingEffectExecutor _floatingEffectExecutor;
  final DesktopSelectorEffectExecutor _selectorEffectExecutor;

  DesktopDestroyPanelsForInstance? destroyPanelsForInstance;

  Future<void> reconcileSessionRemoval({
    required int instanceId,
    required Iterable<int> panelIds,
  }) async {
    final List<int> panelIdList = panelIds.toList(growable: false);
    _markDesiredAbsent(instanceId: instanceId, panelIds: panelIdList);
    await Future.wait(<Future<void>>[
      _destroySelector(instanceId),
      _destroyPanels(instanceId, panelIdList),
      _destroyFloating(instanceId),
    ]);
  }

  void _markDesiredAbsent({
    required int instanceId,
    required Iterable<int> panelIds,
  }) {
    _markWindowAbsent(
      _lifecycleRegistry.currentRef(
        role: DesktopWindowRole.selector,
        instanceId: instanceId,
      ),
      reason: 'reconcile-remove-session',
    );
    _markWindowAbsent(
      _lifecycleRegistry.currentRef(
        role: DesktopWindowRole.floating,
        instanceId: instanceId,
      ),
      reason: 'reconcile-remove-session',
    );
    for (final int panelId in panelIds) {
      _markWindowAbsent(
        _lifecycleRegistry.currentRef(
          role: DesktopWindowRole.panel,
          instanceId: instanceId,
          panelId: panelId,
        ),
        reason: 'reconcile-remove-session',
      );
    }
  }

  void _markWindowAbsent(DesktopWindowRef? ref, {required String reason}) {
    if (ref == null) {
      return;
    }
    _lifecycleRegistry.setDesired(
      ref,
      DesktopWindowDesiredState.absent,
      reason: reason,
    );
  }

  Future<void> _destroySelector(int instanceId) async {
    _windowReconcilerLogger.info('destroy selector instance=$instanceId');
    await _selectorEffectExecutor.destroyInstance(instanceId);
    _windowReconcilerLogger.info(
      'destroy selector completed instance=$instanceId',
    );
  }

  Future<void> _destroyFloating(int instanceId) async {
    _windowReconcilerLogger.info('destroy floating instance=$instanceId');
    await _floatingEffectExecutor.destroyInstance(instanceId);
    _windowReconcilerLogger.info(
      'destroy floating completed instance=$instanceId',
    );
  }

  Future<void> _destroyPanels(int instanceId, List<int> panelIds) async {
    if (panelIds.isEmpty) {
      return;
    }
    final DesktopDestroyPanelsForInstance? destroyer = destroyPanelsForInstance;
    if (destroyer == null) {
      _windowReconcilerLogger.info(
        'destroy panels skipped instance=$instanceId reason=disposer-missing',
      );
      return;
    }
    _windowReconcilerLogger.info(
      'destroy panels instance=$instanceId panelIds=${panelIds.join(',')}',
    );
    try {
      await destroyer(instanceId: instanceId, panelIds: panelIds);
      _windowReconcilerLogger.info(
        'destroy panels completed instance=$instanceId'
        ' panelIds=${panelIds.join(',')}',
      );
    } on Object catch (error, stackTrace) {
      _windowReconcilerLogger.info(
        'destroy panels failed instance=$instanceId'
        ' panelIds=${panelIds.join(',')}'
        ' error=$error stack=$stackTrace',
      );
    }
  }
}
