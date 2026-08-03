import 'web_capability_probe_stub.dart'
    if (dart.library.js_interop) 'web_capability_probe_web.dart'
    as impl;

class WebCapabilitySnapshot {
  const WebCapabilitySnapshot({
    required this.fileSystemAccess,
    required this.taglibWasmReady,
  });

  final bool fileSystemAccess;
  final bool taglibWasmReady;
}

abstract interface class WebCapabilityProbe {
  Future<WebCapabilitySnapshot> probe();
}

class DefaultWebCapabilityProbe implements WebCapabilityProbe {
  const DefaultWebCapabilityProbe();

  @override
  Future<WebCapabilitySnapshot> probe() {
    return impl.probeWebCapabilities();
  }
}
