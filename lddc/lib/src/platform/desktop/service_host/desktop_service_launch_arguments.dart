/// 桌面服务启动参数。
///
/// 这层与 `desktop_multi_window` 子窗口参数分离：
/// - `DesktopWindowLaunchArguments` 负责窗口角色；
/// - `DesktopServiceLaunchArguments` 负责桌面服务引导与 CLI 语义。
///
/// `--not-show` 是服务端口发现链路内部使用的隐藏启动参数。
///
/// 普通用户启动不能因为这个参数缺失而隐藏窗口；当 `--get-service-port`
/// 拉起后台服务时，Windows/Linux/macOS 都会通过同一参数进入隐藏服务入口。
class DesktopServiceLaunchArguments {
  const DesktopServiceLaunchArguments({
    this.getServicePort = false,
    this.notShow = false,
    this.parseError,
  });

  final bool getServicePort;
  final bool notShow;
  final String? parseError;

  bool get hasParseError => parseError != null;

  factory DesktopServiceLaunchArguments.parse(List<String> args) {
    bool getServicePort = false;
    bool notShow = false;
    String? parseError;

    for (final String rawArg in args) {
      final String arg = rawArg.trim();
      switch (arg) {
        case '--get-service-port':
          getServicePort = true;
        case '--not-show':
          notShow = true;
        case '':
          continue;
        default:
          parseError ??= '未知桌面服务参数：$arg';
      }
    }

    return DesktopServiceLaunchArguments(
      getServicePort: getServicePort,
      notShow: notShow,
      parseError: parseError,
    );
  }
}
