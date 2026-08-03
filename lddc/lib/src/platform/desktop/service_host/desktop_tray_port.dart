export 'desktop_tray_port_types.dart';

import 'desktop_tray_port_factory_stub.dart'
    if (dart.library.io) 'desktop_tray_port_factory_io.dart'
    as impl;
import 'desktop_tray_port_types.dart';

DesktopTrayPort createDesktopTrayPort() => impl.createDesktopTrayPort();
