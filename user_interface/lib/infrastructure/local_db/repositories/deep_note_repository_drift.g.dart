// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deep_note_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deepNoteRepositoryDrift)
final deepNoteRepositoryDriftProvider = DeepNoteRepositoryDriftProvider._();

final class DeepNoteRepositoryDriftProvider
    extends
        $FunctionalProvider<
          DeepNoteRepositoryDrift,
          DeepNoteRepositoryDrift,
          DeepNoteRepositoryDrift
        >
    with $Provider<DeepNoteRepositoryDrift> {
  DeepNoteRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deepNoteRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deepNoteRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<DeepNoteRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeepNoteRepositoryDrift create(Ref ref) {
    return deepNoteRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeepNoteRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeepNoteRepositoryDrift>(value),
    );
  }
}

String _$deepNoteRepositoryDriftHash() =>
    r'03e3ecbec8baf3f55c5746d02fa59ee410059a1a';
