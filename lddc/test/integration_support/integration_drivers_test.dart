import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/integration_drivers.dart';
import '../../integration_test/support/integration_harness.dart';

void main() {
  testWidgets('SearchDriver 通过系统返回关闭 Material 预览底部弹层', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              body: FilledButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (BuildContext context) {
                      return const SizedBox(
                        height: 240,
                        child: FilledButton(
                          key: ValueKey<String>(
                            'search_preview_save_tag_button',
                          ),
                          onPressed: null,
                          child: Text('Save'),
                        ),
                      );
                    },
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);

    await SearchDriver(tester).dismissPreviewSheetIfOpen();

    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapVisible 能把横向操作条右侧按钮滚动到可点击区域', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 180,
            height: 64,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 420),
                  FilledButton(
                    key: const ValueKey<String>('horizontal_target'),
                    onPressed: () => tapped = true,
                    child: const Text('Target'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tapVisible(
      tester,
      find.byKey(const ValueKey<String>('horizontal_target')),
      reason: '等待横向操作按钮可点击',
    );

    expect(tapped, isTrue);
    expect(
      find.byKey(const ValueKey<String>('horizontal_target')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
