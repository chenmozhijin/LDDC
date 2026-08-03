import 'package:flutter/material.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/i18n/l10n/app_localizations.dart';

typedef DesktopDropHandler = Future<bool> Function(DragDropParseResult result);
typedef DesktopDropErrorMessageBuilder =
    String Function(BuildContext context, Object error);

/// 将拖拽错误码转换为安全的本地化文案。
///
/// “条目类型不受支持”需要结合页面能力描述，因此由页面传入；播放器私有格式损坏
/// 则统一显示通用错误，不把 AIMP/foobar2000 的底层解析异常直接展示给用户。
String dragDropFailureMessage(
  AppLocalizations l10n,
  DragDropFailure? failure, {
  required String unsupportedItemMessage,
}) {
  return switch (failure) {
    null || DragDropFailure.unsupportedItem => unsupportedItemMessage,
    DragDropFailure.unreadablePrivateMime => l10n.appErrorDragDropInvalid,
  };
}

/// 桌面拖放区域的共享 UI 壳。
///
/// 四个业务页只关心“drop 后如何消费结果”。hover 遮罩、错误本地化、
/// mounted/generation 保护和失败 SnackBar 集中在这里，避免每个页面复制生命周期代码。
class DesktopDropRegionScaffold extends StatefulWidget {
  const DesktopDropRegionScaffold({
    super.key,
    required this.dragDropPort,
    required this.semanticsIdentifier,
    required this.onDrop,
    required this.unsupportedItemMessage,
    required this.errorMessageBuilder,
    required this.child,
  });

  final DragDropPort dragDropPort;
  final String semanticsIdentifier;
  final DesktopDropHandler onDrop;
  final String unsupportedItemMessage;
  final DesktopDropErrorMessageBuilder errorMessageBuilder;
  final Widget child;

  @override
  State<DesktopDropRegionScaffold> createState() =>
      _DesktopDropRegionScaffoldState();
}

class _DesktopDropRegionScaffoldState extends State<DesktopDropRegionScaffold> {
  int _dropGeneration = 0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: widget.semanticsIdentifier,
      container: true,
      explicitChildNodes: true,
      child: DesktopDropSurface(
        dragDropPort: widget.dragDropPort,
        onDrop: _handleDrop,
        overlayBuilder: _buildOverlay,
        child: widget.child,
      ),
    );
  }

  Future<void> _handleDrop(DragDropParseResult result) async {
    final int generation = ++_dropGeneration;
    if (!result.hasItems) {
      _showSnackBar(
        dragDropFailureMessage(
          context.l10n,
          result.failure,
          unsupportedItemMessage: widget.unsupportedItemMessage,
        ),
        generation,
      );
      return;
    }
    try {
      final bool handled = await widget.onDrop(result);
      if (!handled) {
        _showSnackBar(widget.unsupportedItemMessage, generation);
      }
    } catch (error) {
      if (!mounted || generation != _dropGeneration) {
        return;
      }
      _showSnackBar(widget.errorMessageBuilder(context, error), generation);
    }
  }

  Widget _buildOverlay(BuildContext context, bool isDragging) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.08),
          border: Border.all(color: colorScheme.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  void _showSnackBar(String message, int generation) {
    if (!mounted || generation != _dropGeneration) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }
}
