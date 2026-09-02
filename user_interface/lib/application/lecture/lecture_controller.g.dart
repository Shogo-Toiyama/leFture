// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LectureController)
final lectureControllerProvider = LectureControllerProvider._();

final class LectureControllerProvider
    extends $AsyncNotifierProvider<LectureController, void> {
  LectureControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureControllerProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[
          recordingControllerProvider,
          recordingRecoveryServiceProvider,
          orphanRecordingsProvider,
        ],
        $allTransitiveDependencies: <ProviderOrFamily>{
          LectureControllerProvider.$allTransitiveDependencies0,
          LectureControllerProvider.$allTransitiveDependencies1,
          LectureControllerProvider.$allTransitiveDependencies2,
          LectureControllerProvider.$allTransitiveDependencies3,
        },
      );

  static final $allTransitiveDependencies0 = recordingControllerProvider;
  static final $allTransitiveDependencies1 =
      RecordingControllerProvider.$allTransitiveDependencies0;
  static final $allTransitiveDependencies2 =
      RecordingControllerProvider.$allTransitiveDependencies1;
  static final $allTransitiveDependencies3 = orphanRecordingsProvider;

  @override
  String debugGetCreateSourceHash() => _$lectureControllerHash();

  @$internal
  @override
  LectureController create() => LectureController();
}

String _$lectureControllerHash() => r'ef2eaf23dba287b7863c50830cd140ca52f5b0ba';

abstract class _$LectureController extends $AsyncNotifier<void> {
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
