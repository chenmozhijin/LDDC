enum DesktopIpcTask {
  newDesktopLyricsInstance('new_desktop_lyrics_instance'),
  start('start'),
  pause('pause'),
  proceed('proceed'),
  stop('stop'),
  sync('sync'),
  changMusic('chang_music'),
  createPanel('create_panel'),
  updatePanelSurface('update_panel_surface'),
  destroyPanel('destroy_panel'),
  delInstance('del_instance');

  const DesktopIpcTask(this.value);

  final String value;

  static final Map<String, DesktopIpcTask> _byValue =
      Map<String, DesktopIpcTask>.unmodifiable(<String, DesktopIpcTask>{
        for (final task in values) task.value: task,
      });

  static DesktopIpcTask? tryParse(String value) => _byValue[value];
}

enum DesktopPanelSizeSpace {
  hostPhysicalPx('host_physical_px'),
  hostLogicalPx('host_logical_px'),
  flutterLogicalPx('flutter_logical_px'),
  unknownRaw('unknown_raw');

  const DesktopPanelSizeSpace(this.value);

  final String value;

  static final Map<String, DesktopPanelSizeSpace> _byValue =
      Map<String, DesktopPanelSizeSpace>.unmodifiable(
        <String, DesktopPanelSizeSpace>{
          for (final sizeSpace in values) sizeSpace.value: sizeSpace,
        },
      );

  static DesktopPanelSizeSpace? tryParse(String value) => _byValue[value];
}

enum DesktopControlCommandTask {
  play('play'),
  pause('pause'),
  stop('stop'),
  prev('prev'),
  next('next');

  const DesktopControlCommandTask(this.value);

  final String value;

  static final Map<String, DesktopControlCommandTask> _byValue =
      Map<String, DesktopControlCommandTask>.unmodifiable(
        <String, DesktopControlCommandTask>{
          for (final task in values) task.value: task,
        },
      );

  static DesktopControlCommandTask? tryParse(String value) => _byValue[value];
}

/// 客户端信息，对齐Python版 `info.name / info.ver` 语义。
final class DesktopClientInfo {
  const DesktopClientInfo({
    this.name,
    this.version,
    this.extra = const <String, Object?>{},
  });

  final String? name;
  final String? version;
  final Map<String, Object?> extra;

  factory DesktopClientInfo.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> extra = Map<String, Object?>.from(json);
    final Object? nameRaw = extra.remove('name');
    final Object? versionRaw = extra.remove('ver');
    return DesktopClientInfo(
      name: nameRaw?.toString(),
      version: versionRaw?.toString(),
      extra: Map<String, Object?>.unmodifiable(extra),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (name != null) 'name': name,
      if (version != null) 'ver': version,
      ...extra,
    };
  }
}

sealed class DesktopIpcMessage {
  const DesktopIpcMessage();

  Map<String, Object?> toJson();
}

sealed class DesktopClientMessage extends DesktopIpcMessage {
  const DesktopClientMessage({required this.task, this.instanceId});

  final DesktopIpcTask task;
  final int? instanceId;

  Map<String, Object?> buildJsonBase() {
    return <String, Object?>{
      'task': task.value,
      if (instanceId != null) 'id': instanceId,
    };
  }
}

/// 初次建连消息：不包含实例 id。
final class DesktopHelloMessage extends DesktopClientMessage {
  const DesktopHelloMessage({
    this.pid,
    this.availableTaskNames = const <String>[],
    this.clientInfo = const DesktopClientInfo(),
  }) : super(task: DesktopIpcTask.newDesktopLyricsInstance);

  final int? pid;
  final List<String> availableTaskNames;
  final DesktopClientInfo clientInfo;

  Set<DesktopControlCommandTask> get availableControlTasks {
    final Set<DesktopControlCommandTask> tasks = <DesktopControlCommandTask>{};
    for (final String value in availableTaskNames) {
      final DesktopControlCommandTask? task =
          DesktopControlCommandTask.tryParse(value);
      if (task != null) {
        tasks.add(task);
      }
    }
    return tasks;
  }

