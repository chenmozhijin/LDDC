import 'app_update_checker_stub.dart'
    if (dart.library.io) 'app_update_checker_io.dart'
    if (dart.library.html) 'app_update_checker_web.dart'
    as impl;
import '../../core/about/about_ports.dart';

export '../../core/about/about_ports.dart' show AppUpdatePort;

AppUpdatePort createAppUpdatePort() => impl.createAppUpdatePort();
