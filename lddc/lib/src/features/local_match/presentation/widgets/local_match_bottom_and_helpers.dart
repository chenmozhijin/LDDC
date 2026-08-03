import 'package:flutter/material.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/accessibility/app_action_semantics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../application/local_match_page_controller.dart';
import '../../application/local_match_page_state.dart';
import '../../application/local_match_run_validator.dart';
import '../local_match_notice_text.dart';

class LocalMatchBottomActionBar extends StatelessWidget {
  const LocalMatchBottomActionBar({
    super.key,
    required this.state,
    required this.controller,
  });

  final LocalMatchPageState state;
  final LocalMatchPageController controller;

  @override
  Widget build(BuildContext context) {
    final List<String> validationMessages = localMatchInlineValidationMessages(
      context,
      state,
    );
    return SafeArea(
      top: false,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  state.isBusy
                      ? localMatchProgressMessageText(context, state)
                      : validationMessages.isEmpty
                      ? context.l10n.localMatchReadyToStart
                      : validationMessages.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              AppActionSemantics(
                identifier: AppSemanticsIdentifiers.localMatchStart,
                label: state.isBusy
                    ? context.l10n.actionCancel
                    : context.l10n.localMatchActionStart,
                onTap: localMatchResolveStartAction(state)
                    ? controller.startOrCancel
                    : null,
                child: FilledButton.icon(
                  key: const ValueKey<String>('local_match_start_or_cancel'),
                  onPressed: localMatchResolveStartAction(state)
                      ? controller.startOrCancel
                      : null,
                  icon: Icon(
                    state.isBusy
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow_outlined,
                  ),
                  label: Text(
                    state.isBusy
                        ? context.l10n.actionCancel
                        : context.l10n.localMatchActionStart,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool localMatchResolveStartAction(LocalMatchPageState state) {
  if (state.isBusy) {
    return true;
  }
  return state.canStart && validateLocalMatchRun(state).isEmpty;
}

List<String> localMatchInlineValidationMessages(
  BuildContext context,
  LocalMatchPageState state,
) {
  return validateLocalMatchRun(state)
      .map(
        (LocalMatchRunValidationIssue issue) =>
            localMatchValidationIssueText(context, issue),
      )
      .toList(growable: false);
}

List<String> localMatchVisualValidationMessages(
  BuildContext context,
  LocalMatchPageState state,
) {
  const Set<LocalMatchRunValidationCode> inlineOnlyCodes =
      <LocalMatchRunValidationCode>{
        LocalMatchRunValidationCode.emptyLangs,
        LocalMatchRunValidationCode.emptySources,
        LocalMatchRunValidationCode.emptyQueue,
      };
  // 这些基础缺口已经由底部启动栏直接提示；这里必须按结构化 code 过滤，
  // 不能按中文文案比较，否则文案本地化或重写后 UI 与 controller 会再次漂移。
  return validateLocalMatchRun(state)
      .where(
        (LocalMatchRunValidationIssue issue) =>
            !inlineOnlyCodes.contains(issue.code),
      )
      .map(
        (LocalMatchRunValidationIssue issue) =>
            localMatchValidationIssueText(context, issue),
      )
      .toList(growable: false);
}

String? localMatchSkipExistingHint(
  BuildContext context,
  LocalMatchPageState state,
) {
  if (localMatchSkipExistingConfigBlocked(state)) {
    return context.l10n.localMatchSkipExistingConflictHint;
  }
  return null;
}

String localMatchPhaseLabel(BuildContext context, LocalMatchTaskPhase phase) {
  return switch (phase) {
    LocalMatchTaskPhase.idle => context.l10n.localMatchPhaseIdle,
    LocalMatchTaskPhase.scanning => context.l10n.localMatchPhaseScanning,
    LocalMatchTaskPhase.matching => context.l10n.localMatchPhaseMatching,
    LocalMatchTaskPhase.writing => context.l10n.localMatchPhaseWriting,
    LocalMatchTaskPhase.completed => context.l10n.localMatchPhaseCompleted,
  };
}

String localMatchPhaseHint(BuildContext context, LocalMatchTaskPhase phase) {
  return switch (phase) {
    LocalMatchTaskPhase.idle => context.l10n.localMatchPhaseHintIdle,
    LocalMatchTaskPhase.scanning => context.l10n.localMatchPhaseHintScanning,
    LocalMatchTaskPhase.matching => context.l10n.localMatchPhaseHintMatching,
    LocalMatchTaskPhase.writing => context.l10n.localMatchPhaseHintWriting,
    LocalMatchTaskPhase.completed => context.l10n.localMatchPhaseHintCompleted,
  };
}

String localMatchProgressMessageText(
  BuildContext context,
  LocalMatchPageState state,
) {
  final LocalMatchProgressMessage message = state.progressMessage;
  if (message.code == LocalMatchProgressMessageCode.external) {
    final String detail = message.detail?.trim() ?? '';
    return detail.isEmpty
        ? localMatchPhaseHint(context, state.taskPhase)
        : detail;
  }
  return switch (message.code) {
    LocalMatchProgressMessageCode.none => localMatchPhaseHint(
      context,
      state.taskPhase,
    ),
    LocalMatchProgressMessageCode.importCompleted =>
      context.l10n.localMatchProgressImportCompleted,
    LocalMatchProgressMessageCode.cancelling =>
      context.l10n.localMatchNoticeCancelling,
    LocalMatchProgressMessageCode.scanningFiles =>
      context.l10n.localMatchIteratingFiles,
    LocalMatchProgressMessageCode.scanCancelled =>
      context.l10n.localMatchNoticeScanCancelled,
    LocalMatchProgressMessageCode.scanCompleted =>
      context.l10n.localMatchProgressScanCompleted,
    LocalMatchProgressMessageCode.scanFailed =>
      context.l10n.localMatchProgressScanFailed,
    LocalMatchProgressMessageCode.matchingCancelled =>
      context.l10n.localMatchNoticeMatchCancelled,
    LocalMatchProgressMessageCode.matchingCompleted =>
      context.l10n.localMatchProgressMatchCompleted,
    LocalMatchProgressMessageCode.matchingFailed =>
      context.l10n.localMatchProgressMatchFailed,
    LocalMatchProgressMessageCode.preparingMatch =>
      context.l10n.localMatchProgressPreparingMatch,
    LocalMatchProgressMessageCode.external => localMatchPhaseHint(
      context,
      state.taskPhase,
    ),
  };
}

String localMatchPhasePipelineLabel(
  BuildContext context,
  LocalMatchTaskPhase phase,
) {
  return switch (phase) {
    LocalMatchTaskPhase.idle => context.l10n.localMatchPipelineIdle,
    LocalMatchTaskPhase.scanning => context.l10n.localMatchPipelineScanning,
    LocalMatchTaskPhase.matching => context.l10n.localMatchPipelineMatching,
    LocalMatchTaskPhase.writing => context.l10n.localMatchPipelineWriting,
    LocalMatchTaskPhase.completed => context.l10n.localMatchPipelineCompleted,
  };
}

String localMatchSongTitle(BuildContext context, LocalMatchQueueItem item) {
  final String title = item.songInfo.title?.trim() ?? '';
  return title.isNotEmpty ? title : context.l10n.localMatchUnknownSong;
}

String localMatchArtistLabel(SongInfo songInfo) {
  final String? artist = songInfo.artist?.join();
  if (artist == null || artist.trim().isEmpty) {
    return '-';
  }
  return artist;
}

String localMatchArtistAlbumSubtitle(LocalMatchQueueItem item) {
  final List<String> fragments = <String>[
    localMatchArtistLabel(item.songInfo),
    if ((item.songInfo.album ?? '').trim().isNotEmpty) item.songInfo.album!,
  ];
  return fragments.join(' · ');
}

String localMatchDurationLabel(BuildContext context, SongInfo songInfo) {
  return songInfo.formattedDuration.isNotEmpty
      ? songInfo.formattedDuration
      : context.l10n.localMatchUnknownDuration;
}

class LocalMatchRowAction {
  const LocalMatchRowAction({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

List<LocalMatchRowAction> localMatchRowActions(
  BuildContext context,
  LocalMatchQueueItem item,
  bool isSelectionMode,
) {
  final List<LocalMatchRowAction> actions = <LocalMatchRowAction>[
    LocalMatchRowAction(
      value: 'search',
      label: context.l10n.localMatchRowActionOpenInSearch,
      icon: Icons.search_outlined,
    ),
    if (!isSelectionMode)
      LocalMatchRowAction(
        value: 'selectMode',
        label: context.l10n.localMatchRowActionEnterSelection,
        icon: Icons.checklist_outlined,
      ),
  ];
  final String songPath = item.songInfo.path?.trim() ?? '';
  final String outputPath = item.outputPath?.trim() ?? '';
  final bool canOpenSongDirectory =
      songPath.isNotEmpty && !songPath.startsWith('content://');
  final bool canOpenOutputDirectory =
      outputPath.isNotEmpty && !outputPath.startsWith('content://');
  if (canOpenSongDirectory) {
    actions.add(
      LocalMatchRowAction(
        value: 'songDir',
        label: context.l10n.localMatchRowActionOpenSongDirectory,
        icon: Icons.folder_open_outlined,
      ),
    );
  }
  if (canOpenOutputDirectory) {
    actions.add(
      LocalMatchRowAction(
        value: 'saveDir',
        label: context.l10n.localMatchRowActionOpenSaveDirectory,
        icon: Icons.drive_folder_upload_outlined,
      ),
    );
    actions.add(
      LocalMatchRowAction(
        value: 'lyricsFile',
        label: context.l10n.localMatchRowActionOpenLyrics,
        icon: Icons.lyrics_outlined,
      ),
    );
  }
  return actions;
}

List<Source> localMatchAvailableSources(BuildContext context) {
  return const <Source>[Source.qm, Source.kg, Source.ne, Source.lrclib];
}

String localMatchSourceLabel(BuildContext context, Source source) {
  return switch (source) {
    Source.qm => context.l10n.sourceQQMusic,
    Source.kg => context.l10n.sourceKugou,
    Source.ne => context.l10n.sourceNetease,
    Source.lrclib => context.l10n.sourceLrclib,
    _ => source.value,
  };
}

String localMatchSaveModeLabel(BuildContext context, LocalMatchSaveMode value) {
  return switch (value) {
    LocalMatchSaveMode.song => context.l10n.localMatchSaveModeSong,
    LocalMatchSaveMode.mirror => context.l10n.localMatchSaveModeMirror,
    LocalMatchSaveMode.specify => context.l10n.localMatchSaveModeSpecify,
  };
}

String localMatchFileNameModeLabel(
  BuildContext context,
  LocalMatchFileNameMode value,
) {
  return switch (value) {
    LocalMatchFileNameMode.song => context.l10n.localMatchFileNameModeSong,
    LocalMatchFileNameMode.formatBySong =>
      context.l10n.localMatchFileNameModeFormatBySong,
    LocalMatchFileNameMode.formatByLyrics =>
      context.l10n.localMatchFileNameModeFormatByLyrics,
  };
}

String localMatchFileNameModeHint(
  BuildContext context,
  LocalMatchFileNameMode value,
) {
  return switch (value) {
    LocalMatchFileNameMode.song => context.l10n.localMatchFileNameHintSong,
    LocalMatchFileNameMode.formatBySong =>
      context.l10n.localMatchFileNameHintFormatBySong,
    LocalMatchFileNameMode.formatByLyrics =>
      context.l10n.localMatchFileNameHintFormatByLyrics,
  };
}

String localMatchSaveToTagModeLabel(
  BuildContext context,
  LocalMatchSaveToTagMode value,
) {
  return switch (value) {
    LocalMatchSaveToTagMode.onlyFile =>
      context.l10n.localMatchSaveToTagOnlyFile,
    LocalMatchSaveToTagMode.onlyTag => context.l10n.localMatchSaveToTagOnlyTag,
    LocalMatchSaveToTagMode.both => context.l10n.localMatchSaveToTagBoth,
  };
}

String localMatchSavePlanBlockingText(
  BuildContext context,
  LocalMatchSavePlanBlocker blocker,
) {
  return switch (blocker) {
    LocalMatchSavePlanBlocker.needsSaveRoot =>
      context.l10n.localMatchValidationNeedsSaveRoot,
    LocalMatchSavePlanBlocker.needsSongRoot =>
      context.l10n.localMatchValidationNeedsSongRoot,
    LocalMatchSavePlanBlocker.unknown =>
      context.l10n.localMatchValidationUnknownSavePath,
    LocalMatchSavePlanBlocker.none => '',
  };
}

String localMatchPendingLyricsPathText(
  BuildContext context,
  LocalMatchSavePlan plan,
) {
  final String rootLabel = plan.pendingFileNameRootLabel?.trim() ?? '';
  if (rootLabel.isEmpty) {
    return context.l10n.localMatchPendingLyricsFileName;
  }
  return context.l10n.localMatchPendingLyricsFileNameAt(rootLabel);
}

String localMatchSavePlanPreviewText(
  BuildContext context,
  LocalMatchSavePlan plan,
) {
  if (plan.hasBlockingError) {
    return localMatchSavePlanBlockingText(context, plan.blocker);
  }
  final List<String> fragments = <String>[
    if (plan.kind == LocalMatchSavePlanKind.tagOnly)
      context.l10n.localMatchPreviewTagOnly,
    if (plan.kind == LocalMatchSavePlanKind.fileAndTag)
      context.l10n.localMatchPreviewWriteTag,
    if ((plan.targetPath ?? '').trim().isNotEmpty) plan.targetPath!.trim(),
    if ((plan.targetPath ?? '').trim().isEmpty && plan.waitsForLyricsFileName)
      localMatchPendingLyricsPathText(context, plan),
  ];
  return fragments.isEmpty
      ? context.l10n.localMatchPreviewNoOutput
      : fragments.join(' + ');
}

String localMatchQueueItemDisplayLyricsPath(
  BuildContext context,
  LocalMatchQueueItem item,
) {
  final String resolvedOutputPath = item.outputPath?.trim() ?? '';
  if (resolvedOutputPath.isNotEmpty) {
    return resolvedOutputPath;
  }
  if (item.savePlan.kind == LocalMatchSavePlanKind.tagOnly) {
    return context.l10n.localMatchPreviewSongTagOnly;
  }
  if (item.savePlan.waitsForLyricsFileName) {
    return localMatchPendingLyricsPathText(context, item.savePlan);
  }
  return localMatchSavePlanPreviewText(context, item.savePlan);
}

String? localMatchQueueItemFailureSummary(
  BuildContext context,
  LocalMatchQueueItem item,
) {
  if (item.savePlan.hasBlockingError) {
    final String message = localMatchSavePlanBlockingText(
      context,
      item.savePlan.blocker,
    );
    return message.isEmpty
        ? context.l10n.localMatchCalcSavePathFailed
        : message;
  }
  final String text = item.lastStatus?.text.trim() ?? '';
  if (text.isEmpty || !item.hasFailed) {
    return null;
  }
  return text;
}
