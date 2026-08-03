import 'web_capability_probe.dart';

Future<WebCapabilitySnapshot> probeWebCapabilities() async {
  return const WebCapabilitySnapshot(
    fileSystemAccess: false,
    taglibWasmReady: false,
  );
}
