// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_repository_supabase.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(userProfileRepository)
final userProfileRepositoryProvider = UserProfileRepositoryProvider._();

final class UserProfileRepositoryProvider
    extends
        $FunctionalProvider<
          UserProfileRepositorySupabase,
          UserProfileRepositorySupabase,
          UserProfileRepositorySupabase
        >
    with $Provider<UserProfileRepositorySupabase> {
  UserProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userProfileRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userProfileRepositoryHash();

  @$internal
  @override
  $ProviderElement<UserProfileRepositorySupabase> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  UserProfileRepositorySupabase create(Ref ref) {
    return userProfileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserProfileRepositorySupabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserProfileRepositorySupabase>(
        value,
      ),
    );
  }
}

String _$userProfileRepositoryHash() =>
    r'07e0bc1ffaabd638d03907eb051e4c3f2f50ac16';
