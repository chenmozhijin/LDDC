import 'app_config.dart';

/// OpenAI 兼容接口预设的集中描述。
///
/// `OpenAiProfile` 只负责保存配置文件中的枚举值；不同供应商的默认地址、
/// 展示名称以及请求体私有字段都集中放在这里。这样新增供应商时只改这一处，
/// 设置页和请求执行器不会继续各自维护一份容易漏改的 switch。
class OpenAiProfileSpec {
  const OpenAiProfileSpec._({
    required this.profile,
    required this.label,
    required this.defaultBaseUrl,
    required this.providerLimitation,
  });

  final OpenAiProfile profile;
  final String label;
  final String defaultBaseUrl;
  final String providerLimitation;

  /// 非自定义预设选择后自动写入默认 Base URL。
  bool get shouldFillDefaultBaseUrl => defaultBaseUrl.isNotEmpty;

  static OpenAiProfileSpec of(OpenAiProfile profile) {
    return switch (profile) {
      OpenAiProfile.custom => const OpenAiProfileSpec._(
        profile: OpenAiProfile.custom,
        label: '自定义',
        defaultBaseUrl: '',
        providerLimitation: '自定义端点不会自动发送供应商私有字段。',
      ),
      OpenAiProfile.openRouter => const OpenAiProfileSpec._(
        profile: OpenAiProfile.openRouter,
        label: 'OpenRouter',
        defaultBaseUrl: 'https://openrouter.ai/api/v1',
        providerLimitation: '部分强制 reasoning 的模型可能无法禁用思考。',
      ),
      OpenAiProfile.siliconFlow => const OpenAiProfileSpec._(
        profile: OpenAiProfile.siliconFlow,
        label: 'SiliconFlow',
        defaultBaseUrl: 'https://api.siliconflow.cn/v1',
        providerLimitation: '通过 enable_thinking=false 禁用思考。',
      ),
      OpenAiProfile.deepSeek => const OpenAiProfileSpec._(
        profile: OpenAiProfile.deepSeek,
        label: 'DeepSeek',
        defaultBaseUrl: 'https://api.deepseek.com',
        providerLimitation: '通过 thinking.type=disabled 禁用思考。',
      ),
      OpenAiProfile.kimi => const OpenAiProfileSpec._(
        profile: OpenAiProfile.kimi,
        label: 'Kimi',
        defaultBaseUrl: 'https://api.moonshot.cn/v1',
        providerLimitation: '部分 Kimi 思考模型不支持 disabled，因此默认不发送 thinking 字段。',
      ),
    };
  }
}
