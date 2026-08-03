import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc/src/core/config/config.dart';

import 'support/integration_drivers.dart';
import 'support/integration_harness.dart';
import 'support/integration_reporter.dart';

void main() {
  ensureIntegrationBinding();

  testWidgets('settings/about integration: 设置修改并从设置进入关联管理器', (
    WidgetTester tester,
  ) async {
    final IntegrationRuntimeConfig runtime =
        IntegrationRuntimeConfig.fromEnvironment(
          scenarioName: 'settings_about_flow',
        );
    final IntegrationReporter reporter = IntegrationReporter(
      scenarioName: 'settings_about_flow',
      runtimeConfig: runtime,
    );
    addTearDown(reporter.writeSummary);

    await reporter.runScenario(() async {
      final IntegrationAppHandle app = await launchIntegrationApp(
        tester,
        scenarioName: 'settings_about_flow',
        runtimeConfig: runtime,
        reporter: reporter,
      );
      addTearDown(app.dispose);

      final AppShellDriver shell = AppShellDriver(tester);

      await reporter.runStep('open_settings_route', () async {
        await shell.openRoute(AppShellRoute.settings);
        expect(
          find.byKey(const ValueKey<AppShellRoute>(AppShellRoute.settings)),
          findsOneWidget,
        );
      });

      await reporter.runStep('change_language_through_settings', () async {
        await _openSettingsSection(
          tester,
          sectionName: 'app',
          target: find.byKey(
            const ValueKey<String>('settings_app_language_dropdown'),
          ),
        );
        final Finder languageDropdown = find.byKey(
          const ValueKey<String>('settings_app_language_dropdown'),
        );
        await tapVisible(tester, languageDropdown, reason: '等待应用语言下拉框可点击');
        await pumpForMenuOrRoute(tester);
        final Finder languageMenuItem = find
            .byWidgetPredicate(
              (Widget widget) =>
                  widget is DropdownMenuItem<AppLanguage> &&
                  widget.value == AppLanguage.en,
            )
            .last;
        final DropdownMenuItem<AppLanguage> languageItemWidget = tester
            .widget<DropdownMenuItem<AppLanguage>>(languageMenuItem);
        await tapVisible(
          tester,
          find.byWidget(languageItemWidget.child).last,
          timeout: runtime.defaultStepTimeout,
          reason: '等待语言菜单项可点击',
        );
        await pumpUntil(
          tester,
          () =>
              app.workspace.configRepository.current.app.language ==
              AppLanguage.en,
          timeout: runtime.defaultStepTimeout,
          reason: '等待设置页语言修改写入配置仓储',
        );
        final File configFile = await app.workspace.paths.resolveConfigFile();
        expect(configFile.existsSync(), isTrue);
        expect(await configFile.readAsString(), contains('"language"'));
        expect(find.text('Settings'), findsWidgets);
      });

      await reporter.runStep(
        'open_association_manager_from_settings',
        () async {
          await _openSettingsSection(
            tester,
            sectionName: 'tools',
            target: find.byKey(
              const ValueKey<String>('settings_tools_open_association_manager'),
            ),
          );
          final Finder associationManagerEntry = find.byKey(
            const ValueKey<String>('settings_tools_open_association_manager'),
          );
          // 1280x720 真实内容区下，工具分组的关联管理器入口可能在
          // 可滚动详情区的当前 viewport 之外。先让 Scrollable 把真实目标
          // 带入可点击区，再等待 hit test 成功；这样既覆盖用户需要的滚动，
          // 也不会用 warnIfMissed=false 把未命中伪装成正常点击。
          await tapVisible(
            tester,
            associationManagerEntry,
            timeout: runtime.defaultStepTimeout,
            reason: '等待关联管理器入口滚动到可点击位置',
          );
          await pumpUntil(
            tester,
            () => find
                .byKey(
                  const ValueKey<AppShellRoute>(
                    AppShellRoute.associationManager,
                  ),
                )
                .evaluate()
                .isNotEmpty,
            timeout: runtime.defaultStepTimeout,
            reason: '等待关联管理器路由打开',
          );
          expect(
            find.byKey(
              const ValueKey<AppShellRoute>(AppShellRoute.associationManager),
            ),
            findsOneWidget,
          );
        },
      );

      await reporter.runStep('return_to_settings', () async {
        final Finder associationManager = find.byKey(
          const ValueKey<AppShellRoute>(AppShellRoute.associationManager),
        );
        await tester.tap(
          find.descendant(
            of: associationManager,
            matching: find.byIcon(Icons.arrow_back_outlined),
          ),
        );
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey<AppShellRoute>(AppShellRoute.settings))
              .evaluate()
              .isNotEmpty,
          timeout: runtime.defaultStepTimeout,
          reason: '等待返回设置页',
        );
        expect(
          find.byKey(const ValueKey<AppShellRoute>(AppShellRoute.settings)),
          findsOneWidget,
        );
        expect(find.text('Settings'), findsWidgets);
      });

      await reporter.runStep('open_about_route', () async {
        await shell.openRoute(AppShellRoute.about);
        expect(
          find.byKey(const ValueKey<AppShellRoute>(AppShellRoute.about)),
          findsOneWidget,
        );
        expect(find.text('LDDC'), findsWidgets);
        expect(
          find.text('常用链接').evaluate().isNotEmpty ||
              find.text('Quick Links').evaluate().isNotEmpty,
          isTrue,
        );
        expect(find.text('产品状态'), findsNothing);
        expect(find.text('Product Status'), findsNothing);
      });

      await reporter.writeSummary(
        extra: <String, Object?>{
          'configFile': (await app.workspace.paths.resolveConfigFile()).path,
        },
      );
    });
  });
}

Future<void> _openSettingsSection(
  WidgetTester tester, {
  required String sectionName,
  required Finder target,
}) async {
  final Finder anchor = find.byKey(
    ValueKey<String>('settings_anchor_$sectionName'),
  );
  final Finder compactEntry = find.byKey(
    ValueKey<String>('settings_compact_entry_$sectionName'),
  );
  if (anchor.evaluate().isEmpty && compactEntry.evaluate().isEmpty) {
    final Finder compactBack = find.byKey(
      const ValueKey<String>('settings_compact_back'),
    );
    await tapVisible(tester, compactBack, reason: '等待返回紧凑设置分区列表');
  }
  if (anchor.evaluate().length == 1) {
    await tapVisible(tester, anchor, reason: '等待设置分区 $sectionName 锚点可点击');
  } else {
    await tapVisible(tester, compactEntry, reason: '等待紧凑设置分区 $sectionName 可点击');
  }
  await pumpUntil(
    tester,
    () => target.evaluate().length == 1,
    timeout: const Duration(seconds: 5),
    reason: '等待设置分区 $sectionName 内容出现',
  );
}
