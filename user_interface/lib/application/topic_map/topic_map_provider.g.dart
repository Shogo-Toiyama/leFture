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
///
/// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
/// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
/// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
/// 明示的に強制Pullしてから呼び直す)。

@ProviderFor(topicMapForCourse)
final topicMapForCourseProvider = TopicMapForCourseFamily._();

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.
///
/// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
/// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
/// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
/// 明示的に強制Pullしてから呼び直す)。

final class TopicMapForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<TopicMapData?>,
          TopicMapData?,
          Stream<TopicMapData?>
        >
    with $FutureModifier<TopicMapData?>, $StreamProvider<TopicMapData?> {
  /// The course's topic map, or null if the pipeline hasn't generated one yet.
  ///
  /// course_title/total_lectures_covered never live in the map jsonb itself
  /// (see TopicMapData.fromJson) -- they belong to the courses/lectures
  /// tables, so this provider composes the raw map with courseListProvider
  /// and lectureListStreamProvider instead of trusting the json for them.
  ///
  /// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
  /// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
  /// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
  /// 明示的に強制Pullしてから呼び直す)。
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
  $StreamProviderElement<TopicMapData?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TopicMapData?> create(Ref ref) {
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

String _$topicMapForCourseHash() => r'3c4a0b412d7c3df2fe3ca776deefd72517365fba';

/// The course's topic map, or null if the pipeline hasn't generated one yet.
///
/// course_title/total_lectures_covered never live in the map jsonb itself
/// (see TopicMapData.fromJson) -- they belong to the courses/lectures
/// tables, so this provider composes the raw map with courseListProvider
/// and lectureListStreamProvider instead of trusting the json for them.
///
/// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
/// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
/// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
/// 明示的に強制Pullしてから呼び直す)。

final class TopicMapForCourseFamily extends $Family
    with $FunctionalFamilyOverride<Stream<TopicMapData?>, String> {
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
  ///
  /// マップ本体はローカルDB経由(オフライン優先)。書き込み(markStale/
  /// reconstruct)は依然Supabase/Cloud Run直接なので、変更の反映は次のPull
  /// 以降になる(即時反映が必要な箇所はTopicMapReconstructControllerが
  /// 明示的に強制Pullしてから呼び直す)。

  TopicMapForCourseProvider call(String courseId) =>
      TopicMapForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'topicMapForCourseProvider';
}
