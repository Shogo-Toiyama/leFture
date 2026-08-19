// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 🔄 現在のセッション（ログイン状態）を監視

@ProviderFor(authState)
final authStateProvider = AuthStateProvider._();

/// 🔄 現在のセッション（ログイン状態）を監視

final class AuthStateProvider
    extends
        $FunctionalProvider<AsyncValue<AuthState>, AuthState, Stream<AuthState>>
    with $FutureModifier<AuthState>, $StreamProvider<AuthState> {
  /// 🔄 現在のセッション（ログイン状態）を監視
  AuthStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStateHash();

  @$internal
  @override
  $StreamProviderElement<AuthState> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<AuthState> create(Ref ref) {
    return authState(ref);
  }
}

String _$authStateHash() => r'b847a0749c249cf099aa80b49b53501e8104aa8d';

/// 👤 ログイン中のユーザー情報

@ProviderFor(currentUser)
final currentUserProvider = CurrentUserProvider._();

/// 👤 ログイン中のユーザー情報

final class CurrentUserProvider extends $FunctionalProvider<User?, User?, User?>
    with $Provider<User?> {
  /// 👤 ログイン中のユーザー情報
  CurrentUserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserHash();

  @$internal
  @override
  $ProviderElement<User?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  User? create(Ref ref) {
    return currentUser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(User? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<User?>(value),
    );
  }
}

String _$currentUserHash() => r'c0429162e0e7921c0133662fa79ff542e1c18e9d';

/// ✅ ログイン済みかどうか

@ProviderFor(isLoggedIn)
final isLoggedInProvider = IsLoggedInProvider._();

/// ✅ ログイン済みかどうか

final class IsLoggedInProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// ✅ ログイン済みかどうか
  IsLoggedInProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isLoggedInProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isLoggedInHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isLoggedIn(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isLoggedInHash() => r'850bd4884b28e7b961418fa7da4aca5a9bb7a030';

/// 🔐 Auth操作を管理する AsyncNotifier 相当のクラス

@ProviderFor(AuthController)
final authControllerProvider = AuthControllerProvider._();

/// 🔐 Auth操作を管理する AsyncNotifier 相当のクラス
final class AuthControllerProvider
    extends $AsyncNotifierProvider<AuthController, void> {
  /// 🔐 Auth操作を管理する AsyncNotifier 相当のクラス
  AuthControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authControllerProvider',
        isAutoDispose: true,
        dependencies: <ProviderOrFamily>[
          userProfileRepositoryProvider,
          lectureControllerProvider,
        ],
        $allTransitiveDependencies: <ProviderOrFamily>{
          AuthControllerProvider.$allTransitiveDependencies0,
          AuthControllerProvider.$allTransitiveDependencies1,
          AuthControllerProvider.$allTransitiveDependencies2,
          AuthControllerProvider.$allTransitiveDependencies3,
        },
      );

  static final $allTransitiveDependencies0 = userProfileRepositoryProvider;
  static final $allTransitiveDependencies1 = lectureControllerProvider;
  static final $allTransitiveDependencies2 =
      LectureControllerProvider.$allTransitiveDependencies0;
  static final $allTransitiveDependencies3 =
      LectureControllerProvider.$allTransitiveDependencies1;

  @override
  String debugGetCreateSourceHash() => _$authControllerHash();

  @$internal
  @override
  AuthController create() => AuthController();
}

String _$authControllerHash() => r'9c4e701f3831cb60db576c1251df44dfef6afc52';

/// 🔐 Auth操作を管理する AsyncNotifier 相当のクラス

abstract class _$AuthController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
