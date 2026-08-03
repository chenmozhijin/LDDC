// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_page_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SettingsPageController)
final settingsPageControllerProvider = SettingsPageControllerProvider._();

final class SettingsPageControllerProvider
    extends
        $NotifierProvider<
          SettingsPageController,
          PageViewState<SettingsPagePayload>
        > {
  SettingsPageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsPageControllerProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[settingsPageDependenciesProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          SettingsPageControllerProvider.$allTransitiveDependencies0,
        ],
      );

  static final $allTransitiveDependencies0 = settingsPageDependenciesProvider;

  @override
  String debugGetCreateSourceHash() => _$settingsPageControllerHash();

  @$internal
  @override
  SettingsPageController create() => SettingsPageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PageViewState<SettingsPagePayload> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PageViewState<SettingsPagePayload>>(
        value,
      ),
    );
  }
}

String _$settingsPageControllerHash() =>
    r'a75025857d0ed3b93b4194b936a3cb29e6aba3dc';

abstract class _$SettingsPageController
    extends $Notifier<PageViewState<SettingsPagePayload>> {
  PageViewState<SettingsPagePayload> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              PageViewState<SettingsPagePayload>,
              PageViewState<SettingsPagePayload>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                PageViewState<SettingsPagePayload>,
                PageViewState<SettingsPagePayload>
              >,
              PageViewState<SettingsPagePayload>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
