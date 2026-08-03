import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations_en.dart';
import 'package:lddc/src/core/i18n/l10n/app_localizations_zh.dart';
import 'package:lddc/src/shared/ui/error/app_error_presenter.dart';

void main() {
  group('AppErrorPresenter', () {
    test('uses Chinese localization', () {
      final AppError source = AppErrorMapper.fromException(
        const SocketException('connection lost'),
      );
      final AppErrorPresentation presentation =
          AppErrorPresenter.toPresentation(source, AppLocalizationsZh());

      expect(presentation.title, '错误');
      expect(presentation.message, '网络不可用，请检查连接。');
      expect(presentation.actionHint, '请检查网络后重试。');
    });

    test('uses English localization', () {
      final AppError source = AppErrorMapper.fromException(
        const LddcLyricsNotFoundException('not found'),
      );
      final AppErrorPresentation presentation =
          AppErrorPresenter.toPresentation(source, AppLocalizationsEn());

      expect(presentation.title, 'Warning');
      expect(presentation.message, 'No lyrics found.');
      expect(presentation.actionHint, isNull);
    });
  });
}
