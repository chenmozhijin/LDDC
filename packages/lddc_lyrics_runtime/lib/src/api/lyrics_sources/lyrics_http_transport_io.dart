import '../http_transport_io.dart';
import 'kg_http_transport.dart';
import 'lrclib_http_transport.dart';
import 'lyrics_http_transport_adapters.dart';
import 'ne_http_transport.dart';
import 'qm_http_transport.dart';

KgHttpTransport createDefaultKgHttpTransport() {
  return KgHttpTransportAdapter(IoHttpTransport(autoUncompress: false));
}

LrclibHttpTransport createDefaultLrclibHttpTransport() {
  return LrclibHttpTransportAdapter(IoHttpTransport());
}

NeHttpTransport createDefaultNeHttpTransport() {
  return NeHttpTransportAdapter(IoHttpTransport(autoUncompress: false));
}

QmHttpTransport createDefaultQmHttpTransport() {
  return QmHttpTransportAdapter(IoHttpTransport(autoUncompress: false));
}
