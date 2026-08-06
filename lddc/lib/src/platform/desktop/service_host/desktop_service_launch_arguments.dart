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

    for (int index = 0; index < args.length; index += 1) {
      final String arg = args[index].trim();
      switch (arg) {
        case '--get-service-port':
          getServicePort = true;
        case '--not-show':
          notShow = true;
        case '-NSTreatUnknownArgumentsAsOpen':
          // App-hosted XCTest 会由 AppKit 注入这个标准参数，并在
          // 后面跟随单独的 YES/NO 值。两者都不属于 LDDC 桌面服务
          // CLI；如果只忽略标志而留下 NO，应用会在 XCTest runner check-in
          // 之前因“未知参数”退出。这里只消耗精确的 YES/NO；其他
          // 跟随值依旧作为未知参数报错，不放宽公共 CLI。
          if (index + 1 < args.length) {
            final String value = args[index + 1].trim();
            if (value == 'YES' || value == 'NO') {
              index += 1;
            }
          }
          continue;
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
