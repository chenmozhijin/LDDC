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
    required this.pathOpener,
    required this.dragDropPort,
    required this.openInOpenLyrics,
    required this.confirmOverwrite,
  });

  final AppCapability capability;
  final ConfigRepository configRepository;
  final BatchConvertInputPicker inputPicker;
  final BatchConvertUseCase useCase;
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
