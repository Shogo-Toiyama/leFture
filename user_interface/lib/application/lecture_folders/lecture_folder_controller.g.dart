// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_folder_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(LectureFolderController)
final lectureFolderControllerProvider = LectureFolderControllerProvider._();

final class LectureFolderControllerProvider
    extends $AsyncNotifierProvider<LectureFolderController, void> {
  LectureFolderControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureFolderControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureFolderControllerHash();

  @$internal
  @override
  LectureFolderController create() => LectureFolderController();
}

String _$lectureFolderControllerHash() =>
    r'576637cd609ddbf41bf49c32cab3965f92c1e0f8';

abstract class _$LectureFolderController extends $AsyncNotifier<void> {
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
