import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../support/search_workflow_test_support.dart';

void main() {
  testWidgets('SearchWorkspace 在宽屏组合结果区与预览区并同步控制器文本', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController keywordController = TextEditingController(
      text: 'stale',
    );
    final TextEditingController savePathController = TextEditingController(
      text: 'stale',
    );
    final ValueNotifier<int?> selectedRow = ValueNotifier<int?>(null);
    addTearDown(() {
      selectedRow.dispose();
      savePathController.dispose();
      keywordController.dispose();
      controller.dispose();
    });
    final List<bool> expandedChanges = <bool>[];

    await tester.pumpWidget(
      _app(
        SearchWorkspace(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          keywordController: keywordController,
          savePathController: savePathController,
          selectedRowIndexListenable: selectedRow,
          isDesktopPlatform: true,
          canUseAndroidSafListSave: false,
          showTagSave: false,
          onRowsChanged: (_) {},
          onDesktopRowTap: (_) async {},
          onMobileRowTap: (_, _) async {},
          onReturnPath: () {},
          onOpenPreviewSheet: () async {},
          onExpandedLayoutChanged: expandedChanges.add,
          description: '搜索描述',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('search_workspace_split_layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('search_workspace_result_pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('search_workspace_preview_pane')),
      findsOneWidget,
    );
    expect(find.text('搜索描述'), findsOneWidget);
    expect(find.text('搜索歌词'), findsOneWidget);
    expect(find.text('歌词预览'), findsOneWidget);
    expect(keywordController.text, isEmpty);
    expect(savePathController.text, isEmpty);
    expect(expandedChanges, <bool>[true]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchWorkspace 紧凑布局可堆叠预览且隐藏说明', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController keywordController = TextEditingController();
    final TextEditingController savePathController = TextEditingController();
    final ValueNotifier<int?> selectedRow = ValueNotifier<int?>(null);
    addTearDown(() {
      selectedRow.dispose();
      savePathController.dispose();
      keywordController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _app(
        SearchWorkspace(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          keywordController: keywordController,
          savePathController: savePathController,
          selectedRowIndexListenable: selectedRow,
          isDesktopPlatform: false,
          canUseAndroidSafListSave: true,
          showTagSave: false,
          onRowsChanged: (_) {},
          onDesktopRowTap: (_) async {},
          onMobileRowTap: (_, _) async {},
          onReturnPath: () {},
          onOpenPreviewSheet: () async {},
          description: '紧凑说明',
          hideDescriptionInCompact: true,
          compactBehavior: SearchWorkspaceCompactBehavior.stackedPreview,
          showDirectorySave: false,
          showFileSave: true,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('search_workspace_split_layout')),
      findsNothing,
    );
    expect(find.text('紧凑说明'), findsNothing);
    expect(find.text('搜索歌词'), findsOneWidget);
    expect(find.text('歌词预览'), findsOneWidget);
    expect(find.text('保存到文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchWorkspace 不会用旧 post-frame 状态覆盖用户清空的输入', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController keywordController = TextEditingController();
    final TextEditingController savePathController = TextEditingController();
    final ValueNotifier<int?> selectedRow = ValueNotifier<int?>(null);
    addTearDown(() {
      selectedRow.dispose();
      savePathController.dispose();
      keywordController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _app(
        SearchWorkspace(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          keywordController: keywordController,
          savePathController: savePathController,
          selectedRowIndexListenable: selectedRow,
          isDesktopPlatform: true,
          canUseAndroidSafListSave: false,
          showTagSave: false,
          onRowsChanged: (_) {},
          onDesktopRowTap: (_) async {},
          onMobileRowTap: (_, _) async {},
          onReturnPath: () {},
          onOpenPreviewSheet: () async {},
        ),
      ),
    );
    await tester.pump();

    final Finder searchInput = find.byType(EditableText).first;
    await tester.enterText(searchInput, 'old keyword');
    await tester.pump();
    // 先产生真实用户输入，再在受控同步可能排队时清空。
    await tester.enterText(searchInput, '');
    await tester.pump();

    expect(keywordController.text, isEmpty);
    expect(controller.state.keyword, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SearchWorkspace 保存目录输入也不会恢复旧值', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final SearchWorkflowController controller =
        createIdleSearchWorkflowController();
    final TextEditingController keywordController = TextEditingController();
    final TextEditingController savePathController = TextEditingController();
    final ValueNotifier<int?> selectedRow = ValueNotifier<int?>(null);
    addTearDown(() {
      selectedRow.dispose();
      savePathController.dispose();
      keywordController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      _app(
        SearchWorkspace(
          controller: controller,
          strings: SearchUiStrings.zhHans(),
          keywordController: keywordController,
          savePathController: savePathController,
          selectedRowIndexListenable: selectedRow,
          isDesktopPlatform: true,
          canUseAndroidSafListSave: false,
          showTagSave: false,
          onRowsChanged: (_) {},
          onDesktopRowTap: (_) async {},
          onMobileRowTap: (_, _) async {},
          onReturnPath: () {},
          onOpenPreviewSheet: () async {},
        ),
      ),
    );
    await tester.pump();

    final Finder savePathInput = find.byKey(
      const ValueKey<String>('search_preview_save_path_field'),
    );
    await tester.enterText(savePathInput, 'C:/old');
    await tester.pump();
    await tester.enterText(savePathInput, '');
    await tester.pump();

    expect(savePathController.text, isEmpty);
    expect(controller.state.saveDirectoryPath, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));
