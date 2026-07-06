// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'announcement_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(announcementRepository)
final announcementRepositoryProvider = AnnouncementRepositoryProvider._();

final class AnnouncementRepositoryProvider
    extends
        $FunctionalProvider<
          AnnouncementRepositorySupabase,
          AnnouncementRepositorySupabase,
          AnnouncementRepositorySupabase
        >
    with $Provider<AnnouncementRepositorySupabase> {
  AnnouncementRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'announcementRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$announcementRepositoryHash();

  @$internal
  @override
  $ProviderElement<AnnouncementRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AnnouncementRepositorySupabase create(Ref ref) {
    return announcementRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AnnouncementRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AnnouncementRepositorySupabase>(
        value,
      ),
    );
  }
}

String _$announcementRepositoryHash() =>
    r'3439521830db8ef7753a9d391c80e774cf66eaf4';
