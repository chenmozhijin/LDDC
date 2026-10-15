import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('lyricsMimeTypeForName', () {
    test('已知歌词扩展名给出不带异种规范扩展名的 MIME', () {
      // 真机证据（Redmi K50 / Android 14）：`.lrc` 曾经报成 `text/plain`，原生
      // `createDocument` 按 MIME 的规范扩展名 `.txt` 把**新建**目标写成 `c.lrc.txt`
      // （已存在同名文件走覆盖分支不受影响）。所以这里逐条钉住映射结果。
      expect(lyricsMimeTypeForName('a.lrc'), 'application/x-lrc');
      expect(lyricsMimeTypeForName('a.srt'), 'application/x-subrip');
      expect(lyricsMimeTypeForName('a.ass'), 'text/x-ssa');
      expect(lyricsMimeTypeForName('a.ssa'), 'text/x-ssa');
      expect(lyricsMimeTypeForName('a.json'), 'application/json');
      // 规范扩展名与目标一致的类型可以继续使用。
      expect(lyricsMimeTypeForName('a.txt'), 'text/plain');
    });

    test('未知扩展名给自定义类型，避免系统追加扩展名', () {
      expect(lyricsMimeTypeForName('a.unknown'), 'application/x-lddc-lyrics');
      expect(lyricsMimeTypeForName('noext'), 'application/x-lddc-lyrics');
    });

    test('扩展名大小写不敏感', () {
      expect(lyricsMimeTypeForName('A.LRC'), 'application/x-lrc');
      expect(lyricsMimeTypeForName('A.Srt'), 'application/x-subrip');
    });
  });
}
