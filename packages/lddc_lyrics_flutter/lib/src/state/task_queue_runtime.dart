import 'package:flutter/foundation.dart';

final class TaskQueueBinding<T> {
  const TaskQueueBinding({
    required this.itemListenable,
    required this.selectedListenable,
    required this.focusedListenable,
  });

  final ValueListenable<T> itemListenable;
  final ValueListenable<bool> selectedListenable;
  final ValueListenable<bool> focusedListenable;
}

final class TaskQueueRuntime<T> {
  TaskQueueRuntime({required this._idOf});

  final String Function(T item) _idOf;
  final Map<String, _TaskQueueEntry<T>> _entries =
      <String, _TaskQueueEntry<T>>{};
  final ValueNotifier<List<String>> _orderListenable =
      ValueNotifier<List<String>>(const <String>[]);
  final ValueNotifier<int> _revisionListenable = ValueNotifier<int>(0);

  Set<String> _selectedIds = <String>{};
  String? _focusedId;

  ValueListenable<List<String>> get orderListenable => _orderListenable;
  ValueListenable<int> get revisionListenable => _revisionListenable;

  List<String> get order => _orderListenable.value;

  List<T> get snapshot => List<T>.unmodifiable(<T>[
    for (final String id in _orderListenable.value)
      _entries[id]!.itemListenable.value,
  ]);

  int get length => _orderListenable.value.length;

  bool contains(String id) => _entries.containsKey(id);

  T? itemOrNull(String id) => _entries[id]?.itemListenable.value;

  TaskQueueBinding<T>? binding(String id) {
    final _TaskQueueEntry<T>? entry = _entries[id];
    if (entry == null) {
      return null;
    }
    return entry.binding;
  }

  void replaceAll(Iterable<T> items) {
    final List<T> nextItems = <T>[];
    final List<String> nextOrder = <String>[];
    final Set<String> seenIds = <String>{};
    for (final T item in items) {
      final String id = _idOf(item);
      if (!seenIds.add(id)) {
        // 必须在修改任何既有 notifier 前完成校验，否则后置重复 ID 会让替换失败，
        // 却留下部分新数据，调用方无法再把运行时视为原子快照。
        throw ArgumentError.value(id, 'items', 'Duplicate task queue id');
      }
      nextItems.add(item);
      nextOrder.add(id);
    }

    final Map<String, _TaskQueueEntry<T>> nextEntries =
        <String, _TaskQueueEntry<T>>{};
    for (int index = 0; index < nextOrder.length; index += 1) {
      final String id = nextOrder[index];
      final T item = nextItems[index];
      final _TaskQueueEntry<T>? existing = _entries[id];
      if (existing != null) {
        existing.itemListenable.value = item;
        nextEntries[id] = existing;
        continue;
      }
      nextEntries[id] = _TaskQueueEntry<T>(item);
    }

    for (final MapEntry<String, _TaskQueueEntry<T>> entry in _entries.entries) {
      if (!nextEntries.containsKey(entry.key)) {
        entry.value.dispose();
      }
    }

    _entries
      ..clear()
      ..addAll(nextEntries);

    _selectedIds = _selectedIds.where(nextEntries.containsKey).toSet();
    if (_focusedId != null && !nextEntries.containsKey(_focusedId)) {
      _focusedId = null;
    }

    if (!listEquals(_orderListenable.value, nextOrder)) {
      _orderListenable.value = List<String>.unmodifiable(nextOrder);
    }
    _syncSelectionNotifiers();
    _syncFocusedNotifier();
    _bumpRevision();
  }

  void patchItem(String id, T Function(T current) update) {
    final _TaskQueueEntry<T>? entry = _entries[id];
    if (entry == null) {
      return;
    }
    entry.itemListenable.value = update(entry.itemListenable.value);
    _bumpRevision();
  }

  void setSelectedIds(Set<String> itemIds) {
    _selectedIds = itemIds.where(_entries.containsKey).toSet();
    _syncSelectionNotifiers();
  }

  void setFocusedId(String? itemId) {
    _focusedId = itemId != null && _entries.containsKey(itemId) ? itemId : null;
    _syncFocusedNotifier();
  }

  void dispose() {
    for (final _TaskQueueEntry<T> entry in _entries.values) {
      entry.dispose();
    }
    _entries.clear();
    _orderListenable.dispose();
    _revisionListenable.dispose();
  }

  void _syncSelectionNotifiers() {
    for (final MapEntry<String, _TaskQueueEntry<T>> entry in _entries.entries) {
      entry.value.selectedListenable.value = _selectedIds.contains(entry.key);
    }
  }

  void _syncFocusedNotifier() {
    for (final MapEntry<String, _TaskQueueEntry<T>> entry in _entries.entries) {
      entry.value.focusedListenable.value = entry.key == _focusedId;
    }
  }

  void _bumpRevision() {
    _revisionListenable.value += 1;
  }
}

final class _TaskQueueEntry<T> {
  _TaskQueueEntry(T item)
    : itemListenable = ValueNotifier<T>(item),
      selectedListenable = ValueNotifier<bool>(false),
      focusedListenable = ValueNotifier<bool>(false);

  final ValueNotifier<T> itemListenable;
  final ValueNotifier<bool> selectedListenable;
  final ValueNotifier<bool> focusedListenable;
  late final TaskQueueBinding<T> binding = TaskQueueBinding<T>(
    itemListenable: itemListenable,
    selectedListenable: selectedListenable,
    focusedListenable: focusedListenable,
  );

  void dispose() {
    itemListenable.dispose();
    selectedListenable.dispose();
    focusedListenable.dispose();
  }
}
