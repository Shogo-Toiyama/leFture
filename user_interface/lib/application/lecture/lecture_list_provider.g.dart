// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureRepository)
final lectureRepositoryProvider = LectureRepositoryProvider._();

final class LectureRepositoryProvider
    extends
        $FunctionalProvider<
          LectureRepositoryDrift,
          LectureRepositoryDrift,
          LectureRepositoryDrift
        >
    with $Provider<LectureRepositoryDrift> {
  LectureRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureRepositoryHash();

  @$internal
  @override
  $ProviderElement<LectureRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureRepositoryDrift create(Ref ref) {
    return lectureRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureRepositoryDrift>(value),
    );
  }
}

String _$lectureRepositoryHash() => r'343f9e2a89eac7837e8836c897af3defd3bd04ab';

@ProviderFor(lectureListStream)
final lectureListStreamProvider = LectureListStreamFamily._();

final class LectureListStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Lecture>>,
          List<Lecture>,
          Stream<List<Lecture>>
        >
    with $FutureModifier<List<Lecture>>, $StreamProvider<List<Lecture>> {
  LectureListStreamProvider._({
    required LectureListStreamFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'lectureListStreamProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureListStreamHash();

  @override
  String toString() {
    return r'lectureListStreamProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Lecture>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Lecture>> create(Ref ref) {
    final argument = this.argument as String?;
    return lectureListStream(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureListStreamProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureListStreamHash() => r'a421ebc8771b4ade608b337fddd23854be54deb9';

final class LectureListStreamFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Lecture>>, String?> {
  LectureListStreamFamily._()
    : super(
        retry: null,
        name: r'lectureListStreamProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LectureListStreamProvider call(String? courseId) =>
      LectureListStreamProvider._(argument: courseId, from: this);

  @override
  String toString() => r'lectureListStreamProvider';
}

@ProviderFor(allLecturesStream)
final allLecturesStreamProvider = AllLecturesStreamProvider._();

final class AllLecturesStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Lecture>>,
          List<Lecture>,
          Stream<List<Lecture>>
        >
    with $FutureModifier<List<Lecture>>, $StreamProvider<List<Lecture>> {
  AllLecturesStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allLecturesStreamProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allLecturesStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<Lecture>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Lecture>> create(Ref ref) {
    return allLecturesStream(ref);
  }
}

String _$allLecturesStreamHash() => r'411c73f36057c3d5c7469f087ff5731da106192d';
