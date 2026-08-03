import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

import '../../../core/capability/capability.dart';
import '../../../core/config/config.dart';

/// 将 LDDC 配置映射为共享搜索工作流的能力级快照。
extension SearchWorkflowAppConfigMapper on AppConfig {
  SearchWorkflowOptions toSearchWorkflowOptions() {
    final List<Source> sources = <Source>[];
    for (final String value in search.sources) {
      try {
        final Source source = Source.fromValue(value);
        if (!sources.contains(source)) {
          sources.add(source);
        }
      } on ArgumentError {
        // 未知来源由配置迁移层保留；共享控制器只接收可执行来源。
      }
    }
    return SearchWorkflowOptions(
      defaultSaveDirectory: storage.defaultSavePath,
      fileNameFormat: lyrics.fileNameFormat,
      id3Version: lyrics.id3Version,
      autoSelect: match.autoSelect,
      translationSource: translate.source,
      searchSources: sources,
      convertOptions: toLyricsConvertOptions(),
      skipInstrumental: match.skipInst,
    );
  }
}

/// 将 LDDC 平台能力矩阵裁剪为搜索表面真正使用的三项能力。
extension SearchWorkflowAppCapabilityMapper on AppCapability {
  SearchWorkflowCapabilities toSearchWorkflowCapabilities() {
    return SearchWorkflowCapabilities(
      multiWindow: multiWindow,
      androidSafTreeAccess: androidSafTreeAccess,
      audioTagWrite: audioTagWrite,
    );
  }
}
