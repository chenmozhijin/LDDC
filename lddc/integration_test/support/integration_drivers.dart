import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

import 'integration_harness.dart';

class AppShellDriver {
  AppShellDriver(this.tester);

  final WidgetTester tester;

  Future<void> openRoute(
    AppShellRoute route, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final List<String> titles = switch (route) {
      AppShellRoute.search => <String>['搜索', 'Search'],
      AppShellRoute.localMatch => <String>['本地匹配', 'Local Match'],
      AppShellRoute.openLyrics => <String>['打开歌词', 'Open Lyrics'],
      AppShellRoute.associationManager => <String>['歌词关联管理器'],
      AppShellRoute.batchConvert => <String>['批量转换', 'Batch Convert'],
      AppShellRoute.settings => <String>['设置', 'Settings'],
      AppShellRoute.about => <String>['关于', 'About'],
    };
    for (final String title in titles) {
      final Finder destination = find.text(title);
      if (destination.evaluate().isNotEmpty) {
        await tapVisible(
          tester,
          destination.first,
          reason: '等待导航目标 $title 可点击',
        );
        break;
      }
    }
    await pumpUntilVisibleAny(
      tester,
      titles
          .map(
            (String title) => find.descendant(
              of: find.byType(AppBar),
              matching: find.text(title),
            ),
          )
          .toList(growable: false),
      timeout: timeout,
      reason: '等待路由 ${titles.join('/')} 打开',
    );
  }
}

class SearchDriver {
  SearchDriver(this.tester);

  final WidgetTester tester;

  Future<void> enterKeyword(String keyword) async {
    final Finder searchBar = find.byKey(
      const ValueKey<String>('search_toolbar_search_bar'),
    );
    final Finder input = find.descendant(
      of: searchBar,
      matching: find.byType(EditableText),
    );
    // SearchBar 的手势与焦点入口位于外层 Material，而 EditableText 可能被
    // leading/trailing 的命中区域部分覆盖。点击真实 SearchBar 后再向唯一输入框
    // 写入文本，既保持严格 hit test，也与用户点击搜索框的行为一致。
    await tapVisible(tester, searchBar, reason: '等待搜索输入框可点击');
    await tester.enterText(input, keyword);
    await pumpForInteraction(tester);
  }

  Future<void> selectSource(Source source) async {
    await tapVisible(
      tester,
      find.byKey(const ValueKey<String>('search_toolbar_source_menu')),
      reason: '等待搜索源菜单可点击',
    );
    final Finder menuItem = find.byKey(
      ValueKey<String>('search_toolbar_source_item_${source.value}'),
    );
    final PopupMenuItem<String> itemWidget = tester
        .widget<PopupMenuItem<String>>(menuItem);
    final Widget itemChild =
        itemWidget.child ??
        (throw StateError('搜索源菜单项 ${source.value} 缺少可点击内容'));
    // PopupMenuItem 的 key 标记内容节点，实际手势层位于弹出路由外层。
    // 点击其唯一可见 child，既保留严格 hit test，又不依赖坐标。
    await tapVisible(
      tester,
      find.byWidget(itemChild).last,
      reason: '等待搜索源 ${source.value} 可点击',
    );
  }

  Future<void> selectSearchType(SearchType type) async {
    await tapVisible(
      tester,
      find.byKey(ValueKey<String>('search_type_tab_${type.value}')),
      reason: '等待搜索类型 ${type.value} 可点击',
    );
  }

  Future<void> submitSearch() async {
    await tapVisible(
      tester,
      find.byKey(const ValueKey<String>('search_toolbar_search_button')),
      reason: '等待搜索按钮可点击',
    );
  }

  Future<void> openResultAt(int index) async {
    final Finder row = find.byKey(ValueKey<String>('search_result_row_$index'));
    // 生产交互已改为单击立即打开，SearchResultInteractionController 会复用同一行
    // 尚未结束的 Future。旧驱动连续点击两次时，第一次点击可能已经把结果列表替换
    // 为歌单内容，第二次再查找旧 row 就会失败，并让打开请求在 teardown 后继续访问
    // 已释放缓存。这里只发出一次真实点击，场景测试再等待目标状态作为完成边界。
    await tapVisible(tester, row, reason: '等待搜索结果 $index 可点击');
  }

  Future<void> tapSaveDirectory() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_directory_button'),
    );
    await _waitTransientOverlaysToSettle();
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索保存目录按钮可点击');
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_translate_button'),
    );
    await _waitTransientOverlaysToSettle();
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索翻译按钮可点击');
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_file_button'),
    );
    await _waitTransientOverlaysToSettle();
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索保存文件按钮可点击');
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_tag_button'),
    );
    await _waitTransientOverlaysToSettle();
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索写入标签按钮可点击');
  }

  Future<void> dismissPreviewSheetIfOpen() async {
    final Finder sheet = find.ancestor(
      of: find.byKey(const ValueKey<String>('search_preview_save_tag_button')),
      matching: find.byType(BottomSheet),
    );
    if (sheet.evaluate().isEmpty) {
      return;
    }
    // 窄桌面和移动布局会把预览放在模态底部弹层中。
    // 下一次搜索前执行用户可见的返回动作，避免弹层遮住工具栏；
    // 宽屏布局没有 BottomSheet，因此不会额外弹出页面路由。
    await tester.pageBack();
    await pumpUntilGone(
      tester,
      sheet,
      timeout: const Duration(seconds: 5),
      reason: '等待搜索预览底部弹层关闭',
    );
  }

  Future<void> tapBatchSave() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_result_batch_save_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待搜索批量保存按钮可点击');
  }

  Future<void> _waitTransientOverlaysToSettle() async {
    await pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 5),
      reason: '等待搜索页 SnackBar 消失',
    );
  }

  Future<void> _ensurePreviewActionsVisible(Finder target) async {
    if (target.evaluate().length == 1) {
      return;
    }
    final Finder openPreview = find.byKey(
      const ValueKey<String>('search_result_open_preview_button'),
    );
    await tapVisible(tester, openPreview, reason: '等待紧凑布局歌词预览按钮可点击');
    await pumpUntil(
      tester,
      () => target.evaluate().length == 1,
      timeout: const Duration(seconds: 5),
      reason: '等待紧凑布局歌词预览操作区打开',
    );
  }
}

