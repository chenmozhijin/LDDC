import '../../translate/translate.dart';
import '../../network/request_budget.dart';
import 'bing_translate_provider.dart';
import 'google_translate_provider.dart';
import 'google_request_executor.dart';
import 'bing_request_executor.dart';
import 'openai_request_executor.dart';
import 'openai_translate_provider.dart';
import 'translate_runtime_cache.dart';

/// 注册默认翻译 provider 集合。
void registerDefaultTranslateProviders(
  TranslateRegistry registry, {
  required TranslateRuntimeCache cache,
  NetworkRequestBudget budget = kDefaultTranslateRequestBudget,
}) {
  final BingRequestExecutorImpl bingExecutor = BingRequestExecutorImpl(
    timeout: budget.timeout,
  );
  final GoogleRequestExecutorImpl googleExecutor = GoogleRequestExecutorImpl(
    timeout: budget.timeout,
  );
  final OpenAiRequestExecutorImpl openAiExecutor = OpenAiRequestExecutorImpl(
    timeout: budget.timeout,
  );
  registry.registerProviders(<TranslateProvider>[
    BingTranslateProvider(
      cache: cache,
      requestExecutor: bingExecutor.execute,
      close: bingExecutor.close,
    ),
    GoogleTranslateProvider(
      cache: cache,
      requestExecutor: googleExecutor.execute,
      close: googleExecutor.close,
    ),
    OpenAiTranslateProvider(
      cache: cache,
      requestExecutor: openAiExecutor.execute,
      close: openAiExecutor.close,
    ),
  ]);
}
