import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:lddc/src/shared/ui/components/components.dart';

void main() {
  testWidgets('DesktopPageInteractionScope 通过标准快捷键组件触发回调', (
    WidgetTester tester,
  ) async {
    int invokeCount = 0;
    final TextEditingController controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DesktopPageInteractionScope(
            shortcuts: <ShortcutActivator, VoidCallback>{
              const SingleActivator(
                LogicalKeyboardKey.keyS,
                control: true,
              ): () {
                invokeCount += 1;
              },
            },
            // 真实页面包含 EditableText；它的内层文本快捷键曾经先吞掉 Ctrl+O，
            // 因此基线必须在文本框持有 primary focus 时验证页面命令优先级。
            child: TextField(controller: controller, autofocus: true),
          ),
        ),
      ),
    );
    // autofocus 会在后续帧把焦点交给快捷键作用域；等待焦点树稳定后再发送按键，
    // 测试验证的是用户可见的键盘行为，而不是构造阶段的时序细节。
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(invokeCount, 1);
    expect(controller.text, isEmpty);
  });

  testWidgets('DesktopPageInteractionScope 只响应 IndexedStack 当前可见页面', (
    WidgetTester tester,
  ) async {
    int visibleCount = 0;
    int hiddenCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IndexedStack(
            index: 0,
            children: <Widget>[
              DesktopPageInteractionScope(
                shortcuts: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () {
                    visibleCount += 1;
                  },
                },
                child: const Text('Visible'),
              ),
              DesktopPageInteractionScope(
                shortcuts: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(
                    LogicalKeyboardKey.keyS,
                    control: true,
                  ): () {
                    hiddenCount += 1;
                  },
                },
                child: const Text('Hidden'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(visibleCount, 1);
    expect(hiddenCount, 0);
  });

  testWidgets('LyricsFormatDropdown 在固定外层 key 下同步外部格式变化', (
    WidgetTester tester,
  ) async {
    LyricsFormat format = LyricsFormat.lineByLineLrc;
    late StateSetter update;
    await tester.pumpWidget(
      _localizedScaffold(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            update = setState;
            return LyricsFormatDropdown(
              key: const ValueKey<String>('stable_format_control'),
              value: format,
              strings: LyricsUiStrings.zhHans(),
              onChanged: (_) {},
            );
          },
        ),
      ),
    );

    FormFieldState<LyricsFormat> fieldState = tester.state(
      find.byType(DropdownButtonFormField<LyricsFormat>),
    );
    expect(fieldState.value, LyricsFormat.lineByLineLrc);

    update(() {
      format = LyricsFormat.srt;
    });
    await tester.pump();

    fieldState = tester.state(
      find.byType(DropdownButtonFormField<LyricsFormat>),
    );
    expect(fieldState.value, LyricsFormat.srt);
  });

  testWidgets('LyricsOffsetStepper 忽略横向滚动并保留纵向步进语义', (
    WidgetTester tester,
  ) async {
    int offsetMs = 0;
    await tester.pumpWidget(
      _localizedScaffold(
        LyricsOffsetStepper(
          offsetMs: offsetMs,
          strings: LyricsUiStrings.zhHans(),
          onChanged: (int value) {
            offsetMs = value;
          },
        ),
      ),
    );
    final Offset position = tester.getCenter(find.text('0'));

    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(20, 0)),
    );
    await tester.pump();
    expect(offsetMs, 0);

    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(0, -20)),
    );
    await tester.pump();
    expect(offsetMs, 100);
  });

  testWidgets('LyricsPreviewViewport 放在无界父布局中不产生无限约束异常', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LyricsPreviewViewport(text: '第一行\n第二行'),
          ),
        ),
      ),
    );

    expect(find.textContaining('第一行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AdaptivePathText 裁剪 emoji 路径时不拆坏 grapheme', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            child: AdaptivePathText(
              fullPath: r'C:\音乐\👩‍💻组合\歌曲文件名很长.lrc',
              emptyText: '无路径',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AdaptivePathText), findsOneWidget);
  });

  testWidgets('ProgressPanel 渲染进度信息', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProgressPanel(
            title: 'Progress',
            currentValue: 2,
            maxValue: 5,
            statusText: 'Running',
          ),
        ),
      ),
    );

    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('2 / 5'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('EmptyState 与 ErrorState 渲染文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              const EmptyState(message: 'No data'),
              ErrorState(message: 'Oops', retryLabel: 'Retry', onRetry: () {}),
            ],
          ),
        ),
      ),
    );

    expect(find.text('No data'), findsOneWidget);
    expect(find.text('Oops'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('TonalInlineNotice 在窄屏大字号下完整换行', (WidgetTester tester) async {
    const String message = '保存到歌曲目录时会沿用当前文件结构并保留已有歌词文件';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const SizedBox(
              width: 180,
              child: TonalInlineNotice(icon: Icons.info_outline, text: message),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.text(message)).height, greaterThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('任务状态共享组件渲染进度、统计、路径和提示', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TaskProgressStatusCard(
                title: '正在处理',
                detail: '2 / 5 · Running',
                progress: 0.4,
                pipelineLabel: '扫描 -> 写入',
                metrics: Wrap(
                  children: <Widget>[
                    TaskMetricBadge(
                      label: '成功',
                      value: 2,
                      icon: Icons.check_circle_outline,
                    ),
                  ],
                ),
              ),
              QueuePathPreview(label: '输出路径', value: r'C:\Music\a.lrc'),
              QueueExpandedPathBlock(
                label: '完整路径',
                fullText: r'C:\Music\b.lrc',
              ),
              TonalInlineNotice(icon: Icons.info_outline, text: '提示文本'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('正在处理'), findsOneWidget);
    expect(find.text('2 / 5 · Running'), findsOneWidget);
    expect(find.text('扫描 -> 写入'), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('输出路径'), findsOneWidget);
    expect(find.text('完整路径'), findsOneWidget);
    expect(find.textContaining('b.lrc'), findsOneWidget);
    expect(find.text('提示文本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _localizedScaffold(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}
