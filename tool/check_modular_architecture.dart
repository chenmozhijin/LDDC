import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';

const Set<String> _sharedPackages = <String>{
  'lddc_lyrics_core',
  'lddc_lyrics_runtime',
  'lddc_lyrics_flutter',
  'lddc_desktop_lyrics',
};

const Map<String, Set<String>> _allowedSharedEdges = <String, Set<String>>{
  'lddc_lyrics_core': <String>{},
  'lddc_lyrics_runtime': <String>{'lddc_lyrics_core'},
  'lddc_lyrics_flutter': <String>{'lddc_lyrics_core', 'lddc_lyrics_runtime'},
  'lddc_desktop_lyrics': <String>{'lddc_lyrics_core'},
};

const Map<String, Set<String>> _allowedHostEdges = <String, Set<String>>{
  'app': <String>{'app', 'features', 'core', 'infra', 'platform', 'shared'},
  'features': <String>{'features', 'core', 'shared'},
  'core': <String>{'core', 'shared'},
  'infra': <String>{'infra', 'core', 'shared'},
  'platform': <String>{'platform', 'core', 'shared'},
  'shared': <String>{'shared', 'core'},
};

Future<void> main(List<String> args) async {
  final Directory root = args.isEmpty ? Directory.current : Directory(args[0]);
  final List<String> failures = await checkModularArchitecture(root);
  if (failures.isNotEmpty) {
    stderr.writeln('模块化架构门禁失败：');
    for (final String failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('模块化架构门禁通过');
}

/// 使用 analyzer AST 检查生产源码中的真实 import/export，不扫描注释或字符串。
Future<List<String>> checkModularArchitecture(
  Directory root, {
  bool checkPubDependencyGraph = true,
}) async {
  final List<String> failures = <String>[];
  final Map<String, Set<String>> sourceGraph = <String, Set<String>>{};
  _checkHostLayers(root, failures, sourceGraph);
  _checkSharedPackages(root, failures, sourceGraph);
  _checkConsumers(root, failures, sourceGraph);
  _checkCycles(sourceGraph, failures, label: '源码依赖图');
  if (checkPubDependencyGraph &&
      File(_join(root.path, 'pubspec.yaml')).existsSync()) {
    await _checkPubDependencyGraph(root, failures);
  }
  return List<String>.unmodifiable(failures);
}

void _checkHostLayers(
  Directory root,
  List<String> failures,
  Map<String, Set<String>> graph,
) {
  final Directory sourceRoot = Directory(
    _join(root.path, 'lddc', 'lib', 'src'),
  );
  for (final File file in _dartFiles(sourceRoot)) {
    final String? sourceLayer = _hostLayer(sourceRoot, file);
    if (sourceLayer == null) {
      failures.add('${_relative(root, file)} 不属于已声明宿主层');
      continue;
    }
    final String sourceNode = 'host:$sourceLayer';
    graph.putIfAbsent(sourceNode, () => <String>{});
    for (final _DirectiveUri directive in _directives(file, failures, root)) {
      final String uri = directive.uri;
      final String? sharedPackage = _sharedPackageFromUri(uri);
      if (sharedPackage != null) {
        _checkPublicBarrel(root, file, uri, sharedPackage, failures);
        graph[sourceNode]!.add('package:$sharedPackage');
        continue;
      }
      if (uri.startsWith('package:lddc/')) {
        if (uri.contains('/src/') && !uri.startsWith('package:lddc/src/')) {
          failures.add('${_relative(root, file)} 使用了非法宿主 src URI: $uri');
          continue;
        }
        final String? targetLayer = _hostLayerFromPackageUri(uri);
        _checkHostEdge(
          root: root,
          file: file,
          sourceLayer: sourceLayer,
          targetLayer: targetLayer,
          uri: uri,
          failures: failures,
          graph: graph,
        );
        continue;
      }
      if (_isRelativeUri(uri)) {
        final File target = File(_normalize(_join(file.parent.path, uri)));
        if (_isWithin(sourceRoot.path, target.path)) {
          _checkHostEdge(
            root: root,
            file: file,
            sourceLayer: sourceLayer,
            targetLayer: _hostLayer(sourceRoot, target),
            uri: uri,
            failures: failures,
            graph: graph,
          );
        }
      }
    }
  }
}

void _checkHostEdge({
  required Directory root,
  required File file,
  required String sourceLayer,
  required String? targetLayer,
  required String uri,
  required List<String> failures,
  required Map<String, Set<String>> graph,
}) {
  if (targetLayer == null) {
    failures.add('${_relative(root, file)} 无法解析宿主依赖层: $uri');
    return;
  }
  graph['host:$sourceLayer']!.add('host:$targetLayer');
  if (!(_allowedHostEdges[sourceLayer]?.contains(targetLayer) ?? false)) {
    failures.add(
      '${_relative(root, file)} 禁止宿主层依赖 $sourceLayer -> $targetLayer: $uri',
    );
  }
}

void _checkSharedPackages(
  Directory root,
  List<String> failures,
  Map<String, Set<String>> graph,
) {
  for (final String packageName in _sharedPackages) {
    final String node = 'package:$packageName';
    graph.putIfAbsent(node, () => <String>{});
    final Directory lib = Directory(
      _join(root.path, 'packages', packageName, 'lib'),
    );
    for (final File file in _dartFiles(lib)) {
      for (final _DirectiveUri directive in _directives(file, failures, root)) {
        final String uri = directive.uri;
        if (uri.startsWith('package:lddc/')) {
          failures.add('${_relative(root, file)} 反向依赖 LDDC 宿主: $uri');
        }
        final String? targetPackage = _sharedPackageFromUri(uri);
        if (targetPackage != null && targetPackage != packageName) {
          graph[node]!.add('package:$targetPackage');
          _checkPublicBarrel(root, file, uri, targetPackage, failures);
          if (!(_allowedSharedEdges[packageName]?.contains(targetPackage) ??
              false)) {
            failures.add('$packageName 禁止依赖 $targetPackage: $uri');
          }
        }
        _checkPackageSpecificBan(
          root: root,
          file: file,
          packageName: packageName,
          uri: uri,
          failures: failures,
        );
      }
    }
  }
}

void _checkPackageSpecificBan({
  required Directory root,
  required File file,
  required String packageName,
  required String uri,
  required List<String> failures,
}) {
  final bool forbidden = switch (packageName) {
    'lddc_lyrics_core' =>
      uri == 'dart:io' ||
          uri == 'dart:ui' ||
          uri.startsWith('package:flutter') ||
          uri.startsWith('package:riverpod') ||
          uri.startsWith('package:flutter_riverpod'),
    'lddc_lyrics_runtime' =>
      uri.startsWith('package:flutter') ||
          uri.startsWith('package:riverpod') ||
          uri.startsWith('package:flutter_riverpod') ||
          uri.startsWith('package:lddc_desktop_lyrics'),
    'lddc_lyrics_flutter' =>
      uri.startsWith('package:lddc/') ||
          uri.startsWith('package:lddc_desktop_lyrics'),
    'lddc_desktop_lyrics' =>
      uri.startsWith('package:lddc/') ||
          uri.startsWith('package:lddc_lyrics_runtime'),
    _ => false,
  };
  if (forbidden) {
    failures.add('${_relative(root, file)} 的 $packageName 禁止依赖 $uri');
  }
}

void _checkConsumers(
  Directory root,
  List<String> failures,
  Map<String, Set<String>> graph,
) {
  final Directory examples = Directory(_join(root.path, 'examples'));
  for (final File file in _dartFiles(examples)) {
    final String exampleName = _relative(examples, file).split('/').first;
    final String node = 'example:$exampleName';
    graph.putIfAbsent(node, () => <String>{});
    for (final _DirectiveUri directive in _directives(file, failures, root)) {
      final String uri = directive.uri;
      if (uri.startsWith('package:lddc/')) {
        failures.add('${_relative(root, file)} 依赖了 LDDC 应用代码: $uri');
      }
      final String? packageName = _sharedPackageFromUri(uri);
      if (packageName != null) {
        graph[node]!.add('package:$packageName');
        _checkPublicBarrel(root, file, uri, packageName, failures);
      }
    }
  }
  final File mobilePubspec = File(
    _join(root.path, 'examples', 'lyrics_consumer', 'pubspec.yaml'),
  );
  if (mobilePubspec.existsSync() &&
      mobilePubspec.readAsStringSync().contains('lddc_desktop_lyrics:')) {
    failures.add('移动安全消费者不应依赖 lddc_desktop_lyrics');
  }
}

void _checkPublicBarrel(
  Directory root,
  File file,
  String uri,
  String packageName,
  List<String> failures,
) {
  final String expected = 'package:$packageName/$packageName.dart';
  if (uri != expected) {
    failures.add(
      '${_relative(root, file)} 必须通过 $packageName 正式 barrel，实际为 $uri',
    );
  }
}

Iterable<_DirectiveUri> _directives(
  File file,
  List<String> failures,
  Directory root,
) sync* {
  try {
    final ParseStringResult result = parseFile(
      path: _normalize(file.path),
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    for (final Directive directive in result.unit.directives) {
      if (directive is ImportDirective) {
        yield _DirectiveUri(directive.uri.stringValue ?? '');
      } else if (directive is ExportDirective) {
        yield _DirectiveUri(directive.uri.stringValue ?? '');
      }
    }
  } on Object catch (error) {
    failures.add('${_relative(root, file)} AST 解析失败: $error');
  }
}

Future<void> _checkPubDependencyGraph(
  Directory root,
  List<String> failures,
) async {
  final ProcessResult result = await Process.run(
    Platform.resolvedExecutable,
    <String>['pub', 'deps', '--json'],
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    failures.add('无法读取 pub 依赖图: ${result.stderr}');
    return;
  }
  final Map<String, Object?> document =
      jsonDecode(result.stdout as String) as Map<String, Object?>;
  final Map<String, Set<String>> graph = <String, Set<String>>{};
  for (final Object? value in document['packages']! as List<Object?>) {
    final Map<String, Object?> item = value! as Map<String, Object?>;
    final String name = item['name']! as String;
    if (!_sharedPackages.contains(name)) {
      continue;
    }
    final Set<String> dependencies =
        (item['directDependencies']! as List<Object?>)
            .cast<String>()
            .where(_sharedPackages.contains)
            .toSet();
    graph[name] = dependencies;
    if ((item['directDependencies']! as List<Object?>).contains('lddc')) {
      failures.add('$name 的 pubspec 反向依赖 lddc');
    }
    for (final String dependency in dependencies) {
      if (!(_allowedSharedEdges[name]?.contains(dependency) ?? false)) {
        failures.add('$name 的 pubspec 禁止依赖 $dependency');
      }
    }
  }
  for (final String packageName in _sharedPackages) {
    if (!graph.containsKey(packageName)) {
      failures.add('pub 依赖图缺少共享包 $packageName');
    }
  }
  _checkCycles(graph, failures, label: 'pub package 依赖图');
}

void _checkCycles(
  Map<String, Set<String>> graph,
  List<String> failures, {
  required String label,
}) {
  final Set<String> visiting = <String>{};
  final Set<String> visited = <String>{};
  bool visit(String node, List<String> path) {
    if (visiting.contains(node)) {
      failures.add('$label 存在环: ${<String>[...path, node].join(' -> ')}');
      return false;
    }
    if (!visited.add(node)) {
      return true;
    }
    visiting.add(node);
    for (final String dependency in graph[node] ?? const <String>{}) {
      if (dependency == node) {
        continue;
      }
      if (!visit(dependency, <String>[...path, node])) {
        return false;
      }
    }
    visiting.remove(node);
    return true;
  }

  for (final String node in graph.keys) {
    if (!visit(node, const <String>[])) {
      return;
    }
  }
}

Iterable<File> _dartFiles(Directory directory) sync* {
  if (!directory.existsSync()) {
    return;
  }
  for (final FileSystemEntity entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

String? _hostLayer(Directory sourceRoot, File file) {
  if (!_isWithin(sourceRoot.path, file.path)) {
    return null;
  }
  final String relative = _relative(sourceRoot, file);
  return relative.split('/').firstOrNull;
}

String? _hostLayerFromPackageUri(String uri) {
  const String prefix = 'package:lddc/src/';
  if (!uri.startsWith(prefix)) {
    return null;
  }
  final String remainder = uri.substring(prefix.length);
  return remainder.split('/').firstOrNull;
}

String? _sharedPackageFromUri(String uri) {
  if (!uri.startsWith('package:')) {
    return null;
  }
  final String packageName = uri.substring(8).split('/').first;
  return _sharedPackages.contains(packageName) ? packageName : null;
}

bool _isRelativeUri(String uri) {
  return !uri.startsWith('dart:') &&
      !uri.startsWith('package:') &&
      !uri.contains('://');
}

bool _isWithin(String parent, String child) {
  final String normalizedParent = _normalize(parent).toLowerCase();
  final String normalizedChild = _normalize(child).toLowerCase();
  return normalizedChild == normalizedParent ||
      normalizedChild.startsWith('$normalizedParent${Platform.pathSeparator}');
}

String _normalize(String path) {
  return Uri.file(File(path).absolute.path).normalizePath().toFilePath();
}

String _join(String first, [String? second, String? third, String? fourth]) {
  return <String?>[
    first,
    second,
    third,
    fourth,
  ].whereType<String>().join(Platform.pathSeparator);
}

String _relative(Directory root, File file) {
  return file.absolute.path
      .substring(root.absolute.path.length + 1)
      .replaceAll('\\', '/');
}

final class _DirectiveUri {
  const _DirectiveUri(this.uri);

  final String uri;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