  bool supportsControlTask(DesktopControlCommandTask task) {
    // 常见调用只查询一个按钮能力，直接比对协议值即可，避免先解析全部任务并创建
    // 临时 Set。availableControlTasks 仍保留给需要完整能力快照的调用方。
    for (final String value in availableTaskNames) {
      if (value == task.value) {
        return true;
      }
    }
    return false;
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...buildJsonBase(),
      if (pid != null) 'pid': pid,
      'available_tasks': availableTaskNames,
      'info': clientInfo.toJson(),
    };
  }
}

sealed class DesktopInstanceMessage extends DesktopClientMessage {
  const DesktopInstanceMessage({
    required super.task,
    required int instanceId,
    this.playbackTimeMs,
    this.sendTimeSeconds,
  }) : super(instanceId: instanceId);

  int get id => instanceId!;

  final int? playbackTimeMs;
  final double? sendTimeSeconds;

  Map<String, Object?> buildInstanceJsonBase() {
    return <String, Object?>{
      ...buildJsonBase(),
      if (playbackTimeMs != null) 'playback_time': playbackTimeMs,
      if (sendTimeSeconds != null) 'send_time': sendTimeSeconds,
    };
  }
}

/// 无附加字段的实例任务，如 `start/pause/proceed/stop/sync/del_instance`。
final class DesktopSimpleTaskMessage extends DesktopInstanceMessage {
  const DesktopSimpleTaskMessage({
    required super.task,
    required super.instanceId,
    super.playbackTimeMs,
    super.sendTimeSeconds,
  });

  @override
  Map<String, Object?> toJson() => buildInstanceJsonBase();
}

final class DesktopChangMusicMessage extends DesktopInstanceMessage {
  const DesktopChangMusicMessage({
    required super.instanceId,
    this.title,
    this.artist,
    this.album,
    required this.durationMs,
    this.path,
    this.track,
    super.playbackTimeMs,
    super.sendTimeSeconds,
  }) : super(task: DesktopIpcTask.changMusic);

  final String? title;
  final String? artist;
  final String? album;
  final int durationMs;
  final String? path;
  final Object? track;

  String? get normalizedTrack => track?.toString();

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...buildInstanceJsonBase(),
      'title': title,
      'artist': artist,
      'album': album,
      'duration': durationMs,
      'path': path,
      'track': track,
    };
  }
}

final class DesktopPanelCreateMessage extends DesktopInstanceMessage {
  const DesktopPanelCreateMessage({
    required super.instanceId,
    required this.panelId,
    required this.hostWindowId,
  }) : super(task: DesktopIpcTask.createPanel);

  final int panelId;
  final int hostWindowId;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...buildInstanceJsonBase(),
      'panel_id': panelId,
      'host_window_id': hostWindowId,
    };
  }
}

final class DesktopPanelSurfaceUpdateMessage extends DesktopInstanceMessage {
  const DesktopPanelSurfaceUpdateMessage({
    required super.instanceId,
    required this.panelId,
    required this.width,
    required this.height,
    required this.sizeSpace,
    required this.visible,
  }) : super(task: DesktopIpcTask.updatePanelSurface);

  final int panelId;
  final int width;
  final int height;
  final DesktopPanelSizeSpace sizeSpace;
  final bool visible;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...buildInstanceJsonBase(),
      'panel_id': panelId,
      'width': width,
      'height': height,
      'size_space': sizeSpace.value,
      'visible': visible,
    };
  }
}

final class DesktopPanelDestroyMessage extends DesktopInstanceMessage {
  const DesktopPanelDestroyMessage({
    required super.instanceId,
    required this.panelId,
  }) : super(task: DesktopIpcTask.destroyPanel);

  final int panelId;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{...buildInstanceJsonBase(), 'panel_id': panelId};
  }
}

