// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_page_dependencies.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Settings 是可复用的功能页，不能直接读取 app 层或平台层 Provider。
/// 真实文件选择、导航和缓存清理由 app 层在页面外部注入；测试也必须显式注入，
/// 这样缺少运行时能力时会尽早失败，而不是在用户操作时才暴露空实现。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。这里交给生成器声明
// scope 元数据，控制器才能显式引用该依赖，同时继续保留原有 Provider 名称和覆盖方式。

@ProviderFor(settingsPageDependencies)
final settingsPageDependenciesProvider = SettingsPageDependenciesProvider._();

/// Settings 是可复用的功能页，不能直接读取 app 层或平台层 Provider。
/// 真实文件选择、导航和缓存清理由 app 层在页面外部注入；测试也必须显式注入，
/// 这样缺少运行时能力时会尽早失败，而不是在用户操作时才暴露空实现。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。这里交给生成器声明
// scope 元数据，控制器才能显式引用该依赖，同时继续保留原有 Provider 名称和覆盖方式。

final class SettingsPageDependenciesProvider
    extends
        $FunctionalProvider<
          SettingsPageDependencies,
          SettingsPageDependencies,
          SettingsPageDependencies
        >
    with $Provider<SettingsPageDependencies> {
  /// Settings 是可复用的功能页，不能直接读取 app 层或平台层 Provider。
  /// 真实文件选择、导航和缓存清理由 app 层在页面外部注入；测试也必须显式注入，
  /// 这样缺少运行时能力时会尽早失败，而不是在用户操作时才暴露空实现。
  // Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。这里交给生成器声明
  // scope 元数据，控制器才能显式引用该依赖，同时继续保留原有 Provider 名称和覆盖方式。
  SettingsPageDependenciesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsPageDependenciesProvider',
        isAutoDispose: true,
        dependencies: <ProviderOrFamily>[],
        $allTransitiveDependencies: <ProviderOrFamily>[],
      );

  @override
  String debugGetCreateSourceHash() => _$settingsPageDependenciesHash();

  @$internal
  @override
  $ProviderElement<SettingsPageDependencies> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SettingsPageDependencies create(Ref ref) {
    return settingsPageDependencies(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsPageDependencies value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsPageDependencies>(value),
    );
  }
}

String _$settingsPageDependenciesHash() =>
    r'a732b619a7fc5802820fe44391808fb861523b3a';
