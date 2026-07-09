// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_map_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(topicMapRepository)
final topicMapRepositoryProvider = TopicMapRepositoryProvider._();

final class TopicMapRepositoryProvider
    extends
        $FunctionalProvider<
          TopicMapRepositorySupabase,
          TopicMapRepositorySupabase,
          TopicMapRepositorySupabase
        >
    with $Provider<TopicMapRepositorySupabase> {
  TopicMapRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'topicMapRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$topicMapRepositoryHash();

  @$internal
  @override
  $ProviderElement<TopicMapRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TopicMapRepositorySupabase create(Ref ref) {
    return topicMapRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TopicMapRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TopicMapRepositorySupabase>(value),
    );
  }
}

String _$topicMapRepositoryHash() =>
    r'12e5caca87756625dcd6a214963e6f65a33c1e2a';
