import 'package:flutter/foundation.dart';
import 'package:lddc/src/core/capability/capability.dart';

class CapabilityProfiles {
  const CapabilityProfiles._();

  static AppCapability desktop() {
    return AppCapabilityResolver.resolve(
      isWeb: false,
      targetPlatform: TargetPlatform.windows,
    );
  }

  static AppCapability android() {
    return AppCapabilityResolver.resolve(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
    );
  }

  static AppCapability ios() {
    return AppCapabilityResolver.resolve(
      isWeb: false,
      targetPlatform: TargetPlatform.iOS,
    );
  }

  static AppCapability web({
    bool fileSystemAccess = false,
    bool taglibWasmReady = false,
  }) {
    return AppCapabilityResolver.resolve(
      isWeb: true,
      targetPlatform: TargetPlatform.android,
      webFileSystemAccess: fileSystemAccess,
      webTaglibWasmReady: taglibWasmReady,
    );
  }
}
