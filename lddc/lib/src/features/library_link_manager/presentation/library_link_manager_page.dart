import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/library_link/library_link.dart';
import '../application/library_link_manager_page_controller.dart';
import '../application/library_link_manager_page_state.dart';
import 'library_link_manager_widgets.dart';

class LibraryLinkManagerPage extends ConsumerStatefulWidget {
  const LibraryLinkManagerPage({super.key});

  @override
  ConsumerState<LibraryLinkManagerPage> createState() =>
      _LibraryLinkManagerPageState();
}

class _LibraryLinkManagerPageState
    extends ConsumerState<LibraryLinkManagerPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        ref
            .read(libraryLinkManagerPageControllerProvider.notifier)
            .initialize(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final l10n = context.l10n;
    final LibraryLinkManagerPageState state = ref.watch(
      libraryLinkManagerPageControllerProvider,
    );
    final LibraryLinkManagerPageController controller = ref.read(
      libraryLinkManagerPageControllerProvider.notifier,
    );
    final LibraryLinkManagerNotice? notice = state.notice;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: state.busy ? null : controller.returnToSettings,
                icon: const Icon(Icons.arrow_back_outlined),
                label: Text(l10n.libraryLinkManagerReturnToSettings),
              ),
              FilledButton.icon(
                onPressed: state.busy ? null : () => _refresh(controller),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.libraryLinkManagerRefresh),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || state.selectedIds.isEmpty
                    ? null
                    : controller.deleteSelected,
                icon: const Icon(Icons.delete_outline),
                label: Text(
                  l10n.libraryLinkManagerDeleteSelected(state.selectedCount),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || !state.hasItems
                    ? null
                    : () => _deleteAll(controller),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: Text(l10n.libraryLinkManagerDeleteAll),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || !state.hasItems
                    ? null
                    : controller.clearInvalid,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(l10n.libraryLinkManagerClearInvalid),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || !state.hasItems
                    ? null
                    : controller.changeDirectory,
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text(l10n.libraryLinkManagerChangeDirectory),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || !state.hasItems
                    ? null
                    : controller.backupToJson,
                icon: const Icon(Icons.backup_outlined),
                label: Text(l10n.libraryLinkManagerBackupToJson),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy
                    ? null
                    : () => _restoreFromJson(controller),
                icon: const Icon(Icons.restore_outlined),
                label: Text(l10n.libraryLinkManagerRestoreFromJson),
              ),
              FilledButton.tonalIcon(
                onPressed: state.busy || !state.hasItems
                    ? null
                    : controller.exportLyrics,
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(l10n.libraryLinkManagerExportLyrics),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: (String value) {
              setState(() {});
              controller.scheduleSearch(value);
            },
            onSubmitted: (String value) {
              unawaited(controller.submitSearch(value));
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.libraryLinkManagerSearchHint,
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.libraryLinkManagerClearSearch,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        unawaited(controller.submitSearch(''));
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.searchText.isEmpty
                ? l10n.libraryLinkManagerSummary(
                    state.totalCount,
                    state.selectedCount,
                  )
                : l10n.libraryLinkManagerSearchSummary(
                    state.totalCount,
                    state.selectedCount,
                  ),
            style: theme.textTheme.bodyMedium,
          ),
          if (notice != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(_noticeText(context, notice)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Expanded(child: _LibraryLinkList()),
        ],
      ),
    );
  }

  Future<void> _refresh(LibraryLinkManagerPageController controller) {
    return controller.refresh();
  }

  Future<void> _deleteAll(LibraryLinkManagerPageController controller) async {
    if (await _confirm(context.l10n.libraryLinkManagerDeleteAllConfirm)) {
      await controller.deleteAll();
    }
  }

  Future<void> _restoreFromJson(
    LibraryLinkManagerPageController controller,
  ) async {
    final l10n = context.l10n;
    final LibraryLinkManagerRestoreFile? file = await controller
        .pickRestoreFile(
          confirmButtonText: l10n.libraryLinkManagerRestoreAction,
        );
    if (file == null) {
      return;
    }
    if (!await _confirm(l10n.libraryLinkManagerRestoreConfirm)) {
      return;
    }
    await controller.restoreFromJson(
      file: file,
      invalidBackupFormatMessage: l10n.libraryLinkManagerInvalidBackupFormat,
    );
  }

  Future<bool> _confirm(String message) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.l10n.commonConfirm),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.actionConfirm),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }
}

class _LibraryLinkList extends ConsumerStatefulWidget {
  const _LibraryLinkList();

  @override
  ConsumerState<_LibraryLinkList> createState() => _LibraryLinkListState();
}

class _LibraryLinkListState extends ConsumerState<_LibraryLinkList> {
  static const double _itemExtent = 148;

