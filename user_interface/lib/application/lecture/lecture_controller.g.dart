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

String _$lectureControllerHash() => r'7a22b05d981ca58589dbe73e0b3c7467b8e4e5c6';

abstract class _$LectureController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
