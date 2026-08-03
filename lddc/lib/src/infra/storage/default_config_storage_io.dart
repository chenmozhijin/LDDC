import '../../core/config/config_repository.dart';
import 'config_file_storage_io.dart';

ConfigStorage createDefaultConfigStorage() {
  return JsonFileConfigStorage();
}
