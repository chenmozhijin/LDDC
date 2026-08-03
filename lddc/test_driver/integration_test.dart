import 'package:integration_test/integration_test_driver.dart';

/// 通用集成测试宿主入口，让 Windows profile 构建把测试结果回传给命令行。
Future<void> main() => integrationDriver();
