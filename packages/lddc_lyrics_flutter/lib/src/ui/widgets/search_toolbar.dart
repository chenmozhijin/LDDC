import 'package:flutter/material.dart';

/// 搜索工具条来源选项。
final class SearchToolbarSourceItem {
  const SearchToolbarSourceItem({required this.value, required this.label});

  final String value;
  final String label;
}

/// 搜索工具条：封装来源选择、关键词输入与触发动作。
final class SearchToolbar extends StatelessWidget {
  const SearchToolbar({
    super.key,
    required this.keywordController,
    required this.sourceItems,
    required this.selectedSource,
    required this.searchButtonLabel,
    required this.keywordHint,
    required this.sourceLabel,
    required this.onSourceChanged,
    required this.onSearchPressed,
    required this.isCompact,
    this.onKeywordChanged,
  });

  final TextEditingController keywordController;
  final List<SearchToolbarSourceItem> sourceItems;
  final String selectedSource;
  final String searchButtonLabel;
  final String keywordHint;
  final String sourceLabel;
  final ValueChanged<String> onSourceChanged;
  final VoidCallback onSearchPressed;
  final ValueChanged<String>? onKeywordChanged;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildSearchBar(
        trailing: <Widget>[
          PopupMenuButton<String>(
            key: const ValueKey<String>('search_toolbar_source_menu'),
            initialValue: selectedSource,
            tooltip: sourceLabel,
            onSelected: (String value) => onSourceChanged(value),
            itemBuilder: (BuildContext context) {
              return sourceItems
                  .map(
                    (SearchToolbarSourceItem item) => PopupMenuItem<String>(
                      key: ValueKey<String>(
                        'search_toolbar_source_item_${item.value}',
                      ),
                      value: item.value,
                      child: Text(item.label),
                    ),
                  )
                  .toList(growable: false);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: isCompact ? 72 : 92,
                maxWidth: isCompact ? 112 : 148,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.tune_rounded, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _selectedSourceLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down_rounded),
                  ],
                ),
              ),
            ),
          ),
          IconButton.filledTonal(
            key: const ValueKey<String>('search_toolbar_search_button'),
            onPressed: onSearchPressed,
            tooltip: searchButtonLabel,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar({required List<Widget> trailing}) {
    return SearchBar(
      key: const ValueKey<String>('search_toolbar_search_bar'),
      controller: keywordController,
      hintText: keywordHint,
      leading: const Icon(Icons.search_rounded),
      trailing: trailing,
      onChanged: onKeywordChanged,
      onSubmitted: (_) => onSearchPressed(),
      constraints: const BoxConstraints(minHeight: 46, maxHeight: 46),
      padding: const WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  String _selectedSourceLabel() {
    for (final SearchToolbarSourceItem item in sourceItems) {
      if (item.value == selectedSource) {
        return item.label;
      }
    }
    return selectedSource;
  }
}
