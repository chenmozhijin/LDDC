import 'dart:async';

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

  testWidgets('SearchDriver 等待弹层关闭后的输入控制器最终收敛', (WidgetTester tester) async {
    final GlobalKey<_DelayedSearchControllerProbeState> probeKey =
        GlobalKey<_DelayedSearchControllerProbeState>();
    await tester.pumpWidget(
      MaterialApp(home: _DelayedSearchControllerProbe(key: probeKey)),
    );

    await SearchDriver(tester).enterKeyword('song-id-42');

    expect(probeKey.currentState!.controller.text, 'song-id-42');
    expect(probeKey.currentState!.staleWriteExecuted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('持续 SnackBar 不阻塞未被遮挡的本地匹配操作', (WidgetTester tester) async {
    final GlobalKey<ScaffoldMessengerState> messengerKey =
        GlobalKey<ScaffoldMessengerState>();
    bool skipExisting = false;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: CheckboxListTile(
                  key: const ValueKey<String>(
                    'local_match_skip_existing_checkbox',
                  ),
                  value: skipExisting,
                  onChanged: (bool? value) {
                    setState(() => skipExisting = value ?? false);
                  },
                  title: const Text('跳过已有歌词'),
                ),
              ),
            );
          },
        ),
      ),
    );
    messengerKey.currentState!.showSnackBar(
      const SnackBar(duration: Duration(days: 1), content: Text('持续状态提示')),
    );
    await tester.pump();

    await LocalMatchDriver(tester).toggleSkipExisting();

    expect(skipExisting, isTrue);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapVisible 拒绝点击被真实遮罩层覆盖的控件', (WidgetTester tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: FilledButton(
                key: const ValueKey<String>('covered_target'),
                onPressed: () => tapped = true,
                child: const Text('Target'),
              ),
            ),
            const ModalBarrier(dismissible: false, color: Colors.black26),
          ],
        ),
      ),
    );

    await expectLater(
      tapVisible(
        tester,
        find.byKey(const ValueKey<String>('covered_target')),
        timeout: const Duration(milliseconds: 200),
        reason: '等待被遮挡的目标可点击',
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(tapped, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapVisible 拒绝静默选择重复匹配的目标', (WidgetTester tester) async {
    int tappedCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            for (int index = 0; index < 2; index += 1)
              FilledButton(
                key: ValueKey<String>('duplicate_target_$index'),
                onPressed: () => tappedCount += 1,
                child: Text('Target $index'),
              ),
          ],
        ),
      ),
    );

    Object? failure;
    try {
      await tapVisible(
        tester,
        find.byType(FilledButton),
        timeout: const Duration(milliseconds: 200),
        reason: '等待唯一目标可点击',
      );
    } on Object catch (error) {
      failure = error;
    }

    expect(failure, isA<TimeoutException>());
    expect(tappedCount, 0);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedSearchControllerProbe extends StatefulWidget {
  const _DelayedSearchControllerProbe({super.key});

  @override
  State<_DelayedSearchControllerProbe> createState() =>
      _DelayedSearchControllerProbeState();
}

class _DelayedSearchControllerProbeState
    extends State<_DelayedSearchControllerProbe> {
  final TextEditingController controller = TextEditingController(
    text: 'previous-keyword',
  );
  bool staleWriteExecuted = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SearchBar(
        key: const ValueKey<String>('search_toolbar_search_bar'),
        controller: controller,
        onChanged: (String value) {
          // 模拟紧凑布局关闭预览弹层时已排队的旧状态回写：
          // 第一个 post-frame 先短暂恢复旧值，下一帧再由最新业务状态
          // 重建为用户输入。测试驱动必须等待第二步，不能把瞬时旧值
          // 误判为业务失败。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            staleWriteExecuted = true;
            controller.text = 'previous-keyword';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                controller.text = value;
              }
            });
          });
        },
      ),
    );
  }
}
