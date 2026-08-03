import 'dart:io';

class DesktopLyricsDiagnosticEvent {
  DesktopLyricsDiagnosticEvent({
    required this.scope,
    required this.message,
    required this.rawLine,
    required this.timestamp,
    required this.sequence,
    Map<String, String> fields = const <String, String>{},
  }) : fields = Map<String, String>.unmodifiable(fields);

  final String scope;
  final String message;
  final String rawLine;
  final DateTime timestamp;
  final int sequence;
  final Map<String, String> fields;

  String? field(String key) => fields[key];

  int? intField(String key) => int.tryParse(field(key) ?? '');

  bool? boolField(String key) {
    return switch ((field(key) ?? '').toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  String get kind =>
      field('phase') ?? field('reason') ?? field('event') ?? scope;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scope': scope,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'sequence': sequence,
      'kind': kind,
      'fields': fields,
    };
  }
}

class DesktopLyricsDiagnosticCheckpoint {
  const DesktopLyricsDiagnosticCheckpoint({
    required this.name,
    required this.timestamp,
  });

  final String name;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class DesktopLyricsDiagnosticPhase {
  const DesktopLyricsDiagnosticPhase({
    required this.name,
    required this.events,
    required this.endInclusive,
    this.startExclusive,
  });

  final String name;
  final List<DesktopLyricsDiagnosticEvent> events;
  final DateTime? startExclusive;
  final DateTime endInclusive;

  DesktopLyricsDiagnosticEvent? get firstEvent =>
      events.isEmpty ? null : events.first;

  DesktopLyricsDiagnosticEvent? get lastEvent =>
      events.isEmpty ? null : events.last;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'startExclusive': startExclusive?.toIso8601String(),
      'endInclusive': endInclusive.toIso8601String(),
      'eventCount': events.length,
      'firstEvent': firstEvent?.toJson(),
      'lastEvent': lastEvent?.toJson(),
    };
  }
}

class DesktopPanelGenerationSample {
  const DesktopPanelGenerationSample({
    required this.scope,
    required this.kind,
    required this.timestamp,
    required this.sequence,
    this.geometryEpoch,
    this.bindGeneration,
    this.geometryGeneration,
    this.visibilityGeneration,
    this.surfaceReadyGeneration,
    this.renderGeneration,
    this.paintFrameId,
  });

  final String scope;
  final String kind;
  final DateTime timestamp;
  final int sequence;
  final int? geometryEpoch;
  final int? bindGeneration;
  final int? geometryGeneration;
  final int? visibilityGeneration;
  final int? surfaceReadyGeneration;
  final String? renderGeneration;
  final int? paintFrameId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scope': scope,
      'kind': kind,
      'timestamp': timestamp.toIso8601String(),
      'sequence': sequence,
      'geometryEpoch': geometryEpoch,
      'bindGeneration': bindGeneration,
      'geometryGeneration': geometryGeneration,
      'visibilityGeneration': visibilityGeneration,
      'surfaceReadyGeneration': surfaceReadyGeneration,
      'renderGeneration': renderGeneration,
      'paintFrameId': paintFrameId,
    };
  }
}

class DesktopLyricsDiagnosticHarness {
  DesktopLyricsDiagnosticHarness._();

  static const Set<String> panelScopes = <String>{
    'panel-host-bridge',
    'panel-host-native',
    'panel-runtime',
    'panel-shell',
    'panel-render',
  };

  static final RegExp _linePattern = RegExp(
    r'^\[([^\]]+)\]\[level=[^\]]+\]\[role=[^\]]+\]\[pid=\d+\]\[scope=([^\]]+)\]\[instance=[^\]]+\]\[panel=[^\]]+\]\[seq=(\d+)\]\s+(.*)$',
  );
  static final RegExp _fieldKeyPattern = RegExp(
    r'(^| )([A-Za-z][A-Za-z0-9_]*)=',
  );

  static List<DesktopLyricsDiagnosticEvent> parse(String logText) {
    final List<DesktopLyricsDiagnosticEvent> events =
        <DesktopLyricsDiagnosticEvent>[];
    for (final String rawLine in logText.split(RegExp(r'\r?\n'))) {
      if (rawLine.trim().isEmpty) {
        continue;
      }
      final RegExpMatch? match = _linePattern.firstMatch(rawLine);
      if (match == null) {
        continue;
      }
      final String scope = match.group(2) ?? '';
      if (!panelScopes.contains(scope)) {
        continue;
      }
      final DateTime? timestamp = DateTime.tryParse(match.group(1) ?? '');
      if (timestamp == null) {
        continue;
      }
      final String message = match.group(4) ?? '';
      events.add(
        DesktopLyricsDiagnosticEvent(
          scope: scope,
          message: message,
          rawLine: rawLine,
          timestamp: timestamp,
          sequence: int.tryParse(match.group(3) ?? '') ?? 0,
          fields: _parseFields(message),
        ),
      );
    }
    events.sort(_compareEvents);
    return events;
  }

