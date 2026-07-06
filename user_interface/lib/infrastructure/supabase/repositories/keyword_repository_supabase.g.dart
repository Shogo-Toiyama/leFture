// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyword_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(keywordRepository)
final keywordRepositoryProvider = KeywordRepositoryProvider._();

final class KeywordRepositoryProvider
    extends
        $FunctionalProvider<
          KeywordRepositorySupabase,
          KeywordRepositorySupabase,
          KeywordRepositorySupabase
        >
    with $Provider<KeywordRepositorySupabase> {
  KeywordRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keywordRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keywordRepositoryHash();

  @$internal
  @override
  $ProviderElement<KeywordRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  KeywordRepositorySupabase create(Ref ref) {
    return keywordRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeywordRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeywordRepositorySupabase>(value),
    );
  }
}

String _$keywordRepositoryHash() => r'1616798f4eadca63bec2ddb6f66f51fef516eae8';
