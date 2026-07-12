// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyword_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(keywordRepositoryDrift)
final keywordRepositoryDriftProvider = KeywordRepositoryDriftProvider._();

final class KeywordRepositoryDriftProvider
    extends
        $FunctionalProvider<
          KeywordRepositoryDrift,
          KeywordRepositoryDrift,
          KeywordRepositoryDrift
        >
    with $Provider<KeywordRepositoryDrift> {
  KeywordRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keywordRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keywordRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<KeywordRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  KeywordRepositoryDrift create(Ref ref) {
    return keywordRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeywordRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeywordRepositoryDrift>(value),
    );
  }
}

String _$keywordRepositoryDriftHash() =>
    r'57b6b8130a8e35652a895d3fffacb0d72c963032';
