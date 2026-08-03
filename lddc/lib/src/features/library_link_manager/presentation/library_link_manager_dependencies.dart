import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../../core/library_link/library_link.dart';
import '../application/library_link_manager_usecase.dart';

class LibraryLinkManagerDependencies {
  const LibraryLinkManagerDependencies({
    required this.repository,
    required this.filePicker,
    required this.useCase,
    required this.returnToSettings,
  });

  final LibraryLinkRepository repository;
  final AppFilePicker filePicker;
  final LibraryLinkManagerUseCase useCase;
  final VoidCallbackAsync returnToSettings;
}

typedef VoidCallbackAsync = Future<void> Function();

/// 关联库管理页的数据仓储、文件选择与导航回调由 app 层注入。
final Provider<LibraryLinkManagerDependencies>
libraryLinkManagerDependenciesProvider =
    Provider<LibraryLinkManagerDependencies>((Ref ref) {
      throw StateError('LibraryLinkManagerDependencies 必须由 app 层或测试显式注入');
    }, dependencies: const []);
