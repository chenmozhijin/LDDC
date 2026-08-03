import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';

void main() {
  group('AppStoragePaths', () {
    test('Windows 桌面目录对齐Python版语义', () async {
      final AppStoragePaths paths = AppStoragePaths(
        isWindows: true,
        isLinux: false,
        isMacOS: false,
        windowsKnownFolderResolver: (String folderId) async {
          if (folderId == kWindowsKnownFolderRoamingAppData) {
            return r'C:\Users\Test\AppData\Roaming';
          }
          if (folderId == kWindowsKnownFolderLocalAppData) {
            return r'C:\Users\Test\AppData\Local';
          }
          if (folderId == kWindowsKnownFolderDocuments) {
            return r'C:\Users\Test\Documents';
          }
          return null;
        },
        applicationSupportDirectoryResolver: () async => Directory.systemTemp,
        applicationCacheDirectoryResolver: () async => Directory.systemTemp,
        applicationDocumentsDirectoryResolver: () async => Directory.systemTemp,
        libraryDirectoryResolver: () async => Directory.systemTemp,
      );

      expect(
        (await paths.resolveConfigDirectory()).path,
        equals(r'C:\Users\Test\AppData\Roaming\LDDC'),
      );
      expect(
        (await paths.resolveDataDirectory()).path,
        equals(r'C:\Users\Test\AppData\Local\LDDC'),
      );
      expect(
        (await paths.resolveCacheDirectory()).path,
        equals(r'C:\Users\Test\AppData\Local\LDDC\Cache'),
      );
      expect(
        (await paths.resolveLogDirectory()).path,
        equals(r'C:\Users\Test\AppData\Local\LDDC\Logs'),
      );
      expect(
        (await paths.resolveDefaultSaveLyricsDirectory()).path,
        equals(r'C:\Users\Test\Documents\Lyrics'),
      );
    });

    test('Linux 桌面目录对齐 XDG 语义', () async {
      final AppStoragePaths paths = AppStoragePaths(
        isWindows: false,
        isLinux: true,
        isMacOS: false,
        linuxConfigHomeResolver: () async => Directory('/home/tester/.config'),
        linuxDataHomeResolver: () async =>
            Directory('/home/tester/.local/share'),
        linuxCacheHomeResolver: () async => Directory('/home/tester/.cache'),
        applicationSupportDirectoryResolver: () async => Directory.systemTemp,
        applicationCacheDirectoryResolver: () async => Directory.systemTemp,
        applicationDocumentsDirectoryResolver: () async =>
            Directory('/home/tester/Documents'),
        libraryDirectoryResolver: () async => Directory.systemTemp,
      );

      expect(
        (await paths.resolveConfigDirectory()).path,
        equals('/home/tester/.config/LDDC'),
      );
      expect(
        (await paths.resolveDataDirectory()).path,
        equals('/home/tester/.local/share/LDDC'),
      );
      expect(
        (await paths.resolveCacheDirectory()).path,
        equals('/home/tester/.cache/LDDC'),
      );
      expect(
        (await paths.resolveLogDirectory()).path,
        equals('/home/tester/.local/share/LDDC/logs'),
      );
      expect(
        (await paths.resolveDefaultSaveLyricsDirectory()).path,
        equals('/home/tester/Documents/Lyrics'),
      );
    });

    test('移动端目录使用 Flutter 应用目录', () async {
      final AppStoragePaths paths = AppStoragePaths(
        isWindows: false,
        isLinux: false,
        isMacOS: false,
        applicationSupportDirectoryResolver: () async =>
            Directory('/app/support'),
        applicationCacheDirectoryResolver: () async => Directory('/app/cache'),
        applicationDocumentsDirectoryResolver: () async =>
            Directory('/storage/emulated/0/Documents'),
        libraryDirectoryResolver: () async => Directory.systemTemp,
      );

      expect(
        (await paths.resolveConfigDirectory()).path,
        equals('/app/support/config'),
      );
      expect(
        (await paths.resolveDataDirectory()).path,
        equals('/app/support/data'),
      );
      expect(
        (await paths.resolveCacheDirectory()).path,
        equals('/app/cache/lddc'),
      );
      expect(
        (await paths.resolveLogDirectory()).path,
        equals('/app/support/data/logs'),
      );
      expect(
        (await paths.resolveDefaultSaveLyricsDirectory()).path,
        equals('/storage/emulated/0/Documents/Lyrics'),
      );
    });
  });
}
