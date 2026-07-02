// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'galaxy_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GalaxyStateNotifier)
final galaxyStateProvider = GalaxyStateNotifierProvider._();

final class GalaxyStateNotifierProvider
    extends $NotifierProvider<GalaxyStateNotifier, GalaxyState> {
  GalaxyStateNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'galaxyStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$galaxyStateNotifierHash();

  @$internal
  @override
  GalaxyStateNotifier create() => GalaxyStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GalaxyState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GalaxyState>(value),
    );
  }
}

String _$galaxyStateNotifierHash() =>
    r'a528f3a0ab30f4a4a9bb6bf950561f69f849b1a3';

abstract class _$GalaxyStateNotifier extends $Notifier<GalaxyState> {
  GalaxyState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<GalaxyState, GalaxyState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GalaxyState, GalaxyState>,
              GalaxyState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
