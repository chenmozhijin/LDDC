import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/android/saf/android_saf_fd_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('lddc/android_saf_fd');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AndroidSafFdAdapter', () {
    test('openReadOnlyFd 透传 uri 并解析 fd/nameHint', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{'fd': 12, 'nameHint': 'demo.flac'};
          });
      const AndroidSafFdAdapter adapter = AndroidSafFdAdapter();

      final AndroidSafOpenedFileDescriptor opened = await adapter
          .openReadOnlyFd('content://media/external/audio/media/12');

      expect(receivedCall?.method, 'openReadOnlyFd');
      expect(receivedCall?.arguments, <String, Object?>{
        'uri': 'content://media/external/audio/media/12',
      });
      expect(opened.fileDescriptor, 12);
      expect(opened.nameHint, 'demo.flac');
    });

    test('openReadWriteFd 透传 uri 并解析 fd/nameHint', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{'fd': 11, 'nameHint': 'demo.mp3'};
          });
      const AndroidSafFdAdapter adapter = AndroidSafFdAdapter();

      final AndroidSafOpenedFileDescriptor opened = await adapter
          .openReadWriteFd('content://media/external/audio/media/11');

      expect(receivedCall?.method, 'openReadWriteFd');
      expect(receivedCall?.arguments, <String, Object?>{
        'uri': 'content://media/external/audio/media/11',
      });
      expect(opened.fileDescriptor, 11);
      expect(opened.nameHint, 'demo.mp3');
    });

    test('openReadWriteFd 在返回缺少 fd 时抛出 StateError', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <String, Object?>{'nameHint': 'demo.mp3'};
          });
      const AndroidSafFdAdapter adapter = AndroidSafFdAdapter();

      await expectLater(
        adapter.openReadWriteFd('content://media/external/audio/media/11'),
        throwsA(isA<StateError>()),
      );
    });

    test('closeFd 透传 fd 参数', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return null;
          });
      const AndroidSafFdAdapter adapter = AndroidSafFdAdapter();

      await adapter.closeFd(29);

      expect(receivedCall?.method, 'closeFd');
      expect(receivedCall?.arguments, <String, Object?>{'fd': 29});
    });
  });
}
