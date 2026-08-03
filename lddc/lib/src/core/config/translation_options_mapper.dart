import 'app_config.dart';

/// 将宿主配置映射为共享翻译运行时的能力级配置。
extension TranslationOptionsMapper on AppConfig {
  TranslationOptions toTranslationOptions() {
    return TranslationOptions(
      source: translate.source,
      targetLang: translate.targetLang,
      openAi: translate.openAi,
    );
  }
}