class OpenLyricsDriver {
  OpenLyricsDriver(this.tester);

  final WidgetTester tester;

  Future<void> openLyricsFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_open_lyrics_button'),
    );
    await tapVisible(tester, target, reason: '等待打开歌词文件按钮可点击');
  }

  Future<void> openSongFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_open_song_button'),
    );
    await tapVisible(tester, target, reason: '等待打开歌曲文件按钮可点击');
  }

  Future<void> tapConvert() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_convert_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待打开歌词转换按钮可点击');
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_translate_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待打开歌词翻译按钮可点击');
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待打开歌词保存文件按钮可点击');
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_to_tag_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待打开歌词写入标签按钮可点击');
  }

  Future<void> selectLyricsFormat(LyricsFormat format) async {
    await _waitTransientOverlaysToSettle();
    final Finder target = find
        .byKey(const ValueKey<String>('open_lyrics_format_dropdown'))
        .last;
    await tapVisible(tester, target, reason: '等待歌词格式下拉框可点击');
    final Finder menuItem = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget is DropdownMenuItem<LyricsFormat> &&
              widget.value == format,
        )
        .last;
    final DropdownMenuItem<LyricsFormat> itemWidget = tester
        .widget<DropdownMenuItem<LyricsFormat>>(menuItem);
    await tapVisible(
      tester,
      find.byWidget(itemWidget.child).last,
      reason: '等待歌词格式菜单项可点击',
    );
    await pumpForInteraction(tester);
  }

  Future<void> _waitTransientOverlaysToSettle() async {
    await pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 5),
      reason: '等待打开歌词页 SnackBar 消失',
    );
  }
}

class LocalMatchDriver {
  LocalMatchDriver(this.tester);

  final WidgetTester tester;

  Future<void> pickDirectory() async {
    await tapVisible(
      tester,
      find.byKey(const ValueKey<String>('local_match_pick_dirs')),
      reason: '等待本地匹配目录按钮可点击',
    );
  }

  Future<void> selectSaveToTagMode(LocalMatchSaveToTagMode mode) async {
    await _waitTransientOverlaysToSettle();
    final Finder target = find.byKey(
      const ValueKey<String>('local_match_save_to_tag_mode'),
    );
    if (target.evaluate().isEmpty) {
      // 紧凑布局把规则卡默认折叠，先执行用户真实的展开动作；桌面布局
      // 没有折叠入口，因此仅在该 key 存在时处理，不引入平台特判。
      final Finder rulesCard = find.byKey(
        const ValueKey<String>('local_match_rules_card'),
      );
      await tapVisible(tester, rulesCard, reason: '等待本地匹配规则卡可展开');
      await pumpUntil(
        tester,
        () => target.evaluate().length == 1,
        timeout: const Duration(seconds: 5),
        reason: '等待本地匹配规则字段展开',
      );
    }
    await tapVisible(tester, target, reason: '等待标签保存模式下拉框可点击');
    final Finder menuItem = find
        .byWidgetPredicate(
          (Widget widget) =>
              widget is DropdownMenuItem<LocalMatchSaveToTagMode> &&
              widget.value == mode,
        )
        .last;
    final DropdownMenuItem<LocalMatchSaveToTagMode> itemWidget = tester
        .widget<DropdownMenuItem<LocalMatchSaveToTagMode>>(menuItem);
    // DropdownMenuItem 只是菜单内容节点，实际手势层由弹出的菜单路由包裹。
    // 使用其可见子内容作为命中目标，避免为下拉菜单放宽全局点击校验。
    await tapVisible(
      tester,
      find.byWidget(itemWidget.child).last,
      reason: '等待本地匹配标签保存模式可点击',
    );
    await pumpForMenuOrRoute(tester);
  }

  Future<void> toggleSkipExisting() async {
    await _waitTransientOverlaysToSettle();
    await tapVisible(
      tester,
      find.byKey(const ValueKey<String>('local_match_skip_existing_checkbox')),
      reason: '等待“跳过已有歌词”复选框可点击',
    );
  }

  Future<void> tapStartOrCancel() async {
    final Finder target =
        find
            .byKey(const ValueKey<String>('local_match_header_start'))
            .evaluate()
            .isNotEmpty
        ? find.byKey(const ValueKey<String>('local_match_header_start'))
        : find.byKey(const ValueKey<String>('local_match_start_or_cancel'));
    await _waitTransientOverlaysToSettle();
    await tapVisible(tester, target, reason: '等待本地匹配开始或取消按钮可点击');
  }

  Future<void> _waitTransientOverlaysToSettle() async {
    await pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 5),
      reason: '等待本地匹配页 SnackBar 消失',
    );
  }
}
