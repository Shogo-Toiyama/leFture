// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// keepAliveにした副作用として、サインアウト→別アカウントでサインインしても
// このProviderは自動では再取得されなくなる(以前はautoDisposeで一度画面から
// 外れると勝手に消えて次回読み直しになっていた、という偶然の安全策があった)。
// currentUserProviderを監視しておくことで、ユーザーが変わった時に確実に
// 再取得されるようにする(値自体はlistCourses()側でSupabaseのRLSにより
// 自動的にユーザー単位でフィルタされるため使わないが、依存関係としてwatchする)。

@ProviderFor(courseList)
final courseListProvider = CourseListProvider._();

/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// keepAliveにした副作用として、サインアウト→別アカウントでサインインしても
// このProviderは自動では再取得されなくなる(以前はautoDisposeで一度画面から
// 外れると勝手に消えて次回読み直しになっていた、という偶然の安全策があった)。
// currentUserProviderを監視しておくことで、ユーザーが変わった時に確実に
// 再取得されるようにする(値自体はlistCourses()側でSupabaseのRLSにより
// 自動的にユーザー単位でフィルタされるため使わないが、依存関係としてwatchする)。

final class CourseListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Course>>,
          List<Course>,
          FutureOr<List<Course>>
        >
    with $FutureModifier<List<Course>>, $FutureProvider<List<Course>> {
  /// 全コース一覧（attributes 付き）
  // keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
  // Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
  // しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
  // いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
  //
  // keepAliveにした副作用として、サインアウト→別アカウントでサインインしても
  // このProviderは自動では再取得されなくなる(以前はautoDisposeで一度画面から
  // 外れると勝手に消えて次回読み直しになっていた、という偶然の安全策があった)。
  // currentUserProviderを監視しておくことで、ユーザーが変わった時に確実に
  // 再取得されるようにする(値自体はlistCourses()側でSupabaseのRLSにより
  // 自動的にユーザー単位でフィルタされるため使わないが、依存関係としてwatchする)。
  CourseListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'courseListProvider',
        isAutoDispose: false,
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

String _$courseListHash() => r'ad78ee81b9d35581624f3679d03256a928bc9f75';

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

/// Professor アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(professorAttributes)
final professorAttributesProvider = ProfessorAttributesProvider._();

/// Professor アトリビュート一覧（コース作成フォームの候補）

final class ProfessorAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          FutureOr<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $FutureProvider<List<CourseAttribute>> {
  /// Professor アトリビュート一覧（コース作成フォームの候補）
  ProfessorAttributesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'professorAttributesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$professorAttributesHash();

  @$internal
  @override
  $FutureProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CourseAttribute>> create(Ref ref) {
    return professorAttributes(ref);
  }
}

String _$professorAttributesHash() =>
    r'fe7ad25165ee662025809dda498f8419e16ab109';

/// School アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(schoolAttributes)
final schoolAttributesProvider = SchoolAttributesProvider._();

/// School アトリビュート一覧（コース作成フォームの候補）

final class SchoolAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          FutureOr<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $FutureProvider<List<CourseAttribute>> {
  /// School アトリビュート一覧（コース作成フォームの候補）
  SchoolAttributesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'schoolAttributesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$schoolAttributesHash();

  @$internal
  @override
  $FutureProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CourseAttribute>> create(Ref ref) {
    return schoolAttributes(ref);
  }
}

String _$schoolAttributesHash() => r'ace70af5e8b2e7ed7bf5df1aa6cf9988f52f3bec';

/// Subject アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(subjectAttributes)
final subjectAttributesProvider = SubjectAttributesProvider._();

/// Subject アトリビュート一覧（コース作成フォームの候補）

final class SubjectAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          FutureOr<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $FutureProvider<List<CourseAttribute>> {
  /// Subject アトリビュート一覧（コース作成フォームの候補）
  SubjectAttributesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'subjectAttributesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$subjectAttributesHash();

  @$internal
  @override
  $FutureProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<CourseAttribute>> create(Ref ref) {
    return subjectAttributes(ref);
  }
}

String _$subjectAttributesHash() => r'c287d99030220cbeaa37f84122011856f199a23b';
