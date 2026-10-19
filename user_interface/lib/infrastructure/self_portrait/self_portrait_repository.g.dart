// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'self_portrait_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(selfPortraitRepository)
final selfPortraitRepositoryProvider = SelfPortraitRepositoryProvider._();

final class SelfPortraitRepositoryProvider
    extends
        $FunctionalProvider<
          SelfPortraitRepository,
          SelfPortraitRepository,
          SelfPortraitRepository
        >
    with $Provider<SelfPortraitRepository> {
  SelfPortraitRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selfPortraitRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selfPortraitRepositoryHash();

  @$internal
  @override
  $ProviderElement<SelfPortraitRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SelfPortraitRepository create(Ref ref) {
    return selfPortraitRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelfPortraitRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelfPortraitRepository>(value),
    );
  }
}

String _$selfPortraitRepositoryHash() =>
    r'0227faae26e314dc8ba6baa2050c1cc776250510';
