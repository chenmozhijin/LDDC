import 'dart:convert';
import 'dart:io';

import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:path/path.dart' as p;

import '../audio_tag/audio_file_extensions.dart';
import 'unknown_encoding_file_reader.dart';

final RegExp _cueFilePattern = RegExp(r'^"(.*?)" (\w+)$|^(.*?) (\w+)$');
final RegExp _cueWhitespacePattern = RegExp(r'\s+');

/// 将 CUE `mm:ss:ff` 转为毫秒。
///
/// `ff` 是 CD 的 75fps 帧号，不是歌词格式常见的厘秒或毫秒。使用截断可以
/// 保持与 Python 版 `int(frames * (1000 / 75))` 相同的轨道边界。
int _cueTimeToMs(Object minutes, Object seconds, Object frames) {
  final int minute = int.parse(minutes.toString());
  final int second = int.parse(seconds.toString());
  final int frame = int.parse(frames.toString());
  return (minute * 60 + second) * 1000 + (frame * 1000 / 75).toInt();
}

/// CUE 轨道结构，对齐Python版 `Track`。
final class CueTrack {
  CueTrack({
    required this.id,
    required this.type,
    Map<String, int> indexes = const <String, int>{},
    this.pregapMs,
    this.postgapMs,
    this.title,
    this.performer,
    this.songwriter,
    this.isrc,
    this.flags,
    Map<String, String> replaygain = const <String, String>{},
  }) : indexes = Map<String, int>.from(indexes),
       replaygain = Map<String, String>.from(replaygain);

  final String id;
  final String type;
  final Map<String, int> indexes;
  int? pregapMs;
  int? postgapMs;
  String? title;
  String? performer;
  String? songwriter;
  String? isrc;
  String? flags;
  final Map<String, String> replaygain;

  /// 转换为 isolate 可传递的纯字典结构。
  Map<String, Object?> toMap() {
    final Map<String, Object?> data = <String, Object?>{
      'id': id,
      'type': type,
      'indexes': Map<String, int>.from(indexes),
      'replaygain': Map<String, String>.from(replaygain),
    };
    if (pregapMs != null) {
      data['pregapMs'] = pregapMs;
    }
    if (postgapMs != null) {
      data['postgapMs'] = postgapMs;
    }
    if (title != null) {
      data['title'] = title;
    }
    if (performer != null) {
      data['performer'] = performer;
    }
    if (songwriter != null) {
      data['songwriter'] = songwriter;
    }
    if (isrc != null) {
      data['isrc'] = isrc;
    }
    if (flags != null) {
      data['flags'] = flags;
    }
    return data;
  }

  factory CueTrack.fromMap(Map<Object?, Object?> map) {
    final Object? indexesRaw = map['indexes'];
    final Map<String, int> parsedIndexes = <String, int>{};
    if (indexesRaw is Map) {
      for (final MapEntry<Object?, Object?> entry in indexesRaw.entries) {
        final Object? value = entry.value;
        if (value is int) {
          parsedIndexes[entry.key.toString()] = value;
        }
      }
    }
    final Object? replaygainRaw = map['replaygain'];
    final Map<String, String> parsedReplaygain = <String, String>{};
    if (replaygainRaw is Map) {
      for (final MapEntry<Object?, Object?> entry in replaygainRaw.entries) {
        final Object? value = entry.value;
        if (value != null) {
          parsedReplaygain[entry.key.toString()] = value.toString();
        }
      }
    }
    return CueTrack(
      id: map['id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      indexes: parsedIndexes,
      pregapMs: map['pregapMs'] as int?,
      postgapMs: map['postgapMs'] as int?,
      title: map['title'] as String?,
      performer: map['performer'] as String?,
      songwriter: map['songwriter'] as String?,
      isrc: map['isrc'] as String?,
      flags: map['flags'] as String?,
      replaygain: parsedReplaygain,
    );
  }
}

/// CUE 的 FILE 块结构，对齐Python版 `AudioFile`。
final class CueAudioFile {
  CueAudioFile({
    required this.filename,
    required this.type,
    List<CueTrack> tracks = const <CueTrack>[],
  }) : tracks = List<CueTrack>.from(tracks);

