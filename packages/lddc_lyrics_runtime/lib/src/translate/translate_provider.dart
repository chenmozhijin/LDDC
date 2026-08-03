import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'translation_options.dart';
import 'translation_progress.dart';

/// 翻译 provider 端口，对齐Python版 `BaseTranslator` 能力边界。
abstract interface class TranslateProvider {
  /// 当前 provider 对应的翻译源。
  TranslateSource get source;

  /// 当前配置下是否可用（如 OpenAI 需校验密钥/模型/地址）。
  bool isAvailable(TranslationOptions options) => true;

  /// 执行歌词翻译，返回目标语言歌词数据（通常为 `ts`）。
  Future<LyricsData> translateLyrics(
    Lyrics lyrics, {
    required TranslationOptions options,
  });
}

/// OpenAI 兼容翻译源的可选进度能力。
///
/// 行级流式进度是 OpenAI 兼容接口的私有能力，不能挂在通用翻译端口上，
/// 否则 Bing/Google 等 provider 会被迫携带永远不会使用的参数。
abstract interface class OpenAiProgressTranslateProvider
    implements TranslateProvider {
  Future<LyricsData> translateLyricsWithProgress(
    Lyrics lyrics, {
    required TranslationOptions options,
    OpenAiTranslationProgressCallback? onOpenAiProgress,
  });
}

/// 可释放资源的翻译 provider。
///
/// 只有真实 HTTP provider 需要实现关闭逻辑；测试替身和纯内存 provider 可继续
/// 继承基类的 no-op 实现。
abstract interface class ClosableTranslateProvider {
  Future<void> close();
}

/// 翻译 provider 基类：沉淀Python版 `models.py` 的共用工具方法。
abstract class BaseTranslateProvider
    implements TranslateProvider, ClosableTranslateProvider {
  @override
  bool isAvailable(TranslationOptions options) => true;

  @override
  Future<void> close() async {}

  /// 提取原文每行纯文本，顺序对齐 `orig` 行序。
  List<String> getOrigLines(Lyrics lyrics) {
    final LyricsData? origData = lyrics['orig'];
    if (origData == null) {
      return const <String>[];
    }
    return origData
        .map<String>((LyricsLine line) => line.words.map((e) => e.text).join())
        .toList(growable: false);
  }

  /// 将翻译后的文本行回填为 `LyricsData`，并继承原文时间轴。
  LyricsData textsToData(List<String> texts, Lyrics lyrics) {
    final LyricsData origData = lyrics['orig'] ?? const <LyricsLine>[];
    if (texts.length != origData.length) {
      throw LddcTranslateException('翻译结果行数与原文不一致');
    }

    final List<LyricsLine> translated = <LyricsLine>[];
    for (int index = 0; index < origData.length; index += 1) {
      final LyricsLine origLine = origData[index];
      translated.add(
        LyricsLine(
          startMs: origLine.startMs,
          endMs: origLine.endMs,
          words: <LyricsWord>[
            LyricsWord(
              startMs: origLine.startMs,
              endMs: origLine.endMs,
              text: texts[index],
            ),
          ],
        ),
      );
    }
    return translated;
  }
}
