import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart'
    show
        DesktopDragDropEvent,
        DesktopDragDropEventPhase,
        DesktopDragDropPayload,
        DesktopDragDropPort,
        DesktopDropSurface,
        DragDropItemDescriptor,
        DragDropParseResult;

void main() {
  testWidgets('drag update 命中 surface 后显示 overlay，leave 后隐藏', (
    WidgetTester tester,
  ) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort();

    await tester.pumpWidget(_buildSurface(port: port));

    port.add(_event(DesktopDragDropEventPhase.update, x: 20, y: 20));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('drop-overlay')), findsOneWidget);

    port.add(_event(DesktopDragDropEventPhase.leave, x: 0, y: 0));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('drop-overlay')), findsNothing);

    await port.dispose();
  });

  testWidgets('drop 到 surface 外部时不会触发 onDrop', (WidgetTester tester) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort();
    int dropCount = 0;

    await tester.pumpWidget(
      _buildSurface(
        port: port,
        onDrop: (_) async {
          dropCount += 1;
        },
      ),
    );

    port.add(_event(DesktopDragDropEventPhase.drop, x: 180, y: 180));
    await tester.pump();

    expect(dropCount, 0);
    expect(port.parseCount, 0);

    await port.dispose();
  });

  testWidgets('drop 命中 surface 时只解析一次并交付最终条目', (WidgetTester tester) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort();
    DragDropParseResult? delivered;

    await tester.pumpWidget(
      _buildSurface(
        port: port,
        onDrop: (DragDropParseResult result) async {
          delivered = result;
        },
      ),
    );
    port.add(_event(DesktopDragDropEventPhase.enter, x: 20, y: 20));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('drop-overlay')), findsOneWidget);

    port.add(_event(DesktopDragDropEventPhase.drop, x: 20, y: 20));
    await tester.pump();

    expect(port.parseCount, 1);
    expect(delivered?.items.single.path, r'C:\music\song.flac');
    expect(find.byKey(const ValueKey<String>('drop-overlay')), findsNothing);
    await port.dispose();
  });

  testWidgets('IndexedStack 中未显示的 surface 不响应拖放事件', (
    WidgetTester tester,
  ) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort();
    int dropCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          index: 0,
          children: <Widget>[
            const SizedBox(width: 100, height: 100, child: Text('active')),
            DesktopDropSurface(
              dragDropPort: port,
              onDrop: (_) async {
                dropCount += 1;
              },
              overlayBuilder: (_, _) => const ColoredBox(
                key: ValueKey<String>('drop-overlay'),
                color: Colors.blue,
              ),
              child: const SizedBox(width: 100, height: 100),
            ),
          ],
        ),
      ),
    );

    port.add(_event(DesktopDragDropEventPhase.update, x: 20, y: 20));
    await tester.pump();
    port.add(_event(DesktopDragDropEventPhase.drop, x: 20, y: 20));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('drop-overlay')), findsNothing);
    expect(dropCount, 0);
    expect(port.parseCount, 0);

    await port.dispose();
  });
}

Widget _buildSurface({
  required _FakeDesktopDragDropPort port,
  Future<void> Function(DragDropParseResult result)? onDrop,
}) {
  return MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 100,
        height: 100,
        child: DesktopDropSurface(
          dragDropPort: port,
          onDrop: onDrop ?? (_) async {},
          overlayBuilder: (_, _) => const ColoredBox(
            key: ValueKey<String>('drop-overlay'),
            color: Colors.blue,
          ),
          child: const ColoredBox(color: Colors.white),
        ),
      ),
    ),
  );
}

DesktopDragDropEvent _event(
  DesktopDragDropEventPhase phase, {
  required double x,
  required double y,
}) {
  return DesktopDragDropEvent(
    phase: phase,
    payload: DesktopDragDropPayload(
      platform: 'windows',
      x: x,
      y: y,
      coordinateSpace: 'logical',
      formats: const <String>{'CF_HDROP'},
      files: const <String>[r'C:\music\song.flac'],
      privateData: const <String, Uint8List>{},
    ),
  );
}

final class _FakeDesktopDragDropPort implements DesktopDragDropPort {
  final StreamController<DesktopDragDropEvent> _controller =
      StreamController<DesktopDragDropEvent>.broadcast(sync: true);

  int parseCount = 0;

  @override
  bool get isSupported => true;

  @override
  Stream<DesktopDragDropEvent> get events => _controller.stream;

  void add(DesktopDragDropEvent event) {
    _controller.add(event);
  }

  Future<void> dispose() {
    return _controller.close();
  }

  @override
  DragDropParseResult parsePayload(DesktopDragDropPayload payload) {
    parseCount += 1;
    return DragDropParseResult(
      items: <DragDropItemDescriptor>[
        DragDropItemDescriptor.file(payload.files.single),
      ],
      platformFormats: payload.formats,
    );
  }
}
