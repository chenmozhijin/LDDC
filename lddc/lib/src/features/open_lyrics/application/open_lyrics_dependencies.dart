import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'open_lyrics_file_reader.dart';
import 'open_lyrics_input_picker.dart';

class OpenLyricsDependencies {
  const OpenLyricsDependencies({
    required this.configRepository,
    required this.capability,
    required this.lyricsApi,
    required this.translateApi,
    required this.mediaGateway,
    required this.inputPicker,
    required this.fileReader,
    required this.dragDropPort,
  });

  final ConfigRepository configRepository;
  final AppCapability capability;
  final LyricsClient lyricsApi;
  final TranslationClient translateApi;
  final LocalMatchMediaGateway mediaGateway;
  final OpenLyricsInputPicker inputPicker;
  final OpenLyricsFileReader fileReader;
  final DragDropPort dragDropPort;
}

final Provider<OpenLyricsDependencies> openLyricsDependenciesProvider =
    Provider<OpenLyricsDependencies>((Ref ref) {
      throw StateError('OpenLyricsDependencies 必须由 app 层或测试显式注入');
    }, dependencies: const []);
