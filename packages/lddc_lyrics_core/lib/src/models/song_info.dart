import 'package:collection/collection.dart';

import 'model_helpers.dart';
import 'model_enums.dart';

final RegExp _songUriSchemePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

/// 规范化歌曲路径，保证本地文件路径内部不携带 `file://` 前缀。
///
/// 桌面歌词插件可能直接上报 Python 版使用的 `file://` URL。如果把该值原样
/// 存入 [SongInfo.path]，后续生成关联 URL 时会再次添加前缀，造成关联库严格键
/// 无法命中。这里会移除任意层数的 `file://`，但保留 `content://`、HTTP 等
/// 非文件 URI，避免把平台 URI 误改成本地文件路径。
String? normalizeSongPath(Object? rawPath) {
  if (rawPath == null) {
    return null;
  }
  String normalized = rawPath.toString();
  while (normalized.length >= 7 &&
      normalized.substring(0, 7).toLowerCase() == 'file://') {
    normalized = normalized.substring(7);
  }
  return normalized.isEmpty ? null : normalized;
}

/// 把歌曲路径转换为关联库使用的规范 URL。
///
/// 已带 scheme 的平台或网络 URI 原样返回；只有原生文件路径会添加一次
/// `file://`。该函数与 [normalizeSongPath] 配套使用，使读取旧数据和生成新键
/// 始终采用同一规则。
String? songPathToUrl(Object? rawPath) {
  final String? normalized = normalizeSongPath(rawPath);
  if (normalized == null) {
    return null;
  }
  if (_songUriSchemePattern.hasMatch(normalized)) {
    return normalized;
  }
  return 'file://$normalized';
}

/// 歌手集合。
///
/// 语义对齐Python版 `Artist(tuple[str])`：
/// 1. 保序去重
/// 2. 字符串拼接默认使用 `/`
class SongArtist {
  SongArtist(Iterable<String> artists)
    : _artists = List<String>.unmodifiable(orderedUnique(artists));

  final List<String> _artists;

  /// 构造时已冻结，可直接复用同一列表，避免每次读取新建包装对象。
  List<String> get values => _artists;

  bool get isEmpty => _artists.every((String artist) => artist.isEmpty);

  bool get isNotEmpty => !isEmpty;

  /// 按指定分隔符拼接歌手名称。
  String join([String separator = '/']) => _artists.join(separator);

  static SongArtist? tryFromObject(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is SongArtist) {
      return value;
    }
    if (value is String) {
      return SongArtist(<String>[value]);
    }
    if (value is Iterable<Object?>) {
      return SongArtist(
        value.whereType<Object>().map((Object item) => item.toString()),
      );
    }
    return null;
  }

  @override
  String toString() => join();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SongArtist &&
            const ListEquality<String>().equals(_artists, other._artists));
  }

  @override
  int get hashCode => Object.hashAll(_artists);
}

/// 歌曲信息实体，对齐Python版 `SongInfo`。
class SongInfo implements SourceAware {
  const SongInfo({
    required this.source,
    this.title,
    this.subtitle,
    this.artist,
    this.album,
    this.durationMs,
    this.imgUrl,
    this.id,
    this.mid,
    this.hash,
    this.path,
    this.fromCue = false,
    this.language,
  });

  @override
  final Source source;
  final String? title;
  final String? subtitle;
  final SongArtist? artist;
  final String? album;
  final int? durationMs;
  final String? imgUrl;
  final String? id;
  final String? mid;
  final String? hash;
  final String? path;
  final bool fromCue;
  final Language? language;

  /// 标题 + 副标题（例如：`title(subtitle)`）。
  String get fullTitle {
    if (title == null || title!.isEmpty) {
      return '';
    }
    if (subtitle != null && subtitle!.isNotEmpty) {
      return '${title!}(${subtitle!})';
    }
    return title!;
  }

  String get artistText => artist?.toString() ?? '';

  /// 本地文件路径对应的 URL（`file://`）。
  String? get url => songPathToUrl(path);

  /// 生成“歌手 - 标题”展示文本。
  ///
  /// - [full] 为 `true` 时使用完整标题（含副标题）
  /// - [replaceMissing] 为 `true` 时将缺失字段替换为 `?`
  String artistTitle({bool full = false, bool replaceMissing = false}) {
    final String titleValueBase = full ? fullTitle : (title ?? '');
    final String titleValue = titleValueBase.isNotEmpty
        ? titleValueBase
        : (replaceMissing ? '?' : '');
    final String artistValueBase = artistText;
    final String artistValue = artistValueBase.isNotEmpty
        ? artistValueBase
        : (replaceMissing ? '?' : '');
    if (artistValue.isNotEmpty && titleValue.isNotEmpty) {
      return '$artistValue - $titleValue';
    }
    return '$artistValue$titleValue';
  }

