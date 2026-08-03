import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

void main() {
  group('AutoFetchUseCase', () {
    test('信息不足时抛出 NotEnoughInfo', () async {
      final AutoFetchUseCase useCase = AutoFetchUseCase(
        gateway: _FakeGateway(),
      );
      await expectLater(
        () => useCase.execute(
          AutoFetchRequest(
            info: SongInfo(
              source: Source.local,
              artist: SongArtist(<String>['private-artist']),
            ),
          ),
        ),
        throwsA(
          isA<LddcNotEnoughInfoException>()
              .having(
                (LddcNotEnoughInfoException error) => error.message,
                'message',
                '没有足够的信息用于搜索',
              )
              .having(
                (LddcNotEnoughInfoException error) => error.message,
                'message',
                isNot(contains('private-artist')),
              ),
        ),
      );
    });

    test('请求冻结来源列表并拒绝非法数值参数', () {
      final List<Source> sources = <Source>[Source.qm];
      final AutoFetchRequest request = AutoFetchRequest(
        info: const SongInfo(source: Source.local, title: 'Song'),
        sources: sources,
      );
      sources.add(Source.kg);

      expect(request.sources, <Source>[Source.qm]);
      expect(() => request.sources.add(Source.ne), throwsUnsupportedError);
      expect(
        () => AutoFetchRequest(
          info: const SongInfo(source: Source.local, title: 'Song'),
          minScore: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => AutoFetchRequest(
          info: const SongInfo(source: Source.local, title: 'Song'),
          timeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('artist-title 无结果时会回退 title 搜索', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo remote = SongInfo(
        source: Source.qm,
        id: 'qm-1',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Artist - Song',
        songs: <SongInfo>[],
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Song',
        songs: <SongInfo>[remote],
      );
      gateway.setLyricsResult(songId: 'qm-1', lyrics: _buildLyrics(remote));

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.matchedSongInfo.id, 'qm-1');
      expect(gateway.searchCalls.length, 2);
      expect(gateway.searchCalls[0], (
        source: Source.qm,
        keyword: 'Artist - Song',
      ));
      expect(gateway.searchCalls[1], (source: Source.qm, keyword: 'Song'));
    });

    test('artist-title 候选无歌词时仍会回退 title 搜索', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo badRemote = SongInfo(
        source: Source.qm,
        id: 'qm-bad',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo goodRemote = SongInfo(
        source: Source.qm,
        id: 'qm-good',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Artist - Song',
        songs: <SongInfo>[badRemote],
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Song',
        songs: <SongInfo>[goodRemote],
      );
      gateway.setLyricsError(
        songId: 'qm-bad',
        error: const LddcLyricsNotFoundException('没有找到歌词'),
      );
      gateway.setLyricsResult(
        songId: 'qm-good',
        lyrics: _buildLyrics(goodRemote),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.matchedSongInfo.id, 'qm-good');
      expect(gateway.searchCalls, <({Source source, String keyword})>[
        (source: Source.qm, keyword: 'Artist - Song'),
        (source: Source.qm, keyword: 'Song'),
      ]);
    });

    test('仅标题输入时不会重复触发 title 搜索', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(source: Source.local, title: 'Solo');
      final SongInfo remote = SongInfo(
        source: Source.qm,
        id: 'solo-1',
        title: 'Solo',
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Solo',
        songs: <SongInfo>[remote],
      );
      gateway.setLyricsResult(songId: 'solo-1', lyrics: _buildLyrics(remote));

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.matchedSongInfo.id, 'solo-1');
      expect(gateway.searchCalls.length, 1);
      expect(gateway.searchCalls[0], (source: Source.qm, keyword: 'Solo'));
    });

    test('同优先级歌词按来源顺序返回', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Hello',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo qmSong = SongInfo(
        source: Source.qm,
        id: 'qm-song',
        title: 'Hello',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo kgSong = SongInfo(
        source: Source.kg,
        id: 'kg-song',
        title: 'Hello',
        artist: SongArtist(<String>['A']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'A - Hello',
        songs: <SongInfo>[qmSong],
      );
      gateway.setSearchResult(
        source: Source.kg,
        keyword: 'A - Hello',
        songs: <SongInfo>[kgSong],
      );
      gateway.setLyricsResult(songId: 'qm-song', lyrics: _buildLyrics(qmSong));
      gateway.setLyricsResult(songId: 'kg-song', lyrics: _buildLyrics(kgSong));

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.kg, Source.qm],
        ),
      );

      expect(result.lyrics.source, Source.kg);
      expect(result.matchedSongInfo.id, 'kg-song');
    });

    test('十五分窗口内优先选择语言更丰富的歌词', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Rich',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo qmSong = SongInfo(
        source: Source.qm,
        id: 'qm-basic',
        title: 'Rich',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo kgSong = SongInfo(
        source: Source.kg,
        id: 'kg-rich',
        title: 'Rich',
        artist: SongArtist(<String>['A']),
      );
      gateway
        ..setSearchResult(
          source: Source.qm,
          keyword: 'A - Rich',
          songs: <SongInfo>[qmSong],
        )
        ..setSearchResult(
          source: Source.kg,
          keyword: 'A - Rich',
          songs: <SongInfo>[kgSong],
        )
        ..setLyricsResult(songId: 'qm-basic', lyrics: _buildLyrics(qmSong))
        ..setLyricsResult(
          songId: 'kg-rich',
          lyrics: _buildLyrics(kgSong, withTs: true, withRoma: true),
        );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.qm, Source.kg],
        ),
      );

      expect(result.matchedSongInfo.id, 'kg-rich');
    });

    test('includeSearchResults 时会返回命中置顶后的合并结果', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Merge',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo qmSong = SongInfo(
        source: Source.qm,
        id: 'qm-merge',
        title: 'Merge',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo kgSong = SongInfo(
        source: Source.kg,
        id: 'kg-merge',
        title: 'Merge',
        artist: SongArtist(<String>['A']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'A - Merge',
        songs: <SongInfo>[qmSong],
        total: 20,
      );
      gateway.setSearchResult(
        source: Source.kg,
        keyword: 'A - Merge',
        songs: <SongInfo>[kgSong],
        total: 30,
      );
      gateway.setLyricsResult(songId: 'qm-merge', lyrics: _buildLyrics(qmSong));
      gateway.setLyricsResult(songId: 'kg-merge', lyrics: _buildLyrics(kgSong));

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.qm, Source.kg],
          includeSearchResults: true,
        ),
      );

      final APIResultList<SongInfo>? merged = result.searchResults;
      expect(merged, isNotNull);
      expect(merged!.first.id, 'qm-merge');
      expect(merged.any((SongInfo info) => info.id == 'kg-merge'), isTrue);
      final SearchInfo info = merged.info! as SearchInfo;
      expect(info.sources, <Source>[Source.qm, Source.kg]);
      expect(info.keyword, 'A - Merge');
      expect(info.page, isNull);
      expect(merged.sourceRanges[Source.qm]?.total, 20);
      expect(merged.sourceRanges[Source.kg]?.total, 30);
    });

    test('未尝试的低分结果仍按真实分数排序', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      const SongInfo localInfo = SongInfo(source: Source.local, title: 'Exact');
      const SongInfo exact = SongInfo(
        source: Source.qm,
        id: 'exact',
        title: 'Exact',
      );
      const SongInfo low = SongInfo(source: Source.qm, id: 'low', title: 'zzz');
      const SongInfo medium = SongInfo(
        source: Source.qm,
        id: 'medium',
        title: 'Exact live',
      );
      gateway
        ..setSearchResult(
          source: Source.qm,
          keyword: 'Exact',
          songs: const <SongInfo>[exact, low, medium],
        )
        ..setLyricsResult(songId: 'exact', lyrics: _buildLyrics(exact));

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          minScore: 99,
          sources: const <Source>[Source.qm],
          includeSearchResults: true,
        ),
      );

      expect(
        result.searchResults?.map((SongInfo song) => song.id).toList(),
        <String?>['exact', 'medium', 'low'],
      );
      expect(gateway.lyricsCalls, <String>['exact']);
    });

    test('includeSearchResults 保持主命中在第一项', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Primary',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo kgSong = SongInfo(
        source: Source.kg,
        id: 'kg-primary',
        title: 'Primary',
        artist: SongArtist(<String>['A']),
      );
      final SongInfo qmSong = SongInfo(
        source: Source.qm,
        id: 'qm-secondary',
        title: 'Primary',
        artist: SongArtist(<String>['A']),
      );
      gateway.setSearchResult(
        source: Source.kg,
        keyword: 'A - Primary',
        songs: <SongInfo>[kgSong],
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'A - Primary',
        songs: <SongInfo>[qmSong],
      );
      gateway.setLyricsResult(
        songId: 'kg-primary',
        lyrics: _buildLyrics(kgSong),
      );
      gateway.setLyricsResult(
        songId: 'qm-secondary',
        lyrics: _buildLyrics(qmSong),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.kg, Source.qm],
          includeSearchResults: true,
        ),
      );

      expect(result.matchedSongInfo.id, 'kg-primary');
      expect(result.searchResults?.first.id, 'kg-primary');
    });

    test('普通歌曲跳过 subtitle Inst 并采用 KG 正常歌词且置顶', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Last Desire',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo qmInstrumental = SongInfo(
        source: Source.qm,
        id: 'qm-inst',
        title: 'Last Desire',
        subtitle: 'Inst.',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo kgNormal = SongInfo(
        source: Source.kg,
        id: 'kg-normal',
        title: 'Last Desire',
        artist: SongArtist(<String>['Band']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Last Desire',
        songs: <SongInfo>[qmInstrumental],
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Last Desire',
        songs: <SongInfo>[qmInstrumental],
      );
      gateway.setSearchResult(
        source: Source.kg,
        keyword: 'Band - Last Desire',
        songs: <SongInfo>[kgNormal],
      );
      gateway.setLyricsResult(
        songId: 'kg-normal',
        lyrics: _buildLyrics(kgNormal),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.qm, Source.kg],
          includeSearchResults: true,
        ),
      );

      expect(result.matchedSongInfo.id, 'kg-normal');
      expect(result.searchResults?.first.id, 'kg-normal');
      expect(gateway.lyricsCalls, isNot(contains('qm-inst')));
    });

    test('前三个版本冲突不占额度并继续获取第四个正常候选', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Last Desire',
        artist: SongArtist(<String>['Band']),
      );
      final List<SongInfo> conflicts = List<SongInfo>.generate(
        3,
        (int index) => SongInfo(
          source: Source.qm,
          id: 'conflict-$index',
          title: 'Last Desire',
          subtitle: 'off-vocal',
          artist: SongArtist(<String>['Band']),
        ),
      );
      final SongInfo normal = SongInfo(
        source: Source.qm,
        id: 'normal-fourth',
        title: 'Last Desire',
        artist: SongArtist(<String>['Other']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Last Desire',
        songs: <SongInfo>[...conflicts, normal],
      );
      gateway.setLyricsResult(
        songId: 'normal-fourth',
        lyrics: _buildLyrics(normal),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          minScore: 40,
          sources: const <Source>[Source.qm],
        ),
      );

      expect(result.matchedSongInfo.id, 'normal-fourth');
      expect(gateway.lyricsCalls, <String>['normal-fourth']);
    });

    test('空歌词与纯音乐占位均会继续同源后续候选', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo emptySong = SongInfo(
        source: Source.qm,
        id: 'empty',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo instrumentalSong = SongInfo(
        source: Source.qm,
        id: 'instrumental-placeholder',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      final SongInfo normalSong = SongInfo(
        source: Source.qm,
        id: 'usable',
        title: 'Song',
        artist: SongArtist(<String>['Artist']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Artist - Song',
        songs: <SongInfo>[emptySong, instrumentalSong, normalSong],
      );
      gateway.setLyricsResult(
        songId: 'empty',
        lyrics: Lyrics(songInfo: emptySong, source: Source.qm),
      );
      gateway.setLyricsResult(
        songId: 'instrumental-placeholder',
        lyrics: Lyrics.instrumental(songInfo: instrumentalSong),
      );
      gateway.setLyricsResult(
        songId: 'usable',
        lyrics: _buildLyrics(normalSong),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.matchedSongInfo.id, 'usable');
      expect(gateway.lyricsCalls, <String>[
        'empty',
        'instrumental-placeholder',
        'usable',
      ]);
    });

    test('只有版本冲突的 Inst 候选时不会反推纯音乐', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Last Desire',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo conflict = SongInfo(
        source: Source.qm,
        id: 'conflict-inst',
        title: 'Last Desire (Instrumental)',
        artist: SongArtist(<String>['Band']),
        language: Language.instrumental,
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Last Desire',
        songs: <SongInfo>[conflict],
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Last Desire',
        songs: <SongInfo>[conflict],
      );

      await expectLater(
        () => useCase.execute(
          AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
        ),
        throwsA(isA<LddcLyricsNotFoundException>()),
      );
      expect(gateway.lyricsCalls, isEmpty);
    });
    test('普通标题可由同版本 language 证据反推纯音乐', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Quiet Track',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo instrumental = SongInfo(
        source: Source.qm,
        id: 'language-inst',
        title: 'Quiet Track',
        artist: SongArtist(<String>['Band']),
        language: Language.instrumental,
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Quiet Track',
        songs: <SongInfo>[instrumental],
      );
      gateway.setLyricsError(
        songId: 'language-inst',
        error: const LddcLyricsNotFoundException('没有找到歌词'),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.matchedSongInfo.id, 'language-inst');
      expect(result.lyrics.isInstrumental(), isTrue);
    });
    test('候选均未找到歌词时触发纯音乐回退', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Inst',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo instrumental = SongInfo(
        source: Source.qm,
        id: 'inst-song',
        title: 'Inst',
        artist: SongArtist(<String>['Band']),
        language: Language.instrumental,
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Inst',
        songs: <SongInfo>[instrumental],
      );
      gateway.setLyricsError(
        songId: 'inst-song',
        error: const LddcLyricsNotFoundException('没有找到歌词'),
      );

      final AutoFetchResult result = await useCase.execute(
        AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
      );

      expect(result.lyrics.isInstrumental(), isTrue);
      expect(result.matchedSongInfo.id, 'inst-song');
    });

    test('歌词返回时取消会立即停止后续候选', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final Completer<Lyrics> firstLyrics = Completer<Lyrics>();
      bool cancelled = false;
      const SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Cancel',
      );
      const SongInfo first = SongInfo(
        source: Source.qm,
        id: 'first',
        title: 'Cancel',
      );
      const SongInfo second = SongInfo(
        source: Source.qm,
        id: 'second',
        title: 'Cancel',
      );
      gateway
        ..setSearchResult(
          source: Source.qm,
          keyword: 'Cancel',
          songs: const <SongInfo>[first, second],
        )
        ..setLyricsFuture(songId: 'first', lyrics: firstLyrics.future)
        ..setLyricsResult(songId: 'second', lyrics: _buildLyrics(second));

      final Future<AutoFetchResult> future = useCase.execute(
        AutoFetchRequest(
          info: localInfo,
          sources: const <Source>[Source.qm],
          shouldCancel: () => cancelled,
        ),
      );
      expect(await gateway.firstLyricsCall.future, 'first');
      cancelled = true;
      firstLyrics.complete(_buildLyrics(first));

      await expectLater(future, throwsA(isA<AutoFetchCancelledException>()));
      expect(gateway.lyricsCalls, <String>['first']);
    });

    test('超时后迟到搜索结果不会继续请求歌词', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final Completer<void> searchGate = Completer<void>();
      gateway.searchGate = searchGate;
      const SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Timeout',
      );
      const SongInfo remote = SongInfo(
        source: Source.qm,
        id: 'late',
        title: 'Timeout',
      );
      gateway
        ..setSearchResult(
          source: Source.qm,
          keyword: 'Timeout',
          songs: const <SongInfo>[remote],
        )
        ..setLyricsResult(songId: 'late', lyrics: _buildLyrics(remote));

      await expectLater(
        useCase.execute(
          AutoFetchRequest(
            info: localInfo,
            sources: const <Source>[Source.qm],
            timeout: const Duration(milliseconds: 20),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
      searchGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(gateway.lyricsCalls, isEmpty);
    });

    test('仅网络类错误时抛出网络错误', () async {
      final _FakeGateway gateway = _FakeGateway();
      final AutoFetchUseCase useCase = AutoFetchUseCase(gateway: gateway);
      final SongInfo localInfo = SongInfo(
        source: Source.local,
        title: 'Net',
        artist: SongArtist(<String>['Band']),
      );
      final SongInfo remote = SongInfo(
        source: Source.qm,
        id: 'net-song',
        title: 'Net',
        artist: SongArtist(<String>['Band']),
      );
      gateway.setSearchResult(
        source: Source.qm,
        keyword: 'Band - Net',
        songs: <SongInfo>[remote],
      );
      gateway.setLyricsError(
        songId: 'net-song',
        error: const SocketException('network down token=secret-value'),
      );

      await expectLater(
        () => useCase.execute(
          AutoFetchRequest(info: localInfo, sources: const <Source>[Source.qm]),
        ),
        throwsA(
          isA<LddcLyricsRequestException>()
              .having(
                (LddcLyricsRequestException error) => error.message,
                'message',
                '网络请求失败',
              )
              .having(
                (LddcLyricsRequestException error) => error.message,
                'message',
                isNot(contains('secret-value')),
              )
              .having(
                (LddcLyricsRequestException error) => error.cause,
                'cause',
                isA<SocketException>(),
              )
              .having(
                (LddcLyricsRequestException error) =>
                    error.context['failureCount'],
                'failureCount',
                1,
              ),
        ),
      );
    });
  });
}

