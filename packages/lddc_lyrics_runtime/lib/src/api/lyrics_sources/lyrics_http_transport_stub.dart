import '../http_transport.dart';
import 'kg_http_transport.dart';
import 'lrclib_http_transport.dart';
import 'lyrics_http_transport_adapters.dart';
import 'ne_http_transport.dart';
import 'qm_http_transport.dart';

KgHttpTransport createDefaultKgHttpTransport() {
  return const KgHttpTransportAdapter(UnsupportedHttpTransport('KG 在当前平台暂不支持'));
}

LrclibHttpTransport createDefaultLrclibHttpTransport() {
  return const LrclibHttpTransportAdapter(
    UnsupportedHttpTransport('Lrclib 在当前平台暂不支持'),
  );
}

NeHttpTransport createDefaultNeHttpTransport() {
  return const NeHttpTransportAdapter(UnsupportedHttpTransport('NE 在当前平台暂不支持'));
}

QmHttpTransport createDefaultQmHttpTransport() {
  return const QmHttpTransportAdapter(
    UnsupportedHttpTransport('QM 在当前平台暂不支持（Web 不注册该来源）'),
  );
}
