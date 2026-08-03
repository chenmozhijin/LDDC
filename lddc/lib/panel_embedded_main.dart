import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/bootstrap/app_bootstrap.dart';
import 'src/app/desktop/desktop_app.dart';
import 'src/core/logging/logging.dart';
import 'package:lddc_desktop_lyrics/lddc_desktop_lyrics.dart';
import 'src/platform/desktop/window/embedded_panel_channel.dart';

final AppLogger _panelEmbeddedLogger = AppLogger.scope('panel-embedded-main');

Future<void> runPanelEmbeddedMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppBootstrap.ensureCorePortsRegistered();
  final DesktopEmbeddedPanelLaunchPayload payload =
      DesktopEmbeddedPanelLaunchPayload.fromEntrypointArgs(args);
  await AppLogRuntime.initialize(
    role: 'panel',
    instanceId: payload.instanceId,
    panelId: payload.panelId,
  );
  await DesktopEmbeddedPanelRuntime.instance.ensureInitialized(
    payload: payload,
    channel: EmbeddedPanelMethodChannel(payload.channelName),
    logger: _panelEmbeddedLogger.toDesktopLyricsLogger(),
  );
  await AppBootstrap.ensureInitialized();
  AppLogRuntime.updateLevel(AppBootstrap.config.app.logLevel);
  _panelEmbeddedLogger.info(
    'launch embedded panel app'
    ' instance=${payload.instanceId}'
    ' panel=${payload.panelId}'
    ' generation=${payload.generation}'
    ' host=${payload.hostWindowId}',
  );
  runApp(
    ProviderScope(
      child: LddcLightweightDesktopSubWindowApp(
        windowLaunch: DesktopEmbeddedPanelRuntime.instance.windowLaunch,
        config: AppBootstrap.config,
      ),
    ),
  );
}