class _FakeGateway implements AutoFetchLyricsGateway {
  final Map<String, Object> _searchResults = <String, Object>{};
  final Map<String, int> _searchTotals = <String, int>{};
  final Map<String, Object> _lyricsResults = <String, Object>{};
  final List<({Source source, String keyword})> searchCalls =
      <({Source source, String keyword})>[];
  final List<String> lyricsCalls = <String>[];
  final Completer<String> firstLyricsCall = Completer<String>();
  Completer<void>? searchGate;

  void setSearchResult({
    required Source source,
    required String keyword,
    required List<SongInfo> songs,
    int? total,
  }) {
    final String key = _searchKey(source, keyword);
    _searchResults[key] = songs;
    _searchTotals[key] = total ?? songs.length;
  }

  void setSearchError({
    required Source source,
    required String keyword,
    required Exception error,
  }) {
    _searchResults[_searchKey(source, keyword)] = error;
  }

  void setLyricsResult({required String songId, required Lyrics lyrics}) {
    _lyricsResults[songId] = lyrics;
  }

  void setLyricsFuture({
    required String songId,
    required Future<Lyrics> lyrics,
  }) {
    _lyricsResults[songId] = lyrics;
  }

  void setLyricsError({required String songId, required Exception error}) {
    _lyricsResults[songId] = error;
  }

