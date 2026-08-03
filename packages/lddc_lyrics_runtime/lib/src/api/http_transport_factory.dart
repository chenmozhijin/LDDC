import 'http_transport.dart';
import 'http_transport_factory_stub.dart'
    if (dart.library.io) 'http_transport_factory_io.dart';

/// 创建当前平台的默认共享 HTTP 传输。
///
/// 调用方只持有 [HttpTransport] 并负责调用 `close`，不会依赖 runtime 的 IO 实现类。
HttpTransport createDefaultHttpTransport() => createHttpTransportImpl();
