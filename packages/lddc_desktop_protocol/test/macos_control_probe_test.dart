import 'dart:convert';
import 'dart:io';

import 'package:lddc_desktop_protocol/lddc_desktop_protocol.dart';
import 'package:test/test.dart';

import '../platform_test/support/macos_control_probe.dart';

void main() {
  test('macOS control endpoint 直接探针返回业务端口', () async {
    final Directory temporary = await Directory.systemTemp.createTemp(
      'lddc-control-probe-',
    );
    final ServerSocket server = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(() async {
      await server.close();
      await temporary.delete(recursive: true);
    });
    const String token =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final int servicePort = server.port == 43210 ? 43211 : 43210;
    final File controlFile = File(
      '${temporary.path}${Platform.pathSeparator}control.json',
    );
    await controlFile.writeAsString(
      jsonEncode(<String, Object?>{
        'schema': 'lddc.macos_singleton_control',
        'port': server.port,
        'token': token,
      }),
    );

    final Future<void> serverTask = (() async {
      final Socket socket = await server.first;
      final TestSocketFrameReader reader = TestSocketFrameReader(socket);
      try {
        final Map<String, Object?> request = await reader.nextFrame().timeout(
          const Duration(seconds: 5),
        );
        expect(request['_lddcControl'], 1);
        expect(request['token'], token);
        expect(request['command'], 'get_service_port');
        socket.add(
          const DesktopIpcFramer().encodeJson(<String, Object?>{
            '_lddcControl': 1,
            'ok': true,
            'port': servicePort,
          }),
        );
        await socket.flush();
      } finally {
        await reader.dispose();
      }
    })();

    final int probedPort = await probeMacOsControlEndpoint(controlFile);
    await serverTask;
    expect(probedPort, servicePort);
    expect(probedPort, isNot(server.port));
  });
}
