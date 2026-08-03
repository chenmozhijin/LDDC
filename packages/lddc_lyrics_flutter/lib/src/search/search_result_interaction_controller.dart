import 'dart:async';

import 'package:flutter/widgets.dart';

/// 搜索结果列表的本地交互状态。
///
/// 普通搜索页和桌面歌词选择器都需要维护“当前选中行”和“单击打开”
/// 这两段纯 UI 状态。把它们集中到一个小控制器里，可以避免两个页面在
/// 选择清理、重复点击和 build 后回调上继续复制同一套逻辑。
class SearchResultInteractionController {
  final ValueNotifier<int?> selectedRowIndexListenable = ValueNotifier<int?>(
    null,
  );

  int? _openingRowIndex;
  Future<void>? _openingFuture;

  int? get selectedRowIndex => selectedRowIndexListenable.value;

  void dispose() {
    selectedRowIndexListenable.dispose();
  }

  void clearSelection() {
    if (selectedRowIndexListenable.value != null) {
      selectedRowIndexListenable.value = null;
    }
  }

  void reset() {
    clearSelection();
    _openingRowIndex = null;
    _openingFuture = null;
  }

  void selectRow(int rowIndex) {
    if (selectedRowIndexListenable.value != rowIndex) {
      selectedRowIndexListenable.value = rowIndex;
    }
  }

  /// 结果列表在 provider 更新后可能变短。
  ///
  /// 选中状态是 ValueNotifier，若在子树 build 期间立刻通知监听器，
  /// Flutter 会触发重入式重建。这里统一延后一帧清理，让两个搜索入口的
  /// 行为保持一致，也便于测试覆盖这个边界。
  void clearSelectionIfOutOfRange(
    int rowCount, {
    required bool Function() isMounted,
  }) {
    final int? selected = selectedRowIndexListenable.value;
    if (selected == null || selected < rowCount) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) {
        return;
      }
      final int? latest = selectedRowIndexListenable.value;
      if (latest != null && latest >= rowCount) {
        selectedRowIndexListenable.value = null;
      }
    });
  }

  /// 单击结果时立即打开。相同结果尚未完成时复用原 Future，避免鼠标双击
  /// 或触控连续点击重复发起网络请求；切换到另一行则允许新请求接管预览。
  Future<void> handleRowTap(
    int rowIndex, {
    required Future<void> Function(int rowIndex) openRow,
  }) async {
    selectRow(rowIndex);
    final Future<void>? activeFuture = _openingFuture;
    if (_openingRowIndex == rowIndex && activeFuture != null) {
      await activeFuture;
      return;
    }
    final Future<void> future = openRow(rowIndex);
    _openingRowIndex = rowIndex;
    _openingFuture = future;
    unawaited(
      future.then<void>(
        (_) => _clearOpeningFuture(future),
        onError: (Object error, StackTrace stackTrace) {
          _clearOpeningFuture(future);
        },
      ),
    );
    await future;
  }

  void _clearOpeningFuture(Future<void> future) {
    if (identical(_openingFuture, future)) {
      _openingRowIndex = null;
      _openingFuture = null;
    }
  }
}
