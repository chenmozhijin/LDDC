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
        await tester.tap(destination.first);
        await pumpForMenuOrRoute(tester);
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
    final Finder input = find.descendant(
      of: find.byKey(const ValueKey<String>('search_toolbar_search_bar')),
      matching: find.byType(EditableText),
    );
    await tester.tap(input);
    await pumpForInteraction(tester);
    await tester.enterText(input, keyword);
    await pumpForInteraction(tester);
  }

  Future<void> selectSource(Source source) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_source_menu')),
    );
    await pumpForMenuOrRoute(tester);
    await tester.tap(
      find.byKey(
        ValueKey<String>('search_toolbar_source_item_${source.value}'),
      ),
    );
    await pumpForMenuOrRoute(tester);
  }

  Future<void> selectSearchType(SearchType type) async {
    await tester.tap(
      find.byKey(ValueKey<String>('search_type_tab_${type.value}')),
    );
    await pumpForMenuOrRoute(tester);
  }

  Future<void> submitSearch() async {
    await tester.tap(
      find.byKey(const ValueKey<String>('search_toolbar_search_button')),
    );
    await pumpForInteraction(tester);
  }

  Future<void> openResultAt(int index) async {
    final Finder row = find.byKey(ValueKey<String>('search_result_row_$index'));
    // 生产交互已改为单击立即打开，SearchResultInteractionController 会复用同一行
    // 尚未结束的 Future。旧驱动连续点击两次时，第一次点击可能已经把结果列表替换
    // 为歌单内容，第二次再查找旧 row 就会失败，并让打开请求在 teardown 后继续访问
    // 已释放缓存。这里只发出一次真实点击，场景测试再等待目标状态作为完成边界。
    await tester.tap(row);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapSaveDirectory() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_directory_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_translate_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_file_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_tag_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapBatchSave() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_result_batch_save_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> _waitTransientOverlaysToSettle() async {
    await pumpUntilGone(
      tester,
      find.byType(SnackBar),
      timeout: const Duration(seconds: 5),
      reason: '等待搜索页 SnackBar 消失',
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
    await tester.ensureVisible(target);
    await tester.tap(target);
    await pumpForInteraction(tester);
  }

  Future<void> openSongFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_open_song_button'),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await pumpForInteraction(tester);
  }

  Future<void> tapConvert() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_convert_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_translate_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_to_tag_button'),
    );
    await _waitTransientOverlaysToSettle();
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
  }

  Future<void> selectLyricsFormat(LyricsFormat format) async {
    await _waitTransientOverlaysToSettle();
    final Finder target = find
        .byKey(const ValueKey<String>('open_lyrics_format_dropdown'))
        .last;
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
    await tapVisible(
      tester,
      find
          .byWidgetPredicate(
            (Widget widget) =>
                widget is DropdownMenuItem<LyricsFormat> &&
                widget.value == format,
          )
          .last,
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
    await tester.tap(
      find.byKey(const ValueKey<String>('local_match_pick_dirs')),
    );
    await pumpForMenuOrRoute(tester);
  }

  Future<void> selectSaveToTagMode(LocalMatchSaveToTagMode mode) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('local_match_save_to_tag_mode')),
    );
    await pumpForMenuOrRoute(tester);
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
    await tester.ensureVisible(target);
    await pumpForInteraction(tester);
    await tester.tap(target);
    await pumpForMenuOrRoute(tester);
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
