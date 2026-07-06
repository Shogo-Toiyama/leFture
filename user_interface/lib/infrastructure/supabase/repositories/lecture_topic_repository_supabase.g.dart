// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_topic_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureTopicRepository)
final lectureTopicRepositoryProvider = LectureTopicRepositoryProvider._();

final class LectureTopicRepositoryProvider
    extends
        $FunctionalProvider<
          LectureTopicRepositorySupabase,
          LectureTopicRepositorySupabase,
          LectureTopicRepositorySupabase
        >
    with $Provider<LectureTopicRepositorySupabase> {
  LectureTopicRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureTopicRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureTopicRepositoryHash();

  @$internal
  @override
  $ProviderElement<LectureTopicRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureTopicRepositorySupabase create(Ref ref) {
    return lectureTopicRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureTopicRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureTopicRepositorySupabase>(
        value,
      ),
    );
  }
}

String _$lectureTopicRepositoryHash() =>
    r'df4640b97ee6d7a58a48c3162bd1056dd2d65fe3';
