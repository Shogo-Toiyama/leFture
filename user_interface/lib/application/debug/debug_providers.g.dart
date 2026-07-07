// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'debug_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DebugForceEmptyHome)
final debugForceEmptyHomeProvider = DebugForceEmptyHomeProvider._();

final class DebugForceEmptyHomeProvider
    extends $NotifierProvider<DebugForceEmptyHome, bool> {
  DebugForceEmptyHomeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'debugForceEmptyHomeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$debugForceEmptyHomeHash();

  @$internal
  @override
  DebugForceEmptyHome create() => DebugForceEmptyHome();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$debugForceEmptyHomeHash() =>
    r'8a762621ae54079aca3a49a34540f9584635258e';

abstract class _$DebugForceEmptyHome extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