/// 服务端建连响应：Python版字段只有 `v/id`。
final class DesktopInstanceAckMessage extends DesktopIpcMessage {
  const DesktopInstanceAckMessage({
    required this.apiVersion,
    required this.instanceId,
  });

  final int apiVersion;
  final int instanceId;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{'v': apiVersion, 'id': instanceId};
  }
}

/// 服务端向客户端下发的控制任务。
final class DesktopControlCommandMessage extends DesktopIpcMessage {
  const DesktopControlCommandMessage({required this.task});

  final DesktopControlCommandTask task;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{'task': task.value};
  }
}

/// Python版任务字典解析器：将 JSON 字典映射为 Flutter 侧强类型消息。
final class DesktopIpcMessageCodec {
  const DesktopIpcMessageCodec();

  DesktopClientMessage decodeClientMessage(Map<String, Object?> json) {
    final DesktopIpcTask task = _readTask(json);
    if (task == DesktopIpcTask.newDesktopLyricsInstance) {
      return _decodeHelloMessage(json);
    }

    final int instanceId = _requireInt(json, 'id');
    switch (task) {
      case DesktopIpcTask.start:
      case DesktopIpcTask.pause:
      case DesktopIpcTask.proceed:
      case DesktopIpcTask.stop:
      case DesktopIpcTask.sync:
      case DesktopIpcTask.delInstance:
        return DesktopSimpleTaskMessage(
          task: task,
          instanceId: instanceId,
          playbackTimeMs: _readOptionalInt(json, 'playback_time'),
          sendTimeSeconds: _readOptionalDouble(json, 'send_time'),
        );
      case DesktopIpcTask.changMusic:
        return DesktopChangMusicMessage(
          instanceId: instanceId,
          title: _readOptionalString(json, 'title'),
          artist: _readOptionalString(json, 'artist'),
          album: _readOptionalString(json, 'album'),
          durationMs: _requireInt(json, 'duration'),
          path: _readOptionalString(json, 'path'),
          track: _readOptionalTrack(json, 'track'),
          playbackTimeMs: _readOptionalInt(json, 'playback_time'),
          sendTimeSeconds: _readOptionalDouble(json, 'send_time'),
        );
      case DesktopIpcTask.createPanel:
        return DesktopPanelCreateMessage(
          instanceId: instanceId,
          panelId: _requireInt(json, 'panel_id'),
          hostWindowId: _requireInt(json, 'host_window_id'),
        );
      case DesktopIpcTask.updatePanelSurface:
        return DesktopPanelSurfaceUpdateMessage(
          instanceId: instanceId,
          panelId: _requireInt(json, 'panel_id'),
          width: _requireNonNegativeInt(json, 'width'),
          height: _requireNonNegativeInt(json, 'height'),
          sizeSpace: _requirePanelSizeSpace(json, 'size_space'),
          visible: _requireBool(json, 'visible'),
        );
      case DesktopIpcTask.destroyPanel:
        return DesktopPanelDestroyMessage(
          instanceId: instanceId,
          panelId: _requireInt(json, 'panel_id'),
        );
      case DesktopIpcTask.newDesktopLyricsInstance:
        throw const FormatException('桌面 IPC 解析异常：建连消息不应带 id');
    }
  }

  DesktopInstanceAckMessage decodeInstanceAck(Map<String, Object?> json) {
    return DesktopInstanceAckMessage(
      apiVersion: _requireInt(json, 'v'),
      instanceId: _requireInt(json, 'id'),
    );
  }

  DesktopControlCommandMessage decodeControlCommand(Map<String, Object?> json) {
    final Object? taskRaw = json['task'];
    if (taskRaw is! String) {
      throw const FormatException('桌面 IPC 控制任务解析失败：task 缺失');
    }
    final DesktopControlCommandTask? task = DesktopControlCommandTask.tryParse(
      taskRaw,
    );
    if (task == null) {
      throw FormatException('桌面 IPC 控制任务不受支持：$taskRaw');
    }
    return DesktopControlCommandMessage(task: task);
  }