  @override
  Future<APIResultList<SongInfo>> searchSongs({
    required Source source,
    required String keyword,
    required SearchType searchType,
  }) async {
    searchCalls.add((source: source, keyword: keyword));
    await searchGate?.future;
    final String key = _searchKey(source, keyword);
    final Object? value = _searchResults[key];
    if (value is Exception) {
      throw value;
    }
    final List<SongInfo> songs = value is List<SongInfo> ? value : <SongInfo>[];
    final int total = _searchTotals[key] ?? songs.length;
    final SourceRange range = songs.isEmpty
        ? SourceRange(start: 0, end: -1, total: total)
        : SourceRange(start: 0, end: songs.length - 1, total: total);
    return APIResultList<SongInfo>(
      songs,
      info: SearchInfo(
        source: source,
        keyword: keyword,
        searchType: searchType,
        page: 1,
      ),
      ranges: <Source, SourceRange>{source: range},
    );
  }

  @override
  Future<Lyrics> getLyrics(SongInfo info) async {
    final String key = info.id ?? info.title ?? '';
    lyricsCalls.add(key);
    if (!firstLyricsCall.isCompleted) {
      firstLyricsCall.complete(key);
    }
    final Object? value = _lyricsResults[key];
    if (value == null) {
      throw const LddcLyricsNotFoundException('没有找到歌词');
    }
    if (value is Exception) {
      throw value;
    }
    if (value is Future<Lyrics>) {
      return value;
    }
    return value as Lyrics;
  }

