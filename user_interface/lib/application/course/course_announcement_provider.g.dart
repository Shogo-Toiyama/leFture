// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_announcement_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
/// ローカルDB経由でオフライン優先。

@ProviderFor(latestAnnouncementForCourse)
final latestAnnouncementForCourseProvider =
    LatestAnnouncementForCourseFamily._();

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
/// ローカルDB経由でオフライン優先。

final class LatestAnnouncementForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<Announcement?>,
          Announcement?,
          Stream<Announcement?>
        >
    with $FutureModifier<Announcement?>, $StreamProvider<Announcement?> {
  /// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
  /// ローカルDB経由でオフライン優先。
  LatestAnnouncementForCourseProvider._({
    required LatestAnnouncementForCourseFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'latestAnnouncementForCourseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$latestAnnouncementForCourseHash();

  @override
  String toString() {
    return r'latestAnnouncementForCourseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Announcement?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Announcement?> create(Ref ref) {
    final argument = this.argument as String;
    return latestAnnouncementForCourse(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LatestAnnouncementForCourseProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$latestAnnouncementForCourseHash() =>
    r'1ce222de6444ceda64d607351639c3bff1b22873';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
/// ローカルDB経由でオフライン優先。

final class LatestAnnouncementForCourseFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Announcement?>, String> {
  LatestAnnouncementForCourseFamily._()
    : super(
        retry: null,
        name: r'latestAnnouncementForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント。
  /// ローカルDB経由でオフライン優先。

  LatestAnnouncementForCourseProvider call(String courseId) =>
      LatestAnnouncementForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'latestAnnouncementForCourseProvider';
}

/// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

@ProviderFor(activeAnnouncementsForCourse)
final activeAnnouncementsForCourseProvider =
    ActiveAnnouncementsForCourseFamily._();

/// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

final class ActiveAnnouncementsForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          Stream<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $StreamProvider<List<Announcement>> {
  /// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
  /// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。
  ActiveAnnouncementsForCourseProvider._({
    required ActiveAnnouncementsForCourseFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'activeAnnouncementsForCourseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activeAnnouncementsForCourseHash();

  @override
  String toString() {
    return r'activeAnnouncementsForCourseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Announcement>> create(Ref ref) {
    final argument = this.argument as String;
    return activeAnnouncementsForCourse(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ActiveAnnouncementsForCourseProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activeAnnouncementsForCourseHash() =>
    r'0adededdd42c971279a8d92b1b80e3551c71bd61';

/// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

final class ActiveAnnouncementsForCourseFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Announcement>>, String> {
  ActiveAnnouncementsForCourseFamily._()
    : super(
        retry: null,
        name: r'activeAnnouncementsForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// コースに属する全レクチャーを横断した、未完了、または直近5分以内に完了したアナウンスメント一覧。
  /// ローカルDB経由でオフライン優先。30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

  ActiveAnnouncementsForCourseProvider call(String courseId) =>
      ActiveAnnouncementsForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'activeAnnouncementsForCourseProvider';
}

/// コースに属する全レクチャーを横断した、全アナウンスメント一覧（完了・未完了問わず全件）。

@ProviderFor(allAnnouncementsForCourse)
final allAnnouncementsForCourseProvider = AllAnnouncementsForCourseFamily._();

/// コースに属する全レクチャーを横断した、全アナウンスメント一覧（完了・未完了問わず全件）。

final class AllAnnouncementsForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          Stream<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $StreamProvider<List<Announcement>> {
  /// コースに属する全レクチャーを横断した、全アナウンスメント一覧（完了・未完了問わず全件）。
  AllAnnouncementsForCourseProvider._({
    required AllAnnouncementsForCourseFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'allAnnouncementsForCourseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$allAnnouncementsForCourseHash();

  @override
  String toString() {
    return r'allAnnouncementsForCourseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Announcement>> create(Ref ref) {
    final argument = this.argument as String;
    return allAnnouncementsForCourse(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AllAnnouncementsForCourseProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$allAnnouncementsForCourseHash() =>
    r'9da483985d836058134e400441347ef106414963';

/// コースに属する全レクチャーを横断した、全アナウンスメント一覧（完了・未完了問わず全件）。

final class AllAnnouncementsForCourseFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Announcement>>, String> {
  AllAnnouncementsForCourseFamily._()
    : super(
        retry: null,
        name: r'allAnnouncementsForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// コースに属する全レクチャーを横断した、全アナウンスメント一覧（完了・未完了問わず全件）。

  AllAnnouncementsForCourseProvider call(String courseId) =>
      AllAnnouncementsForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'allAnnouncementsForCourseProvider';
}
