// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchases_identity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(purchasesIdentity)
final purchasesIdentityProvider = PurchasesIdentityProvider._();

final class PurchasesIdentityProvider
    extends
        $FunctionalProvider<
          PurchasesIdentityService,
          PurchasesIdentityService,
          PurchasesIdentityService
        >
    with $Provider<PurchasesIdentityService> {
  PurchasesIdentityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'purchasesIdentityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$purchasesIdentityHash();

  @$internal
  @override
  $ProviderElement<PurchasesIdentityService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PurchasesIdentityService create(Ref ref) {
    return purchasesIdentity(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PurchasesIdentityService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PurchasesIdentityService>(value),
    );
  }
}

String _$purchasesIdentityHash() => r'612a5ec75a3b16d2cc4b88f97d9d5f01ee1dbcb6';
