import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/platform/android/saf/android_saf_tree_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('lddc/android_saf_tree');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AndroidSafTreeAdapter', () {
    test('pickTree 返回 token', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'uri': 'content://tree/primary%3AMusic',
              'displayName': 'Music',
            };
          });
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();

      final AndroidSafTreeToken token = await adapter.pickTree(
        initialUri: 'content://tree/primary%3ADownload',
      );

      expect(receivedCall?.method, 'pickTree');
      expect(receivedCall?.arguments, <String, Object?>{
        'initialUri': 'content://tree/primary%3ADownload',
      });
      expect(token.uri, 'content://tree/primary%3AMusic');
      expect(token.displayName, 'Music');
    });

    test('pickTree 返回空结果时抛出异常', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async => null);
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();

      await expectLater(adapter.pickTree(), throwsA(isA<StateError>()));
    });

    test('persistTreePermission 透传 uri', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return null;
          });
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();

      await adapter.persistTreePermission('content://tree/primary%3AMusic');

      expect(receivedCall?.method, 'persistTreePermission');
      expect(receivedCall?.arguments, <String, Object?>{
        'uri': 'content://tree/primary%3AMusic',
      });
    });

    test('listPersistedTrees 解析列表', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            return <Object?>[
              <String, Object?>{
                'uri': 'content://tree/primary%3AMusic',
                'displayName': 'Music',
                'persistedTimeMs': 100,
                'readable': true,
                'writable': false,
              },
            ];
          });
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();

      final List<AndroidSafPersistedTree> trees = await adapter
          .listPersistedTrees();

      expect(trees, hasLength(1));
      expect(trees.single.uri, 'content://tree/primary%3AMusic');
      expect(trees.single.displayName, 'Music');
      expect(trees.single.persistedTimeMs, 100);
      expect(trees.single.readable, isTrue);
      expect(trees.single.writable, isFalse);
    });

    test('listChildrenPage 透传分页参数并解析目录子项', () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'entries': <Object?>[
                <String, Object?>{
                  'uri': 'content://doc/audio1',
                  'displayName': 'a.mp3',
                  'mimeType': 'audio/mpeg',
                  'isDirectory': false,
                  'isFile': true,
                  'sizeBytes': 1024,
                  'lastModifiedMs': 99,
                },
              ],
              'nextOffset': 128,
            };
          });
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();

      final AndroidSafTreePage page = await adapter.listChildrenPage(
        uri: 'content://tree/primary%3AMusic',
        offset: 0,
        limit: 128,
      );

      expect(receivedCall?.method, 'listChildrenPage');
      expect(receivedCall?.arguments, <String, Object?>{
        'uri': 'content://tree/primary%3AMusic',
        'offset': 0,
        'limit': 128,
      });
      final List<AndroidSafTreeEntry> entries = page.entries;
      expect(entries, hasLength(1));
      expect(entries.single.uri, 'content://doc/audio1');
      expect(entries.single.displayName, 'a.mp3');
      expect(entries.single.isFile, isTrue);
      expect(entries.single.isDirectory, isFalse);
      expect(entries.single.sizeBytes, 1024);
      expect(entries.single.lastModifiedMs, 99);
      expect(page.nextOffset, 128);
    });

    test('writeDocument 一次性透传定位、创建和写入参数', () async {
      MethodCall? receivedCall;
      const AndroidSafTreeAdapter adapter = AndroidSafTreeAdapter();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            receivedCall = call;
            return <String, Object?>{
              'uri': 'content://doc/song-1.lrc',
              'displayName': 'song-1.lrc',
            };
          });

      final AndroidSafWriteDocumentResult result = await adapter.writeDocument(
        treeUri: 'content://tree/primary%3AMusic',
        displayName: 'song-1.lrc',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(result.uri, 'content://doc/song-1.lrc');
      expect(result.displayName, 'song-1.lrc');
      expect(receivedCall?.method, 'writeDocument');
      final Map<Object?, Object?> arguments =
          receivedCall?.arguments as Map<Object?, Object?>;
      expect(arguments['treeUri'], 'content://tree/primary%3AMusic');
      expect(arguments['displayName'], 'song-1.lrc');
      expect(arguments['mimeType'], 'text/plain');
      expect(arguments.containsKey('overwritePolicy'), isFalse);
      expect(arguments['bytes'], isA<Uint8List>());
    });
  });
}
