import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

/// 真实请求单来源用例定义。
class LiveApiCase {
  const LiveApiCase({
    required this.source,
    required this.songKeyword,
    this.paginationSongKeyword,
    this.songlistKeyword,
    this.albumKeyword,
    this.preferSecondSong = false,
    this.enableSongIdFlow = false,
    this.enableSonglistFlow = false,
    this.enableAlbumFlow = false,
  });

  final Source source;
  final String songKeyword;
  final String? paginationSongKeyword;
  final String? songlistKeyword;
  final String? albumKeyword;
  final bool preferSecondSong;
  final bool enableSongIdFlow;
  final bool enableSonglistFlow;
  final bool enableAlbumFlow;
}

/// 单个执行步骤结果。
class LiveApiStepResult {
  const LiveApiStepResult({
    required this.step,
    required this.success,
    required this.elapsedMs,
    this.errorCategory,
    this.errorMessage,
  });

  final String step;
  final bool success;
  final int elapsedMs;
  final String? errorCategory;
  final String? errorMessage;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'step': step,
      'success': success,
      'elapsedMs': elapsedMs,
      'errorCategory': errorCategory,
      'errorMessage': errorMessage,
    };
  }
}

/// 单个来源联调报告。
class LiveApiSourceReport {
  const LiveApiSourceReport({
    required this.source,
    required this.success,
    required this.elapsedMs,
    required this.steps,
  });

  final Source source;
  final bool success;
  final int elapsedMs;
  final List<LiveApiStepResult> steps;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'source': source.value,
      'success': success,
      'elapsedMs': elapsedMs,
      'steps': steps
          .map<Map<String, Object?>>((LiveApiStepResult step) => step.toMap())
          .toList(growable: false),
    };
  }
}

/// 默认真实请求矩阵：对齐Python版 `LDDC/tests/test_api.py`。
const List<LiveApiCase> kDefaultLiveApiCases = <LiveApiCase>[
  LiveApiCase(
    source: Source.ne,
    songKeyword: "one's future",
    songlistKeyword: 'Kud Wafter',
    albumKeyword: 'Kud Wafter Original SoundTrack',
    preferSecondSong: true,
    enableSongIdFlow: true,
    enableSonglistFlow: true,
    enableAlbumFlow: true,
  ),
  LiveApiCase(
    source: Source.qm,
    songKeyword: "one's future",
    paginationSongKeyword: '周杰伦',
    songlistKeyword: 'Kud Wafter',
    albumKeyword: 'Kud Wafter Original SoundTrack',
    preferSecondSong: true,
    enableSongIdFlow: true,
    enableSonglistFlow: true,
    enableAlbumFlow: true,
  ),
  LiveApiCase(
    source: Source.kg,
    songKeyword: 'アルカテイル',
    songlistKeyword: 'Kud Wafter',
    albumKeyword: 'Kud Wafter Original SoundTrack',
    enableSonglistFlow: true,
    enableAlbumFlow: true,
  ),
  LiveApiCase(source: Source.lrclib, songKeyword: 'アルカテイル'),
];
