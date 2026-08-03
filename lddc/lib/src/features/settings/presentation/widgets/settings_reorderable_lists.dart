import 'package:flutter/material.dart';

import '../../application/settings_page_models.dart';
import 'settings_data_helpers.dart';

class SettingsReorderableLabelList extends StatelessWidget {
  const SettingsReorderableLabelList({
    super.key,
    required this.items,
    required this.onChanged,
    this.reorderHint,
  });

  final List<SettingsOrderedToggleItem> items;
  final ValueChanged<List<SettingsOrderedToggleItem>> onChanged;
  final String? reorderHint;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      key: key,
      shrinkWrap: true,
      primary: false,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      onReorderItem: (int oldIndex, int newIndex) {
        onChanged(reorderItems(items, oldIndex, newIndex));
      },
      itemBuilder: (BuildContext context, int index) {
        final SettingsOrderedToggleItem item = items[index];
        // 设置卡片已经提供统一表面；列表项只保留分隔线，避免卡片套卡片
        // 造成层级误判。拖拽仍使用 Flutter 原生重排能力，不改变数据更新次数。
        return Column(
          key: ValueKey<String>('label_${item.value}'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(item.label),
              trailing: _SettingsDragHandle(index: index, hint: reorderHint),
            ),
            if (index != items.length - 1) const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class SettingsReorderableToggleList extends StatelessWidget {
  const SettingsReorderableToggleList({
    super.key,
    required this.items,
    required this.onChanged,
    this.reorderHint,
  });

  final List<SettingsOrderedToggleItem> items;
  final ValueChanged<List<SettingsOrderedToggleItem>> onChanged;
  final String? reorderHint;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      key: key,
      shrinkWrap: true,
      primary: false,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      onReorderItem: (int oldIndex, int newIndex) {
        onChanged(reorderItems(items, oldIndex, newIndex));
      },
      itemBuilder: (BuildContext context, int index) {
        final SettingsOrderedToggleItem item = items[index];
        return Column(
          key: ValueKey<String>('toggle_${item.value}'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Checkbox(
                value: item.selected,
                onChanged: (bool? selected) {
                  final List<SettingsOrderedToggleItem> updated =
                      List<SettingsOrderedToggleItem>.from(items);
                  updated[index] = item.copyWith(selected: selected ?? false);
                  onChanged(updated);
                },
              ),
              title: Text(item.label),
              trailing: _SettingsDragHandle(index: index, hint: reorderHint),
            ),
            if (index != items.length - 1) const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _SettingsDragHandle extends StatelessWidget {
  const _SettingsDragHandle({required this.index, this.hint});

  final int index;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final Widget handle = ReorderableDragStartListener(
      index: index,
      child: const SizedBox.square(
        dimension: 48,
        child: Center(child: ExcludeSemantics(child: Icon(Icons.drag_handle))),
      ),
    );
    final String? message = hint;
    if (message == null || message.isEmpty) {
      return handle;
    }
    // 拖拽图标没有文字标签，必须同时覆盖鼠标悬停和读屏语义；
    // 48dp 固定命中区也避免桌面与触屏设备上难以抓取。
    return Semantics(
      container: true,
      label: message,
      child: Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: handle,
      ),
    );
  }
}
