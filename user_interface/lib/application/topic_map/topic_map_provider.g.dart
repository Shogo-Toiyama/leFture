// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_map_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.

@ProviderFor(topicMapForCourse)
final topicMapForCourseProvider = TopicMapForCourseFamily._();

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.

final class TopicMapForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<TopicMapData?>,
          TopicMapData?,
          FutureOr<TopicMapData?>
        >
    with $FutureModifier<TopicMapData?>, $FutureProvider<TopicMapData?> {
  /// The course's topic map, or null if the pipeline hasn't generated one yet.
  ///
  /// course_title/total_lectures_covered never live in the map jsonb itself
  /// (see TopicMapData.fromJson) -- they belong to the courses/lectures
  /// tables, so this provider composes the raw map with courseListProvider
  /// and lectureListStreamProvider instead of trusting the json for them.
  TopicMapForCourseProvider._({
    required TopicMapForCourseFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'topicMapForCourseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$topicMapForCourseHash();

  @override
  String toString() {
    return r'topicMapForCourseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<TopicMapData?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<TopicMapData?> create(Ref ref) {
    final argument = this.argument as String;
    return topicMapForCourse(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is TopicMapForCourseProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$topicMapForCourseHash() => r'567555af731b832899db476c5b33c82c45639cc0';

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.

final class TopicMapForCourseFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<TopicMapData?>, String> {
  TopicMapForCourseFamily._()
    : super(
        retry: null,
        name: r'topicMapForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The course's topic map, or null if the pipeline hasn't generated one yet.
  ///
  /// course_title/total_lectures_covered never live in the map jsonb itself
  /// (see TopicMapData.fromJson) -- they belong to the courses/lectures
  /// tables, so this provider composes the raw map with courseListProvider
  /// and lectureListStreamProvider instead of trusting the json for them.

  TopicMapForCourseProvider call(String courseId) =>
      TopicMapForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'topicMapForCourseProvider';
}
