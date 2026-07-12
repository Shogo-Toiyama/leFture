// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_card_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reviewCardRepositoryDrift)
final reviewCardRepositoryDriftProvider = ReviewCardRepositoryDriftProvider._();

final class ReviewCardRepositoryDriftProvider
    extends
        $FunctionalProvider<
          ReviewCardRepositoryDrift,
          ReviewCardRepositoryDrift,
          ReviewCardRepositoryDrift
        >
    with $Provider<ReviewCardRepositoryDrift> {
  ReviewCardRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewCardRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewCardRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<ReviewCardRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReviewCardRepositoryDrift create(Ref ref) {
    return reviewCardRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReviewCardRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReviewCardRepositoryDrift>(value),
    );
  }
}

String _$reviewCardRepositoryDriftHash() =>
    r'6fe6fb5e2978f6e8b1363b925d2ab2687972ca8c';
