import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lddc_lyrics_flutter/lddc_lyrics_flutter.dart';

/// LDDC 宿主的搜索依赖注入点，共享 Flutter 包不感知 Riverpod。
final Provider<SearchWorkflowDependencies> searchWorkflowDependenciesProvider =
    Provider<SearchWorkflowDependencies>((Ref ref) {
      throw StateError('SearchWorkflowDependencies 必须由 app 层或测试显式注入');
    }, dependencies: const []);

/// 共享控制器实例，仅由需要发出命令或直接监听的宿主组件读取。
final ChangeNotifierProvider<SearchWorkflowController>
searchWorkflowControllerInstanceProvider =
    ChangeNotifierProvider<SearchWorkflowController>((Ref ref) {
      return SearchWorkflowController(
        dependencies: ref.watch(searchWorkflowDependenciesProvider),
      );
    }, dependencies: [searchWorkflowDependenciesProvider]);

/// LDDC 的只读状态适配器，保留现有 Provider 选择器和测试等待工具的高效用法。
final Provider<SearchWorkflowState> searchWorkflowControllerProvider =
    Provider<SearchWorkflowState>((Ref ref) {
      return ref.watch(searchWorkflowControllerInstanceProvider).state;
    }, dependencies: [searchWorkflowControllerInstanceProvider]);
