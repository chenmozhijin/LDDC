import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';
import 'local_match_input_picker.dart';

typedef AndroidLyricsPersistenceFactory =
    LyricsSavePersistencePort Function(AndroidSafTreeToken tree);

typedef OpenLocalMatchSongInSearch =
    Future<void> Function(SongInfo songInfo, List<Source> preferredSources);

/// 本地匹配页面依赖门面。
///
/// feature 层只依赖这里声明的纯 Dart 端口和用例；文件选择、SAF、标签库、导航和
/// 歌词 API 等真实运行时能力都由 app 层注入。这样测试可以直接替换依赖，页面也
/// 不会因为平台插件初始化失败而拖垮业务状态。
class LocalMatchDependencies {
  const LocalMatchDependencies({
    required this.configRepository,
    required this.capability,
    required this.inputPicker,
    required this.desktopGetInfosUseCase,
    required this.androidGetInfosUseCase,
    required this.androidBatchUseCase,
    required this.localMatchUseCase,
    required this.androidTreePort,
    required this.androidFdPort,
    required this.androidContentPort,
    required this.pathOpener,
    required this.mediaGateway,
    required this.dragDropPort,
    required this.androidLyricsPersistenceFactory,
    required this.openInSearch,
  });

  final ConfigRepository configRepository;
  final AppCapability capability;
  final LocalMatchInputPicker inputPicker;
  final LocalMatchGetInfosUseCase desktopGetInfosUseCase;
  final AndroidSafLocalMatchGetInfosUseCase androidGetInfosUseCase;
  final AndroidSafLocalMatchBatchUseCase androidBatchUseCase;
  final LocalMatchUseCase localMatchUseCase;
  final AndroidSafTreePort androidTreePort;
  final AndroidSafFdPort androidFdPort;
  final AndroidSafContentPort androidContentPort;
  final AppPathOpener pathOpener;
  final LocalMatchMediaGateway mediaGateway;
  final DragDropPort dragDropPort;
  final AndroidLyricsPersistenceFactory androidLyricsPersistenceFactory;
  final OpenLocalMatchSongInSearch openInSearch;
}

final Provider<LocalMatchDependencies> localMatchDependenciesProvider =
    Provider<LocalMatchDependencies>((Ref ref) {
      throw StateError('LocalMatchDependencies 必须由 app 层或测试显式注入');
    }, dependencies: const []);
