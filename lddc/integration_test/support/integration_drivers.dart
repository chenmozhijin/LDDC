import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/app/shell/app_shell_route.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
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
  SearchDriver(this.tester, {this.readState});

  final WidgetTester tester;
  final SearchWorkflowState Function()? readState;

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

    // 收敛条件拆成两个独立事实分别判定：输入框文本是否等于测试输入，以及业务
    // 状态是否跟随。旧实现把两者塞进同一个条件并共用一条超时消息，导致 run
    // 34564263324 的失败无法判读——日志同时打印了 controller 与 expected，
    // 无法区分“输入框没清空”和“状态没跟随”，只能靠猜。
    //
    // 必须保留有界轮询：紧凑布局关闭预览弹层时可能有已排队的旧状态回写，输入框
    // 会先瞬时恢复旧值、下一帧才重建为用户输入（见 integration_drivers_test.dart
    // 的 _DelayedSearchControllerProbe）。只做一次瞬时取样会把这种正常收敛误判
    // 为业务失败。
    bool controllerConverged = false;
    bool stateConverged = false;
    try {
      await pumpUntil(
        tester,
        () {
          controllerConverged = _keywordControllerMatches(input, keyword);
          stateConverged = _keywordStateMatches(keyword);
          return controllerConverged && stateConverged;
        },
        timeout: const Duration(seconds: 5),
        reason: '搜索输入框和业务关键词没有收敛到测试输入',
      );
      return;
    } on TimeoutException {
      // 输入框已经是目标文本、只有业务状态没跟上时，补一次显式的 onChanged
      // 重放并在有界窗口内再等待。这与用户输入走完全相同的状态通路，不绕过
      // 产品逻辑、不直接写状态；仍不收敛就按确定性问题失败。
      if (controllerConverged) {
        await _replayKeywordOnChanged(input, keyword);
        try {
          await pumpUntil(
            tester,
            () {
              stateConverged = _keywordStateMatches(keyword);
              return stateConverged;
            },
            timeout: const Duration(seconds: 1),
            reason: '搜索业务状态在重放输入回调后仍未收敛',
          );
          return;
        } on TimeoutException {
          stateConverged = false;
        }
      }
    }

    throw TimeoutException(
      '搜索输入没有收敛: '
      '${_keywordConvergenceDiagnostics(input, keyword, controllerConverged, stateConverged)}',
      const Duration(seconds: 5),
    );
  }

  /// 输入框当前文本是否严格等于期望关键词；输入框不唯一时返回 false。
  bool _keywordControllerMatches(Finder input, String keyword) {
    if (input.evaluate().length != 1) {
      return false;
    }
    return tester.widget<EditableText>(input).controller.text == keyword;
  }

  /// 业务状态关键词是否已跟随；未注入状态读取器时视为无需校验。
  bool _keywordStateMatches(String keyword) {
    final SearchWorkflowState? state = readState?.call();
    return state == null || state.keyword == keyword;
  }

  /// 重放一次 SearchBar 的 onChanged 通路，用于输入框已收敛但状态滞后的场景。
  Future<void> _replayKeywordOnChanged(Finder input, String keyword) async {
    if (input.evaluate().length != 1) {
      return;
    }
    final EditableText editable = tester.widget<EditableText>(input);
    editable.onChanged?.call(keyword);
  }

  /// 失败诊断必须同时打印输入框、业务状态与当前搜索条件，才能区分
  /// “输入框没清空”与“状态没跟随”两种根因。
  String _keywordConvergenceDiagnostics(
    Finder input,
    String keyword,
    bool controllerConverged,
    bool stateConverged,
  ) {
    final String controllerText = input.evaluate().length == 1
        ? tester.widget<EditableText>(input).controller.text
        : '<输入框数量=${input.evaluate().length}>';
    final SearchWorkflowState? state = readState?.call();
    return 'expected=$keyword, controller=$controllerText, '
        'state=${state?.keyword ?? '<未提供状态读取器>'}, '
        'source=${state?.selectedSource.value ?? '<unknown>'}, '
        'type=${state?.selectedSearchType.value ?? '<unknown>'}, '
        'controllerConverged=$controllerConverged, '
        'stateConverged=$stateConverged';
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
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索保存目录按钮可点击');
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_translate_button'),
    );
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索翻译按钮可点击');
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_file_button'),
    );
    await _ensurePreviewActionsVisible(target);
    await tapVisible(tester, target, reason: '等待搜索保存文件按钮可点击');
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('search_preview_save_tag_button'),
    );
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
    final bool handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue, reason: '搜索预览底部弹层必须能响应系统返回动作');
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
    await tapVisible(tester, target, reason: '等待搜索批量保存按钮可点击');
  }

  Future<void> _ensurePreviewActionsVisible(Finder target) async {
    if (target.evaluate().length == 1) {
      return;
    }
    final Finder openPreview = find.byKey(
      const ValueKey<String>('search_result_open_preview_button'),
    );
    // Android 的结果操作条可能把“预览”入口放在横向 viewport 外。旧驱动先
    // 等待 hitTestable，导致真正负责滚动的 tapVisible 永远没有机会执行。先等待
    // 入口建立并把它滚入视口，再判断异步 BottomSheet 是否已经出现；后续仍由
    // tapVisible 做严格命中检查，不使用坐标或吞掉真实遮挡问题。
    await pumpUntil(
      tester,
      () => target.evaluate().length == 1 || openPreview.evaluate().length == 1,
      timeout: const Duration(seconds: 5),
      reason: '等待移动端预览弹层或预览入口建立',
    );
    if (target.evaluate().length == 1) {
      return;
    }
    await Scrollable.ensureVisible(
      tester.element(openPreview),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await pumpForInteraction(tester);
    await pumpUntil(
      tester,
      () =>
          target.evaluate().length == 1 ||
          openPreview.hitTestable().evaluate().length == 1,
      timeout: const Duration(seconds: 5),
      reason: '等待移动端预览弹层或预览入口稳定',
    );
    if (target.evaluate().length == 1) {
      return;
    }
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
    await tapVisible(tester, target, reason: '等待打开歌词转换按钮可点击');
  }

  Future<void> tapTranslate() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_translate_button'),
    );
    await tapVisible(tester, target, reason: '等待打开歌词翻译按钮可点击');
  }

  Future<void> tapSaveFile() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_button'),
    );
    await tapVisible(tester, target, reason: '等待打开歌词保存文件按钮可点击');
  }

  Future<void> tapSaveTag() async {
    final Finder target = find.byKey(
      const ValueKey<String>('open_lyrics_save_to_tag_button'),
    );
    await tapVisible(tester, target, reason: '等待打开歌词写入标签按钮可点击');
  }

  Future<void> selectLyricsFormat(LyricsFormat format) async {
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
    final Finder tile = find.byKey(
      const ValueKey<String>('local_match_skip_existing_checkbox'),
    );
    if (tile.evaluate().length != 1) {
      throw StateError('“跳过已有歌词”选项不存在或不唯一');
    }
    final Finder checkbox = find.descendant(
      of: tile,
      matching: find.byType(Checkbox),
    );
    if (checkbox.evaluate().length != 1) {
      throw StateError('“跳过已有歌词”选项没有唯一的复选框控件');
    }
    final Checkbox checkboxWidget = tester.widget<Checkbox>(checkbox);
    if (checkboxWidget.onChanged == null) {
      throw StateError('“跳过已有歌词”选项当前不可操作');
    }
    // 标题文本只是 ListTile 的显示内容，在 Linux 真实命中树中不承担手势。
    // 直接操作 CheckboxListTile 创建的唯一 Checkbox，既对应用户可见控件，
    // 也继续经过 tapVisible 的滚动、唯一性和遮挡校验。
    await tapVisible(tester, checkbox, reason: '等待“跳过已有歌词”复选框可点击');
  }

  Future<void> tapStartOrCancel() async {
    final Finder target =
        find
            .byKey(const ValueKey<String>('local_match_header_start'))
            .evaluate()
            .isNotEmpty
        ? find.byKey(const ValueKey<String>('local_match_header_start'))
        : find.byKey(const ValueKey<String>('local_match_start_or_cancel'));
    await tapVisible(tester, target, reason: '等待本地匹配开始或取消按钮可点击');
  }
}
