// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(recordingRepository)
final recordingRepositoryProvider = RecordingRepositoryProvider._();

final class RecordingRepositoryProvider
    extends
        $FunctionalProvider<
          RecordingRepository,
          RecordingRepository,
          RecordingRepository
        >
    with $Provider<RecordingRepository> {
  RecordingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordingRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordingRepositoryHash();

  @$internal
  @override
  $ProviderElement<RecordingRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RecordingRepository create(Ref ref) {
    return recordingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordingRepository>(value),
    );
  }
}

String _$recordingRepositoryHash() =>
    r'4173aec50b7cc6abcc0546c9c9f0fd9c10d96ac4';
