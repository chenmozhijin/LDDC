import '../../core/config/config_repository.dart';

ConfigStorage createDefaultConfigStorage() {
  return InMemoryConfigStorage();
}
