import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart' show Override;

import '../core/i18n/i18n.dart';
import '../core/logging/logging.dart';
import '../features/about/application/about_page_dependencies.dart';
import '../features/about/presentation/about_page.dart';
import '../features/settings/application/settings_page_dependencies.dart';
import '../features/settings/presentation/settings_page.dart';
import '../platform/about/app_link_opener.dart';
import '../platform/about/app_update_checker.dart';
import 'bootstrap/app_runtime_providers.dart';
import 'shell/app_shell_providers.dart';
import 'shell/app_shell_route.dart';

class AppSearchPageScope extends _UnsupportedWebFeature {
  const AppSearchPageScope({super.key}) : super(route: AppShellRoute.search);
}

class AppLocalMatchPageScope extends _UnsupportedWebFeature {
  const AppLocalMatchPageScope({super.key})
    : super(route: AppShellRoute.localMatch);
}

class AppOpenLyricsPageScope extends _UnsupportedWebFeature {
  const AppOpenLyricsPageScope({super.key})
    : super(route: AppShellRoute.openLyrics);
}

class AppLibraryLinkManagerPageScope extends _UnsupportedWebFeature {
  const AppLibraryLinkManagerPageScope({super.key})
    : super(route: AppShellRoute.associationManager);
}

class AppBatchConvertPageScope extends _UnsupportedWebFeature {
  const AppBatchConvertPageScope({super.key})
    : super(route: AppShellRoute.batchConvert);
}

class AppSettingsPageScope extends ConsumerWidget {
  const AppSettingsPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: <Override>[
        settingsPageDependenciesProvider.overrideWithValue(
          SettingsPageDependencies(
            config: ref.watch(appConfigSnapshotProvider),
            capability: ref.watch(appCapabilityProvider),
            updateConfig: ref.read(configRepositoryProvider).update,
            pickDirectory: ({String? initialDirectory}) async => null,
            openAssociationManager: () async {
              ref.read(appShellRouteListenableProvider).value =
                  AppShellRoute.associationManager;
            },
            openLogDirectory: () async {
              throw UnsupportedError('Web 平台没有本地日志目录');
            },
            clearCache: () async {
              // Web 端不创建 sqlite 持久缓存，因此没有需要释放的本地缓存文件。
            },
            logFailure:
                ({
                  required String action,
                  required Object error,
                  required StackTrace stackTrace,
                  required Map<String, Object?> fields,
                }) {
                  AppLogger.scope('settings-web').error(
                    'Web 设置页操作失败',
                    fields: <String, Object?>{
                      'action': action,
                      'error': error.toString(),
                      'stackTrace': stackTrace.toString(),
                      ...fields,
                    },
                  );
                },
          ),
        ),
      ],
      child: const SettingsPage(),
    );
  }
}

class AppAboutPageScope extends ConsumerWidget {
  const AppAboutPageScope({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: <Override>[
        aboutPageDependenciesProvider.overrideWithValue(
          AboutPageDependencies(
            configRepository: ref.watch(configRepositoryProvider),
            linkOpener: createAppLinkOpener(),
            updatePort: createAppUpdatePort(),
          ),
        ),
      ],
      child: const AboutPage(),
    );
  }
}

class _UnsupportedWebFeature extends StatelessWidget {
  const _UnsupportedWebFeature({required this.route, super.key});

  final AppShellRoute route;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '${route.title(context.l10n)} 不支持 Web 平台',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
