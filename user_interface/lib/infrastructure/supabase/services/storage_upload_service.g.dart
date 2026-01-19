// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_upload_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(storageUploadService)
final storageUploadServiceProvider = StorageUploadServiceProvider._();

final class StorageUploadServiceProvider
    extends
        $FunctionalProvider<
          StorageUploadService,
          StorageUploadService,
          StorageUploadService
        >
    with $Provider<StorageUploadService> {
  StorageUploadServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageUploadServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageUploadServiceHash();

  @$internal
  @override
  $ProviderElement<StorageUploadService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StorageUploadService create(Ref ref) {
    return storageUploadService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StorageUploadService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StorageUploadService>(value),
    );
  }
}

String _$storageUploadServiceHash() =>
    r'e8f689e250e6e1efec1559cd4389ab67486f0ab7';
