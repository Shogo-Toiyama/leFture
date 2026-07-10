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
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureControllerHash();

  @$internal
  @override
  LectureController create() => LectureController();
}

String _$lectureControllerHash() => r'e8bb375b59afd3c3d82d27ae8b6f8d63152b8d1a';

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
