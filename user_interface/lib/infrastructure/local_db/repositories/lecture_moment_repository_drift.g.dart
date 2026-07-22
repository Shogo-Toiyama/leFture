// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_moment_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureMomentRepositoryDrift)
final lectureMomentRepositoryDriftProvider =
    LectureMomentRepositoryDriftProvider._();

final class LectureMomentRepositoryDriftProvider
    extends
        $FunctionalProvider<
          LectureMomentRepositoryDrift,
          LectureMomentRepositoryDrift,
          LectureMomentRepositoryDrift
        >
    with $Provider<LectureMomentRepositoryDrift> {
  LectureMomentRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureMomentRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureMomentRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<LectureMomentRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureMomentRepositoryDrift create(Ref ref) {
    return lectureMomentRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureMomentRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureMomentRepositoryDrift>(value),
    );
  }
}

String _$lectureMomentRepositoryDriftHash() =>
    r'b007cd2d3c8cec028969ee585a4a5c8bef0c7dba';
