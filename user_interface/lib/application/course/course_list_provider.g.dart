// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全コース一覧（attributes 付き）

@ProviderFor(courseList)
final courseListProvider = CourseListProvider._();

/// 全コース一覧（attributes 付き）

final class CourseListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Course>>,
          List<Course>,
          FutureOr<List<Course>>
        >
    with $FutureModifier<List<Course>>, $FutureProvider<List<Course>> {
  /// 全コース一覧（attributes 付き）
  CourseListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'courseListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$courseListHash();

  @$internal
  @override
  $FutureProviderElement<List<Course>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Course>> create(Ref ref) {
    return courseList(ref);
  }
}

String _$courseListHash() => r'86b1eb9c5e9361a31c0261363bae3913c207c32b';

/// Year アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(yearAttributes)
final yearAttributesProvider = YearAttributesProvider._();

/// Year アトリビュート一覧（コース作成フォームの候補）

final class YearAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          FutureOr<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $FutureProvider<List<CourseAttribute>> {
  /// Year アトリビュート一覧（コース作成フォームの候補）
  YearAttributesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'yearAttributesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$yearAttributesHash();

  @$internal
  @override
  $FutureProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CourseAttribute>> create(Ref ref) {
    return yearAttributes(ref);
  }
}

String _$yearAttributesHash() => r'4cd1ab5276fc6b5e40629e44bed6f51fa59d7f65';

/// Term アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(termAttributes)
final termAttributesProvider = TermAttributesProvider._();

/// Term アトリビュート一覧（コース作成フォームの候補）

final class TermAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          FutureOr<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $FutureProvider<List<CourseAttribute>> {
  /// Term アトリビュート一覧（コース作成フォームの候補）
  TermAttributesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'termAttributesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$termAttributesHash();

  @$internal
  @override
  $FutureProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CourseAttribute>> create(Ref ref) {
    return termAttributes(ref);
  }
}

String _$termAttributesHash() => r'33c5cd66be6dd731cc1aa5ebb5be114952e5c046';
