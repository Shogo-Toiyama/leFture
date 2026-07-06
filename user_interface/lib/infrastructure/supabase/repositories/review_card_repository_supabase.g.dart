// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_card_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(reviewCardRepository)
final reviewCardRepositoryProvider = ReviewCardRepositoryProvider._();

final class ReviewCardRepositoryProvider
    extends
        $FunctionalProvider<
          ReviewCardRepositorySupabase,
          ReviewCardRepositorySupabase,
          ReviewCardRepositorySupabase
        >
    with $Provider<ReviewCardRepositorySupabase> {
  ReviewCardRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reviewCardRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reviewCardRepositoryHash();

  @$internal
  @override
  $ProviderElement<ReviewCardRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ReviewCardRepositorySupabase create(Ref ref) {
    return reviewCardRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReviewCardRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReviewCardRepositorySupabase>(value),
    );
  }
}

String _$reviewCardRepositoryHash() =>
    r'97dd6695d69a5e64b9b7642db9845b2fc9a1d794';
