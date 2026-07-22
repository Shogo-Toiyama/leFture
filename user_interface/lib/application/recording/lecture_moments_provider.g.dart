// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_moments_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureMoments)
final lectureMomentsProvider = LectureMomentsFamily._();

final class LectureMomentsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LectureMoment>>,
          List<LectureMoment>,
          Stream<List<LectureMoment>>
        >
    with
        $FutureModifier<List<LectureMoment>>,
        $StreamProvider<List<LectureMoment>> {
  LectureMomentsProvider._({
    required LectureMomentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lectureMomentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureMomentsHash();

  @override
  String toString() {
    return r'lectureMomentsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LectureMoment>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LectureMoment>> create(Ref ref) {
    final argument = this.argument as String;
    return lectureMoments(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureMomentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureMomentsHash() => r'c0eacf9d77e24bddbc5771ad6265aeb71eeda1f9';

final class LectureMomentsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<LectureMoment>>, String> {
  LectureMomentsFamily._()
    : super(
        retry: null,
        name: r'lectureMomentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LectureMomentsProvider call(String lectureId) =>
      LectureMomentsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureMomentsProvider';
}
