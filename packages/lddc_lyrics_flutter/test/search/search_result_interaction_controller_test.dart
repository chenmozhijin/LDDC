import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

void main() {
  test('桌面单击同一行立即打开且连续点击复用同一个 Future', () async {
    final SearchResultInteractionController controller =
        SearchResultInteractionController();
    addTearDown(controller.dispose);
    final List<int> openedRows = <int>[];
    final Completer<void> completer = Completer<void>();
    final Future<void> first = controller.handleRowTap(
      2,
      openRow: (int rowIndex) {
        openedRows.add(rowIndex);
        return completer.future;
      },
    );
    final Future<void> second = controller.handleRowTap(
      2,
      openRow: (int rowIndex) async {
        openedRows.add(rowIndex);
      },
    );

    completer.complete();
    await Future.wait<void>(<Future<void>>[first, second]);
    expect(controller.selectedRowIndex, 2);
    expect(openedRows, <int>[2]);
  });

  testWidgets('结果行变短时延后一帧清理越界选中项', (WidgetTester tester) async {
    final SearchResultInteractionController controller =
        SearchResultInteractionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(const SizedBox.shrink());

    controller.selectRow(4);
    controller.clearSelectionIfOutOfRange(2, isMounted: () => true);

    // 清理发生在下一帧，避免列表子树 build 过程中同步通知监听器。
    expect(controller.selectedRowIndex, 4);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(controller.selectedRowIndex, isNull);
  });
}
