// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recordingRepositoryDrift)
final recordingRepositoryDriftProvider = RecordingRepositoryDriftProvider._();

final class RecordingRepositoryDriftProvider
    extends
        $FunctionalProvider<
          RecordingRepositoryDrift,
          RecordingRepositoryDrift,
          RecordingRepositoryDrift
        >
    with $Provider<RecordingRepositoryDrift> {
  RecordingRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordingRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordingRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<RecordingRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecordingRepositoryDrift create(Ref ref) {
    return recordingRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordingRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordingRepositoryDrift>(value),
    );
  }
}

String _$recordingRepositoryDriftHash() =>
    r'56d04af60d6e91928dddb84818b801eefb2a7c67';
