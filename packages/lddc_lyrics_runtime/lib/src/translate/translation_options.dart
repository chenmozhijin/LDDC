/// 翻译服务源。
enum TranslateSource {
  bing('BING'),
  google('GOOGLE'),
  openai('OPENAI');

  const TranslateSource(this.value);

  final String value;
}

/// 翻译目标语言。
enum TranslateTargetLang {
  simplifiedChinese('SIMPLIFIED_CHINESE'),
  traditionalChinese('TRADITIONAL_CHINESE'),
  english('ENGLISH'),
  japanese('JAPANESE'),
  korean('KOREAN'),
  spanish('SPANISH'),
  french('FRENCH'),
  portuguese('PORTUGUESE'),
  german('GERMAN'),
  russian('RUSSIAN');

  const TranslateTargetLang(this.value);

  final String value;
}

/// OpenAI 兼容接口预设。
enum OpenAiProfile {
  custom('CUSTOM'),
  openRouter('OPENROUTER'),
  siliconFlow('SILICONFLOW'),
  deepSeek('DEEPSEEK'),
  kimi('KIMI');

  const OpenAiProfile(this.value);

  final String value;
}

/// OpenAI 兼容接口配置。
final class OpenAiConfig {
  const OpenAiConfig({
    required this.profile,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final OpenAiProfile profile;
  final String baseUrl;
  final String apiKey;
  final String model;
}

/// 单次翻译能力使用的独立配置。
final class TranslationOptions {
  const TranslationOptions({
    required this.source,
    required this.targetLang,
    required this.openAi,
  });

  final TranslateSource source;
  final TranslateTargetLang targetLang;
  final OpenAiConfig openAi;
}

typedef TranslationOptionsResolver = TranslationOptions Function();
