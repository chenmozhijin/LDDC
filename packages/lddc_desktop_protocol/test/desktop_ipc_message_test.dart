import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('DesktopIpcMessageCodec', () {
    const DesktopIpcMessageCodec codec = DesktopIpcMessageCodec();

    test('解析建连消息并保留客户端信息', () {
      final DesktopClientMessage message = codec.decodeClientMessage(
        <String, Object?>{
          'task': 'new_desktop_lyrics_instance',
          'pid': 2233,
          'available_tasks': <Object?>['play', 'pause', 'prev', null, ''],
          'info': <String, Object?>{
            'name': 'foo_lddc',
            'ver': '0.1.4',
            'channel': 'stable',
          },
        },
      );

      expect(message, isA<DesktopHelloMessage>());
      final DesktopHelloMessage hello = message as DesktopHelloMessage;
      expect(hello.pid, 2233);
      expect(hello.availableTaskNames, <String>['play', 'pause', 'prev']);
      expect(hello.availableControlTasks, <DesktopControlCommandTask>{
        DesktopControlCommandTask.play,
        DesktopControlCommandTask.pause,
        DesktopControlCommandTask.prev,
      });
      expect(hello.clientInfo.name, 'foo_lddc');
      expect(hello.clientInfo.version, '0.1.4');
      expect(hello.clientInfo.extra, <String, Object?>{'channel': 'stable'});
      expect(hello.supportsControlTask(DesktopControlCommandTask.prev), isTrue);
      expect(
        hello.supportsControlTask(DesktopControlCommandTask.next),
        isFalse,
      );
    });

    test('解析 chang_music 并保留原始 track 语义', () {
      final DesktopClientMessage message = codec
          .decodeClientMessage(<String, Object?>{
            'task': 'chang_music',
            'id': 7,
            'title': 'Song',
            'artist': 'Artist',
            'album': 'Album',
            'duration': 180000,
            'path': r'D:\music\song.flac',
            'track': 12,
            'playback_time': 3200,
            'send_time': 12.5,
          });

      expect(message, isA<DesktopChangMusicMessage>());
      final DesktopChangMusicMessage changMusic =
          message as DesktopChangMusicMessage;
      expect(changMusic.id, 7);
      expect(changMusic.title, 'Song');
      expect(changMusic.artist, 'Artist');
      expect(changMusic.album, 'Album');
      expect(changMusic.durationMs, 180000);
      expect(changMusic.path, r'D:\music\song.flac');
      expect(changMusic.track, 12);
      expect(changMusic.normalizedTrack, '12');
      expect(changMusic.playbackTimeMs, 3200);
      expect(changMusic.sendTimeSeconds, 12.5);
    });

    test('解析 create_panel 并保留宿主窗口句柄', () {
      final DesktopClientMessage message = codec.decodeClientMessage(
        <String, Object?>{
          'task': 'create_panel',
          'id': 5,
          'panel_id': 101,
          'host_window_id': 202,
        },
      );

      expect(message, isA<DesktopPanelCreateMessage>());
      final DesktopPanelCreateMessage createMessage =
          message as DesktopPanelCreateMessage;
      expect(createMessage.id, 5);
      expect(createMessage.panelId, 101);
      expect(createMessage.hostWindowId, 202);
      expect(createMessage.toJson(), <String, Object?>{
        'task': 'create_panel',
        'id': 5,
        'panel_id': 101,
        'host_window_id': 202,
      });
    });

    test('不再接受内部历史 bind_panel 任务名', () {
      expect(
        () => codec.decodeClientMessage(<String, Object?>{
          'task': 'bind_panel',
          'id': 5,
          'panel_id': 101,
          'host_window_id': 202,
        }),
        throwsFormatException,
      );
    });

    test('解析 update_panel_surface 并保留尺寸语义', () {
      final DesktopClientMessage message = codec
          .decodeClientMessage(<String, Object?>{
            'task': 'update_panel_surface',
            'id': 5,
            'panel_id': 101,
            'width': 640,
            'height': 320,
            'size_space': 'host_physical_px',
            'visible': true,
          });

      expect(message, isA<DesktopPanelSurfaceUpdateMessage>());
      final DesktopPanelSurfaceUpdateMessage updateMessage =
          message as DesktopPanelSurfaceUpdateMessage;
      expect(updateMessage.panelId, 101);
      expect(updateMessage.width, 640);
      expect(updateMessage.height, 320);
      expect(updateMessage.sizeSpace, DesktopPanelSizeSpace.hostPhysicalPx);
      expect(updateMessage.visible, isTrue);
      expect(updateMessage.toJson(), <String, Object?>{
        'task': 'update_panel_surface',
        'id': 5,
        'panel_id': 101,
        'width': 640,
        'height': 320,
        'size_space': 'host_physical_px',
        'visible': true,
      });
    });

    test('解析 destroy_panel', () {
      final DesktopClientMessage message = codec.decodeClientMessage(
        <String, Object?>{'task': 'destroy_panel', 'id': 5, 'panel_id': 101},
      );

      expect(message, isA<DesktopPanelDestroyMessage>());
      expect(
        (message as DesktopPanelDestroyMessage).toJson(),
        <String, Object?>{'task': 'destroy_panel', 'id': 5, 'panel_id': 101},
      );
    });

    test('服务端握手响应只接受 v 和 id', () {
      final DesktopInstanceAckMessage ack = codec.decodeInstanceAck(
        <String, Object?>{'v': 2, 'id': 4096},
      );

      expect(ack.apiVersion, 2);
      expect(ack.instanceId, 4096);
      expect(ack.toJson(), <String, Object?>{'v': 2, 'id': 4096});
    });

    test('有限整数型 double 可无损解析为协议整数', () {
      final DesktopInstanceAckMessage ack = codec.decodeInstanceAck(
        <String, Object?>{'v': 2.0, 'id': 4096.0},
      );

      expect(ack.apiVersion, 2);
      expect(ack.instanceId, 4096);
    });

    test('协议整数拒绝小数和非有限数值', () {
      for (final double invalidValue in <double>[
        1.5,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => codec.decodeInstanceAck(<String, Object?>{
            'v': invalidValue,
            'id': 1,
          }),
          throwsFormatException,
          reason: '非法整数值 $invalidValue 应在 IPC 边界被拒绝',
        );
      }
    });

    test('协议浮点字段拒绝非有限数值', () {
      for (final double invalidValue in <double>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => codec.decodeClientMessage(<String, Object?>{
            'task': 'sync',
            'id': 1,
            'send_time': invalidValue,
          }),
          throwsFormatException,
          reason: '非法浮点值 $invalidValue 应在 IPC 边界被拒绝',
        );
      }
    });

    test('解析服务端控制任务', () {
      final DesktopControlCommandMessage command = codec.decodeControlCommand(
        <String, Object?>{'task': 'next'},
      );

      expect(command.task, DesktopControlCommandTask.next);
      expect(command.toJson(), <String, Object?>{'task': 'next'});
    });

    test('不接受 change_music 别名', () {
      expect(
        () => codec.decodeClientMessage(<String, Object?>{
          'task': 'change_music',
          'id': 1,
        }),
        throwsFormatException,
      );
    });

    test('task 缺失时抛出异常', () {
      expect(
        () => codec.decodeClientMessage(<String, Object?>{'id': 1}),
        throwsFormatException,
      );
    });

    test('chang_music 的 duration 类型错误时抛出异常', () {
      expect(
        () => codec.decodeClientMessage(<String, Object?>{
          'task': 'chang_music',
          'id': 3,
          'duration': '180000',
        }),
        throwsFormatException,
      );
    });

    test('track 只允许 int 或 string', () {
      expect(
        () => codec.decodeClientMessage(<String, Object?>{
          'task': 'chang_music',
          'id': 3,
          'duration': 180000,
          'track': <int>[1, 2],
        }),
        throwsFormatException,
      );
    });

    test('面板宽高拒绝负值', () {
      for (final String key in <String>['width', 'height']) {
        final Map<String, Object?> payload = <String, Object?>{
          'task': 'update_panel_surface',
          'id': 5,
          'panel_id': 101,
          'width': 640,
          'height': 320,
          'size_space': 'host_physical_px',
          'visible': true,
          key: -1,
        };

        expect(
          () => codec.decodeClientMessage(payload),
          throwsFormatException,
          reason: '$key 不能为负数',
        );
      }
    });
  });
}
