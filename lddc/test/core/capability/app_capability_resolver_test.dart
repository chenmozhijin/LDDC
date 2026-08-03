import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lddc/src/core/capability/capability.dart';

import '../../support/capability_profiles.dart';

void main() {
  group('AppCapabilityResolver', () {
    test('windows capability profile', () {
      final AppCapability capability = AppCapabilityResolver.resolve(
        isWeb: false,
        targetPlatform: TargetPlatform.windows,
      );

      expect(capability.multiWindow, isTrue);
      expect(capability.desktopPanelDetached, isTrue);
      expect(capability.desktopPanelEmbedded, isTrue);
      expect(capability.systemTray, isTrue);
      expect(capability.globalHotkey, isTrue);
      expect(capability.audioTagWrite, isTrue);
      expect(capability.directoryRecursiveScan, isTrue);
      expect(capability.androidSafTreeAccess, isFalse);
      expect(capability.webFileSystemAccess, isFalse);
    });

    test('android capability profile', () {
      final AppCapability capability = AppCapabilityResolver.resolve(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );

      expect(capability.multiWindow, isFalse);
      expect(capability.desktopPanelDetached, isFalse);
      expect(capability.desktopPanelEmbedded, isFalse);
      expect(capability.systemTray, isFalse);
      expect(capability.globalHotkey, isFalse);
      expect(capability.audioTagWrite, isTrue);
      expect(capability.directoryRecursiveScan, isTrue);
      expect(capability.androidSafTreeAccess, isTrue);
      expect(capability.androidCueTrackResolve, isTrue);
    });

    test('web capability follows injected flags', () {
      final AppCapability capability = AppCapabilityResolver.resolve(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
        webFileSystemAccess: true,
        webTaglibWasmReady: true,
      );

      expect(capability.multiWindow, isFalse);
      expect(capability.audioTagWrite, isTrue);
      expect(capability.directoryRecursiveScan, isFalse);
      expect(capability.webFileSystemAccess, isTrue);
      expect(capability.webTaglibWasmReady, isTrue);
    });

    test('test profiles stay aligned with resolver defaults', () {
      expect(
        CapabilityProfiles.desktop().toMap(),
        equals(
          AppCapabilityResolver.resolve(
            isWeb: false,
            targetPlatform: TargetPlatform.windows,
          ).toMap(),
        ),
      );
      expect(
        CapabilityProfiles.android().toMap(),
        equals(
          AppCapabilityResolver.resolve(
            isWeb: false,
            targetPlatform: TargetPlatform.android,
          ).toMap(),
        ),
      );
      expect(
        CapabilityProfiles.ios().toMap(),
        equals(
          AppCapabilityResolver.resolve(
            isWeb: false,
            targetPlatform: TargetPlatform.iOS,
          ).toMap(),
        ),
      );
    });
  });
}
