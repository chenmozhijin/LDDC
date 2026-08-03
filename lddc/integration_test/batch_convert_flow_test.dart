import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc/src/platform/files/app_file_picker.dart';
import 'package:path/path.dart' as p;

import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('batch convert integration: 可导入文件并完成最小转换链路', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'batch_convert_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'batch_convert_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'batch_convert_flow',
        runtimeConfig: runtime,
        reporter: reporter,
      );
      addTearDown(app.dispose);

      final AppShellDriver shell = AppShellDriver(tester);
      final String sourcePath = p.join(app.workspace.root.path, 'demo.srt');
      final String saveRoot = app.workspace.exportsDir.path;
      final String outputPath = p.join(saveRoot, 'demo.lrc');

      await File(
        sourcePath,
      ).writeAsString('1\n00:00:00,000 --> 00:00:02,000\n集成测试\n');
      app.filePicker.files = <PickedFileHandle>[
        PickedFileHandle(name: 'demo.srt', path: sourcePath),
      ];
      app.filePicker.directory = saveRoot;

      await reporter.runStep('open_batch_convert_route', () async {
        await shell.openRoute(AppShellRoute.batchConvert);
        expect(
          find.byKey(const ValueKey<String>('batch_convert_queue_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('batch_convert_status_strip')),
          findsOneWidget,
        );
      });

      await reporter.runStep('pick_files', () async {
        await tester.tap(_batchActionFinder('pick_files'));
        await pumpUntil(
          tester,
          () => find.textContaining('demo.srt').evaluate().isNotEmpty,
          timeout: runtime.defaultStepTimeout,
          reason: '等待批量转换队列显示 SRT 输入',
        );
      });

      await reporter.runStep('select_save_root', () async {
        final Finder compactControls = find.byKey(
          const ValueKey<String>('batch_convert_compact_controls'),
        );
        if (compactControls.evaluate().isNotEmpty) {
          await tester.tap(compactControls);
          await pumpForInteraction(tester);
        }
        await tester.tap(
          find.byKey(const ValueKey<String>('batch_convert_select_save_root')),
        );
        await pumpUntil(
          tester,
          () => find.textContaining(saveRoot).evaluate().isNotEmpty,
          timeout: runtime.defaultStepTimeout,
          reason: '等待保存目录显示',
        );
        expect(find.textContaining(saveRoot), findsWidgets);
      });

      await reporter.runStep('start_convert', () async {
        await tester.tap(_batchActionFinder('start_or_cancel'));
        await tester.pump();
        await pumpUntil(
          tester,
          () => File(outputPath).existsSync(),
          timeout: const Duration(seconds: 10),
          reason: '等待批量转换输出文件生成',
        );
        await pumpForInteraction(tester);
        final String output = await File(outputPath).readAsString();
        expect(output, contains('集成测试'));
        expect(output, contains('[00:00'));
        expect(output, isNot(contains('-->')));
        expect(find.byIcon(Icons.task_alt_outlined), findsOneWidget);
      });

      await reporter.writeSummary();
    });
  });
}

Finder _batchActionFinder(String action) {
  final Finder compact = find.byKey(
    ValueKey<String>('batch_convert_compact_$action'),
  );
  if (compact.evaluate().isNotEmpty) {
    return compact;
  }
  return find.byKey(ValueKey<String>('batch_convert_$action'));
}