  final Set<int> _pendingRequiredIndexes = <int>{};
  final ScrollController _scrollController = ScrollController();
  bool _requiredRequestScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (
      bool loading,
      int totalCount,
      Map<int, List<LibraryLinkItem>> loadedChunks,
    ) = ref.watch(
      libraryLinkManagerPageControllerProvider.select(
        (LibraryLinkManagerPageState state) =>
            (state.loading, state.totalCount, state.loadedChunks),
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : totalCount == 0
          ? Center(child: Text(context.l10n.libraryLinkManagerEmpty))
          : Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              interactive: true,
              thickness: 10,
              radius: const Radius.circular(4),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                // 卡片内容已收敛为单行配置区，因此可以使用紧凑且稳定的固定高度。
                // 固定 extent 仍可让滚动条直接跳到任意索引，无需测量 2800 条记录。
                itemExtent: _itemExtent,
                scrollCacheExtent: const ScrollCacheExtent.pixels(1800),
                itemCount: totalCount,
                itemBuilder: (BuildContext context, int index) {
                  final LibraryLinkItem? item = _itemAt(index, loadedChunks);
                  if (item == null) {
                    _scheduleRequiredIndex(index);
                    return LibraryLinkPlaceholderCard(
                      key: ValueKey<String>('library_link_placeholder_$index'),
                    );
                  }
                  return _SelectableLibraryLinkRow(
                    key: ValueKey<int>(item.id),
                    item: item,
                  );
                },
              ),
            ),
    );
  }

  LibraryLinkItem? _itemAt(
    int index,
    Map<int, List<LibraryLinkItem>> loadedChunks,
  ) {
    final int chunkIndex = index ~/ LibraryLinkManagerPageController.chunkSize;
    final List<LibraryLinkItem>? chunk = loadedChunks[chunkIndex];
    if (chunk == null) {
      return null;
    }
    final int localIndex =
        index - (chunkIndex * LibraryLinkManagerPageController.chunkSize);
    return localIndex >= 0 && localIndex < chunk.length
        ? chunk[localIndex]
        : null;
  }

  void _scheduleRequiredIndex(int index) {
    _pendingRequiredIndexes.add(index);
    if (_requiredRequestScheduled) {
      return;
    }
    _requiredRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requiredRequestScheduled = false;
      if (!mounted || _pendingRequiredIndexes.isEmpty) {
        return;
      }
      final Set<int> indexes = Set<int>.from(_pendingRequiredIndexes);
      _pendingRequiredIndexes.clear();
      ref
          .read(libraryLinkManagerPageControllerProvider.notifier)
          .handleRequiredIndexes(indexes);
    });
  }
}

class _SelectableLibraryLinkRow extends ConsumerWidget {
  const _SelectableLibraryLinkRow({super.key, required this.item});

  final LibraryLinkItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool selected = ref.watch(
      libraryLinkManagerPageControllerProvider.select(
        (LibraryLinkManagerPageState state) =>
            state.selectedIds.contains(item.id),
      ),
    );
    final LibraryLinkManagerPageController controller = ref.read(
      libraryLinkManagerPageControllerProvider.notifier,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LibraryLinkItemCard(
        item: item,
        selected: selected,
        durationText: _formatDuration(item.song.durationMs),
        onSelectedChanged: (bool? value) {
          controller.toggleSelection(item.id, value);
        },
      ),
    );
  }
}

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '';
  }
  final Duration duration = Duration(milliseconds: durationMs);
  final int minutes = duration.inMinutes.remainder(60);
  final int seconds = duration.inSeconds.remainder(60);
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _noticeText(BuildContext context, LibraryLinkManagerNotice notice) {
  final l10n = context.l10n;
  final String detail = notice.detail ?? '';
  final String path = notice.path ?? '';
  final int count = notice.count ?? 0;
  return switch (notice.code) {
    LibraryLinkManagerNoticeCode.loadFailed =>
      l10n.libraryLinkManagerLoadFailed(detail),
    LibraryLinkManagerNoticeCode.deleteSelectedSuccess =>
      l10n.libraryLinkManagerDeleteSelectedSuccess,
    LibraryLinkManagerNoticeCode.deleteAllSuccess =>
      l10n.libraryLinkManagerDeleteAllSuccess,
    LibraryLinkManagerNoticeCode.clearInvalidSuccess =>
      l10n.libraryLinkManagerClearInvalidSuccess(count),
    LibraryLinkManagerNoticeCode.changeDirectorySuccess =>
      l10n.libraryLinkManagerChangeDirectorySuccess(count),
    LibraryLinkManagerNoticeCode.backupSuccess =>
      l10n.libraryLinkManagerBackupSuccess(path),
    LibraryLinkManagerNoticeCode.restoreSuccess =>
      l10n.libraryLinkManagerRestoreSuccess,
    LibraryLinkManagerNoticeCode.exportSuccess =>
      l10n.libraryLinkManagerExportSuccess(count),
    LibraryLinkManagerNoticeCode.operationFailed =>
      l10n.libraryLinkManagerOperationFailed(detail),
  };
}
