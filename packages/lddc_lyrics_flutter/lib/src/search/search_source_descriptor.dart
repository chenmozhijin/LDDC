import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import '../ui/search_ui_strings.dart';

/// 搜索页可展示来源的集中描述。
///
/// 搜索工具条、结果来源标签和测试都从这里取来源顺序与显示名，避免新增或下线
/// 来源时在多个 presentation 文件里同步修改。这里不直接读取 provider registry，
/// 因为 `multi` 是 UI 聚合入口而不是远端 provider；真实搜索范围仍由 controller
/// 根据配置和来源能力解析。
class SearchSourceDescriptor {
  const SearchSourceDescriptor({required this.source});

  final Source source;

  String label(SearchUiStrings strings) => strings.sourceLabel(source);

  String get diagnosticLabel {
    return switch (source) {
      Source.multi => '聚合',
      Source.qm => 'QQ音乐',
      Source.kg => '酷狗音乐',
      Source.ne => '网易云音乐',
      Source.lrclib => 'LRCLIB',
      Source.local => '本地',
    };
  }
}

const List<SearchSourceDescriptor> kSearchToolbarSourceDescriptors =
    <SearchSourceDescriptor>[
      SearchSourceDescriptor(source: Source.multi),
      SearchSourceDescriptor(source: Source.qm),
      SearchSourceDescriptor(source: Source.kg),
      SearchSourceDescriptor(source: Source.ne),
      SearchSourceDescriptor(source: Source.lrclib),
    ];

String searchSourceDiagnosticLabel(Source source) {
  for (final SearchSourceDescriptor descriptor
      in kSearchToolbarSourceDescriptors) {
    if (descriptor.source == source) {
      return descriptor.diagnosticLabel;
    }
  }
  return SearchSourceDescriptor(source: source).diagnosticLabel;
}
