import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../../core/i18n/i18n.dart';
import '../../features/search/application/search_ui_host_mapper.dart';
import '../../features/search/application/search_workflow_providers.dart';
import '../../platform/files/app_file_picker.dart';
import '../app_feature_scopes.dart';
import '../bootstrap/app_providers.dart';

class DesktopSelectorWindowContent extends ConsumerStatefulWidget {
  const DesktopSelectorWindowContent({
    required this.instanceId,
    required this.contextSnapshot,
    required this.onLyricsSelected,
    super.key,
  });

  final int instanceId;
  final DesktopSelectorWindowContext? contextSnapshot;
  final Future<bool> Function(DesktopSelectorLyricsSelectedIntent intent)
  onLyricsSelected;

  @override
  ConsumerState<DesktopSelectorWindowContent> createState() =>
      _DesktopSelectorWindowContentState();
}

final class _DesktopSelectorWindowContentState
    extends ConsumerState<DesktopSelectorWindowContent> {
  late final SearchWorkflowDependencies _searchDependencies;

  @override
  void initState() {
    super.initState();
    // selector engine 只在窗口实例创建时装配一次 feature 依赖；上下文 refresh
    // 不能重新创建 ProviderScope，否则 Riverpod 会 dispose 正在工作的 controller。
    _searchDependencies = buildSearchWorkflowDependencies(ref);
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: <Override>[
        searchWorkflowDependenciesProvider.overrideWithValue(
          _searchDependencies,
        ),
      ],
      child: _DesktopSelectorSearchSurface(
        instanceId: widget.instanceId,
        initialState: _toFeatureInitialState(widget.contextSnapshot),
        dependencies: SearchLyricsSelectorDependencies(
          pickLocalLyricsPath: () async {
            final PickedFileHandle? file = await ref
                .read(appFilePickerProvider)
                .pickFile(
                  allowedExtensions: const <String>['qrc', 'krc', 'lrc'],
                  label: 'lyrics',
                );
            return file?.path;
          },
          loadLocalLyrics: (String path) {
            return ref.read(lyricsApiProvider).getLyrics(path: path);
          },
        ),
        onLyricsSelected: widget.onLyricsSelected,
      ),
    );
  }

  SearchLyricsSelectorInitialState? _toFeatureInitialState(
    DesktopSelectorWindowContext? context,
  ) {
    if (context == null) {
      return null;
    }
    // 桌面窗口协议的 refreshToken 只用于标记宿主上下文刷新。
    // 转成 feature 层的 refreshRevision 后，搜索页面不需要知道 payload 字段名。
    return SearchLyricsSelectorInitialState(
      keyword: context.keyword,
      lyrics: context.lyrics,
      langs: context.langs,
      offsetMs: context.offsetMs,
      refreshRevision: context.refreshToken,
    );
  }
}

/// 在子 ProviderScope 内取得独立控制器，确保每个选择器窗口都有自己的搜索状态。
final class _DesktopSelectorSearchSurface extends ConsumerStatefulWidget {
  const _DesktopSelectorSearchSurface({
    required this.instanceId,
    required this.initialState,
    required this.dependencies,
    required this.onLyricsSelected,
  });

  final int instanceId;
  final SearchLyricsSelectorInitialState? initialState;
  final SearchLyricsSelectorDependencies dependencies;
  final Future<bool> Function(DesktopSelectorLyricsSelectedIntent intent)
  onLyricsSelected;

  @override
  ConsumerState<_DesktopSelectorSearchSurface> createState() =>
      _DesktopSelectorSearchSurfaceState();
}

final class _DesktopSelectorSearchSurfaceState
    extends ConsumerState<_DesktopSelectorSearchSurface> {
  late final SearchWorkflowController _controller;
  VoidCallback? _unregisterDiagnostics;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(searchWorkflowControllerInstanceProvider);
    _unregisterDiagnostics = DesktopSubWindowRuntime.instance
        .registerSelectorRuntimeDiagnosticsProvider(() {
          final SearchWorkflowDiagnostics diagnostics = _controller.diagnostics;
          return DesktopSelectorRuntimeDiagnostics(
            available: true,
            hasActiveBatch: diagnostics.hasActiveBatch,
            hasActiveRequest: diagnostics.hasActiveRequest,
            hasPendingRequest: diagnostics.hasPendingRequest,
            hasDebounceTimer: diagnostics.hasDebounceTimer,
            isSearching: diagnostics.isSearching,
            isLoadingMore: diagnostics.isLoadingMore,
            searchBatchStartedCount: diagnostics.searchBatchStartedCount,
            searchBatchSettledCount: diagnostics.searchBatchSettledCount,
            sourceRequestStartedCount: diagnostics.sourceRequestStartedCount,
            sourceRequestSettledCount: diagnostics.sourceRequestSettledCount,
          );
        });
  }

  @override
  void dispose() {
    _unregisterDiagnostics?.call();
    _unregisterDiagnostics = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchLyricsSelectorPage(
      // 子 engine 可能先以空上下文首帧，再通过 MethodChannel 收到首次 show
      // payload。切换一次 identity 让 selector 页面走 initState 的确定性自动搜索
      // 路径；后续仍复用同一 identity，由 refreshRevision/关键词语义决定是否搜索。
      key: ValueKey<bool>(widget.initialState != null),
      controller: _controller,
      strings: context.l10n.toSearchUiStrings(),
      initialState: widget.initialState,
      dependencies: widget.dependencies,
      onLyricsSelected: (SearchLyricsSelectorResult result) {
        return widget.onLyricsSelected(
          DesktopSelectorLyricsSelectedIntent(
            instanceId: widget.instanceId,
            lyrics: result.lyrics,
            path: result.path,
            langs: result.langs,
            offsetMs: result.offsetMs,
            isInstrumental: result.isInstrumental,
          ),
        );
      },
    );
  }
}
