// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_runtime_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 运行期能力开关快照，统一从 Riverpod 树读取。

@ProviderFor(appCapability)
final appCapabilityProvider = AppCapabilityProvider._();

/// 运行期能力开关快照，统一从 Riverpod 树读取。

final class AppCapabilityProvider
    extends $FunctionalProvider<AppCapability, AppCapability, AppCapability>
    with $Provider<AppCapability> {
  /// 运行期能力开关快照，统一从 Riverpod 树读取。
  AppCapabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appCapabilityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appCapabilityHash();

  @$internal
  @override
  $ProviderElement<AppCapability> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppCapability create(Ref ref) {
    return appCapability(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppCapability value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppCapability>(value),
    );
  }
}

String _$appCapabilityHash() => r'0179c9d4646aacca083aeb1461092371558269e9';

/// 运行期配置快照：
/// 优先消费配置流最新值，未就绪时回退到仓储当前值。

@ProviderFor(appConfigSnapshot)
final appConfigSnapshotProvider = AppConfigSnapshotProvider._();

/// 运行期配置快照：
/// 优先消费配置流最新值，未就绪时回退到仓储当前值。

final class AppConfigSnapshotProvider
    extends $FunctionalProvider<AppConfig, AppConfig, AppConfig>
    with $Provider<AppConfig> {
  /// 运行期配置快照：
  /// 优先消费配置流最新值，未就绪时回退到仓储当前值。
  AppConfigSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appConfigSnapshotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appConfigSnapshotHash();

  @$internal
  @override
  $ProviderElement<AppConfig> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppConfig create(Ref ref) {
    return appConfigSnapshot(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppConfig value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppConfig>(value),
    );
  }
}

String _$appConfigSnapshotHash() => r'e7e5d6660a46c3c2f8225127389f5df141d339ec';

/// 当前应用 locale：
/// `auto` 跟随系统，显式语言则映射到受支持的 locale。

@ProviderFor(appLocale)
final appLocaleProvider = AppLocaleProvider._();

/// 当前应用 locale：
/// `auto` 跟随系统，显式语言则映射到受支持的 locale。

final class AppLocaleProvider
    extends $FunctionalProvider<Locale?, Locale?, Locale?>
    with $Provider<Locale?> {
  /// 当前应用 locale：
  /// `auto` 跟随系统，显式语言则映射到受支持的 locale。
  AppLocaleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLocaleProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLocaleHash();

  @$internal
  @override
  $ProviderElement<Locale?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Locale? create(Ref ref) {
    return appLocale(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Locale? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Locale?>(value),
    );
  }
}

String _$appLocaleHash() => r'29ddf62618b2484035488f27a852445dfc7062f6';

/// 主题模式映射：保持与配置 `app.colorScheme` 一致。

@ProviderFor(appThemeMode)
final appThemeModeProvider = AppThemeModeProvider._();

/// 主题模式映射：保持与配置 `app.colorScheme` 一致。

final class AppThemeModeProvider
    extends $FunctionalProvider<ThemeMode, ThemeMode, ThemeMode>
    with $Provider<ThemeMode> {
  /// 主题模式映射：保持与配置 `app.colorScheme` 一致。
  AppThemeModeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeModeHash();

  @$internal
  @override
  $ProviderElement<ThemeMode> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeMode create(Ref ref) {
    return appThemeMode(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$appThemeModeHash() => r'ef891d7de674b95e76f16c215441ffb89f2f835b';

/// 亮色主题：用于 Light/System(亮色) 分支。

@ProviderFor(appLightTheme)
final appLightThemeProvider = AppLightThemeProvider._();

/// 亮色主题：用于 Light/System(亮色) 分支。

final class AppLightThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  /// 亮色主题：用于 Light/System(亮色) 分支。
  AppLightThemeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLightThemeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLightThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return appLightTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$appLightThemeHash() => r'6b80bf20f6091cd30b15e5678a441ffdda86b04b';

/// 暗色主题：用于 Dark/System(暗色) 分支。

@ProviderFor(appDarkTheme)
final appDarkThemeProvider = AppDarkThemeProvider._();

/// 暗色主题：用于 Dark/System(暗色) 分支。

final class AppDarkThemeProvider
    extends $FunctionalProvider<ThemeData, ThemeData, ThemeData>
    with $Provider<ThemeData> {
  /// 暗色主题：用于 Dark/System(暗色) 分支。
  AppDarkThemeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDarkThemeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDarkThemeHash();

  @$internal
  @override
  $ProviderElement<ThemeData> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ThemeData create(Ref ref) {
    return appDarkTheme(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeData>(value),
    );
  }
}

String _$appDarkThemeHash() => r'd8a020ba4d29239aeab37308f3513d63cb256bab';
