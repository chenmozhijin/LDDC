// ignore_for_file: avoid_slow_async_io
// 配置存储测试需要验证异步文件状态检查，避免测试把实现重新拉回同步 API。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lddc/src/core/config/config.dart';
import 'package:lddc/src/infra/storage/app_storage_paths_io.dart';
import 'package:lddc/src/infra/storage/config_file_storage_io.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lddc_config_storage_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('JsonFileConfigStorage 会以Python版键名写入并按内部键读取 config.json', () async {
    final AppStoragePaths paths = AppStoragePaths(
      isWindows: false,
      isLinux: false,
      isMacOS: false,
      applicationSupportDirectoryResolver: () async => tempDir,
      applicationCacheDirectoryResolver: () async =>
          Directory('${tempDir.path}/cache'),
      applicationDocumentsDirectoryResolver: () async =>
          Directory('${tempDir.path}/documents'),
      libraryDirectoryResolver: () async => tempDir,
    );
    final JsonFileConfigStorage storage = JsonFileConfigStorage(paths: paths);

    await storage.write(<String, Object?>{
      'schemaVersion': 1,
      ConfigKey.appLanguage: 'auto',
      ConfigKey.desktopRefreshRate: 60,
    });

    final Map<String, Object?>? values = await storage.read();
    final File file = await paths.resolveConfigFile();
    final Map<String, Object?> rawFile = Map<String, Object?>.from(
      jsonDecode(await file.readAsString()) as Map<dynamic, dynamic>,
    );

    expect(await file.exists(), isTrue);
    expect(values?['schemaVersion'], equals(1));
    expect(values?[ConfigKey.appLanguage], equals('auto'));
    expect(values?[ConfigKey.desktopRefreshRate], equals(60));
    expect(rawFile.containsKey('schemaVersion'), isFalse);
    expect(rawFile['language'], equals('auto'));
    expect(rawFile['desktop_lyrics_refresh_rate'], equals(60));
    expect(rawFile.containsKey(ConfigKey.desktopRefreshRate), isFalse);
  });

  test('JsonFileConfigStorage 可直接读取Python版 snake_case config.json', () async {
    final AppStoragePaths paths = AppStoragePaths(
      isWindows: false,
      isLinux: false,
      isMacOS: false,
      applicationSupportDirectoryResolver: () async => tempDir,
      applicationCacheDirectoryResolver: () async =>
          Directory('${tempDir.path}/cache'),
      applicationDocumentsDirectoryResolver: () async =>
          Directory('${tempDir.path}/documents'),
      libraryDirectoryResolver: () async => tempDir,
    );
    final JsonFileConfigStorage storage = JsonFileConfigStorage(paths: paths);
    final File file = await paths.resolveConfigFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'desktop_lyrics_font_size': 26.0,
        'lyrics_panel_font_size': 14.0,
        'default_save_path': '/tmp/lyrics',
      }),
    );

    final Map<String, Object?>? values = await storage.read();

    expect(values?[ConfigKey.desktopFontSize], equals(26.0));
    expect(values?[ConfigKey.desktopPanelFontSize], equals(14.0));
    expect(values?[ConfigKey.storageDefaultSavePath], equals('/tmp/lyrics'));
    expect(
      values?['schemaVersion'],
      equals(ConfigDefaults.currentSchemaVersion),
    );
  });

  test('AppBootstrap 默认仍可通过 DefaultConfigRepository 读取文件型配置', () async {
    final AppStoragePaths paths = AppStoragePaths(
      isWindows: false,
      isLinux: false,
      isMacOS: false,
      applicationSupportDirectoryResolver: () async => tempDir,
      applicationCacheDirectoryResolver: () async =>
          Directory('${tempDir.path}/cache'),
      applicationDocumentsDirectoryResolver: () async =>
          Directory('${tempDir.path}/documents'),
      libraryDirectoryResolver: () async => tempDir,
    );
    final JsonFileConfigStorage storage = JsonFileConfigStorage(paths: paths);
    await storage.write(<String, Object?>{
      'schemaVersion': 1,
      ConfigKey.desktopFontSize: 26.0,
    });

    final DefaultConfigRepository repository = DefaultConfigRepository(
      storage: storage,
      defaultSavePathResolver: () async =>
          (await paths.resolveDefaultSaveLyricsDirectory()).path,
    );
    final AppConfig config = await repository.load();

    expect(config.desktop.fontSize, equals(26.0));
  });
}
