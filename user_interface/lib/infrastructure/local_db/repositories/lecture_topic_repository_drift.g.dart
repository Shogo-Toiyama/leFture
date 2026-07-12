// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_topic_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureTopicRepositoryDrift)
final lectureTopicRepositoryDriftProvider =
    LectureTopicRepositoryDriftProvider._();

final class LectureTopicRepositoryDriftProvider
    extends
        $FunctionalProvider<
          LectureTopicRepositoryDrift,
          LectureTopicRepositoryDrift,
          LectureTopicRepositoryDrift
        >
    with $Provider<LectureTopicRepositoryDrift> {
  LectureTopicRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureTopicRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureTopicRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<LectureTopicRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureTopicRepositoryDrift create(Ref ref) {
    return lectureTopicRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureTopicRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureTopicRepositoryDrift>(value),
    );
  }
}

String _$lectureTopicRepositoryDriftHash() =>
    r'cf2168049e99303668c2b334cadd76f4a12cc30b';
