// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリ全体で共有するオンライン/オフライン状態。
/// オフラインバナー表示や、ネットワーク処理を開始する前のガードに使う。

@ProviderFor(isOnline)
final isOnlineProvider = IsOnlineProvider._();

/// アプリ全体で共有するオンライン/オフライン状態。
/// オフラインバナー表示や、ネットワーク処理を開始する前のガードに使う。

final class IsOnlineProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// アプリ全体で共有するオンライン/オフライン状態。
  /// オフラインバナー表示や、ネットワーク処理を開始する前のガードに使う。
  IsOnlineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isOnlineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isOnlineHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return isOnline(ref);
  }
}

String _$isOnlineHash() => r'df49223d8e4809d7877b13dc9f1c7ac4f4ba2d2c';