  String get formattedDuration {
    return formatDurationMmSs(durationMs);
  }

  /// 生成浅拷贝并覆写部分字段。
  SongInfo copyWith({
    Source? source,
    Object? title = copyWithSentinel,
    Object? subtitle = copyWithSentinel,
    Object? artist = copyWithSentinel,
    Object? album = copyWithSentinel,
    Object? durationMs = copyWithSentinel,
    Object? imgUrl = copyWithSentinel,
    Object? id = copyWithSentinel,
    Object? mid = copyWithSentinel,
    Object? hash = copyWithSentinel,
    Object? path = copyWithSentinel,
    bool? fromCue,
    Object? language = copyWithSentinel,
  }) {
    return SongInfo(
      source: source ?? this.source,
      title: identical(title, copyWithSentinel) ? this.title : title as String?,
      subtitle: identical(subtitle, copyWithSentinel)
          ? this.subtitle
          : subtitle as String?,
      artist: identical(artist, copyWithSentinel)
          ? this.artist
          : artist as SongArtist?,
      album: identical(album, copyWithSentinel) ? this.album : album as String?,
      durationMs: identical(durationMs, copyWithSentinel)
          ? this.durationMs
          : durationMs as int?,
      imgUrl: identical(imgUrl, copyWithSentinel)
          ? this.imgUrl
          : imgUrl as String?,
      id: identical(id, copyWithSentinel) ? this.id : id as String?,
      mid: identical(mid, copyWithSentinel) ? this.mid : mid as String?,
      hash: identical(hash, copyWithSentinel) ? this.hash : hash as String?,
      path: identical(path, copyWithSentinel) ? this.path : path as String?,
      fromCue: fromCue ?? this.fromCue,
      language: identical(language, copyWithSentinel)
          ? this.language
          : language as Language?,
    );
  }

  /// 转换为可序列化字典，键名对齐Python版字段命名。
  Map<String, Object?> toMap() {
    final Map<String, Object?> data = <String, Object?>{
      'source': source.value,
      'from_cue': fromCue,
    };
    if (title != null) {
      data['title'] = title;
    }
    if (subtitle != null) {
      data['subtitle'] = subtitle;
    }
    if (artist != null) {
      data['artist'] = artist!.values;
    }
    if (album != null) {
      data['album'] = album;
    }
    if (durationMs != null) {
      data['duration'] = durationMs;
    }
    if (imgUrl != null) {
      data['imgurl'] = imgUrl;
    }
    if (id != null) {
      data['id'] = id;
    }
    if (mid != null) {
      data['mid'] = mid;
    }
    if (hash != null) {
      data['hash'] = hash;
    }
    if (path != null) {
      data['path'] = path;
    }
    if (language != null) {
      data['language'] = language!.value;
    }
    return data;
  }

  /// 从字典构建 [SongInfo]。
  ///
  /// 兼容Python版常见输入：
  /// - `source` 可为 code/name/value
  /// - `path` 支持 `file://` 前缀
  /// - `id` 支持 `int/str`
  factory SongInfo.fromMap(Map<String, Object?> info) {
    final Object? source = info['source'];
    if (source == null) {
      throw ArgumentError.value(info, 'info', 'source is required');
    }
    final String? normalizedPath = normalizeSongPath(info['path']);

    final Object? languageRaw = info['language'];
    final Language? language = languageRaw == null
        ? null
        : Language.fromValue(languageRaw);

    return SongInfo(
      source: Source.fromValue(source),
      title: info['title'] is String ? info['title'] as String : null,
      subtitle: info['subtitle'] is String ? info['subtitle'] as String : null,
      artist: SongArtist.tryFromObject(info['artist']),
      album: info['album'] is String ? info['album'] as String : null,
      durationMs: parseNullableInt(info['duration']),
      imgUrl: info['imgurl']?.toString(),
      id: info['id']?.toString(),
      mid: info['mid']?.toString(),
      hash: info['hash']?.toString(),
      path: normalizedPath,
      fromCue: info['from_cue'] is bool ? info['from_cue'] as bool : false,
      language: language,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SongInfo &&
            source == other.source &&
            title == other.title &&
            subtitle == other.subtitle &&
            artist == other.artist &&
            album == other.album &&
            durationMs == other.durationMs &&
            imgUrl == other.imgUrl &&
            id == other.id &&
            mid == other.mid &&
            hash == other.hash &&
            path == other.path &&
            fromCue == other.fromCue &&
            language == other.language);
  }

  @override
  int get hashCode => Object.hash(
    source,
    title,
    subtitle,
    artist,
    album,
    durationMs,
    imgUrl,
    id,
    mid,
    hash,
    path,
    fromCue,
    language,
  );
}
