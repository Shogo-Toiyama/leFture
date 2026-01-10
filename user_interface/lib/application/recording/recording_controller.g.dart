// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recording_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioRecorderService)
final audioRecorderServiceProvider = AudioRecorderServiceProvider._();

final class AudioRecorderServiceProvider
    extends
        $FunctionalProvider<
          AudioRecorderService,
          AudioRecorderService,
          AudioRecorderService
        >
    with $Provider<AudioRecorderService> {
  AudioRecorderServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'audioRecorderServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$audioRecorderServiceHash();

  @$internal
  @override
  $ProviderElement<AudioRecorderService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AudioRecorderService create(Ref ref) {
    return audioRecorderService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AudioRecorderService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AudioRecorderService>(value),
    );
  }
}

String _$audioRecorderServiceHash() =>
    r'76fc78b2e639128b697494153a841eed41968c33';

@ProviderFor(pendingUploadStore)
final pendingUploadStoreProvider = PendingUploadStoreProvider._();

final class PendingUploadStoreProvider
    extends
        $FunctionalProvider<
          PendingUploadStore,
          PendingUploadStore,
          PendingUploadStore
        >
    with $Provider<PendingUploadStore> {
  PendingUploadStoreProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pendingUploadStoreProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pendingUploadStoreHash();

  @$internal
  @override
  $ProviderElement<PendingUploadStore> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PendingUploadStore create(Ref ref) {
    return pendingUploadStore(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PendingUploadStore value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PendingUploadStore>(value),
    );
  }
}

String _$pendingUploadStoreHash() =>
    r'405d82d439fac2611a29c8c9ce54e8dedc153118';

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
        isAutoDispose: true,
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
    r'bc07342b250d5f9db3164b6aa8094517edc80a4e';

@ProviderFor(RecordingController)
final recordingControllerProvider = RecordingControllerProvider._();

final class RecordingControllerProvider
    extends $NotifierProvider<RecordingController, RecordingState> {
  RecordingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recordingControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recordingControllerHash();

  @$internal
  @override
  RecordingController create() => RecordingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RecordingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RecordingState>(value),
    );
  }
}

String _$recordingControllerHash() =>
    r'050be868a96dc37a0beadb6bb62eeb66a9aea451';

abstract class _$RecordingController extends $Notifier<RecordingState> {
  RecordingState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<RecordingState, RecordingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RecordingState, RecordingState>,
              RecordingState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
