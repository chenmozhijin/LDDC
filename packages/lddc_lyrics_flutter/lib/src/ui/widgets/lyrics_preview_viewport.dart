import 'package:flutter/material.dart';

/// 歌词预览文本视口：保留原始换行，不自动折行，并显示横纵滚动条。
final class LyricsPreviewViewport extends StatefulWidget {
  const LyricsPreviewViewport({super.key, required this.text});

  final String text;

  @override
  State<LyricsPreviewViewport> createState() => _LyricsPreviewViewportState();
}

class _LyricsPreviewViewportState extends State<LyricsPreviewViewport> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          notificationPredicate: (ScrollNotification notification) {
            return notification.metrics.axis == Axis.vertical;
          },
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (ScrollNotification notification) {
              return notification.metrics.axis == Axis.horizontal;
            },
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 0,
                  minHeight: constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : 0,
                ),
                child: SingleChildScrollView(
                  controller: _verticalController,
                  child: SelectableText(widget.text),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
