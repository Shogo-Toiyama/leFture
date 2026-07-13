// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_map_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(topicMapRepositoryDrift)
final topicMapRepositoryDriftProvider = TopicMapRepositoryDriftProvider._();

final class TopicMapRepositoryDriftProvider
    extends
        $FunctionalProvider<
          TopicMapRepositoryDrift,
          TopicMapRepositoryDrift,
          TopicMapRepositoryDrift
        >
    with $Provider<TopicMapRepositoryDrift> {
  TopicMapRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'topicMapRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$topicMapRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<TopicMapRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TopicMapRepositoryDrift create(Ref ref) {
    return topicMapRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TopicMapRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TopicMapRepositoryDrift>(value),
    );
  }
}

String _$topicMapRepositoryDriftHash() =>
    r'b99be7aba813edde4dab990ea0f39bef225e6b8b';
