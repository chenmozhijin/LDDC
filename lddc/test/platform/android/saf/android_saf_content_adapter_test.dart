import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/android/saf/android_saf_content_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('lddc/android_saf_content');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AndroidSafContentAdapter', () {
    test('readBytes 透传 uri 与 maxBytes', () async {
      MethodCall? receivedCall;
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return bytes;
          });
      const AndroidSafContentAdapter adapter = AndroidSafContentAdapter();

      final Uint8List actual = await adapter.readBytes(
        'content://doc/cue1',
        maxBytes: 1024,
      );

      expect(receivedCall?.method, 'readBytes');
      expect(receivedCall?.arguments, <String, Object?>{
        'uri': 'content://doc/cue1',
        'maxBytes': 1024,
      });
      expect(actual, bytes);
    });
  });
}
