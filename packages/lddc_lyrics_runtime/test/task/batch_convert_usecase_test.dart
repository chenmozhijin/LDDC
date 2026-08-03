import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as path;

void main() {
  group('BatchConvertUseCase', () {
    late BatchConvertUseCase useCase;

    setUp(() {
      useCase = BatchConvertUseCase(
        localProvider: createDefaultLocalLyricsProvider(),
      );
    });

    test('单条失败不会中断整批，且逐条日志可追踪', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-batch-convert-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String source1 = path.join(dir.path, 'a.lrc');
      final String source2 = path.join(dir.path, 'missing.unknown');
      final String source3 = path.join(dir.path, 'c.srt');
      await File(source1).writeAsString('[00:00.00]第一行');
      await File(
        source3,
      ).writeAsString('1\n00:00:00,000 --> 00:00:01,000\n第三行');

      final String output1 = path.join(dir.path, 'out', 'a.lrc');
      final String output2 = path.join(dir.path, 'out', 'b.lrc');
      final String output3 = path.join(dir.path, 'out', 'c.lrc');
      final List<BatchConvertProgress> progressEvents =
          <BatchConvertProgress>[];

      final BatchConvertResult result = await useCase.run(
        items: <BatchConvertItem>[
          BatchConvertItem(sourcePath: source1, targetPath: output1),
          BatchConvertItem(sourcePath: source2, targetPath: output2),
          BatchConvertItem(sourcePath: source3, targetPath: output3),
        ],
        targetFormat: LyricsFormat.lineByLineLrc,
        onProgress: progressEvents.add,
      );

      expect(result.successCount, 2);
      expect(result.failureCount, 1);
      expect(result.cancelled, isFalse);
      expect(result.logs.length, 3);
      expect(
        result.logs.map((BatchConvertLogEntry entry) => entry.status).toList(),
        <BatchConvertStatusType>[
          BatchConvertStatusType.success,
          BatchConvertStatusType.failure,
          BatchConvertStatusType.success,
        ],
      );
      expect(result.logs[1].error, isA<FileSystemException>());

      expect(File(output1).existsSync(), isTrue);
      expect(File(output2).existsSync(), isFalse);
      expect(File(output3).existsSync(), isTrue);
      expect(await File(output1).readAsString(), contains('['));
      expect(await File(output3).readAsString(), contains('['));

      expect(progressEvents.length, 4);
      expect(progressEvents[0].status, isNull);
      expect(progressEvents[0].value, 0);
      expect(progressEvents[0].maxValue, 3);
      expect(progressEvents[1].status?.index, 0);
      expect(progressEvents[1].status?.type, BatchConvertStatusType.success);
      expect(progressEvents[2].status?.index, 1);
      expect(progressEvents[2].status?.type, BatchConvertStatusType.failure);
      expect(
        progressEvents[3].message.code,
        BatchConvertProgressMessageCode.empty,
      );
      expect(progressEvents[3].status?.index, 2);
      expect(progressEvents[3].status?.type, BatchConvertStatusType.success);
    });

    test('取消后仅中断后续条目，不回滚已完成结果', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-batch-convert-cancel-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final List<String> sources = <String>[
        path.join(dir.path, '1.lrc'),
        path.join(dir.path, '2.lrc'),
        path.join(dir.path, '3.lrc'),
      ];
      for (final String source in sources) {
        await File(source).writeAsString('[00:00.00]取消测试');
      }

      final List<String> outputs = <String>[
        path.join(dir.path, 'out', '1.srt'),
        path.join(dir.path, 'out', '2.srt'),
        path.join(dir.path, 'out', '3.srt'),
      ];
      final BatchConvertCancellationToken token =
          BatchConvertCancellationToken();

      final BatchConvertResult result = await useCase.run(
        items: <BatchConvertItem>[
          for (int index = 0; index < sources.length; index += 1)
            BatchConvertItem(
              sourcePath: sources[index],
              targetPath: outputs[index],
            ),
        ],
        targetFormat: LyricsFormat.srt,
        cancellationToken: token,
        onProgress: (BatchConvertProgress progress) {
          if (progress.value == 1) {
            token.cancel();
          }
        },
      );

      expect(result.cancelled, isTrue);
      expect(result.successCount, 1);
      expect(result.failureCount, 0);
      expect(result.logs.length, 1);
      expect(File(outputs[0]).existsSync(), isTrue);
      expect(File(outputs[1]).existsSync(), isFalse);
      expect(File(outputs[2]).existsSync(), isFalse);
    });

    test('覆盖源文件必须由调用方显式确认', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-batch-convert-overwrite-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String source = path.join(dir.path, 'same.lrc');
      const String originalText = '[00:00.00]覆盖确认测试\n[00:01.00]第二行';
      await File(source).writeAsString(originalText);

      final BatchConvertResult refused = await useCase.run(
        items: <BatchConvertItem>[
          BatchConvertItem(sourcePath: source, targetPath: source),
        ],
        targetFormat: LyricsFormat.srt,
      );

      expect(refused.successCount, 0);
      expect(refused.failureCount, 1);
      expect(await File(source).readAsString(), originalText);

      final BatchConvertResult confirmed = await useCase.run(
        items: <BatchConvertItem>[
          BatchConvertItem(sourcePath: source, targetPath: source),
        ],
        targetFormat: LyricsFormat.srt,
        allowOverwrite: true,
      );

      expect(confirmed.successCount, 1);
      expect(confirmed.failureCount, 0);
      expect(await File(source).readAsString(), contains('-->'));
    });

    test('未知扩展名按 lrc->ass->srt 统一回退解析', () async {
      final Directory dir = await Directory.systemTemp.createTemp(
        'lddc-batch-convert-fallback-',
      );
      addTearDown(() async {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      });

      final String source = path.join(dir.path, 'demo.txt');
      final String output = path.join(dir.path, 'out', 'demo.lrc');
      await File(source).writeAsString('[00:00.00]未知扩展名歌词');

      final BatchConvertResult result = await useCase.run(
        items: <BatchConvertItem>[
          BatchConvertItem(sourcePath: source, targetPath: output),
        ],
        targetFormat: LyricsFormat.lineByLineLrc,
      );

      expect(result.successCount, 1);
      expect(result.failureCount, 0);
      expect(File(output).existsSync(), isTrue);
      expect(await File(output).readAsString(), contains('未知扩展名歌词'));
    });

    test('写盘期间取消仍记录当前成功，并使用启动时的任务快照', () async {
      final Completer<void> writeStarted = Completer<void>();
      final Completer<void> writeGate = Completer<void>();
      final _ControlledBatchConvertFileIo fileIo =
          _ControlledBatchConvertFileIo(
            writeStarted: writeStarted,
            writeGate: writeGate,
          );
      final BatchConvertUseCase controlledUseCase = BatchConvertUseCase(
        localProvider: createDefaultLocalLyricsProvider(),
        fileIo: fileIo,
      );
      final List<BatchConvertItem> items = <BatchConvertItem>[
        const BatchConvertItem(
          sourcePath: 'first.lrc',
          targetPath: 'first.srt',
        ),
        const BatchConvertItem(
          sourcePath: 'second.lrc',
          targetPath: 'second.srt',
        ),
      ];
      final BatchConvertCancellationToken token =
          BatchConvertCancellationToken();

      final Future<BatchConvertResult> pending = controlledUseCase.run(
        items: items,
        targetFormat: LyricsFormat.srt,
        cancellationToken: token,
      );
      await writeStarted.future;
      items.clear();
      token.cancel();
      writeGate.complete();
      final BatchConvertResult result = await pending;

      expect(result.cancelled, isTrue);
      expect(result.successCount, 1);
      expect(result.failureCount, 0);
      expect(result.logs, hasLength(1));
      expect(fileIo.writeTargets, <String>['first.srt']);
    });
  });
}

class _ControlledBatchConvertFileIo implements BatchConvertFileIo {
  _ControlledBatchConvertFileIo({
    required this.writeStarted,
    required this.writeGate,
  });

  final Completer<void> writeStarted;
  final Completer<void> writeGate;
  final List<String> writeTargets = <String>[];

  @override
  Future<Uint8List> readBytes(String path) async {
    return Uint8List.fromList(utf8.encode('[00:00.00]snapshot'));
  }

  @override
  Future<String> writeText({
    required String sourcePath,
    required String targetPath,
    required String text,
    required bool allowOverwrite,
  }) async {
    writeTargets.add(targetPath);
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
    }
    await writeGate.future;
    return targetPath;
  }
}
