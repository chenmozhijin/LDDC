import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../lyrics_ui_strings.dart';

/// 歌词格式下拉框：供搜索页与打开歌词页复用。
final class LyricsFormatDropdown extends StatelessWidget {
  const LyricsFormatDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    required this.strings,
    this.compact = false,
    this.labelText,
    this.formats,
  });

  final LyricsFormat value;
  final ValueChanged<LyricsFormat> onChanged;
  final LyricsUiStrings strings;
  final bool compact;
  final String? labelText;
  final List<LyricsFormat>? formats;

  @override
  Widget build(BuildContext context) {
    final List<LyricsFormat> effectiveFormats =
        formats ?? LyricsFormatCapabilities.exportableFormats;
    return DropdownButtonFormField<LyricsFormat>(
      // FormField 会把 initialValue 缓存在自己的 State 中。即使外层组件使用固定 key，
      // 格式值变化时也必须重建内部表单状态，否则控制器已经更新，界面仍可能显示旧格式。
      key: ValueKey<LyricsFormat>(value),
      initialValue: value,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(
        labelText: labelText ?? strings.text(LyricsUiTextKey.formatLabel),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: compact ? 10 : 12,
        ),
      ),
      items: effectiveFormats
          .map(
            (LyricsFormat format) => DropdownMenuItem<LyricsFormat>(
              value: format,
              child: Text(strings.formatLabel(format)),
            ),
          )
          .toList(growable: false),
      onChanged: (LyricsFormat? nextValue) {
        if (nextValue == null) {
          return;
        }
        onChanged(nextValue);
      },
    );
  }
}

/// 偏移量步进器：保留鼠标滚轮按 100ms 步进的Python版语义。
final class LyricsOffsetStepper extends StatelessWidget {
  const LyricsOffsetStepper({
    super.key,
    required this.offsetMs,
    required this.onChanged,
    required this.strings,
    this.compact = false,
    this.labelText,
  });

  final int offsetMs;
  final ValueChanged<int> onChanged;
  final LyricsUiStrings strings;
  final bool compact;
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        final double verticalDelta = event.scrollDelta.dy;
        // 触控板可能只产生横向滚动；这类事件不代表增减意图，不能误改歌词偏移。
        if (verticalDelta == 0) {
          return;
        }
        onChanged(verticalDelta > 0 ? offsetMs - 100 : offsetMs + 100);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${labelText ?? strings.text(LyricsUiTextKey.offsetLabel)}:'),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => onChanged(offsetMs - 100),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 16,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: compact ? 48 : 56,
                maxWidth: compact ? 84 : 96,
              ),
              child: Text(
                '$offsetMs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              onPressed: () => onChanged(offsetMs + 100),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              splashRadius: 16,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌词参数行：语言分段在上，格式与偏移同处一行。
///
/// 搜索预览（抽屉与内嵌控制块）与打开歌词页共用同一套参数排布。此前两处都是
/// 「格式独占一行 + 偏移独占一行」的竖向堆叠，移动端要占掉两行高度。这里改为
/// 一行：格式下拉用 [Flexible] 吃掉剩余宽度并限制上限，偏移步进器保持自身宽度，
/// 因此任何窗口宽度都不会横向溢出，也不会在大窗口里被拉成一整条。
final class LyricsParameterRow extends StatelessWidget {
  const LyricsParameterRow({
    super.key,
    required this.strings,
    required this.selectedLangs,
    required this.onLangsChanged,
    required this.format,
    required this.onFormatChanged,
    required this.offsetMs,
    required this.onOffsetChanged,
    this.compact = false,
    this.languageKey,
    this.formatKey,
    this.offsetKey,
  });

  final LyricsUiStrings strings;
  final Set<String> selectedLangs;
  final ValueChanged<Set<String>> onLangsChanged;
  final LyricsFormat format;
  final ValueChanged<LyricsFormat> onFormatChanged;
  final int offsetMs;
  final ValueChanged<int> onOffsetChanged;
  final bool compact;

  /// 三个子控件的 key。各宿主页面的测试依赖各自稳定的 key，因此由调用方传入。
  final Key? languageKey;
  final Key? formatKey;
  final Key? offsetKey;

  /// 格式下拉的最大宽度：宽屏上不跟着窗口一起变宽，避免出现一整条下拉框。
  static const double _maximumFormatWidth = 240;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: LyricsLanguageSegments(
            key: languageKey,
            compact: compact,
            strings: strings,
            selected: selectedLangs,
            onSelectionChanged: onLangsChanged,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _maximumFormatWidth,
                ),
                child: LyricsFormatDropdown(
                  key: formatKey,
                  value: format,
                  strings: strings,
                  compact: compact,
                  onChanged: onFormatChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            LyricsOffsetStepper(
              key: offsetKey,
              offsetMs: offsetMs,
              strings: strings,
              compact: compact,
              onChanged: onOffsetChanged,
            ),
          ],
        ),
      ],
    );
  }
}

/// 歌词语言分段按钮：仅接收选择集与回调，不绑定业务状态对象。
final class LyricsLanguageSegments extends StatelessWidget {
  const LyricsLanguageSegments({
    super.key,
    required this.selected,
    required this.onSelectionChanged,
    required this.strings,
    this.compact = false,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onSelectionChanged;
  final LyricsUiStrings strings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Set<String> normalizedSelected =
        LyricsLanguageRegistry.normalizeTokenList(selected).toSet();
    final List<ButtonSegment<String>> segments = LyricsLanguageRegistry
        .previewOrder
        .map(
          (String key) => ButtonSegment<String>(
            value: key,
            // SegmentedButton 会让所有分段采用最大固有宽度。未选中项也保留与
            // 默认勾选图标相同的布局，避免最长的“罗马音”被选中后整体跳宽。
            icon: const ExcludeSemantics(
              child: Opacity(opacity: 0, child: Icon(Icons.check)),
            ),
            label: Text(strings.languageLabel(key)),
          ),
        )
        .toList(growable: false);
    return SegmentedButton<String>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
      ),
      multiSelectionEnabled: true,
      emptySelectionAllowed: true,
      segments: segments,
      selected: normalizedSelected,
      onSelectionChanged: (Set<String> next) {
        onSelectionChanged(
          LyricsLanguageRegistry.orderedSelection(next).toSet(),
        );
      },
    );
  }
}