  DesktopHelloMessage _decodeHelloMessage(Map<String, Object?> json) {
    final Object? rawAvailableTasks = json['available_tasks'];
    if (rawAvailableTasks is! List<Object?>) {
      throw const FormatException('桌面 IPC 建连消息缺少 available_tasks');
    }
    final Object? rawInfo = json['info'];
    if (rawInfo != null && rawInfo is! Map<Object?, Object?>) {
      throw const FormatException('桌面 IPC 建连消息 info 字段类型错误');
    }
    return DesktopHelloMessage(
      pid: _readOptionalInt(json, 'pid'),
      availableTaskNames: rawAvailableTasks
          .map((Object? value) => value?.toString() ?? '')
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      clientInfo: DesktopClientInfo.fromJson(
        _normalizeObjectMap(rawInfo as Map<Object?, Object?>?),
      ),
    );
  }

  DesktopIpcTask _readTask(Map<String, Object?> json) {
    final Object? taskRaw = json['task'];
    if (taskRaw is! String) {
      throw const FormatException('桌面 IPC 解析失败：task 缺失');
    }
    final DesktopIpcTask? task = DesktopIpcTask.tryParse(taskRaw);
    if (task == null) {
      throw FormatException('桌面 IPC 任务不受支持：$taskRaw');
    }
    return task;
  }

  static Map<String, Object?> _normalizeObjectMap(
    Map<Object?, Object?>? value,
  ) {
    if (value == null) {
      return const <String, Object?>{};
    }
    final Map<String, Object?> normalized = <String, Object?>{};
    value.forEach((Object? key, Object? entryValue) {
      if (key != null) {
        normalized[key.toString()] = entryValue;
      }
    });
    return normalized;
  }

  static int _requireInt(Map<String, Object?> json, String key) {
    final int? value = _readOptionalInt(json, key);
    if (value == null) {
      throw FormatException('桌面 IPC 字段缺失或类型错误：$key');
    }
    return value;
  }

  static int _requireNonNegativeInt(Map<String, Object?> json, String key) {
    final int value = _requireInt(json, key);
    if (value < 0) {
      throw FormatException('桌面 IPC 字段必须是非负整数：$key');
    }
    return value;
  }

  static bool _requireBool(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    if (raw is bool) {
      return raw;
    }
    throw FormatException('桌面 IPC 字段缺失或类型错误：$key');
  }

  static DesktopPanelSizeSpace _requirePanelSizeSpace(
    Map<String, Object?> json,
    String key,
  ) {
    final String? raw = _readOptionalString(json, key);
    final DesktopPanelSizeSpace? sizeSpace = raw == null
        ? null
        : DesktopPanelSizeSpace.tryParse(raw);
    if (sizeSpace == null) {
      throw FormatException('桌面 IPC 字段缺失或类型错误：$key');
    }
    return sizeSpace;
  }

  static int? _readOptionalInt(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    return switch (raw) {
      null => null,
      int value => value,
      // JSON 小数即使数值接近整数也不能直接截断；只有有限且没有小数部分的
      // double 才能无损转换为协议整数，其余数值统一作为格式错误处理。
      double value when value.isFinite && value == value.truncateToDouble() =>
        value.toInt(),
      double _ => throw FormatException('桌面 IPC 数值字段必须是有限整数：$key'),
      _ => null,
    };
  }

  static double? _readOptionalDouble(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    return switch (raw) {
      null => null,
      double value when value.isFinite => value,
      int value => value.toDouble(),
      double _ => throw FormatException('桌面 IPC 数值字段必须是有限数值：$key'),
      _ => null,
    };
  }

  static String? _readOptionalString(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    return switch (raw) {
      null => null,
      String value => value,
      _ => null,
    };
  }

  static Object? _readOptionalTrack(Map<String, Object?> json, String key) {
    final Object? raw = json[key];
    return switch (raw) {
      null => null,
      int value => value,
      String value => value,
      _ => throw FormatException('桌面 IPC track 字段类型错误：$raw'),
    };
  }
}
