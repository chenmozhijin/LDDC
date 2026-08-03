import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/library_link/library_link.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import '../../../shared/ui/components/adaptive_path_text.dart';

/// 关联库单行卡片。
///
/// 这个组件只负责把一条 `LibraryLinkItem` 展示成 Material 卡片，不直接读写
/// repository，也不持有滚动、分页或批量操作状态。页面层只需要把选中状态和
/// checkbox 回调传进来，方便后续维护时把“展示”和“数据操作”分开理解。
class LibraryLinkItemCard extends StatelessWidget {
  const LibraryLinkItemCard({
    super.key,
    required this.item,
    required this.selected,
    required this.durationText,
    required this.onSelectedChanged,
  });

  final LibraryLinkItem item;
  final bool selected;
  final String durationText;
  final ValueChanged<bool?> onSelectedChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final String title = (item.song.title ?? '').trim().isEmpty
        ? l10n.libraryLinkManagerUnnamedSong
        : item.song.title!;
    final String artistText = item.song.artistText.trim().isEmpty
        ? l10n.libraryLinkManagerUnknownArtist
        : item.song.artistText;
    final String albumText = (item.song.album ?? '').trim().isEmpty
        ? l10n.libraryLinkManagerUnknownAlbum
        : item.song.album!;
    final String subtitle = '$artistText · $albumText';
    final List<_ConfigChipData> configChips = _buildConfigChips(context, item);
    final List<Widget> trailingChips = <Widget>[
      if (durationText.isNotEmpty)
        Tooltip(
          message: durationText,
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: const Icon(Icons.schedule_outlined, size: 16),
            label: Text(durationText),
          ),
        ),
      ...configChips.map(
        (_ConfigChipData chip) => Tooltip(
          message: chip.tooltip,
          child: Chip(
            visualDensity: VisualDensity.compact,
            avatar: Icon(chip.icon, size: 16),
            label: Text(chip.label),
          ),
        ),
      ),
    ];
    return Card(
      color: selected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Checkbox(value: selected, onChanged: onSelectedChanged),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Tooltip(
                          message: title,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                      if (trailingChips.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 2,
                          child: SizedBox(
                            height: 40,
                            // 配置项保持单行并允许横向浏览，避免数量或窗口宽度
                            // 改变卡片高度，从而维持虚拟列表稳定且紧凑的行高。
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  for (
                                    int index = 0;
                                    index < trailingChips.length;
                                    index += 1
                                  ) ...<Widget>[
                                    if (index > 0) const SizedBox(width: 6),
                                    trailingChips[index],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Tooltip(
                    message: subtitle,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PathSummaryLine(
                    label: l10n.libraryLinkManagerSongPathLabel,
                    fullPath: item.song.path,
                    emptyText: l10n.libraryLinkManagerSongPathEmpty,
                  ),
                  const SizedBox(height: 4),
                  _PathSummaryLine(
                    label: l10n.libraryLinkManagerLyricsPathLabel,
                    fullPath: item.lyricsPath,
                    emptyText: l10n.libraryLinkManagerLyricsPathEmpty,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分页窗口尚未加载完成时的占位卡片。
///
/// 真实行按内容自然高度展示；占位卡片只保持同类视觉密度，不再强行固定高度，
/// 避免英文、大字号或配置 chip 较多时被列表裁切。
class LibraryLinkPlaceholderCard extends StatelessWidget {
  const LibraryLinkPlaceholderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SkeletonBar(
                      width: 180,
                      color: colorScheme.surfaceContainer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SkeletonPill(
                    width: 96,
                    color: colorScheme.surfaceContainerHigh,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SkeletonBar(width: 240, color: colorScheme.surfaceContainer),
              const SizedBox(height: 10),
              _SkeletonBar(
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 8),
              _SkeletonBar(
                width: double.infinity,
                color: colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathSummaryLine extends StatelessWidget {
  const _PathSummaryLine({
    required this.label,
    required this.fullPath,
    required this.emptyText,
  });

  final String label;
  final String? fullPath;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(width: 8),
        Expanded(
          child: AdaptivePathText(
            fullPath: fullPath,
            emptyText: emptyText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SkeletonPill extends StatelessWidget {
  const _SkeletonPill({this.width = 72, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ConfigChipData {
  const _ConfigChipData({
    required this.icon,
    required this.label,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final String tooltip;
}

List<_ConfigChipData> _buildConfigChips(
  BuildContext context,
  LibraryLinkItem item,
) {
  final l10n = context.l10n;
  final Map<String, Object?> config = item.configSnapshot;
  final List<_ConfigChipData> chips = <_ConfigChipData>[
    _ConfigChipData(
      icon: Icons.queue_music_outlined,
      label: l10n.libraryLinkManagerTrackLabel(
        _trackNumberLabel(context, item.song.id),
      ),
      tooltip: l10n.libraryLinkManagerTrackTooltip(
        _trackNumberLabel(context, item.song.id),
      ),
    ),
  ];
  int recognizedCount = 0;
  if (config case <String, Object?>{'offset': final Object? rawOffset}) {
    final int? offset = DynamicReader.asInt(rawOffset);
    if (offset != null) {
      final String offsetText = '${offset >= 0 ? '+' : ''}${offset}ms';
      recognizedCount += 1;
      chips.add(
        _ConfigChipData(
          icon: Icons.tune_outlined,
          label: l10n.libraryLinkManagerOffsetLabel(offsetText),
          tooltip: l10n.libraryLinkManagerOffsetTooltip(offsetText),
        ),
      );
    }
  }
  if (config case <String, Object?>{'langs': final Object? rawLangs}) {
    final List<String> langs = DynamicReader.asStringList(rawLangs);
    if (langs.isNotEmpty) {
      recognizedCount += 1;
      final String display = langs
          .map((String value) => _langLabel(context, value))
          .join('/');
      chips.add(
        _ConfigChipData(
          icon: Icons.translate_outlined,
          label: l10n.libraryLinkManagerLanguagesLabel(display),
          tooltip: l10n.libraryLinkManagerLanguagesTooltip(display),
        ),
      );
    }
  }
  if (config['inst'] == true) {
    recognizedCount += 1;
    chips.add(
      _ConfigChipData(
        icon: Icons.music_off_outlined,
        label: l10n.libraryLinkManagerInstrumental,
        tooltip: l10n.libraryLinkManagerInstrumentalTooltip,
      ),
    );
  }
  if (config['disable_auto_search'] == true) {
    recognizedCount += 1;
    chips.add(
      _ConfigChipData(
        icon: Icons.block_outlined,
        label: l10n.libraryLinkManagerDisableAutoSearch,
        tooltip: l10n.libraryLinkManagerDisableAutoSearchTooltip,
      ),
    );
  }
  final List<MapEntry<String, Object?>> unknownEntries = config.entries
      .where(
        (MapEntry<String, Object?> entry) => !const <String>{
          'offset',
          'langs',
          'inst',
          'disable_auto_search',
        }.contains(entry.key),
      )
      .toList(growable: false);
  if (unknownEntries.isNotEmpty) {
    chips.add(
      _ConfigChipData(
        icon: Icons.more_horiz_outlined,
        label: l10n.libraryLinkManagerOtherConfig(unknownEntries.length),
        tooltip: unknownEntries
            .map(
              (MapEntry<String, Object?> entry) =>
                  '${entry.key}=${_stringifyValue(entry.value)}',
            )
            .join('\n'),
      ),
    );
  }
  if (recognizedCount == 0 && unknownEntries.isEmpty) {
    chips.add(
      _ConfigChipData(
        icon: Icons.settings_suggest_outlined,
        label: l10n.libraryLinkManagerDefaultConfig,
        tooltip: l10n.libraryLinkManagerDefaultConfigTooltip,
      ),
    );
  }
  return chips;
}

String _trackNumberLabel(BuildContext context, String? trackNumber) {
  final String normalized = (trackNumber ?? '').trim();
  return normalized.isEmpty
      ? context.l10n.libraryLinkManagerTrackEmpty
      : normalized;
}

String _langLabel(BuildContext context, String value) {
  return switch (value) {
    'orig' => context.l10n.lyricOriginal,
    'ts' => context.l10n.lyricTranslation,
    'roma' => context.l10n.lyricRomanized,
    _ => value,
  };
}

String _stringifyValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  if (value is List || value is Map) {
    return jsonEncode(value);
  }
  return value.toString();
}
