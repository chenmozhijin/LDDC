// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'about_page_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AboutPageController)
final aboutPageControllerProvider = AboutPageControllerProvider._();

final class AboutPageControllerProvider
    extends
        $AsyncNotifierProvider<
          AboutPageController,
          PageViewState<AboutPagePayload>
        > {
  AboutPageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aboutPageControllerProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[aboutPageDependenciesProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          AboutPageControllerProvider.$allTransitiveDependencies0,
        ],
      );

  static final $allTransitiveDependencies0 = aboutPageDependenciesProvider;

  @override
  String debugGetCreateSourceHash() => _$aboutPageControllerHash();

  @$internal
  @override
  AboutPageController create() => AboutPageController();
}

String _$aboutPageControllerHash() =>
    r'408334ce9cc2653f76a4a59ce514b2ae0cb35a88';

abstract class _$AboutPageController
    extends $AsyncNotifier<PageViewState<AboutPagePayload>> {
  FutureOr<PageViewState<AboutPagePayload>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<PageViewState<AboutPagePayload>>,
              PageViewState<AboutPagePayload>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<PageViewState<AboutPagePayload>>,
                PageViewState<AboutPagePayload>
              >,
              AsyncValue<PageViewState<AboutPagePayload>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
