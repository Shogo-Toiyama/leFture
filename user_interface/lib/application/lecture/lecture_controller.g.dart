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
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureControllerHash();

  @$internal
  @override
  LectureController create() => LectureController();
}

String _$lectureControllerHash() => r'dc0d662870654cf8c972080d1a054d91e6307aec';

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