  String _searchKey(Source source, String keyword) =>
      '${source.value}|$keyword';
}

Lyrics _buildLyrics(
  SongInfo songInfo, {
  bool verbatim = true,
  bool withTs = false,
  bool withRoma = false,
}) {
  final LyricsData orig = <LyricsLine>[
    LyricsLine(
      startMs: 0,
      endMs: 1000,
      words: const <LyricsWord>[
        LyricsWord(startMs: 0, endMs: 1000, text: '歌词'),
      ],
    ),
  ];
  final Map<String, LyricsData> data = <String, LyricsData>{'orig': orig};
  final Map<String, LyricsType> types = <String, LyricsType>{
    'orig': verbatim ? LyricsType.verbatim : LyricsType.lineByLine,
  };
  if (withTs) {
    data['ts'] = <LyricsLine>[
      LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: const <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 1000, text: '翻译'),
        ],
      ),
    ];
    types['ts'] = LyricsType.lineByLine;
  }
  if (withRoma) {
    data['roma'] = <LyricsLine>[
      LyricsLine(
        startMs: 0,
        endMs: 1000,
        words: const <LyricsWord>[
          LyricsWord(startMs: 0, endMs: 1000, text: 'roma'),
        ],
      ),
    ];
    types['roma'] = LyricsType.lineByLine;
  }
  return Lyrics(
    songInfo: songInfo,
    source: songInfo.source,
    data: data,
    types: types,
  );
}
