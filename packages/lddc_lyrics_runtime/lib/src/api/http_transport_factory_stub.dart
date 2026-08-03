import 'http_transport.dart';

HttpTransport createHttpTransportImpl() {
  return const UnsupportedHttpTransport('当前平台不支持 dart:io HTTP 传输');
}
