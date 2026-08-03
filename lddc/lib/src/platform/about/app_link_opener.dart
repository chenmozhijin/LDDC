import 'app_link_opener_stub.dart'
    if (dart.library.io) 'app_link_opener_io.dart'
    if (dart.library.html) 'app_link_opener_io.dart'
    as impl;
import '../../core/about/about_ports.dart';

export '../../core/about/about_ports.dart' show AppLinkOpener;

AppLinkOpener createAppLinkOpener() => impl.createAppLinkOpener();
