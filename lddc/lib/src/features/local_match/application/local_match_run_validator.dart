import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'local_match_page_state.dart';

/// 本地匹配启动前的统一校验。
///
/// controller 和 UI 都从这里读取同一组 code/detail，最终文案只在 UI 层
/// 通过当前 locale 渲染，避免页面显示允许启动、controller 又用另一套中文文案拦截。
List<LocalMatchRunValidationIssue> validateLocalMatchRun(
  LocalMatchPageState state,
) {
  final List<LocalMatchRunValidationIssue> issues =
      <LocalMatchRunValidationIssue>[];
  if (state.selectedLangs.isEmpty) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.emptyLangs,
      ),
    );
  }
  if (state.selectedSources.isEmpty) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.emptySources,
      ),
    );
  }
  if (state.queueItems.isEmpty) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.emptyQueue,
      ),
    );
  }
  if (state.saveToTagMode != LocalMatchSaveToTagMode.onlyFile &&
      !LyricsFormatCapabilities.isLrcFamily(state.lyricsFormat)) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.tagRequiresLrc,
      ),
    );
  }
  if (state.skipExistingLyrics && _skipExistingConfigBlocked(state)) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.skipExistingFileNameConflict,
      ),
    );
  }
  if (state.isDesktopMode) {
    final List<LocalMatchSavePlanBlocker> blockers = state.queueItems
        .where((LocalMatchQueueItem item) => item.savePlan.hasBlockingError)
        .map((LocalMatchQueueItem item) => item.savePlan.blocker)
        .toSet()
        .toList(growable: false);
    for (final LocalMatchSavePlanBlocker blocker in blockers) {
      issues.add(
        LocalMatchRunValidationIssue(
          code: LocalMatchRunValidationCode.savePlanBlocked,
          savePlanBlocker: blocker,
        ),
      );
    }
  } else if (state.isAndroidMode) {
    if (state.androidTreeToken == null) {
      issues.add(
        const LocalMatchRunValidationIssue(
          code: LocalMatchRunValidationCode.missingAndroidTree,
        ),
      );
    }
    // mirror/specify 缺保存根树、歌曲不在授权树内（或路径形态无法推导）都会让写入逐条失败，
    // 必须在启动前拦住；校验与写入共用同一个目标推导纯函数，避免"校验放行、执行必失败"。
    final List<LocalMatchSavePlanBlocker> androidBlockers = state.queueItems
        .where((LocalMatchQueueItem item) => item.savePlan.hasBlockingError)
        .map((LocalMatchQueueItem item) => item.savePlan.blocker)
        .toSet()
        .toList(growable: false);
    for (final LocalMatchSavePlanBlocker blocker in androidBlockers) {
      issues.add(
        LocalMatchRunValidationIssue(
          code: LocalMatchRunValidationCode.savePlanBlocked,
          savePlanBlocker: blocker,
        ),
      );
    }
  }
  return List<LocalMatchRunValidationIssue>.unmodifiable(issues);
}

bool localMatchSkipExistingConfigBlocked(LocalMatchPageState state) {
  return _skipExistingConfigBlocked(state);
}

bool localMatchIsLrcFamily(LyricsFormat format) {
  return LyricsFormatCapabilities.isLrcFamily(format);
}

bool _skipExistingConfigBlocked(LocalMatchPageState state) {
  return state.saveToTagMode != LocalMatchSaveToTagMode.onlyTag &&
      state.fileNameMode == LocalMatchFileNameMode.formatByLyrics;
}
