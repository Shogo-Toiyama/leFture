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
    r'26e48612b633de618911cf51f5da335745571baa';

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

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

@ProviderFor(activeAnnouncementsForCourse)
final activeAnnouncementsForCourseProvider =
    ActiveAnnouncementsForCourseFamily._();

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

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
  /// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
  /// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
  /// そのまま反映される。
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
    r'555b08f2f6d589d291e61ce3e4640fdd466e1d99';

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

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

  /// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
  /// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
  /// そのまま反映される。

  ActiveAnnouncementsForCourseProvider call(String courseId) =>
      ActiveAnnouncementsForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'activeAnnouncementsForCourseProvider';
}