  final String filename;
  final String type;
  final List<CueTrack> tracks;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'filename': filename,
      'type': type,
      'tracks': tracks.map((CueTrack track) => track.toMap()).toList(),
    };
  }

  factory CueAudioFile.fromMap(Map<Object?, Object?> map) {
    final Object? tracksRaw = map['tracks'];
    final List<CueTrack> parsedTracks = tracksRaw is List
        ? tracksRaw
              .whereType<Map>()
              .map(
                (Map<Object?, Object?> track) =>
                    CueTrack.fromMap(Map<Object?, Object?>.from(track)),
              )
              .toList(growable: false)
        : const <CueTrack>[];
    return CueAudioFile(
      filename: map['filename']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      tracks: parsedTracks,
    );
  }
}

/// 音频时长解析回调：返回音频总时长（毫秒）。
typedef CueAudioDurationResolver = int? Function(String audioPath);
typedef CueAudioPathResolver = String? Function(CueData cue, CueAudioFile file);
typedef CueAudioExistsChecker = bool Function(String audioPath);

/// CUE 数据结构，对齐Python版 `CueData`。
final class CueData {
  CueData({
    required this.path,
    this.title,
    this.performer,
    this.songwriter,
    this.catalog,
    List<CueAudioFile> files = const <CueAudioFile>[],
    this.genre,
    this.discid,
    this.date,
    this.comment,
    this.cdtextfile,
    this.rem = '',
  }) : files = List<CueAudioFile>.from(files);

  /// CUE 文件路径。
  final String path;
  String? title;
  String? performer;
  String? songwriter;
  String? catalog;
  final List<CueAudioFile> files;
  String? genre;
  String? discid;
  String? date;
  String? comment;
  String? cdtextfile;
  String rem;

  Map<String, Object?> toMap() {
    final Map<String, Object?> data = <String, Object?>{
      'path': path,
      'files': files.map((CueAudioFile file) => file.toMap()).toList(),
      'rem': rem,
    };
    if (title != null) {
      data['title'] = title;
    }
    if (performer != null) {
      data['performer'] = performer;
    }
    if (songwriter != null) {
      data['songwriter'] = songwriter;
    }
    if (catalog != null) {
      data['catalog'] = catalog;
    }
    if (genre != null) {
      data['genre'] = genre;
    }
    if (discid != null) {
      data['discid'] = discid;
    }
    if (date != null) {
      data['date'] = date;
    }
    if (comment != null) {
      data['comment'] = comment;
    }
    if (cdtextfile != null) {
      data['cdtextfile'] = cdtextfile;
    }
    return data;
  }

  factory CueData.fromMap(Map<Object?, Object?> map) {
    final Object? filesRaw = map['files'];
    final List<CueAudioFile> parsedFiles = filesRaw is List
        ? filesRaw
              .whereType<Map>()
              .map(
                (Map<Object?, Object?> file) =>
                    CueAudioFile.fromMap(Map<Object?, Object?>.from(file)),
              )
              .toList(growable: false)
        : const <CueAudioFile>[];
    return CueData(
      path: map['path']?.toString() ?? '',
      title: map['title'] as String?,
      performer: map['performer'] as String?,
      songwriter: map['songwriter'] as String?,
      catalog: map['catalog'] as String?,
      files: parsedFiles,
      genre: map['genre'] as String?,
      discid: map['discid'] as String?,
      date: map['date'] as String?,
      comment: map['comment'] as String?,
      cdtextfile: map['cdtextfile'] as String?,
      rem: map['rem'] as String? ?? '',
    );
  }

