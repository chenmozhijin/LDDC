import 'package:flutter/material.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';

import '../../../../core/i18n/i18n.dart';

class DesktopColorSettings extends StatelessWidget {
  const DesktopColorSettings({
    super.key,
    required this.playedColors,
    required this.unplayedColors,
    required this.onPlayedColorsChanged,
    required this.onUnplayedColorsChanged,
  });

  final List<RgbColor> playedColors;
  final List<RgbColor> unplayedColors;
  final ValueChanged<List<List<int>>> onPlayedColorsChanged;
  final ValueChanged<List<List<int>>> onUnplayedColorsChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.l10n.settingsDesktopGradientColors,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        _ColorListEditor(
          title: context.l10n.settingsDesktopPlayedColors,
          colors: playedColors,
          addKey: const ValueKey<String>('settings_desktop_add_played_color'),
          onChanged: onPlayedColorsChanged,
        ),
        const SizedBox(height: 16),
        _ColorListEditor(
          title: context.l10n.settingsDesktopUnplayedColors,
          colors: unplayedColors,
          addKey: const ValueKey<String>('settings_desktop_add_unplayed_color'),
          onChanged: onUnplayedColorsChanged,
        ),
      ],
    );
  }
}

class _ColorListEditor extends StatelessWidget {
  const _ColorListEditor({
    required this.title,
    required this.colors,
    required this.addKey,
    required this.onChanged,
  });

  final String title;
  final List<RgbColor> colors;
  final Key addKey;
  final ValueChanged<List<List<int>>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            FilledButton.tonalIcon(
              key: addKey,
              onPressed: () => _editColor(
                context,
                initialColor: const RgbColor(255, 255, 255),
                onConfirmed: (RgbColor color) {
                  final List<List<int>> updated = colors
                      .map((RgbColor item) => item.toTuple())
                      .toList(growable: true);
                  updated.add(color.toTuple());
                  onChanged(updated);
                },
              ),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.settingsAddColor),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int index = 0; index < colors.length; index += 1) ...<Widget>[
          _ColorRow(
            key: ValueKey<String>('${title}_$index'),
            title: '$title ${index + 1}',
            color: colors[index],
            onEdit: () => _editColor(
              context,
              initialColor: colors[index],
              onConfirmed: (RgbColor color) {
                final List<List<int>> updated = colors
                    .map((RgbColor item) => item.toTuple())
                    .toList(growable: true);
                updated[index] = color.toTuple();
                onChanged(updated);
              },
            ),
            onDelete: colors.length <= 1
                ? null
                : () {
                    final List<List<int>> updated = colors
                        .map((RgbColor item) => item.toTuple())
                        .toList(growable: true);
                    updated.removeAt(index);
                    onChanged(updated);
                  },
          ),
          if (index != colors.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _editColor(
    BuildContext context, {
    required RgbColor initialColor,
    required ValueChanged<RgbColor> onConfirmed,
  }) async {
    final RgbColor? color = await showDialog<RgbColor>(
      context: context,
      builder: (BuildContext context) =>
          _ColorEditorDialog(initialColor: initialColor),
    );
    if (color != null) {
      onConfirmed(color);
    }
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    super.key,
    required this.title,
    required this.color,
    required this.onEdit,
    this.onDelete,
  });

  final String title;
  final RgbColor color;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final Color preview = Color.fromARGB(255, color.r, color.g, color.b);
    final String hex =
        '#'
                '${color.r.toRadixString(16).padLeft(2, '0')}'
                '${color.g.toRadixString(16).padLeft(2, '0')}'
                '${color.b.toRadixString(16).padLeft(2, '0')}'
            .toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: preview,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '$hex  (${color.r}, ${color.g}, ${color.b})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: <Widget>[
                    IconButton(
                      tooltip: context.l10n.settingsEditColor,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: context.l10n.settingsDeleteColor,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorEditorDialog extends StatefulWidget {
  const _ColorEditorDialog({required this.initialColor});

  final RgbColor initialColor;

  @override
  State<_ColorEditorDialog> createState() => _ColorEditorDialogState();
}

class _ColorEditorDialogState extends State<_ColorEditorDialog> {
  late double _r = widget.initialColor.r.toDouble();
  late double _g = widget.initialColor.g.toDouble();
  late double _b = widget.initialColor.b.toDouble();

  @override
  Widget build(BuildContext context) {
    final Color preview = Color.fromARGB(
      255,
      _r.round(),
      _g.round(),
      _b.round(),
    );
    return AlertDialog(
      title: Text(context.l10n.settingsEditColor),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
            ),
            const SizedBox(height: 16),
            _ColorChannelSlider(
              label: 'R',
              value: _r,
              activeColor: Colors.red,
              onChanged: (double value) => setState(() => _r = value),
            ),
            _ColorChannelSlider(
              label: 'G',
              value: _g,
              activeColor: Colors.green,
              onChanged: (double value) => setState(() => _g = value),
            ),
            _ColorChannelSlider(
              label: 'B',
              value: _b,
              activeColor: Colors.blue,
              onChanged: (double value) => setState(() => _b = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(RgbColor(_r.round(), _g.round(), _b.round())),
          child: Text(context.l10n.commonConfirm),
        ),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final double value;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            Text(value.round().toString()),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(
            context,
          ).copyWith(activeTrackColor: activeColor, thumbColor: activeColor),
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
