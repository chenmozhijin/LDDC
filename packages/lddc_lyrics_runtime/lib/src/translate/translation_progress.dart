/// OpenAI 兼容接口的流式翻译进度。
///
/// Bing/Google 当前请求很快且没有逐行流式响应，本模型只服务 OpenAI
/// 兼容接口。UI 只读取数字状态，不把中文文案写进业务状态，避免后续本地化
/// 或页面布局调整时牵动翻译核心逻辑。
final class OpenAiTranslationProgress {
  const OpenAiTranslationProgress({
    required this.completedLines,
    required this.totalLines,
    required this.isIndeterminate,
  }) : assert(completedLines >= 0),
       assert(totalLines >= 0);

  /// 创建尚未收到首行响应的初始进度。
  ///
  /// 调用方只负责提供待翻译的原文行数，核心模型统一保证初始完成数为 0，
  /// 并使用不确定进度，避免 application 层反向依赖 UI helper。
  const OpenAiTranslationProgress.initial({required int totalLines})
    : this(completedLines: 0, totalLines: totalLines, isIndeterminate: true);

  /// 已完整收到并确认带有 `NN|` 行号前缀的译文行数。
  final int completedLines;

  /// 本次需要翻译的原文总行数。
  final int totalLines;

  /// 是否处于无法计算行级百分比的阶段。
  ///
  /// 例如流式连接尚未返回第一行，或当前平台/端点回落到普通 buffered 请求。
  final bool isIndeterminate;

  double? get value {
    if (isIndeterminate || totalLines <= 0) {
      return null;
    }
    return (completedLines / totalLines).clamp(0.0, 1.0);
  }
}

typedef OpenAiTranslationProgressCallback =
    void Function(OpenAiTranslationProgress progress);
