// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_announcement_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント

@ProviderFor(latestAnnouncementForCourse)
final latestAnnouncementForCourseProvider =
    LatestAnnouncementForCourseFamily._();

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント

final class LatestAnnouncementForCourseProvider
    extends
        $FunctionalProvider<
          AsyncValue<Announcement?>,
          Announcement?,
          FutureOr<Announcement?>
        >
    with $FutureModifier<Announcement?>, $FutureProvider<Announcement?> {
  /// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント
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
  $FutureProviderElement<Announcement?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Announcement?> create(Ref ref) {
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
    r'16430eafe18535239da7b500c9041ebdd7523b1d';

/// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント

final class LatestAnnouncementForCourseFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Announcement?>, String> {
  LatestAnnouncementForCourseFamily._()
    : super(
        retry: null,
        name: r'latestAnnouncementForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// コースに属する全レクチャーを横断した、未完了のうち最新のアナウンスメント

  LatestAnnouncementForCourseProvider call(String courseId) =>
      LatestAnnouncementForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'latestAnnouncementForCourseProvider';
}

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

@ProviderFor(ActiveAnnouncementsForCourse)
final activeAnnouncementsForCourseProvider =
    ActiveAnnouncementsForCourseFamily._();

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
final class ActiveAnnouncementsForCourseProvider
    extends
        $AsyncNotifierProvider<
          ActiveAnnouncementsForCourse,
          List<Announcement>
        > {
  /// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
  /// AsyncNotifier として管理することで、Done/Undo 操作後も
  /// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
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
  ActiveAnnouncementsForCourse create() => ActiveAnnouncementsForCourse();

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
    r'2558f872aacd58b93263d1eb972925e332bf8efb';

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

final class ActiveAnnouncementsForCourseFamily extends $Family
    with
        $ClassFamilyOverride<
          ActiveAnnouncementsForCourse,
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          FutureOr<List<Announcement>>,
          String
        > {
  ActiveAnnouncementsForCourseFamily._()
    : super(
        retry: null,
        name: r'activeAnnouncementsForCourseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
  /// AsyncNotifier として管理することで、Done/Undo 操作後も
  /// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

  ActiveAnnouncementsForCourseProvider call(String courseId) =>
      ActiveAnnouncementsForCourseProvider._(argument: courseId, from: this);

  @override
  String toString() => r'activeAnnouncementsForCourseProvider';
}

/// コースに属する全レクチャーを横断した、未完了のアナウンスメント一覧。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

abstract class _$ActiveAnnouncementsForCourse
    extends $AsyncNotifier<List<Announcement>> {
  late final _$args = ref.$arg as String;
  String get courseId => _$args;

  FutureOr<List<Announcement>> build(String courseId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<Announcement>>, List<Announcement>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Announcement>>, List<Announcement>>,
              AsyncValue<List<Announcement>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
