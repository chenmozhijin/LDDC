import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'package:test/test.dart';

void main() {
  test('拖放条目按歌曲、文件和目录保留稳定业务分类', () {
    final DragDropSongDescriptor song = DragDropSongDescriptor(
      path: 'song.flac',
      track: '03',
      index: '2',
    );
    final DragDropItemDescriptor songItem = DragDropItemDescriptor.song(song);
    final DragDropItemDescriptor fileItem = DragDropItemDescriptor.file(
      'lyrics.lrc',
    );
    final DragDropItemDescriptor directoryItem =
        DragDropItemDescriptor.directory('album');

    expect(songItem.kind, DragDropItemKind.songInfoLike);
    expect(songItem.path, 'song.flac');
    expect(songItem.song, same(song));
    expect(songItem.song?.track, '03');
    expect(songItem.song?.index, '2');
    expect(fileItem.kind, DragDropItemKind.localFile);
    expect(fileItem.song, isNull);
    expect(directoryItem.kind, DragDropItemKind.directory);
    expect(directoryItem.song, isNull);
  });

  test('空白路径在任何拖放条目入口都会被拒绝', () {
    expect(() => DragDropSongDescriptor(path: '   '), throwsArgumentError);
    expect(() => DragDropItemDescriptor.file(''), throwsArgumentError);
    expect(() => DragDropItemDescriptor.directory('\t'), throwsArgumentError);
  });

  test('拖放解析结果冻结输入集合并准确报告是否有条目', () {
    final List<DragDropItemDescriptor> items = <DragDropItemDescriptor>[
      DragDropItemDescriptor.file('song.flac'),
    ];
    final Set<String> formats = <String>{'text/uri-list'};
    final DragDropParseResult result = DragDropParseResult(
      items: items,
      platformFormats: formats,
      failure: DragDropFailure.unreadablePrivateMime,
    );
    items.clear();
    formats.clear();

    expect(result.hasItems, isTrue);
    expect(result.items.single.path, 'song.flac');
    expect(result.platformFormats, <String>{'text/uri-list'});
    expect(result.failure, DragDropFailure.unreadablePrivateMime);
    expect(() => result.items.clear(), throwsUnsupportedError);
    expect(() => result.platformFormats.clear(), throwsUnsupportedError);
    expect(
      DragDropParseResult(
        items: const <DragDropItemDescriptor>[],
        platformFormats: const <String>{},
      ).hasItems,
      isFalse,
    );
    expect(const UnsupportedDragDropPort(), isA<DragDropPort>());
  });
}
