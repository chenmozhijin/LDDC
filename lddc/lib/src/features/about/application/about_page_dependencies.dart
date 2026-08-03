import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/about/about_ports.dart';
import '../../../core/config/config.dart';

part 'about_page_dependencies.g.dart';

class AboutPageDependencies {
  const AboutPageDependencies({
    required this.configRepository,
    required this.linkOpener,
    required this.updatePort,
  });

  final ConfigRepository configRepository;
  final AppLinkOpener linkOpener;
  final AppUpdatePort updatePort;
}

/// 关于页只关心“能否打开链接、能否检查更新、如何读取配置”。
/// 真实平台实现由 app 层注入，避免 feature 反向依赖 app provider 或平台适配器。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。使用生成器维护
// scope 元数据，避免关于页控制器跨过页面作用域读取到错误的依赖实例。
@Riverpod(dependencies: [])
AboutPageDependencies aboutPageDependencies(Ref ref) {
  throw StateError('AboutPageDependencies 必须由 app 层或测试显式注入');
}
