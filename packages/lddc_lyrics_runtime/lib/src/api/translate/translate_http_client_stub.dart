import '../http_transport.dart';
import 'translate_http_client_adapter.dart';
import 'translate_http_client.dart';

TranslateHttpClient createDefaultTranslateHttpClient() =>
    const TranslateHttpClientAdapter(UnsupportedHttpTransport('当前平台不支持翻译网络请求'));
