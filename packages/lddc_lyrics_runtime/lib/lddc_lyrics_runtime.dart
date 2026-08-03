/// LDDC 的无 UI 歌词运行时公共 API。
library;

// 稳定端口、模型与用例。
export 'src/api/http_transport.dart';
export 'src/api/http_transport_factory.dart';
export 'src/api/lyrics_sources/ne_client_profile.dart';
export 'src/api/lyrics_sources/ne_cover_request_policy.dart';
export 'src/api/lyrics_sources/ne_device_ids.dart';
export 'src/api/lyrics_sources/qm_request_executor.dart' show QmApiClient;
export 'src/audio_tag/audio_file_extensions.dart';
export 'src/audio_tag/audio_tag_port.dart';
export 'src/auto_fetch/auto_fetch.dart';
export 'src/cache/cache_facade.dart';
export 'src/cache/cache_store.dart';
export 'src/cache/cache_ttl.dart';
export 'src/cache/cache_types.dart';
export 'src/error/app_error_mapper.dart';
export 'src/files/background_file_io.dart';
export 'src/files/file_ports.dart';
export 'src/logging/runtime_logger.dart';
export 'src/lyrics_source/local_lyrics_input_normalizer.dart';
export 'src/lyrics_source/lyrics_client.dart';
export 'src/lyrics_source/lyrics_source_provider.dart';
export 'src/lyrics_source/lyrics_source_registry.dart';
export 'src/network/request_budget.dart';
export 'src/network/request_cancellation.dart';
export 'src/parser/cue_parser.dart';
export 'src/parser/unknown_encoding_file_reader.dart';
export 'src/task/task.dart';
export 'src/translate/translation_client.dart';
export 'src/translate/translation_options.dart';
export 'src/translate/translation_progress.dart';

// 正式组合根与默认组件工厂。具体 executor、transport adapter、协议 reader、
// TranslateApi、测试缓存和 *Impl 均留在 src 内，不构成消费者兼容面。
export 'src/runtime/default_runtime_factories.dart';
export 'src/runtime/lddc_lyrics_runtime.dart';
