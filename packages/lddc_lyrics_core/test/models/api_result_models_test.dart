import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('APIResultList', () {
    test('sourceRanges 与 more 语义对齐', () {
      final SongInfo qmA = const SongInfo(
        source: Source.qm,
        id: '1',
        title: 'A',
      );
      final SongInfo neA = const SongInfo(
        source: Source.ne,
        id: '2',
        title: 'B',
      );
      final SongInfo qmB = const SongInfo(
        source: Source.qm,
        id: '3',
        title: 'C',
      );

      final APIResultList<SourceAware> result = APIResultList<SourceAware>(
        <SourceAware>[qmA, neA, qmB],
        ranges: <Source, SourceRange>{
          Source.qm: const SourceRange(start: 0, end: 1, total: 3),
          Source.ne: const SourceRange(start: 0, end: 0, total: 1),
        },
      );

      expect(result.length, 3);
      expect(result[0].source, Source.qm);
      expect(result[1].source, Source.ne);
      expect(result[2].source, Source.qm);
      expect(result.more, <Source>[Source.qm]);
      expect(
        result.sourceRanges[Source.qm],
        const SourceRange(start: 0, end: 1, total: 3),
      );
    });

    test('合并分页结果并保持范围拼接规则', () {
      final APIResultList<SongInfo> page1 = APIResultList<SongInfo>(
        const <SongInfo>[
          SongInfo(source: Source.qm, id: '1', title: 'A'),
          SongInfo(source: Source.qm, id: '2', title: 'B'),
        ],
        info: SearchInfo(
          source: Source.qm,
          keyword: 'key',
          searchType: SearchType.song,
          page: 1,
        ),
        ranges: const SourceRange(start: 0, end: 1, total: 4),
        cached: true,
      );
      final APIResultList<SongInfo> page2 = APIResultList<SongInfo>(
        const <SongInfo>[
          SongInfo(source: Source.qm, id: '3', title: 'C'),
          SongInfo(source: Source.qm, id: '4', title: 'D'),
        ],
        info: SearchInfo(
          source: Source.qm,
          keyword: 'key',
          searchType: SearchType.song,
          page: 2,
        ),
        ranges: const SourceRange(start: 2, end: 3, total: 4),
        cached: false,
      );

      final APIResultList<SongInfo> merged = page1 + page2;
      expect(merged.length, 4);
      expect(
        merged.sourceRanges[Source.qm],
        const SourceRange(start: 0, end: 3, total: 4),
      );
      expect(merged.cached, isFalse);
      expect(merged.info, isA<SearchInfo>());
      final SearchInfo mergedInfo = merged.info! as SearchInfo;
      expect(mergedInfo.sources, <Source>[Source.qm]);
      expect(mergedInfo.page, isNull);
    });

    test('非相邻分页范围合并会抛错', () {
      final APIResultList<SongInfo> page1 = APIResultList<SongInfo>(
        const <SongInfo>[SongInfo(source: Source.ne, id: '1', title: 'A')],
        ranges: const SourceRange(start: 0, end: 0, total: 3),
      );
      final APIResultList<SongInfo> page2 = APIResultList<SongInfo>(
        const <SongInfo>[SongInfo(source: Source.ne, id: '3', title: 'C')],
        ranges: const SourceRange(start: 2, end: 2, total: 3),
      );

      expect(() => page1 + page2, throwsArgumentError);
    });

    test('非空结果必须显式提供 ranges', () {
      expect(
        () => APIResultList<SongInfo>(const <SongInfo>[
          SongInfo(source: Source.qm, id: '1', title: 'A'),
        ]),
        throwsArgumentError,
      );
    });

    test('空结果不提供 ranges 合法', () {
      final APIResultList<SongInfo> result = APIResultList<SongInfo>(
        const <SongInfo>[],
      );

      expect(result, isEmpty);
      expect(result.sourceRanges, isEmpty);
    });

    test('copyWith 复用不可变快照并允许显式清空 info', () {
      final APIResultList<SongInfo> result = APIResultList<SongInfo>(
        const <SongInfo>[SongInfo(source: Source.qm, id: '1', title: 'A')],
        info: SearchInfo(
          source: Source.qm,
          keyword: 'key',
          searchType: SearchType.song,
          page: 1,
        ),
        ranges: const SourceRange(start: 0, end: 0, total: 1),
      );

      final APIResultList<SongInfo> copied = result.copyWith(
        info: null,
        cached: true,
      );

      expect(copied.info, isNull);
      expect(copied.cached, isTrue);
      expect(identical(copied.sourceRanges, result.sourceRanges), isTrue);
      expect(() => copied.sourceRanges.clear(), throwsUnsupportedError);
    });

    test('sources 不受 ranges Map 插入顺序影响', () {
      final APIResultList<SongInfo> result = APIResultList<SongInfo>(
        const <SongInfo>[
          SongInfo(source: Source.ne, id: '2', title: 'B'),
          SongInfo(source: Source.qm, id: '1', title: 'A'),
        ],
        ranges: <Source, SourceRange>{
          Source.ne: const SourceRange(start: 0, end: 0, total: 1),
          Source.qm: const SourceRange(start: 0, end: 0, total: 1),
        },
      );

      expect(result.sources, <Source>[Source.qm, Source.ne]);
    });

    test('每个来源的 ranges 长度必须与实际条目数一致', () {
      expect(
        () => APIResultList<SongInfo>(
          const <SongInfo>[
            SongInfo(source: Source.qm, id: '1', title: 'A'),
            SongInfo(source: Source.qm, id: '2', title: 'B'),
            SongInfo(source: Source.ne, id: '3', title: 'C'),
          ],
          ranges: const <Source, SourceRange>{
            Source.qm: SourceRange(start: 0, end: 0, total: 2),
            Source.ne: SourceRange(start: 0, end: 1, total: 2),
          },
        ),
        throwsArgumentError,
      );
    });

    test('ranges 拒绝负数与超出 total 的下标', () {
      expect(
        () => APIResultList<SongInfo>(const <SongInfo>[
          SongInfo(source: Source.qm, id: '1', title: 'A'),
        ], ranges: const SourceRange(start: 1, end: 1, total: 1)),
        throwsArgumentError,
      );
    });
  });
}
