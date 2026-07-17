// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ログイン中ユーザーの user_profiles レコード

@ProviderFor(currentUserProfile)
final currentUserProfileProvider = CurrentUserProfileProvider._();

/// ログイン中ユーザーの user_profiles レコード

final class CurrentUserProfileProvider
    extends
        $FunctionalProvider<
          AsyncValue<UserProfile?>,
          UserProfile?,
          Stream<UserProfile?>
        >
    with $FutureModifier<UserProfile?>, $StreamProvider<UserProfile?> {
  /// ログイン中ユーザーの user_profiles レコード
  CurrentUserProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserProfileProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserProfileHash();

  @$internal
  @override
  $StreamProviderElement<UserProfile?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<UserProfile?> create(Ref ref) {
    return currentUserProfile(ref);
  }
}

String _$currentUserProfileHash() =>
    r'62397841b12ded0a34d368dc007faa25c4a2ae1c';