  /// 查找某个 FILE 条目指向的音频路径，逻辑对齐Python版 `get_audio_path`。
  String? getAudioPath(
    CueAudioFile file, {
    CueAudioPathResolver? audioPathResolver,
    CueAudioExistsChecker? audioExistsChecker,
  }) {
    if (audioPathResolver != null) {
      final String? resolved = audioPathResolver(this, file);
      if (resolved == null || resolved.trim().isEmpty) {
        return null;
      }
      return resolved;
    }

    final CueAudioExistsChecker exists =
        audioExistsChecker ?? _defaultAudioExistsChecker;
    final String cueDirectory = p.dirname(path);
    final String filenameStem = p.basenameWithoutExtension(file.filename);
    final String cueStem = p.withoutExtension(path);
    final String songPath = p.normalize(p.join(cueDirectory, file.filename));
    if (exists(songPath)) {
      return songPath;
    }

    for (final String extension in audioFileExtensions) {
      final String candidateInCueDir = p.normalize(
        p.join(cueDirectory, '$filenameStem.$extension'),
      );
      if (exists(candidateInCueDir)) {
        return candidateInCueDir;
      }

      final String candidateByCueStem = p.normalize('$cueStem.$extension');
      if (exists(candidateByCueStem)) {
        return candidateByCueStem;
      }
    }
    return null;
  }

  /// 获取 CUE 引用的可定位音频路径列表。
  List<String> getAudioPaths({
    CueAudioPathResolver? audioPathResolver,
    CueAudioExistsChecker? audioExistsChecker,
  }) {
    final List<String> paths = <String>[];
    for (final CueAudioFile file in files) {
      final String? songPath = getAudioPath(
        file,
        audioPathResolver: audioPathResolver,
        audioExistsChecker: audioExistsChecker,
      );
      if (songPath != null) {
        paths.add(songPath);
      }
    }
    return paths;
  }

  /// 将 CUE 轨道转换为 `SongInfo` 列表，对齐Python版 `to_songinfos`。
  List<SongInfo> toSongInfos({
    CueAudioDurationResolver? durationResolver,
    CueAudioPathResolver? audioPathResolver,
    CueAudioExistsChecker? audioExistsChecker,
  }) {
    final List<SongInfo> songInfos = <SongInfo>[];
    final CueAudioExistsChecker exists =
        audioExistsChecker ?? _defaultAudioExistsChecker;
    for (final CueAudioFile file in files) {
      final String? resolvedAudioPath = getAudioPath(
        file,
        audioPathResolver: audioPathResolver,
        audioExistsChecker: audioExistsChecker,
      );
      final String songPath =
          resolvedAudioPath ??
          (audioPathResolver == null
              ? p.join(p.dirname(path), file.filename)
              : file.filename);

      for (int index = 0; index < file.tracks.length; index += 1) {
        final CueTrack track = file.tracks[index];
        final int? index01 = track.indexes['01'];
        if (index01 == null) {
          throw StateError('CUE 轨道 ${track.id} 缺少 INDEX 01');
        }
        final int startMs = index01 - (track.pregapMs ?? 0);

        int? endMs;
        if (index < file.tracks.length - 1) {
          final CueTrack nextTrack = file.tracks[index + 1];
          final int? nextStart = nextTrack.indexes['01'];
          if (nextStart == null) {
            throw StateError('CUE 轨道 ${nextTrack.id} 缺少 INDEX 01');
          }
          endMs = nextStart + (track.postgapMs ?? 0);
        } else if (durationResolver != null || exists(songPath)) {
          try {
            endMs = durationResolver?.call(songPath);
          } catch (_) {
            endMs = null;
          }
        }

        final int? durationMs = endMs == null
            ? null
            : (endMs - startMs).clamp(0, 2147483647);
        songInfos.add(
          SongInfo(
            source: Source.local,
            title: track.title,
            artist: _buildArtist(track),
            album: title,
            durationMs: durationMs,
            id: track.id,
            fromCue: true,
            path: songPath,
          ),
        );
      }
    }
    return songInfos;
  }

