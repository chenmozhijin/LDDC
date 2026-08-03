import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';

import 'translation_progress.dart';

/// 歌词翻译的能力级公共契约。
///
/// 配置解析、来源初始化、重试和进度转发由默认 TranslateApi 实现唯一负责，
/// Flutter 控制器只面向此契约调用，不需要感知 registry 或宿主配置仓储。
abstract interface class TranslationClient {
  Future<void> init();

  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  });

  /// 幂等释放 provider、HTTP 客户端和当前客户端独占的翻译缓存。
  Future<void> close();
}
