// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'announcement_repository_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(announcementRepositoryDrift)
final announcementRepositoryDriftProvider =
    AnnouncementRepositoryDriftProvider._();

final class AnnouncementRepositoryDriftProvider
    extends
        $FunctionalProvider<
          AnnouncementRepositoryDrift,
          AnnouncementRepositoryDrift,
          AnnouncementRepositoryDrift
        >
    with $Provider<AnnouncementRepositoryDrift> {
  AnnouncementRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'announcementRepositoryDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$announcementRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<AnnouncementRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AnnouncementRepositoryDrift create(Ref ref) {
    return announcementRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AnnouncementRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AnnouncementRepositoryDrift>(value),
    );
  }
}

String _$announcementRepositoryDriftHash() =>
    r'782106152a42d8ee331b649931e5f2e879d80a4d';