  SongArtist _buildArtist(CueTrack track) {
    if (track.performer != null && performer != null) {
      return SongArtist(<String>[track.performer!, performer!]);
    }
    if (track.performer != null) {
      return SongArtist(<String>[track.performer!]);
    }
    if (track.songwriter != null) {
      return SongArtist(<String>[track.songwriter!]);
    }
    if (performer != null) {
      return SongArtist(<String>[performer!]);
    }
    if (songwriter != null) {
      return SongArtist(<String>[songwriter!]);
    }
    return SongArtist(const <String>[]);
  }
}

bool _defaultAudioExistsChecker(String audioPath) =>
    File(audioPath).existsSync();

/// 解析 CUE 文件内容，输出结构化 `CueData`。
CueData parseCue({required String cuePath, String? data}) {
  // UI 等主 isolate 链路使用 parseCueFile() 异步读取；后台扫描 worker 已经
  // 与界面线程隔离，可使用同步 path 入口减少 Future 和消息往返开销。
  final String cueContent = data ?? _readCueText(cuePath);
  final CueData cue = CueData(path: cuePath);

  CueTrack? currentTrack;
  CueAudioFile? currentFile;

  for (final String originalLine in const LineSplitter().convert(cueContent)) {
    String line = originalLine.trimRight();
    if (line.isEmpty) {
      continue;
    }

    try {
      // 缩进等级按 2 空格计算，和Python版保持一致。
      final int indent = (line.length - line.trimLeft().length) ~/ 2;
      line = line.trimLeft();
      final ({String command, String args}) parsed = _parseCueCommand(line);
      final String command = parsed.command.toUpperCase();
      final String args = parsed.args;

      if (indent == 0) {
        _handleGlobalCommand(
          cue: cue,
          command: command,
          args: args,
          onFile: (CueAudioFile file) {
            // 新 FILE 块必须先解除上一条轨道的上下文。损坏 CUE 若在新 FILE
            // 后直接出现轨道级命令，也不能回头改写前一个文件的最后一轨。
            currentTrack = null;
            currentFile = file;
            cue.files.add(file);
          },
        );
      } else if (indent == 1 && command == 'TRACK') {
        final CueAudioFile? file = currentFile;
        if (file == null) {
          continue;
        }
        final List<String> segments = args.split(_cueWhitespacePattern);
        if (segments.length >= 2) {
          final CueTrack track = CueTrack(id: segments[0], type: segments[1]);
          currentTrack = track;
          file.tracks.add(track);
        }
      } else if (indent >= 2) {
        final CueTrack? track = currentTrack;
        if (track != null) {
          _handleTrackCommand(track: track, command: command, args: args);
        }
      }
    } catch (_) {
      // 对齐Python版：单行解析失败只跳过，不中断整体解析。
      continue;
    }
  }

  return cue;
}

/// 异步读取并解析 CUE 文件，供用户触发的批处理链路复用。
Future<CueData> parseCueFile({required String cuePath}) async {
  final String cueContent = await readUnknownEncodingFileAsync(cuePath);
  return parseCue(cuePath: cuePath, data: cueContent);
}

({String command, String args}) _parseCueCommand(String line) {
  final int spaceIndex = line.indexOf(' ');
  if (spaceIndex < 0) {
    return (command: line, args: '');
  }
  return (
    command: line.substring(0, spaceIndex).trim(),
    args: line.substring(spaceIndex + 1),
  );
}

