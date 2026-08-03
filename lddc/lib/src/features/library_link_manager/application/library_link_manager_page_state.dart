import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import '../../../core/library_link/library_link.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

enum LibraryLinkManagerNoticeCode {
  loadFailed,
  deleteSelectedSuccess,
  deleteAllSuccess,
  clearInvalidSuccess,
  changeDirectorySuccess,
  backupSuccess,
  restoreSuccess,
  exportSuccess,
  operationFailed,
}

typedef LibraryLinkManagerNotice = PageNotice<LibraryLinkManagerNoticeCode>;

extension LibraryLinkManagerNoticePath on LibraryLinkManagerNotice {
  String? get path {
    final Object? value = extra;
    return value is String ? value : null;
  }
}

class LibraryLinkManagerPageState {
  const LibraryLinkManagerPageState({
    required this.loading,
    required this.busy,
    required this.totalCount,
    required this.searchText,
    required this.selectedIds,
    required this.loadedChunks,
    this.notice,
  });

  factory LibraryLinkManagerPageState.initial() {
    return const LibraryLinkManagerPageState(
      loading: true,
      busy: false,
      totalCount: 0,
      searchText: '',
      selectedIds: <int>{},
      loadedChunks: <int, List<LibraryLinkItem>>{},
    );
  }

  final bool loading;
  final bool busy;
  final int totalCount;
  final String searchText;
  final Set<int> selectedIds;
  final Map<int, List<LibraryLinkItem>> loadedChunks;
  final LibraryLinkManagerNotice? notice;

  int get selectedCount => selectedIds.length;
  bool get hasItems => totalCount > 0;

  LibraryLinkItem? itemAt(int index, {required int chunkSize}) {
    final int chunkIndex = index ~/ chunkSize;
    final List<LibraryLinkItem>? chunk = loadedChunks[chunkIndex];
    if (chunk == null) {
      return null;
    }
    final int localIndex = index - (chunkIndex * chunkSize);
    if (localIndex < 0 || localIndex >= chunk.length) {
      return null;
    }
    return chunk[localIndex];
  }

  LibraryLinkManagerPageState copyWith({
    bool? loading,
    bool? busy,
    int? totalCount,
    String? searchText,
    Set<int>? selectedIds,
    Map<int, List<LibraryLinkItem>>? loadedChunks,
    LibraryLinkManagerNotice? notice,
    bool clearNotice = false,
  }) {
    return LibraryLinkManagerPageState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      totalCount: totalCount ?? this.totalCount,
      searchText: searchText ?? this.searchText,
      selectedIds: selectedIds ?? this.selectedIds,
      loadedChunks: loadedChunks ?? this.loadedChunks,
      notice: clearNotice ? null : (notice ?? this.notice),
    );
  }
}

class LibraryLinkManagerRestoreFile {
  const LibraryLinkManagerRestoreFile(this.handle);

  final PickedFileHandle handle;
}
