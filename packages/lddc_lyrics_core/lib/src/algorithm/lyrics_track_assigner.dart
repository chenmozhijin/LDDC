import '../models/models.dart';

/// 根据歌词行的时间重叠关系分配桌面显示侧边与轨道。
class LyricsTrackAssigner {
  const LyricsTrackAssigner();

  Map<(Direction, int), List<(int, LyricsLine)>> assignPositions(
    List<LyricsLine> lines,
  ) {
    if (lines.isEmpty) {
      return <(Direction, int), List<(int, LyricsLine)>>{};
    }

    final List<(int, LyricsLine)> sortedLines =
        <(int, LyricsLine)>[
          for (int index = 0; index < lines.length; index += 1)
            (index, lines[index]),
        ]..sort(((int, LyricsLine) left, (int, LyricsLine) right) {
          return (left.$2.startMs ?? 0).compareTo(right.$2.startMs ?? 0);
        });

    final Map<(Direction, int), List<(int, LyricsLine)>> results =
        <(Direction, int), List<(int, LyricsLine)>>{};
    // 同一槽位在任意时刻最多有一条活动歌词，只需记录该槽位的结束时间。
    // 这样可避免每处理一行都复制活动列表并重新构造占用集合。
    final Map<(Direction, int), int> activeUntil = <(Direction, int), int>{};
    Direction lastTrack1Side = Direction.right;

    for (final (int index, LyricsLine line) in sortedLines) {
      final int startMs = line.startMs ?? 0;
      final int endMs = line.endMs ?? startMs;
      activeUntil.removeWhere((_, int activeEndMs) => activeEndMs <= startMs);

      late final (Direction, int) position;
      if (activeUntil.isEmpty) {
        final Direction side = lastTrack1Side == Direction.right
            ? Direction.left
            : Direction.right;
        position = (side, 1);
        lastTrack1Side = side;
      } else {
        int track = 1;
        while (true) {
          final (Direction, int) right = (Direction.right, track);
          if (!activeUntil.containsKey(right)) {
            position = right;
            if (track == 1) {
              lastTrack1Side = Direction.right;
            }
            break;
          }
          final (Direction, int) left = (Direction.left, track);
          if (!activeUntil.containsKey(left)) {
            position = left;
            if (track == 1) {
              lastTrack1Side = Direction.left;
            }
            break;
          }
          track += 1;
        }
      }

      results.putIfAbsent(position, () => <(int, LyricsLine)>[]).add((
        index,
        line,
      ));
      activeUntil[position] = endMs;
    }
    return results;
  }
}
