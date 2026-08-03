import 'model_helpers.dart';

/// 方位枚举，对齐Python版 `Direction`。
enum Direction {
  left(1, 'LEFT'),
  right(2, 'RIGHT'),
  top(3, 'TOP'),
  bottom(4, 'BOTTOM'),
  topLeft(5, 'TOP_LEFT'),
  topRight(6, 'TOP_RIGHT'),
  bottomLeft(7, 'BOTTOM_LEFT'),
  bottomRight(8, 'BOTTOM_RIGHT');

  const Direction(this.code, this.value);

  final int code;
  final String value;

  /// 兼容 code/name/value 三种输入。
  static Direction fromValue(Object? value) {
    return parsePythonEnum<Direction>(
      rawValue: value,
      values: Direction.values,
      codeOf: (Direction item) => item.code,
      wireValueOf: (Direction item) => item.value,
      enumName: 'Direction',
    );
  }
}

/// 歌词/歌曲数据来源，对齐Python版 `Source` 枚举。
enum Source {
  multi(0, 'MULTI'),
  qm(1, 'QM'),
  kg(2, 'KG'),
  ne(3, 'NE'),
  lrclib(4, 'LRCLIB'),
  local(100, 'Local');

  const Source(this.code, this.value);

  final int code;
  final String value;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [Source]。
  static Source fromValue(Object? value) {
    return parsePythonEnum<Source>(
      rawValue: value,
      values: Source.values,
      codeOf: (Source item) => item.code,
      wireValueOf: (Source item) => item.value,
      enumName: 'Source',
    );
  }

  /// 当前来源支持的搜索类型集合。
  Set<SearchType> get supportedSearchTypes {
    switch (this) {
      case Source.multi:
        return const <SearchType>{
          SearchType.song,
          SearchType.album,
          SearchType.songlist,
        };
      case Source.qm:
      case Source.ne:
        return const <SearchType>{
          SearchType.song,
          SearchType.album,
          SearchType.songlist,
          SearchType.songId,
        };
      case Source.kg:
        return const <SearchType>{
          SearchType.song,
          SearchType.album,
          SearchType.songlist,
        };
      case Source.lrclib:
        return const <SearchType>{SearchType.song};
      case Source.local:
        return const <SearchType>{};
    }
  }
}

/// 提供来源字段读取能力的统一接口。
abstract interface class SourceAware {
  Source get source;
}

/// 搜索类型，对齐Python版 `SearchType`。
enum SearchType {
  song(0, 'SONG'),
  album(1, 'ALBUM'),
  songlist(2, 'SONGLIST'),
  songId(3, 'SONGID'),
  artist(4, 'ARTIST'),
  lyrics(7, 'LYRICS');

  const SearchType(this.code, this.value);

  final int code;
  final String value;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [SearchType]。
  static SearchType fromValue(Object? value) {
    return parsePythonEnum<SearchType>(
      rawValue: value,
      values: SearchType.values,
      codeOf: (SearchType item) => item.code,
      wireValueOf: (SearchType item) => item.value,
      enumName: 'SearchType',
    );
  }
}

/// 歌曲语言类型，对齐Python版 `Language` 枚举。
enum Language {
  instrumental(0, 'INSTRUMENTAL'),
  other(1, 'OTHER'),
  chinese(2, 'CHINESE'),
  english(3, 'ENGLISH'),
  japanese(4, 'JAPANESE'),
  korean(5, 'KOREAN');

  const Language(this.code, this.value);

  final int code;
  final String value;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [Language]。
  static Language fromValue(Object? value) {
    return parsePythonEnum<Language>(
      rawValue: value,
      values: Language.values,
      codeOf: (Language item) => item.code,
      wireValueOf: (Language item) => item.value,
      enumName: 'Language',
    );
  }
}

/// 歌词时间戳类型（纯文本/逐词/逐行），对齐Python版 `LyricsType`。
enum LyricsType {
  plainText(0, 'PlainText'),
  verbatim(1, 'VERBATIM'),
  lineByLine(2, 'LINEBYLINE');

  const LyricsType(this.code, this.value);

  final int code;
  final String value;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [LyricsType]。
  static LyricsType fromValue(Object? value) {
    return parsePythonEnum<LyricsType>(
      rawValue: value,
      values: LyricsType.values,
      codeOf: (LyricsType item) => item.code,
      wireValueOf: (LyricsType item) => item.value,
      enumName: 'LyricsType',
    );
  }
}

/// 歌词导出格式，对齐Python版 `LyricsFormat`。
enum LyricsFormat {
  verbatimLrc(0, 'VERBATIMLRC', '.lrc'),
  lineByLineLrc(1, 'LINEBYLINELRC', '.lrc'),
  enhancedLrc(2, 'ENHANCEDLRC', '.lrc'),
  srt(3, 'SRT', '.srt'),
  ass(4, 'ASS', '.ass'),
  qrc(5, 'QRC', '.qrc'),
  krc(6, 'KRC', '.krc'),
  yrc(7, 'YRC', '.yrc'),
  json(8, 'JSON', '.json');

  const LyricsFormat(this.code, this.value, this.ext);

  final int code;
  final String value;

  /// 对齐Python版 `LyricsFormat.ext`。
  final String ext;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [LyricsFormat]。
  static LyricsFormat fromValue(Object? value) {
    return parsePythonEnum<LyricsFormat>(
      rawValue: value,
      values: LyricsFormat.values,
      codeOf: (LyricsFormat item) => item.code,
      wireValueOf: (LyricsFormat item) => item.value,
      enumName: 'LyricsFormat',
    );
  }
}

/// 歌单类型（专辑/歌单），对齐Python版 `SongListType`。
enum SongListType {
  album(0, 'ALBUM'),
  songlist(1, 'SONGLIST');

  const SongListType(this.code, this.value);

  final int code;
  final String value;

  /// 兼容多种输入（枚举/整型 code/字符串 name 或 value）并转换为 [SongListType]。
  static SongListType fromValue(Object? value) {
    return parsePythonEnum<SongListType>(
      rawValue: value,
      values: SongListType.values,
      codeOf: (SongListType item) => item.code,
      wireValueOf: (SongListType item) => item.value,
      enumName: 'SongListType',
    );
  }
}
