import '../http_transport_io.dart';
import 'translate_http_client_adapter.dart';
import 'translate_http_client.dart';

TranslateHttpClient createDefaultTranslateHttpClient() =>
    TranslateHttpClientAdapter(IoHttpTransport());
