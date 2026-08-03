import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('Desktop lyrics timing 规格', () {
    test('scene document 会归一排序乱序 assigned slots', () {
      final LyricsLine late = _line(3000, 4000, 'late');
      final LyricsLine early = _line(1000, 2000, 'early');
      final LyricsLine sameStartLaterIndex = _line(1000, 2500, 'same');

      final DesktopLyricsSceneDocument document = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.lyrics,
        selectedLangs: const <String>['orig'],
        langOrder: const <String>['orig'],
        durationMs: 6000,
        assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
          (Direction.left, 0): <(int, LyricsLine)>[
            (3, late),
            (2, sameStartLaterIndex),
            (1, early),
          ],
        },
      );

      final List<(int, LyricsLine)> sorted =
          document.assignedLyricsSlots[(Direction.left, 0)]!;
      expect(sorted.map((entry) => entry.$1), <int>[1, 2, 3]);
      expect(sorted.map((entry) => entry.$2.text), <String>[
        'early',
        'same',
        'late',
      ]);
    });

    test('slot window 在前奏、当前行、尾奏都保持可解释状态', () {
      final List<(int, LyricsLine)> entries = <(int, LyricsLine)>[
        (0, _line(1000, 2000, 'first')),
        (1, _line(3000, 4000, 'second')),
      ];

      expect(
        _resolve(entries, 500)?.focusKind,
        DesktopLyricsSlotFocusKind.next,
      );
      expect(
        _resolve(entries, 1500)?.focusKind,
        DesktopLyricsSlotFocusKind.current,
      );
      expect(
        _resolve(entries, 2500)?.entry.$1,
        1,
        reason: '两行间隔正中点按下一句显示，避免空窗闪烁。',
      );
      expect(
        _resolve(entries, 5000)?.focusKind,
        DesktopLyricsSlotFocusKind.previous,
      );
    });

    test('翻译行通过原文 slot index 跟随当前行，不受自身文本时间缺失影响', () {
      final LyricsLine orig = _line(1000, 2000, '君の名は');
      final LyricsLine translation = LyricsLine(
        startMs: null,
        endMs: null,
        words: <LyricsWord>[
          LyricsWord(startMs: null, endMs: null, text: '你的名字'),
        ],
      );
      final DesktopLyricsSceneDocument document = DesktopLyricsSceneDocument(
        mode: DesktopLyricsSceneMode.lyrics,
        selectedLangs: const <String>['orig', 'ts'],
        langOrder: const <String>['orig', 'ts'],
        durationMs: 3000,
        lyricsMapping: <String, Map<int, LyricsLine>>{
          'ts': <int, LyricsLine>{0: translation},
        },
        assignedLyricsSlots: <(Direction, int), List<(int, LyricsLine)>>{
          (Direction.left, 0): <(int, LyricsLine)>[(0, orig)],
        },
      );

      final DesktopLyricsSlotWindow<(int, LyricsLine)>? window = _resolve(
        document.assignedLyricsSlots[(Direction.left, 0)]!,
        1500,
      );

      expect(window?.focusKind, DesktopLyricsSlotFocusKind.current);
      expect(document.lyricsMapping['ts']?[window!.entry.$1]?.text, '你的名字');
    });
  });
}

DesktopLyricsSlotWindow<(int, LyricsLine)>? _resolve(
  List<(int, LyricsLine)> entries,
  int currentTimeMs,
) {
  return resolveDesktopLyricsSlotWindow<(int, LyricsLine)>(
    entries: entries,
    currentTimeMs: currentTimeMs,
    durationMs: 6000,
    resolveLineStartMs: ((int, LyricsLine) entry) =>
        resolveDesktopLyricsLineStartMs(entry.$2),
    resolveLineEndMs: ((int, LyricsLine) entry) =>
        resolveDesktopLyricsLineEndMs(entry.$2),
  );
}

LyricsLine _line(int startMs, int endMs, String text) {
  return LyricsLine(
    startMs: startMs,
    endMs: endMs,
    words: <LyricsWord>[LyricsWord(startMs: startMs, endMs: endMs, text: text)],
  );
}
