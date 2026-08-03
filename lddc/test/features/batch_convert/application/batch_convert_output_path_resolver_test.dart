import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/features/batch_convert/application/batch_convert_output_path_resolver.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:path/path.dart' as p;

void main() {
  test('批量转换默认写到源文件目录并替换扩展名', () {
    final String source = p.join('music', 'album', 'song.srt');

    final String output = BatchConvertOutputPathResolver.resolve(
      sourcePath: source,
      targetFormat: LyricsFormat.lineByLineLrc,
    );

    expect(output, p.normalize(p.join('music', 'album', 'song.lrc')));
  });

  test('批量转换优先使用显式保存目录', () {
    final String output = BatchConvertOutputPathResolver.resolve(
      sourcePath: p.join('music', 'song.ass'),
      targetFormat: LyricsFormat.srt,
      saveRootPath: p.join('exports', 'lyrics'),
    );

    expect(output, p.normalize(p.join('exports', 'lyrics', 'song.srt')));
  });

  test('批量转换缺少源路径时返回空展示路径', () {
    final String output = BatchConvertOutputPathResolver.resolve(
      sourcePath: '  ',
      targetFormat: LyricsFormat.srt,
    );

    expect(output, isEmpty);
  });
}
