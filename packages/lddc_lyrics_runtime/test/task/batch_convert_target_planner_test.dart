import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _musicTreeUri = 'content://provider/tree/primary%3AMusic';

void main() {
  group('planBatchConvertTarget', () {
    test('本地源未选保存树时写到源文件所在目录', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: LocalFileSource(p.join('input', 'demo.ass')),
        targetFileName: 'demo.srt',
      );

      final BatchConvertTarget target = plan.target;
      expect(target, isA<LocalFileTarget>());
      expect((target as LocalFileTarget).path, p.join('input', 'demo.srt'));
      expect(plan.displayPath, p.join('input', 'demo.srt'));
    });

    test('本地源指定保存目录时写到该目录', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: LocalFileSource(p.join('input', 'demo.ass')),
        targetFileName: 'demo.srt',
        localSaveRootPath: p.join('out'),
      );

      expect((plan.target as LocalFileTarget).path, p.join('out', 'demo.srt'));
      expect(plan.displayPath, p.join('out', 'demo.srt'));
    });

    test('本地源（缓存副本）选定 SAF 树后平铺写到树根', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: LocalFileSource(
          p.join('/data', 'user', '0', 'com.cmzj.lddc', 'cache', 'demo.ass'),
        ),
        targetFileName: 'demo.srt',
        saveTreeUri: 'content://provider/tree/primary%3AMusic',
        saveTreeLabel: '内部存储',
      );

      final BatchConvertTarget target = plan.target;
      expect(target, isA<SafDocumentTarget>());
      final SafDocumentTarget safTarget = target as SafDocumentTarget;
      expect(
        safTarget.target.treeUri,
        'content://provider/tree/primary%3AMusic',
      );
      expect(safTarget.target.directorySegments, isEmpty);
      expect(safTarget.fileName, 'demo.srt');
      expect(plan.displayPath, '内部存储/demo.srt');
    });

    test('树内源镜像其相对目录（多层）', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: const SafDocumentSource(
          documentUri:
              'content://provider/tree/primary%3AMusic/document/primary%3AMusic%2FAlbum%2Fdisc%2Fa.lrc',
          treeUri: 'content://provider/tree/primary%3AMusic',
          treeLabel: '内部存储',
          displayPath: '内部存储/Album/disc/a.lrc',
        ),
        targetFileName: 'a.srt',
        saveTreeUri: 'content://provider/tree/primary%3AMusic',
        saveTreeLabel: '内部存储',
      );

      final SafDocumentTarget safTarget = plan.target as SafDocumentTarget;
      expect(safTarget.target.directorySegments, <String>['Album', 'disc']);
      expect(plan.displayPath, '内部存储/Album/disc/a.srt');
    });

    test('树根下的源平铺到树根', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: const SafDocumentSource(
          documentUri:
              'content://provider/tree/primary%3AMusic/document/primary%3AMusic%2Fa.lrc',
          treeUri: 'content://provider/tree/primary%3AMusic',
          treeLabel: '内部存储',
          displayPath: '内部存储/a.lrc',
        ),
        targetFileName: 'a.srt',
        saveTreeUri: 'content://provider/tree/primary%3AMusic',
        saveTreeLabel: '内部存储',
      );

      expect(
        (plan.target as SafDocumentTarget).target.directorySegments,
        isEmpty,
      );
    });

    test('SAF 源缺少保存树时直接报错，不静默退化', () {
      expect(
        () => planBatchConvertTarget(
          source: const SafDocumentSource(
            documentUri:
                'content://provider/tree/primary%3AMusic/document/primary%3AMusic%2Fa.lrc',
            treeUri: 'content://provider/tree/primary%3AMusic',
            treeLabel: '内部存储',
            displayPath: '内部存储/a.lrc',
          ),
          targetFileName: 'a.srt',
        ),
        throwsArgumentError,
      );
    });

    test('源在另一棵树时仍按源所在树的相对层级镜像到所选树', () {
      final BatchConvertTargetPlan plan = planBatchConvertTarget(
        source: const SafDocumentSource(
          documentUri:
              'content://provider/tree/primary%3ADownload/document/primary%3ADownload%2Fsub%2Fa.lrc',
          treeUri: 'content://provider/tree/primary%3ADownload',
          treeLabel: '下载',
          displayPath: '下载/sub/a.lrc',
        ),
        targetFileName: 'a.srt',
        saveTreeUri: _musicTreeUri,
        saveTreeLabel: '内部存储',
      );

      final SafDocumentTarget safTarget = plan.target as SafDocumentTarget;
      // 与本地匹配 mirror 同义：目标树 = 所选树，层级 = 源在自己树内的相对目录。
      expect(safTarget.target.treeUri, _musicTreeUri);
      expect(safTarget.target.directorySegments, <String>['sub']);
      expect(plan.displayPath, '内部存储/sub/a.srt');
    });

    test('源文档 URI 不可解析时直接报错', () {
      expect(
        () => planBatchConvertTarget(
          source: const SafDocumentSource(
            documentUri: 'C:/lyrics/a.lrc',
            treeUri: _musicTreeUri,
            treeLabel: '内部存储',
            displayPath: 'a.lrc',
          ),
          targetFileName: 'a.srt',
          saveTreeUri: _musicTreeUri,
          saveTreeLabel: '内部存储',
        ),
        throwsArgumentError,
      );
    });

    test('空文件名直接报错', () {
      expect(
        () => planBatchConvertTarget(
          source: LocalFileSource(p.join('input', 'demo.ass')),
          targetFileName: '   ',
        ),
        throwsArgumentError,
      );
    });
  });
}
