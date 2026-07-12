// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fun_fact_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(funFactRepositoryDrift)
final funFactRepositoryDriftProvider = FunFactRepositoryDriftProvider._();

final class FunFactRepositoryDriftProvider
    extends
        $FunctionalProvider<
          FunFactRepositoryDrift,
          FunFactRepositoryDrift,
          FunFactRepositoryDrift
        >
    with $Provider<FunFactRepositoryDrift> {
  FunFactRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'funFactRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$funFactRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<FunFactRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FunFactRepositoryDrift create(Ref ref) {
    return funFactRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FunFactRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FunFactRepositoryDrift>(value),
    );
  }
}

String _$funFactRepositoryDriftHash() =>
    r'd05668ea01afe62a94ecab9f95f8c885335a8a58';
