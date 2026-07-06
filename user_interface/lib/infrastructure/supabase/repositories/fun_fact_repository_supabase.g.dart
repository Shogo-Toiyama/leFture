// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fun_fact_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(funFactRepository)
final funFactRepositoryProvider = FunFactRepositoryProvider._();

final class FunFactRepositoryProvider
    extends
        $FunctionalProvider<
          FunFactRepositorySupabase,
          FunFactRepositorySupabase,
          FunFactRepositorySupabase
        >
    with $Provider<FunFactRepositorySupabase> {
  FunFactRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'funFactRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$funFactRepositoryHash();

  @$internal
  @override
  $ProviderElement<FunFactRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FunFactRepositorySupabase create(Ref ref) {
    return funFactRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FunFactRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FunFactRepositorySupabase>(value),
    );
  }
}

String _$funFactRepositoryHash() => r'8ba6ccce5f74feef3a5dc579d2762bea97a28395';
