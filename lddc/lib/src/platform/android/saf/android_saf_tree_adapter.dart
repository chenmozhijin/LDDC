import 'package:flutter/services.dart';

import 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart';

export 'package:lddc_lyrics_runtime/lddc_lyrics_runtime.dart'
    show
        AndroidSafPersistedTree,
        AndroidSafTreeEntry,
        AndroidSafTreePage,
        AndroidSafTreePort,
        AndroidSafTreeToken,
        AndroidSafWriteDocumentResult;

/// 通过 MethodChannel 调用 Android SAF 目录能力。
class AndroidSafTreeAdapter implements AndroidSafTreePort {
  const AndroidSafTreeAdapter({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'lddc/android_saf_tree',
  );

  final MethodChannel _channel;

  @override
  Future<AndroidSafTreeToken> pickTree({String? initialUri}) async {
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('pickTree', <String, Object?>{
          'initialUri': initialUri,
        });
    if (result == null) {
      throw StateError('Android SAF 目录选择失败：返回结果为空');
    }
    final Object? uriRaw = result['uri'];
    if (uriRaw is! String || uriRaw.trim().isEmpty) {
      throw StateError('Android SAF 目录选择失败：uri 字段缺失');
    }
    return AndroidSafTreeToken(
      uri: uriRaw,
      displayName: result['displayName'] as String?,
    );
  }

  @override
  Future<void> persistTreePermission(String uri) async {
    await _channel.invokeMethod<void>(
      'persistTreePermission',
      <String, Object?>{'uri': uri},
    );
  }

  @override
  Future<List<AndroidSafPersistedTree>> listPersistedTrees() async {
    final List<Object?>? result = await _channel.invokeListMethod<Object?>(
      'listPersistedTrees',
    );
    if (result == null) {
      return const <AndroidSafPersistedTree>[];
    }
    return result.map(_parsePersistedTree).toList(growable: false);
  }

  @override
  Future<AndroidSafTreePage> listChildrenPage({
    required String uri,
    required int offset,
    required int limit,
  }) async {
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>(
          'listChildrenPage',
          <String, Object?>{'uri': uri, 'offset': offset, 'limit': limit},
        );
    if (result == null) {
      throw StateError('Android SAF 目录分页失败：返回结果为空');
    }
    final Object? entriesRaw = result['entries'];
    if (entriesRaw is! List) {
      throw StateError('Android SAF 目录分页 entries 字段类型错误');
    }
    final int? nextOffset = _nonNegativeInt(result['nextOffset'], 'nextOffset');
    return AndroidSafTreePage(
      entries: entriesRaw.map(_parseTreeEntry).toList(growable: false),
      nextOffset: nextOffset,
    );
  }

  @override
  Future<AndroidSafWriteDocumentResult> writeDocument({
    required String treeUri,
    required String displayName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final Map<Object?, Object?>? result = await _channel
        .invokeMapMethod<Object?, Object?>('writeDocument', <String, Object?>{
          'treeUri': treeUri,
          'displayName': displayName,
          'mimeType': mimeType,
          'bytes': bytes,
        });
    if (result == null) {
      throw StateError('Android SAF 写入文档失败：返回结果为空');
    }
    final String uri = _requiredString(result, 'uri', '写入文档结果');
    final String resultDisplayName =
        _stringOrNull(result['displayName'], 'displayName') ?? displayName;
    return AndroidSafWriteDocumentResult(
      uri: uri,
      displayName: resultDisplayName,
    );
  }

  AndroidSafPersistedTree _parsePersistedTree(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw StateError('Android SAF 持久授权项类型错误');
    }
    final String uri = _requiredString(value, 'uri', '持久授权项');
    return AndroidSafPersistedTree(
      uri: uri,
      displayName: _stringOrNull(value['displayName'], 'displayName'),
      persistedTimeMs:
          _nonNegativeInt(value['persistedTimeMs'], 'persistedTimeMs') ?? 0,
      readable: _boolOrFalse(value['readable'], 'readable'),
      writable: _boolOrFalse(value['writable'], 'writable'),
    );
  }

  AndroidSafTreeEntry _parseTreeEntry(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw StateError('Android SAF 目录子项类型错误');
    }
    final String uri = _requiredString(value, 'uri', '目录子项');
    final String displayName = _requiredString(value, 'displayName', '目录子项');
    return AndroidSafTreeEntry(
      uri: uri,
      displayName: displayName,
      mimeType: _stringOrNull(value['mimeType'], 'mimeType'),
      isDirectory: _boolOrFalse(value['isDirectory'], 'isDirectory'),
      isFile: _boolOrFalse(value['isFile'], 'isFile'),
      sizeBytes: _nonNegativeInt(value['sizeBytes'], 'sizeBytes'),
      lastModifiedMs: _nonNegativeInt(
        value['lastModifiedMs'],
        'lastModifiedMs',
      ),
    );
  }

  String _requiredString(
    Map<Object?, Object?> value,
    String field,
    String context,
  ) {
    final String? parsed = _stringOrNull(value[field], field);
    if (parsed == null) {
      throw StateError('Android SAF $context 缺少 $field');
    }
    return parsed;
  }

  String? _stringOrNull(Object? value, String field) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw StateError('Android SAF $field 字段类型错误');
    }
    final String normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _boolOrFalse(Object? value, String field) {
    if (value == null) {
      return false;
    }
    if (value is! bool) {
      throw StateError('Android SAF $field 字段类型错误');
    }
    return value;
  }

  int? _nonNegativeInt(Object? value, String field) {
    if (value == null) {
      return null;
    }
    if (value is! int || value < 0) {
      throw StateError('Android SAF $field 字段必须是非负整数');
    }
    return value;
  }
}
