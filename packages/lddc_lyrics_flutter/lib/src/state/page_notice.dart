/// 页面一次性通知级别。
enum PageNoticeSeverity { info, success, warning, error }

/// 页面一次性通知。
///
/// [code] 是 feature 自己定义的语义码，UI 层根据当前 locale 渲染文案；[detail]
/// 仅承载异常细节或路径等参数。这样既能本地化，也不会把中文句子写进业务状态。
final class PageNotice<TCode> {
  const PageNotice({
    this.id = 0,
    this.severity = PageNoticeSeverity.info,
    required this.code,
    this.detail,
    this.count,
    this.totalCount,
    this.successCount,
    this.failureCount,
    this.skippedCount,
    this.extra,
  });

  final int id;
  final PageNoticeSeverity severity;
  final TCode code;
  final String? detail;
  final int? count;
  final int? totalCount;
  final int? successCount;
  final int? failureCount;
  final int? skippedCount;

  /// 少数页面需要携带结构化附加数据，例如本地匹配启动验证问题列表。
  /// 共享通知模型不理解具体类型，消费方按自己的 code 再读取并转换。
  final Object? extra;
}
