import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc/src/platform/drag_drop/drag_drop_port.dart';
import 'package:lddc/src/shared/ui/drag_drop/desktop_drop_region_scaffold.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  test('拖拽失败码由 UI 层映射为安全本地化文案', () {
    final AppLocalizations zh = lookupAppLocalizations(const Locale('zh'));
    final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

    expect(
      dragDropFailureMessage(
        zh,
        DragDropFailure.unsupportedItem,
        unsupportedItemMessage: zh.searchDropUnsupportedItem,
      ),
      zh.searchDropUnsupportedItem,
    );
    expect(
      dragDropFailureMessage(
        zh,
        DragDropFailure.unreadablePrivateMime,
        unsupportedItemMessage: zh.searchDropUnsupportedItem,
      ),
      zh.appErrorDragDropInvalid,
    );
    expect(
      dragDropFailureMessage(
        en,
        DragDropFailure.unreadablePrivateMime,
        unsupportedItemMessage: en.openLyricsDropUnsupportedItem,
      ),
      en.appErrorDragDropInvalid,
    );
  });

  testWidgets('私有格式损坏由共享壳显示安全文案且不调用页面处理器', (WidgetTester tester) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort(
      DragDropParseResult(
        items: const <DragDropItemDescriptor>[],
        platformFormats: const <String>{kAimpDropFormat},
        failure: DragDropFailure.unreadablePrivateMime,
      ),
    );
    addTearDown(port.dispose);
    bool handled = false;

    await tester.pumpWidget(
      _buildApp(
        port: port,
        onDrop: (_) async {
          handled = true;
          return true;
        },
      ),
    );
    port.drop();
    await tester.pump();

    expect(handled, isFalse);
    expect(find.text('拖拽数据无效。'), findsOneWidget);
  });

  testWidgets('页面拒绝已解析条目时显示页面自己的支持范围提示', (WidgetTester tester) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort(
      DragDropParseResult(
        items: <DragDropItemDescriptor>[
          DragDropItemDescriptor.file(r'C:\music\song.flac'),
        ],
        platformFormats: const <String>{'CF_HDROP'},
      ),
    );
    addTearDown(port.dispose);

    await tester.pumpWidget(_buildApp(port: port, onDrop: (_) async => false));
    port.drop();
    await tester.pump();

    expect(find.text('当前页面不接受此条目'), findsOneWidget);
  });

  testWidgets('页面处理器抛出异步异常时由共享壳统一转换提示', (WidgetTester tester) async {
    final _FakeDesktopDragDropPort port = _FakeDesktopDragDropPort(
      DragDropParseResult(
        items: <DragDropItemDescriptor>[
          DragDropItemDescriptor.file(r'C:\music\song.flac'),
        ],
        platformFormats: const <String>{'CF_HDROP'},
      ),
    );
    addTearDown(port.dispose);

    await tester.pumpWidget(
      _buildApp(
        port: port,
        onDrop: (_) async => throw const FormatException('底层细节'),
      ),
    );
    port.drop();
    await tester.pump();

    expect(find.text('拖拽处理失败'), findsOneWidget);
    expect(find.textContaining('底层细节'), findsNothing);
  });
}

Widget _buildApp({
  required _FakeDesktopDragDropPort port,
  required DesktopDropHandler onDrop,
}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 100,
          height: 100,
          child: DesktopDropRegionScaffold(
            dragDropPort: port,
            semanticsIdentifier: 'lddc.test.drop_region',
            onDrop: onDrop,
            unsupportedItemMessage: '当前页面不接受此条目',
            errorMessageBuilder: (_, _) => '拖拽处理失败',
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

final class _FakeDesktopDragDropPort implements DesktopDragDropPort {
  _FakeDesktopDragDropPort(this.result);

  final DragDropParseResult result;
  final StreamController<DesktopDragDropEvent> _controller =
      StreamController<DesktopDragDropEvent>.broadcast(sync: true);

  @override
  bool get isSupported => true;

  @override
  Stream<DesktopDragDropEvent> get events => _controller.stream;

  void drop() {
    _controller.add(
      DesktopDragDropEvent(
        phase: DesktopDragDropEventPhase.drop,
        payload: const DesktopDragDropPayload(
          platform: 'windows',
          x: 20,
          y: 20,
          coordinateSpace: 'logical',
          formats: <String>{'CF_HDROP'},
          files: <String>[],
          privateData: <String, Uint8List>{},
        ),
      ),
    );
  }

  Future<void> dispose() => _controller.close();

  @override
  DragDropParseResult parsePayload(DesktopDragDropPayload payload) => result;
}
