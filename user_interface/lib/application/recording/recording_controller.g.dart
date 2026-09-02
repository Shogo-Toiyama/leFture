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
        dependencies: <ProviderOrFamily>[],
        $allTransitiveDependencies: <ProviderOrFamily>[],
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
    r'fe4bab74a01bff1ffa02e051f2bbd010f56f37cf';

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
        dependencies: <ProviderOrFamily>[
          audioRecorderServiceProvider,
          recordingRecoveryServiceProvider,
        ],
        $allTransitiveDependencies: <ProviderOrFamily>[
          RecordingControllerProvider.$allTransitiveDependencies0,
          RecordingControllerProvider.$allTransitiveDependencies1,
        ],
      );

  static final $allTransitiveDependencies0 = audioRecorderServiceProvider;
  static final $allTransitiveDependencies1 = recordingRecoveryServiceProvider;

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
    r'd3b61b81372a2ae434ebd70aef606c59bb99680c';

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