void _handleGlobalCommand({
  required CueData cue,
  required String command,
  required String args,
  required void Function(CueAudioFile file) onFile,
}) {
  if (command == 'FILE') {
    final RegExpMatch? match = _cueFilePattern.firstMatch(args);
    if (match == null) {
      return;
    }
    final String filename = _parseCueQuoted(
      match.group(1) ?? match.group(3) ?? '',
    );
    final String type = (match.group(2) ?? match.group(4) ?? '').trim();
    if (filename.isEmpty || type.isEmpty) {
      return;
    }
    onFile(CueAudioFile(filename: filename, type: type));
    return;
  }

  if (command == 'REM') {
    final int firstSpace = args.indexOf(' ');
    if (firstSpace < 0) {
      cue.rem += _parseCueQuoted(args);
      return;
    }
    final String subCommand = args
        .substring(0, firstSpace)
        .trim()
        .toUpperCase();
    final String subArgs = args.substring(firstSpace + 1);
    final String value = _parseCueQuoted(subArgs);
    if (subCommand == 'GENRE') {
      cue.genre = value;
      return;
    }
    if (subCommand == 'DISCID') {
      cue.discid = value;
      return;
    }
    if (subCommand == 'DATE') {
      cue.date = value;
      return;
    }
    if (subCommand == 'COMMENT') {
      cue.comment = value;
      return;
    }
    if (subCommand == 'CDTEXTFILE') {
      cue.cdtextfile = value;
      return;
    }
    cue.rem += _parseCueQuoted(args);
    return;
  }

  if (command == 'TITLE') {
    cue.title = _parseCueQuoted(args);
    return;
  }
  if (command == 'PERFORMER') {
    cue.performer = _parseCueQuoted(args);
    return;
  }
  if (command == 'SONGWRITER') {
    cue.songwriter = _parseCueQuoted(args);
    return;
  }
  if (command == 'CATALOG') {
    cue.catalog = _parseCueQuoted(args);
    return;
  }
}

void _handleTrackCommand({
  required CueTrack track,
  required String command,
  required String args,
}) {
  if (command == 'INDEX') {
    final List<String> segments = args.split(_cueWhitespacePattern);
    if (segments.length < 2) {
      return;
    }
    final List<String> timeParts = segments[1].split(':');
    if (timeParts.length != 3) {
      return;
    }
    track.indexes[segments[0]] = _cueTimeToMs(
      timeParts[0],
      timeParts[1],
      timeParts[2],
    );
    return;
  }

  if (command == 'PREGAP') {
    final List<String> timeParts = args.trim().split(':');
    if (timeParts.length == 3) {
      track.pregapMs = _cueTimeToMs(timeParts[0], timeParts[1], timeParts[2]);
    }
    return;
  }

  if (command == 'POSTGAP') {
    final List<String> timeParts = args.trim().split(':');
    if (timeParts.length == 3) {
      track.postgapMs = _cueTimeToMs(timeParts[0], timeParts[1], timeParts[2]);
    }
    return;
  }

  if (command == 'REM') {
    if (!args.startsWith('REPLAYGAIN_')) {
      return;
    }
    final int firstSpace = args.indexOf(' ');
    if (firstSpace < 0) {
      return;
    }
    final String gainType = args.substring(0, firstSpace).trim();
    final String gainValue = _parseCueQuoted(args.substring(firstSpace + 1));
    track.replaygain[gainType] = gainValue;
    return;
  }

  if (command == 'TITLE') {
    track.title = _parseCueQuoted(args);
    return;
  }
  if (command == 'PERFORMER') {
    track.performer = _parseCueQuoted(args);
    return;
  }
  if (command == 'SONGWRITER') {
    track.songwriter = _parseCueQuoted(args);
    return;
  }
  if (command == 'ISRC') {
    track.isrc = _parseCueQuoted(args);
    return;
  }
  if (command == 'FLAGS') {
    track.flags = _parseCueQuoted(args);
    return;
  }
}

/// 处理 CUE 引号参数：`"abc"` -> `abc`。
String _parseCueQuoted(String text) {
  final String trimmed = text.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _readCueText(String cuePath) {
  // 对齐Python版：CUE 文本也走统一未知编码读取，避免 UTF-8/Latin-1 二选一丢失中文编码场景。
  return readUnknownEncodingFile(cuePath);
}
