// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'about_page_dependencies.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 关于页只关心“能否打开链接、能否检查更新、如何读取配置”。
/// 真实平台实现由 app 层注入，避免 feature 反向依赖 app provider 或平台适配器。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。使用生成器维护
// scope 元数据，避免关于页控制器跨过页面作用域读取到错误的依赖实例。

@ProviderFor(aboutPageDependencies)
final aboutPageDependenciesProvider = AboutPageDependenciesProvider._();

/// 关于页只关心“能否打开链接、能否检查更新、如何读取配置”。
/// 真实平台实现由 app 层注入，避免 feature 反向依赖 app provider 或平台适配器。
// Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。使用生成器维护
// scope 元数据，避免关于页控制器跨过页面作用域读取到错误的依赖实例。

final class AboutPageDependenciesProvider
    extends
        $FunctionalProvider<
          AboutPageDependencies,
          AboutPageDependencies,
          AboutPageDependencies
        >
    with $Provider<AboutPageDependencies> {
  /// 关于页只关心“能否打开链接、能否检查更新、如何读取配置”。
  /// 真实平台实现由 app 层注入，避免 feature 反向依赖 app provider 或平台适配器。
  // Riverpod 3.4 会在运行时校验 scoped provider 的传递依赖。使用生成器维护
  // scope 元数据，避免关于页控制器跨过页面作用域读取到错误的依赖实例。
  AboutPageDependenciesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aboutPageDependenciesProvider',
        isAutoDispose: true,
        dependencies: <ProviderOrFamily>[],
        $allTransitiveDependencies: <ProviderOrFamily>[],
      );

  @override
  String debugGetCreateSourceHash() => _$aboutPageDependenciesHash();

  @$internal
  @override
  $ProviderElement<AboutPageDependencies> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AboutPageDependencies create(Ref ref) {
    return aboutPageDependencies(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AboutPageDependencies value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AboutPageDependencies>(value),
    );
  }
}

String _$aboutPageDependenciesHash() =>
    r'c57bac057b5485b5030fd1207460c7bc6d4c2037';
