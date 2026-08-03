import 'src/app/bootstrap/app_entrypoint.dart'
    if (dart.library.io) 'src/app/bootstrap/app_entrypoint_io.dart'
    as app_entrypoint;

@pragma('vm:entry-point')
Future<void> panelEmbeddedMain(List<String> args) {
  return app_entrypoint.runPanelEmbeddedEntrypoint(args);
}

Future<void> main(List<String> args) {
  return app_entrypoint.runAppEntrypoint(args);
}

Future<void> runHiddenDesktopServiceEntrypoint({required List<String> args}) {
  return app_entrypoint.runHiddenDesktopServiceEntrypoint(args: args);
}
