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
        isAutoDispose: false,
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
    r'7081d9a2fae2b11c928c1cc02aed343f1be507b0';

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
        isAutoDispose: false,
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
    r'5dade295f75398e8dd830ebf1e258a9334fa3074';

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
    r'bb6a0aa5c200e361253e0b6deff5933397b5ffe9';

@ProviderFor(lectureWriteService)
final lectureWriteServiceProvider = LectureWriteServiceProvider._();

final class LectureWriteServiceProvider
    extends
        $FunctionalProvider<
          LectureWriteService,
          LectureWriteService,
          LectureWriteService
        >
    with $Provider<LectureWriteService> {
  LectureWriteServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureWriteServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureWriteServiceHash();

  @$internal
  @override
  $ProviderElement<LectureWriteService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureWriteService create(Ref ref) {
    return lectureWriteService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureWriteService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureWriteService>(value),
    );
  }
}

String _$lectureWriteServiceHash() =>
    r'be7c04c738076527a7c9dd7622272248db2abc07';

@ProviderFor(uploadManager)
final uploadManagerProvider = UploadManagerProvider._();

final class UploadManagerProvider
    extends $FunctionalProvider<UploadManager, UploadManager, UploadManager>
    with $Provider<UploadManager> {
  UploadManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'uploadManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$uploadManagerHash();

  @$internal
  @override
  $ProviderElement<UploadManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UploadManager create(Ref ref) {
    return uploadManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UploadManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UploadManager>(value),
    );
  }
}

String _$uploadManagerHash() => r'95a7fc61108c11969d3c7c88126adc53e4ab5d24';

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
        isAutoDispose: false,
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
    r'6276ee388528832dd8c6bac692211752cba5743f';

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
