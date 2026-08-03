import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';

class SettingsSectionBlock extends StatelessWidget {
  const SettingsSectionBlock({
    super.key,
    required this.title,
    this.summary,
    this.showHeader = true,
    this.headerAction,
    required this.cards,
  });

  final String title;
  final String? summary;
  final bool showHeader;
  final Widget? headerAction;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (showHeader) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?headerAction,
            ],
          ),
          if (summary case final String text) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
        for (int index = 0; index < cards.length; index += 1) ...<Widget>[
          cards[index],
          if (index != cards.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class SettingsCompactSectionEntry extends StatelessWidget {
  const SettingsCompactSectionEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class SettingsCompactSectionHeader extends StatelessWidget {
  const SettingsCompactSectionHeader({
    super.key,
    required this.title,
    this.summary,
    required this.onBack,
    this.action,
  });

  final String title;
  final String? summary;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        IconButton(
          key: const ValueKey<String>('settings_compact_back'),
          tooltip: context.l10n.settingsBackToSections,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (summary case final String text) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class SettingsSubsectionHeader extends StatelessWidget {
  const SettingsSubsectionHeader({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        if (description case final String text) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class SettingsPlaceholderHintCard extends StatelessWidget {
  const SettingsPlaceholderHintCard({super.key, required this.template});

  final String template;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.settingsAvailablePlaceholders,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(context.l10n.settingsPlaceholderTitleArtist),
          Text(context.l10n.settingsPlaceholderAlbumId),
          Text(context.l10n.settingsPlaceholderLangs),
          const SizedBox(height: 8),
          Text(context.l10n.settingsCurrentTemplate(template)),
        ],
      ),
    );
  }
}

class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onSubmitted,
    this.helperText,
    this.obscureText = false,
  });

  final String label;
  final String initialValue;
  final String? helperText;
  final bool obscureText;
  final ValueChanged<String> onSubmitted;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _lastExternalValue = '';
  String _lastSubmittedValue = '';

  @override
  void initState() {
    super.initState();
    _lastExternalValue = widget.initialValue;
    _lastSubmittedValue = widget.initialValue;
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(SettingsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue == _lastExternalValue) {
      return;
    }
    _lastExternalValue = widget.initialValue;
    if (_focusNode.hasFocus) {
      return;
    }
    // 外部配置刷新时只在未编辑状态同步文本，避免用户输入过程中的 rebuild
    // 把 composing、光标位置或尚未提交的内容覆盖掉。
    _controller.text = widget.initialValue;
    _lastSubmittedValue = widget.initialValue;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _submitIfChanged();
    }
  }

  void _submitIfChanged() {
    final String value = _controller.text;
    if (value == _lastSubmittedValue) {
      return;
    }
    _lastSubmittedValue = value;
    widget.onSubmitted(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.key ?? ValueKey<String>('settings_text_${widget.label}'),
      controller: _controller,
      focusNode: _focusNode,
      obscureText: widget.obscureText,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
      ),
      onFieldSubmitted: (_) => _submitIfChanged(),
    );
  }
}

class SettingsSliderField extends StatefulWidget {
  const SettingsSliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  State<SettingsSliderField> createState() => _SettingsSliderFieldState();
}

class _SettingsSliderFieldState extends State<SettingsSliderField> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(SettingsSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
            Text(_formatValue(), style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: _value.clamp(widget.min, widget.max),
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: _formatValue(),
          onChanged: (double value) {
            setState(() {
              _value = value;
            });
          },
          onChangeEnd: widget.onChanged,
        ),
      ],
    );
  }

  String _formatValue() {
    if (widget.valueLabel.contains('px')) {
      return '${_value.toStringAsFixed(0)} px';
    }
    return widget.valueLabel;
  }
}
