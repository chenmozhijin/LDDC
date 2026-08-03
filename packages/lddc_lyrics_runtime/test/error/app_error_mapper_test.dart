import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

void main() {
  group('AppErrorCode metadata', () {
    test('所有错误码都有单一元数据入口', () {
      for (final AppErrorCode code in AppErrorCode.values) {
        expect(code.value, isNotEmpty);
        expect(tryParseAppErrorCode(code.value), code);
      }
    });

    test('IPC 输入只接受明确允许的协议码', () {
      expect(
        tryParseIpcAppErrorCode(AppErrorCode.ipcPanelNotFound.value),
        AppErrorCode.ipcPanelNotFound,
      );
      expect(
        tryParseIpcAppErrorCode(AppErrorCode.apiRequestFailed.value),
        null,
      );
    });
  });

  group('AppErrorMapper', () {
    test('maps structured lddc exception', () {
      final AppError appError = AppErrorMapper.fromException(
        const LddcLyricsNotFoundException(
          '没有找到歌词: test',
          context: <String, Object?>{'source': 'QM'},
        ),
      );

      expect(appError.code, AppErrorCode.lyricsNotFound);
      expect(appError.severity, AppErrorSeverity.warning);
      expect(appError.message, '没有找到歌词: test');
      expect(appError.context['source'], 'QM');
    });

    test('maps timeout exception', () {
      final AppError appError = AppErrorMapper.fromException(
        TimeoutException('自动获取超时'),
      );

      expect(appError.code, AppErrorCode.operationTimeout);
      expect(appError.message, '自动获取超时');
    });

    test('ordinary text is not classified by contains fallback', () {
      final AppError jsonText = AppErrorMapper.fromException(
        Exception('日志里提到 JSON 但不是 JSON 解析失败'),
      );
      final AppError lyricsText = AppErrorMapper.fromException(
        Exception('没有找到歌词字段说明'),
      );

      expect(jsonText.code, AppErrorCode.unknown);
      expect(lyricsText.code, AppErrorCode.unknown);
    });

    test('maps filesystem exception', () {
      final AppError appError = AppErrorMapper.fromException(
        const FileSystemException('write failed', 'C:/demo.txt'),
      );

      expect(appError.code, AppErrorCode.ioFailure);
      expect(appError.detail, 'C:/demo.txt');
    });

    test('maps filesystem access denied to permission error', () {
      final AppError appError = AppErrorMapper.fromException(
        const FileSystemException(
          'access denied',
          'C:/protected.txt',
          OSError('Access is denied', 5),
        ),
      );

      expect(appError.code, AppErrorCode.permissionDenied);
      expect(appError.detail, 'C:/protected.txt');
    });

    test(
      'FormatException defaults to invalid payload instead of JSON text',
      () {
        final FormatException error = const FormatException(
          '字段格式错误',
          'token=secret-value',
          6,
        );
        final AppError appError = AppErrorMapper.fromException(error);

        expect(appError.code, AppErrorCode.invalidPayload);
        expect(appError.detail, isNull);
        expect(appError.context['offset'], 6);
        expect(appError.context['sourceType'], 'String');
        expect(appError.cause, same(error));
      },
    );

    test('maps ipc protocol codes through metadata', () {
      final AppError appError = AppErrorMapper.fromIpcProtocolCode(
        protocolCode: 'E_PANEL_NOT_FOUND',
        message: 'panel 7 not found',
      );
      final AppError unknown = AppErrorMapper.fromIpcProtocolCode(
        protocolCode: 'E_API_REQUEST',
        message: 'not accepted by ipc',
      );

      expect(appError.code, AppErrorCode.ipcPanelNotFound);
      expect(appError.severity, AppErrorSeverity.warning);
      expect(unknown.code, AppErrorCode.unknown);
      expect(unknown.context['protocolCode'], 'E_API_REQUEST');
    });

    test('aggregated auto fetch errors keep typed causes', () {
      final LddcAutoFetchUnknownException error = LddcAutoFetchUnknownException(
        '自动获取时发生未知错误',
        causes: const <AppFailureCause>[
          AppFailureCause(error: LddcApiRequestException('source failed')),
        ],
      );
      final AppError appError = AppErrorMapper.fromException(error);

      expect(appError.code, AppErrorCode.autoFetchUnknown);
      expect(error.causes, hasLength(1));
      expect(appError.detail, contains('source failed'));
    });
  });
}
