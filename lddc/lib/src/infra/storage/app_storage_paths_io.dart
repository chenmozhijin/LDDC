import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/app_storage_paths_port.dart';

typedef DirectoryResolver = Future<Directory> Function();
typedef NullableDirectoryResolver = Future<Directory?> Function();
typedef WindowsKnownFolderPathResolver =
    Future<String?> Function(String folderId);

/// `FOLDERID_RoamingAppData`
const String kWindowsKnownFolderRoamingAppData =
    '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}';

/// `FOLDERID_LocalAppData`
const String kWindowsKnownFolderLocalAppData =
    '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}';

/// `FOLDERID_Documents`
const String kWindowsKnownFolderDocuments =
    '{FDD39AD0-238F-46AF-ADB4-6C85480369C7}';

/// LDDC 统一存储路径解析器。
///
/// 设计约束：
/// - 桌面端直接复用Python版目录语义，而不是引入第二套持久化布局；
/// - Android/iOS 走 Flutter 平台目录，保持移动端实现简洁；
/// - 仅负责持久化路径，不承载 runtime socket / bootstrap 临时路径。
class AppStoragePaths implements AppStoragePathsPort {
  AppStoragePaths({
    bool? isWindows,
    bool? isLinux,
    bool? isMacOS,
    WindowsKnownFolderPathResolver? windowsKnownFolderResolver,
    NullableDirectoryResolver? linuxConfigHomeResolver,
    NullableDirectoryResolver? linuxDataHomeResolver,
    NullableDirectoryResolver? linuxCacheHomeResolver,
    DirectoryResolver? applicationSupportDirectoryResolver,
    DirectoryResolver? applicationCacheDirectoryResolver,
    DirectoryResolver? applicationDocumentsDirectoryResolver,
    DirectoryResolver? libraryDirectoryResolver,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _isLinux = isLinux ?? Platform.isLinux,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _pathContext = p.Context(
         style: (isWindows ?? Platform.isWindows)
             ? p.Style.windows
             : p.Style.posix,
       ),
       _windowsKnownFolderResolver =
           windowsKnownFolderResolver ?? _defaultWindowsKnownFolderResolver,
       _linuxConfigHomeResolver =
           linuxConfigHomeResolver ?? _defaultLinuxConfigHomeResolver,
       _linuxDataHomeResolver =
           linuxDataHomeResolver ?? _defaultLinuxDataHomeResolver,
       _linuxCacheHomeResolver =
           linuxCacheHomeResolver ?? _defaultLinuxCacheHomeResolver,
       _applicationSupportDirectoryResolver =
           applicationSupportDirectoryResolver ??
           getApplicationSupportDirectory,
       _applicationCacheDirectoryResolver =
           applicationCacheDirectoryResolver ?? getApplicationCacheDirectory,
       _applicationDocumentsDirectoryResolver =
           applicationDocumentsDirectoryResolver ??
           getApplicationDocumentsDirectory,
       _libraryDirectoryResolver =
           libraryDirectoryResolver ?? getLibraryDirectory;

  final bool _isWindows;
  final bool _isLinux;
  final bool _isMacOS;
  final p.Context _pathContext;
  final WindowsKnownFolderPathResolver _windowsKnownFolderResolver;
  final NullableDirectoryResolver _linuxConfigHomeResolver;
  final NullableDirectoryResolver _linuxDataHomeResolver;
  final NullableDirectoryResolver _linuxCacheHomeResolver;
  final DirectoryResolver _applicationSupportDirectoryResolver;
  final DirectoryResolver _applicationCacheDirectoryResolver;
  final DirectoryResolver _applicationDocumentsDirectoryResolver;
  final DirectoryResolver _libraryDirectoryResolver;

  Future<Directory> resolveConfigDirectory() async {
    if (_isWindows) {
      final Directory roaming = await _requireWindowsFolder(
        kWindowsKnownFolderRoamingAppData,
      );
      return Directory(_pathContext.join(roaming.path, 'LDDC'));
    }
    if (_isLinux) {
      final Directory configHome =
          await _linuxConfigHomeResolver() ??
          await _applicationSupportDirectoryResolver();
      return Directory(_pathContext.join(configHome.path, 'LDDC'));
    }
    if (_isMacOS) {
      final Directory library = await _libraryDirectoryResolver();
      return Directory(_pathContext.join(library.path, 'Preferences', 'LDDC'));
    }
    final Directory support = await _applicationSupportDirectoryResolver();
    return Directory(_pathContext.join(support.path, 'config'));
  }

  @override
  Future<Directory> resolveDataDirectory() async {
    if (_isWindows) {
      final Directory local = await _requireWindowsFolder(
        kWindowsKnownFolderLocalAppData,
      );
      return Directory(_pathContext.join(local.path, 'LDDC'));
    }
    if (_isLinux) {
      final Directory dataHome =
          await _linuxDataHomeResolver() ??
          await _applicationSupportDirectoryResolver();
      return Directory(_pathContext.join(dataHome.path, 'LDDC'));
    }
    if (_isMacOS) {
      final Directory library = await _libraryDirectoryResolver();
      return Directory(
        _pathContext.join(library.path, 'Application Support', 'LDDC'),
      );
    }
    final Directory support = await _applicationSupportDirectoryResolver();
    return Directory(_pathContext.join(support.path, 'data'));
  }

  Future<Directory> resolveCacheDirectory() async {
    if (_isWindows) {
      final Directory data = await resolveDataDirectory();
      return Directory(_pathContext.join(data.path, 'Cache'));
    }
    if (_isLinux) {
      final Directory cacheHome =
          await _linuxCacheHomeResolver() ??
          await _applicationCacheDirectoryResolver();
      return Directory(_pathContext.join(cacheHome.path, 'LDDC'));
    }
    if (_isMacOS) {
      final Directory library = await _libraryDirectoryResolver();
      return Directory(_pathContext.join(library.path, 'Caches', 'LDDC'));
    }
    final Directory cache = await _applicationCacheDirectoryResolver();
    return Directory(_pathContext.join(cache.path, 'lddc'));
  }

  @override
  Future<Directory> resolveLogDirectory() async {
    if (_isWindows) {
      final Directory data = await resolveDataDirectory();
      return Directory(_pathContext.join(data.path, 'Logs'));
    }
    if (_isLinux) {
      final Directory data = await resolveDataDirectory();
      return Directory(_pathContext.join(data.path, 'logs'));
    }
    if (_isMacOS) {
      final Directory library = await _libraryDirectoryResolver();
      return Directory(_pathContext.join(library.path, 'Logs', 'LDDC'));
    }
    final Directory data = await resolveDataDirectory();
    return Directory(_pathContext.join(data.path, 'logs'));
  }

  Future<Directory> resolveDefaultSaveLyricsDirectory() async {
    if (_isWindows) {
      final Directory documents = await _requireWindowsFolder(
        kWindowsKnownFolderDocuments,
      );
      return Directory(_pathContext.join(documents.path, 'Lyrics'));
    }
    final Directory documents = await _applicationDocumentsDirectoryResolver();
    return Directory(_pathContext.join(documents.path, 'Lyrics'));
  }

  Future<File> resolveConfigFile() async {
    final Directory directory = await resolveConfigDirectory();
    return File(_pathContext.join(directory.path, 'config.json'));
  }

  @override
  Future<File> resolveLibraryLinkDatabaseFile() async {
    final Directory directory = await resolveDataDirectory();
    return File(_pathContext.join(directory.path, 'local_song_lyrics.db'));
  }

  @override
  Future<File> resolveCacheDatabaseFile() async {
    final Directory directory = await resolveCacheDirectory();
    return File(_pathContext.join(directory.path, 'cache.sqlite3'));
  }

  @override
  Future<File> resolveInfoFile() async {
    final Directory directory = await resolveDataDirectory();
    return File(_pathContext.join(directory.path, 'info.json'));
  }

  Future<Directory> _requireWindowsFolder(String folderId) async {
    final String? path = await _windowsKnownFolderResolver(folderId);
    if (path == null || path.isEmpty) {
      throw FileSystemException('无法获取 Windows Known Folder', folderId);
    }
    return Directory(path);
  }

  static Future<String?> _defaultWindowsKnownFolderResolver(
    String folderId,
  ) async {
    final Map<String, String> env = Platform.environment;
    if (folderId == kWindowsKnownFolderRoamingAppData) {
      return env['APPDATA'];
    }
    if (folderId == kWindowsKnownFolderLocalAppData) {
      return env['LOCALAPPDATA'];
    }
    if (folderId == kWindowsKnownFolderDocuments) {
      final String? profile = env['USERPROFILE'];
      if (profile == null || profile.isEmpty) {
        return null;
      }
      return p.Context(style: p.Style.windows).join(profile, 'Documents');
    }
    return null;
  }

  static Future<Directory?> _defaultLinuxConfigHomeResolver() async {
    return _linuxXdgDirectory('XDG_CONFIG_HOME', '.config');
  }

  static Future<Directory?> _defaultLinuxDataHomeResolver() async {
    return _linuxXdgDirectory('XDG_DATA_HOME', p.join('.local', 'share'));
  }

  static Future<Directory?> _defaultLinuxCacheHomeResolver() async {
    return _linuxXdgDirectory('XDG_CACHE_HOME', '.cache');
  }

  static Directory? _linuxXdgDirectory(String variableName, String fallback) {
    final Map<String, String> env = Platform.environment;
    final String? configured = env[variableName];
    if (configured != null && configured.isNotEmpty) {
      return Directory(configured);
    }
    final String? home = env['HOME'];
    if (home == null || home.isEmpty) {
      return null;
    }
    return Directory(p.Context(style: p.Style.posix).join(home, fallback));
  }
}
