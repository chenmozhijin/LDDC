import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

final class BatchConvertOutputPathResolver {
  const BatchConvertOutputPathResolver._();

  static String resolve({
    required String sourcePath,
    required LyricsFormat targetFormat,
    String? saveRootPath,
  }) {
    return LyricsSavePlanner.planBatchConvert(
      sourcePath: sourcePath,
      targetFormat: targetFormat,
      saveRootPath: saveRootPath,
    ).displayPath;
  }
}
