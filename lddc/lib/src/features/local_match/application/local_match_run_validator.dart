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
  } else if (state.isAndroidMode && state.androidTreeToken == null) {
    issues.add(
      const LocalMatchRunValidationIssue(
        code: LocalMatchRunValidationCode.missingAndroidTree,
      ),
    );
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
