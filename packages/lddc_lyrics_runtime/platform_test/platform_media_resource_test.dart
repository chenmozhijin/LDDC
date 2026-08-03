import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lddc_lyrics_core/lddc_lyrics_core.dart';
import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('生产媒体网关重复读写匿名音频后释放文件和临时资源', () async {
    final _MediaTestEnvironment environment =
        _MediaTestEnvironment.fromProcessEnvironment();
    final _MediaEvidence evidence = _MediaEvidence(environment);
    Object? failure;
    StackTrace? failureStack;

    try {
      final _FixtureManifest manifest = await _FixtureManifest.load(
        environment.fixtureDirectory,
      );
      await environment.prepare();
      evidence.add('media', 'fixture_manifest_verified');

      for (int cycle = 0; cycle < environment.loopCount; cycle += 1) {
        await _runCycle(
          environment: environment,
          manifest: manifest,
          cycle: cycle,
          evidence: evidence,
        );
      }

      await manifest.verifyTrackedSourcesUnchanged();
      evidence
        ..add('media', 'tracked_fixtures_remained_read_only')
        ..add('resourceCleanup', 'media_workspaces_deleted');
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      try {
        await environment.cleanup();
      } on Object catch (error, stackTrace) {
        failure ??= error;
        failureStack ??= stackTrace;
      }
      await evidence.write(failure);
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack ?? StackTrace.current);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _runCycle({
  required _MediaTestEnvironment environment,
  required _FixtureManifest manifest,
  required int cycle,
  required _MediaEvidence evidence,
}) async {
  final Directory cycleDirectory = Directory(
    p.join(environment.workDirectory.path, 'cycle-$cycle'),
  );
  await cycleDirectory.create(recursive: true);

  final Map<String, File> copied = <String, File>{};
  for (final _FixtureSpec fixture in manifest.audioFixtures) {
    final File destination = File(p.join(cycleDirectory.path, fixture.file));
    await File(
      p.join(manifest.directory.path, fixture.file),
    ).copy(destination.path);
    expect(await _sha256(destination), fixture.sha256);
    copied[fixture.id] = destination;
  }

  final LocalMatchMediaGateway gateway = createDefaultLocalMatchMediaGateway();
  for (final String id in <String>['audio_mp3', 'audio_flac']) {
    final _FixtureSpec fixture = manifest.byId(id);
    final File file = copied[id]!;
    await _verifyMetadata(gateway, file, fixture);
    expect(await gateway.hasLyricsTag(file.path), isTrue);
    expect(
      await gateway.readAudioLyricsText(songPath: file.path),
      fixture.embeddedLyrics,
    );

    final String writtenLyrics = '[00:00.00]LDDC platform cycle $cycle';
    await gateway.writeLyricsTag(
      songPath: file.path,
      lyricsText: writtenLyrics,
      lyrics: _buildTimedLyrics(file.path, cycle),
      id3Version: Id3Version.v24,
    );

    // 写入后通过新的后台 isolate 重开文件，避免同一 TagLib 会话缓存造成假绿。
    await _verifyMetadata(gateway, file, fixture);
    expect(await gateway.hasLyricsTag(file.path), isTrue);
    expect(
      await gateway.readAudioLyricsText(songPath: file.path),
      writtenLyrics,
    );
    evidence.addArtifact(
      name: 'cycle-$cycle-${fixture.file}',
      size: await file.length(),
      sha256: await _sha256(file),
    );
  }

  await _verifyMetadata(
    gateway,
    copied['audio_wav']!,
    manifest.byId('audio_wav'),
  );
  evidence.add('media', 'cycle_${cycle}_metadata_lyrics_round_trip');

  // Windows 无法重命名仍被 TagLib 持有的文件；逐轮重命名再删除可直接暴露句柄泄漏。
  final Directory releasedDirectory = Directory(
    '${cycleDirectory.path}.released',
  );
  await cycleDirectory.rename(releasedDirectory.path);
  await releasedDirectory.delete(recursive: true);
  expect(cycleDirectory.existsSync(), isFalse);
  expect(releasedDirectory.existsSync(), isFalse);
  evidence.add('resourceCleanup', 'cycle_${cycle}_handles_released');
  evidence.recordRssSample();
}

Future<void> _verifyMetadata(
  LocalMatchMediaGateway gateway,
  File file,
  _FixtureSpec fixture,
) async {
  final List<SongInfo> infos = await gateway.readAudioSongInfos(file.path);
  expect(infos, hasLength(1));
  final SongInfo info = infos.single;
  expect(info.title, fixture.title);
  expect(info.artist?.values, <String>[fixture.artist]);
  expect(info.album, fixture.album);
  expect(info.id, fixture.track);

  final int? durationMs = await gateway.readAudioDurationMs(file.path);
  expect(durationMs, isNotNull);
  expect(durationMs, greaterThanOrEqualTo(0));
  // dart_taglib 0.1.0 只公开整秒时长；允许的区间精确反映该量化边界。
  expect(
    (durationMs! - fixture.requiredDurationMs).abs(),
    lessThanOrEqualTo(1000),
  );
}

Lyrics _buildTimedLyrics(String songPath, int cycle) {
  return Lyrics(
    songInfo: SongInfo(source: Source.local, path: songPath),
    source: Source.local,
    data: <String, LyricsData>{
      'orig': <LyricsLine>[
        LyricsLine(
          startMs: 0,
          endMs: 250,
          words: <LyricsWord>[
            LyricsWord(
              startMs: 0,
              endMs: 250,
              text: 'LDDC platform cycle $cycle',
            ),
          ],
        ),
      ],
    },
    types: const <String, LyricsType>{'orig': LyricsType.lineByLine},
  );
}

final class _MediaTestEnvironment {
  const _MediaTestEnvironment({
    required this.runId,
    required this.platform,
    required this.fixtureDirectory,
    required this.workDirectory,
    required this.evidenceFile,
    required this.loopCount,
  });

  final String runId;
  final String platform;
  final Directory fixtureDirectory;
  final Directory workDirectory;
  final File evidenceFile;
  final int loopCount;

  factory _MediaTestEnvironment.fromProcessEnvironment() {
    final int loopCount = int.parse(
      _requiredEnvironment('LDDC_MEDIA_LOOP_COUNT'),
    );
    if (loopCount != 3 && loopCount != 20) {
      throw StateError('媒体资源循环只允许 PR 的 3 次或定时性能任务的 20 次');
    }
    final Directory evidenceDirectory = Directory(
      _requiredEnvironment('LDDC_NATIVE_EVIDENCE_DIR'),
    );
    return _MediaTestEnvironment(
      runId: _requiredEnvironment('LDDC_IT_RUN_ID'),
      platform: _requiredEnvironment('LDDC_IT_PLATFORM'),
      fixtureDirectory: Directory(
        _requiredEnvironment('LDDC_MEDIA_FIXTURE_DIR'),
      ),
      workDirectory: Directory(_requiredEnvironment('LDDC_MEDIA_WORK_DIR')),
      evidenceFile: File(
        p.join(evidenceDirectory.path, 'platform_media_resource.json'),
      ),
      loopCount: loopCount,
    );
  }

  Future<void> prepare() async {
    if (!fixtureDirectory.existsSync()) {
      throw StateError('匿名媒体 fixture 目录不存在');
    }
    await Directory(evidenceFile.parent.path).create(recursive: true);
    if (workDirectory.existsSync()) {
      throw StateError('媒体测试工作目录必须是全新的 runId 隔离目录');
    }
    await workDirectory.create(recursive: true);
  }

  Future<void> cleanup() async {
    if (workDirectory.existsSync()) {
      await workDirectory.delete(recursive: true);
    }
  }
}

final class _FixtureManifest {
  _FixtureManifest({required this.directory, required this.fixtures});

  final Directory directory;
  final List<_FixtureSpec> fixtures;

  Iterable<_FixtureSpec> get audioFixtures =>
      fixtures.where((_FixtureSpec fixture) => fixture.id.startsWith('audio_'));

  _FixtureSpec byId(String id) {
    return fixtures.singleWhere((_FixtureSpec fixture) => fixture.id == id);
  }

  static Future<_FixtureManifest> load(Directory directory) async {
    final File manifestFile = File(p.join(directory.path, 'manifest.json'));
    final Object? decoded = jsonDecode(await manifestFile.readAsString());
    final Map<String, Object?> manifest = Map<String, Object?>.from(
      decoded! as Map<Object?, Object?>,
    );
    expect(manifest['schemaVersion'], 1);
    expect(manifest['originClass'], 'anonymousSynthetic');
    final List<_FixtureSpec> fixtures = (manifest['fixtures']! as List<Object?>)
        .map<_FixtureSpec>((Object? item) {
          return _FixtureSpec.fromJson(
            Map<String, Object?>.from(item! as Map<Object?, Object?>),
          );
        })
        .toList(growable: false);
    final _FixtureManifest result = _FixtureManifest(
      directory: directory,
      fixtures: fixtures,
    );
    for (final _FixtureSpec fixture in fixtures) {
      final File file = File(p.join(directory.path, fixture.file));
      expect(await file.length(), fixture.size);
      expect(await _sha256(file), fixture.sha256);
    }
    return result;
  }

  Future<void> verifyTrackedSourcesUnchanged() async {
    for (final _FixtureSpec fixture in fixtures) {
      final File file = File(p.join(directory.path, fixture.file));
      expect(await file.length(), fixture.size);
      expect(await _sha256(file), fixture.sha256);
    }
  }
}

final class _FixtureSpec {
  const _FixtureSpec({
    required this.id,
    required this.file,
    required this.size,
    required this.sha256,
    required this.durationMs,
    required this.title,
    required this.artist,
    required this.album,
    required this.track,
    required this.embeddedLyrics,
  });

  final String id;
  final String file;
  final int size;
  final String sha256;
  final int? durationMs;
  final String title;
  final String artist;
  final String album;
  final String? track;
  final String? embeddedLyrics;

  factory _FixtureSpec.fromJson(Map<String, Object?> json) {
    return _FixtureSpec(
      id: json['id']! as String,
      file: json['file']! as String,
      size: json['size']! as int,
      sha256: json['sha256']! as String,
      durationMs: json['durationMs'] as int?,
      title: json['title']! as String,
      artist: json['artist']! as String,
      album: json['album']! as String,
      track: json['track'] as String?,
      embeddedLyrics: json['embeddedLyrics'] as String?,
    );
  }

  int get requiredDurationMs {
    final int? value = durationMs;
    if (value == null) {
      throw StateError('音频 fixture $id 缺少 durationMs');
    }
    return value;
  }
}

final class _MediaEvidence {
  _MediaEvidence(this.environment) : _rssBaseline = ProcessInfo.currentRss;

  final _MediaTestEnvironment environment;
  final int _rssBaseline;
  final List<int> _rssSamples = <int>[];
  final Map<String, List<Map<String, Object?>>> _actions =
      <String, List<Map<String, Object?>>>{};
  final List<Map<String, Object?>> _artifacts = <Map<String, Object?>>[];

  void add(String capability, String action) {
    _actions.putIfAbsent(capability, () => <Map<String, Object?>>[]).add(
      <String, Object?>{'action': action},
    );
  }

  void addArtifact({
    required String name,
    required int size,
    required String sha256,
  }) {
    _artifacts.add(<String, Object?>{
      'name': name,
      'size': size,
      'sha256': sha256,
    });
  }

  void recordRssSample() {
    _rssSamples.add(ProcessInfo.currentRss);
  }

  Future<void> write(Object? failure) async {
    final bool cleaned = !environment.workDirectory.existsSync();
    final int rssFinal = ProcessInfo.currentRss;
    final List<int> sortedRss = <int>[..._rssSamples]..sort();
    final int rssP95 = sortedRss.isEmpty
        ? rssFinal
        : sortedRss[((sortedRss.length * 0.95).ceil() - 1)
              .clamp(0, sortedRss.length - 1)
              .toInt()];
    final Map<String, Object?> payload = <String, Object?>{
      'runId': environment.runId,
      'scenario': 'platform_media_resource',
      'profile': 'platform',
      'platform': environment.platform,
      'framework': 'dart-native-assets',
      'steps': <Map<String, Object?>>[
        <String, Object?>{
          'step': 'platform_media_resource',
          'success': failure == null && cleaned,
          'error': failure == null ? null : '${failure.runtimeType}: $failure',
        },
      ],
      'capabilityEvidence': _actions,
      'resources': <String, Object?>{
        'baseline': <String, Object?>{'tempFileCount': 0},
        'final': <String, Object?>{'tempFileCount': cleaned ? 0 : 1},
        'thresholds': <String, Object?>{'tempFileCount': 0},
      },
      'artifacts': _artifacts,
      'extra': <String, Object?>{
        'loopCount': environment.loopCount,
        'memory': <String, Object?>{
          // 必须先在相同 runner image 上积累三次 20 轮报告，之后才能版本化
          // P95 + 20% 阈值；当前状态不能被解释为内存门禁已经完成。
          'status': 'baseline_pending',
          'rssBaselineBytes': _rssBaseline,
          'rssP95Bytes': rssP95,
          'rssFinalBytes': rssFinal,
          'sampleCount': _rssSamples.length,
        },
      },
    };
    final File temporary = File('${environment.evidenceFile.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
      flush: true,
    );
    if (environment.evidenceFile.existsSync()) {
      await environment.evidenceFile.delete();
    }
    await temporary.rename(environment.evidenceFile.path);
  }
}

Future<String> _sha256(File file) async {
  return (await sha256.bind(file.openRead()).first).toString();
}

String _requiredEnvironment(String name) {
  final String value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw StateError('缺少环境变量 $name');
  }
  return value;
}
