import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'batch_convert_input_picker.dart';
import 'batch_convert_overwrite_summary.dart';

class BatchConvertDependencies {
  const BatchConvertDependencies({
    required this.capability,
    required this.configRepository,
    required this.inputPicker,
    required this.useCase,
    required this.fileIo,
    required this.pathOpener,
    required this.dragDropPort,
    required this.openInOpenLyrics,
    required this.confirmOverwrite,
  });

  final AppCapability capability;
  final ConfigRepository configRepository;
  final BatchConvertInputPicker inputPicker;
  final BatchConvertUseCase useCase;

  /// 覆盖预检用的文件 IO。
  ///
  /// 必须与 [useCase] 使用同一份实现：安卓端 SAF 目标的"是否已存在"只能由
  /// SAF IO 枚举授权树得出，本地 IO 会直接抛 UnsupportedError。
  final BatchConvertFileIo fileIo;
  final AppPathOpener pathOpener;
  final DragDropPort dragDropPort;
  final Future<void> Function(String lyricsPath) openInOpenLyrics;
  final Future<bool> Function(BatchConvertOverwriteSummary summary)
  confirmOverwrite;
}

final Provider<BatchConvertDependencies> batchConvertDependenciesProvider =
    Provider<BatchConvertDependencies>((Ref ref) {
      throw StateError('BatchConvertDependencies 必须由 app 层或测试显式注入');
    }, dependencies: const []);