  static List<DesktopLyricsDiagnosticEvent> filter(
    Iterable<DesktopLyricsDiagnosticEvent> events, {
    String? scope,
    String? kind,
    String? messageContains,
    Map<String, String> fields = const <String, String>{},
  }) {
    return events
        .where((DesktopLyricsDiagnosticEvent event) {
          if (scope != null && event.scope != scope) {
            return false;
          }
          if (kind != null && event.kind != kind) {
            return false;
          }
          if (messageContains != null &&
              !event.message.contains(messageContains)) {
            return false;
          }
          for (final MapEntry<String, String> entry in fields.entries) {
            if (event.field(entry.key) != entry.value) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false)
      ..sort(_compareEvents);
  }

  static List<DesktopLyricsDiagnosticPhase> sliceByCheckpoints(
    Iterable<DesktopLyricsDiagnosticEvent> events,
    Iterable<DesktopLyricsDiagnosticCheckpoint> checkpoints,
  ) {
    final List<DesktopLyricsDiagnosticEvent> sortedEvents = events.toList(
      growable: false,
    )..sort(_compareEvents);
    final List<DesktopLyricsDiagnosticCheckpoint> sortedCheckpoints =
        checkpoints.toList(growable: false)..sort(
          (
            DesktopLyricsDiagnosticCheckpoint left,
            DesktopLyricsDiagnosticCheckpoint right,
          ) => left.timestamp.compareTo(right.timestamp),
        );
    final List<DesktopLyricsDiagnosticPhase> phases =
        <DesktopLyricsDiagnosticPhase>[];
    DateTime? previousTimestamp;
    for (final DesktopLyricsDiagnosticCheckpoint checkpoint
        in sortedCheckpoints) {
      final List<DesktopLyricsDiagnosticEvent> phaseEvents = sortedEvents
          .where((DesktopLyricsDiagnosticEvent event) {
            if (previousTimestamp != null &&
                !event.timestamp.isAfter(previousTimestamp)) {
              return false;
            }
            return !event.timestamp.isAfter(checkpoint.timestamp);
          })
          .toList(growable: false);
      phases.add(
        DesktopLyricsDiagnosticPhase(
          name: checkpoint.name,
          events: phaseEvents,
          startExclusive: previousTimestamp,
          endInclusive: checkpoint.timestamp,
        ),
      );
      previousTimestamp = checkpoint.timestamp;
    }
    return phases;
  }

  static List<DesktopPanelGenerationSample> extractGenerationSamples(
    Iterable<DesktopLyricsDiagnosticEvent> events,
  ) {
    final List<DesktopPanelGenerationSample> samples =
        <DesktopPanelGenerationSample>[];
    for (final DesktopLyricsDiagnosticEvent event in events) {
      final int? geometryEpoch = event.intField('geometryEpoch');
      final int? bindGeneration =
          event.intField('bindGeneration') ??
          event.intField('surfaceBindGeneration');
      final int? geometryGeneration =
          event.intField('geometryGeneration') ??
          event.intField('surfaceGeometryGeneration');
      final int? visibilityGeneration =
          event.intField('visibilityGeneration') ??
          event.intField('surfaceVisibilityGeneration');
      final int? surfaceReadyGeneration =
          event.intField('surfaceReadyGeneration') ??
          event.intField('surfaceReadyGeneration');
      final String? renderGeneration = event.field('renderGeneration');
      final int? paintFrameId = event.intField('paintFrameId');
      if (geometryEpoch == null &&
          bindGeneration == null &&
          geometryGeneration == null &&
          visibilityGeneration == null &&
          surfaceReadyGeneration == null &&
          renderGeneration == null &&
          paintFrameId == null) {
        continue;
      }
      samples.add(
        DesktopPanelGenerationSample(
          scope: event.scope,
          kind: event.kind,
          timestamp: event.timestamp,
          sequence: event.sequence,
          geometryEpoch: geometryEpoch,
          bindGeneration: bindGeneration,
          geometryGeneration: geometryGeneration,
          visibilityGeneration: visibilityGeneration,
          surfaceReadyGeneration: surfaceReadyGeneration,
          renderGeneration: renderGeneration,
          paintFrameId: paintFrameId,
        ),
      );
    }
    samples.sort((
      DesktopPanelGenerationSample left,
      DesktopPanelGenerationSample right,
    ) {
      final int compareTime = left.timestamp.compareTo(right.timestamp);
      if (compareTime != 0) {
        return compareTime;
      }
      return left.sequence.compareTo(right.sequence);
    });
    return samples;
  }

  static Future<List<DesktopLyricsDiagnosticEvent>> readFromDirectory(
    String logDirectoryPath,
  ) async {
    final Directory directory = Directory(logDirectoryPath);
    if (!directory.existsSync()) {
      return const <DesktopLyricsDiagnosticEvent>[];
    }
    final List<File> files = <File>[
      for (final FileSystemEntity entity in directory.listSync(
        followLinks: false,
      ))
        if (entity is File && entity.path.toLowerCase().endsWith('.log'))
          entity,
    ]..sort((File left, File right) => left.path.compareTo(right.path));
    final List<DesktopLyricsDiagnosticEvent> events =
        <DesktopLyricsDiagnosticEvent>[];
    for (final File file in files) {
      events.addAll(parse(await file.readAsString()));
    }
    events.sort(_compareEvents);
    return events;
  }

  static int _compareEvents(
    DesktopLyricsDiagnosticEvent left,
    DesktopLyricsDiagnosticEvent right,
  ) {
    final int compareTime = left.timestamp.compareTo(right.timestamp);
    if (compareTime != 0) {
      return compareTime;
    }
    return left.sequence.compareTo(right.sequence);
  }

  static Map<String, String> _parseFields(String message) {
    final List<RegExpMatch> matches = _fieldKeyPattern
        .allMatches(message)
        .toList(growable: false);
    if (matches.isEmpty) {
      return const <String, String>{};
    }
    final Map<String, String> fields = <String, String>{};
    for (int index = 0; index < matches.length; index += 1) {
      final RegExpMatch match = matches[index];
      final String key = match.group(2) ?? '';
      if (key.isEmpty) {
        continue;
      }
      final int prefixLength = (match.group(1) ?? '').length;
      final int keyStart = match.start + prefixLength;
      final int valueStart = keyStart + key.length + 1;
      final int valueEnd = index + 1 < matches.length
          ? matches[index + 1].start
          : message.length;
      fields[key] = message.substring(valueStart, valueEnd).trim();
    }
    return fields;
  }
}
