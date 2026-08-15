// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'course_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(courseRepositoryDrift)
final courseRepositoryDriftProvider = CourseRepositoryDriftProvider._();

final class CourseRepositoryDriftProvider
    extends
        $FunctionalProvider<
          CourseRepositoryDrift,
          CourseRepositoryDrift,
          CourseRepositoryDrift
        >
    with $Provider<CourseRepositoryDrift> {
  CourseRepositoryDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'courseRepositoryDriftProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$courseRepositoryDriftHash();

  @$internal
  @override
  $ProviderElement<CourseRepositoryDrift> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CourseRepositoryDrift create(Ref ref) {
    return courseRepositoryDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CourseRepositoryDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CourseRepositoryDrift>(value),
    );
  }
}

String _$courseRepositoryDriftHash() =>
    r'f53bc646ef5858bd0598539e726abcb589270391';

/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// 以前はSupabaseへ直接問い合わせるだけで、ローカルDBにキャッシュしていな
// かった(Lecture等は他のエンティティと違いこの1つだけ例外だった)。
// これだと通信が悪い状態でPull-to-Refresh等によりこのProviderが再取得
// された時、正常に取得できていたコース一覧が失われて見えるバグがあった
// (CoursesPage/CoursePageが「コースが1つも無い」状態に見えてしまう)。
// 他のエンティティと同じく、ローカルDB(Drift)のStreamをそのまま表示に
// 使う形に変更した — DriftのStreamは元々のクエリ結果を保持し続けるので、
// 通信状態に関わらず「最後に同期できた状態」を表示し続けられる。
//
// 書き込み(作成/更新/削除/復元)は引き続きオンライン時にSupabaseへ直接
// 行っており、その直後は[LectureController.pullCoursesNow]を呼んで
// ローカルDBへの反映を即座に行う(各呼び出し元を参照)。
//
// 以前はここでcurrentUserProviderをwatchして、アカウント切り替え時に自動で
// 再取得されるようにしていたが、Supabaseの認証イベント(サインイン直後など)を
// きっかけにHomeのビルド中にこのProviderが再取得されてしまい、Riverpodの
// 「ビルド中にProviderを変更できない」エラーが発生した。
// 常時Reactiveに監視するのではなく、サインアウト処理側(my_account_page.dart)で
// 明示的にref.invalidate(courseListProvider)する方式に変更した(踏襲)。

@ProviderFor(courseList)
final courseListProvider = CourseListProvider._();

/// 全コース一覧（attributes 付き）
// keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
// Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
// しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
// いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
//
// 以前はSupabaseへ直接問い合わせるだけで、ローカルDBにキャッシュしていな
// かった(Lecture等は他のエンティティと違いこの1つだけ例外だった)。
// これだと通信が悪い状態でPull-to-Refresh等によりこのProviderが再取得
// された時、正常に取得できていたコース一覧が失われて見えるバグがあった
// (CoursesPage/CoursePageが「コースが1つも無い」状態に見えてしまう)。
// 他のエンティティと同じく、ローカルDB(Drift)のStreamをそのまま表示に
// 使う形に変更した — DriftのStreamは元々のクエリ結果を保持し続けるので、
// 通信状態に関わらず「最後に同期できた状態」を表示し続けられる。
//
// 書き込み(作成/更新/削除/復元)は引き続きオンライン時にSupabaseへ直接
// 行っており、その直後は[LectureController.pullCoursesNow]を呼んで
// ローカルDBへの反映を即座に行う(各呼び出し元を参照)。
//
// 以前はここでcurrentUserProviderをwatchして、アカウント切り替え時に自動で
// 再取得されるようにしていたが、Supabaseの認証イベント(サインイン直後など)を
// きっかけにHomeのビルド中にこのProviderが再取得されてしまい、Riverpodの
// 「ビルド中にProviderを変更できない」エラーが発生した。
// 常時Reactiveに監視するのではなく、サインアウト処理側(my_account_page.dart)で
// 明示的にref.invalidate(courseListProvider)する方式に変更した(踏襲)。

final class CourseListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Course>>,
          List<Course>,
          Stream<List<Course>>
        >
    with $FutureModifier<List<Course>>, $StreamProvider<List<Course>> {
  /// 全コース一覧（attributes 付き）
  // keepAlive: true — Welcome画面で先読み(ref.read(...future))した直後に
  // Welcomeが破棄されると、autoDisposeのままではこのProviderも一緒に破棄されて
  // しまい、Home表示時にもう一度ゼロから読み込み直し(ローディング表示)になって
  // いた。セッション中は保持することで、Welcomeでの先読みがHomeまで活きる。
  //
  // 以前はSupabaseへ直接問い合わせるだけで、ローカルDBにキャッシュしていな
  // かった(Lecture等は他のエンティティと違いこの1つだけ例外だった)。
  // これだと通信が悪い状態でPull-to-Refresh等によりこのProviderが再取得
  // された時、正常に取得できていたコース一覧が失われて見えるバグがあった
  // (CoursesPage/CoursePageが「コースが1つも無い」状態に見えてしまう)。
  // 他のエンティティと同じく、ローカルDB(Drift)のStreamをそのまま表示に
  // 使う形に変更した — DriftのStreamは元々のクエリ結果を保持し続けるので、
  // 通信状態に関わらず「最後に同期できた状態」を表示し続けられる。
  //
  // 書き込み(作成/更新/削除/復元)は引き続きオンライン時にSupabaseへ直接
  // 行っており、その直後は[LectureController.pullCoursesNow]を呼んで
  // ローカルDBへの反映を即座に行う(各呼び出し元を参照)。
  //
  // 以前はここでcurrentUserProviderをwatchして、アカウント切り替え時に自動で
  // 再取得されるようにしていたが、Supabaseの認証イベント(サインイン直後など)を
  // きっかけにHomeのビルド中にこのProviderが再取得されてしまい、Riverpodの
  // 「ビルド中にProviderを変更できない」エラーが発生した。
  // 常時Reactiveに監視するのではなく、サインアウト処理側(my_account_page.dart)で
  // 明示的にref.invalidate(courseListProvider)する方式に変更した(踏襲)。
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
  $StreamProviderElement<List<Course>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Course>> create(Ref ref) {
    return courseList(ref);
  }
}

String _$courseListHash() => r'cf63d48a9526a918b27afde45cf136b4188e5e93';

/// Year アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(yearAttributes)
final yearAttributesProvider = YearAttributesProvider._();

/// Year アトリビュート一覧（コース作成フォームの候補）

final class YearAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          Stream<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $StreamProvider<List<CourseAttribute>> {
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
  $StreamProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CourseAttribute>> create(Ref ref) {
    return yearAttributes(ref);
  }
}

String _$yearAttributesHash() => r'2141ff3bd090b447c0d5edb595738009d7c8d1eb';

/// Term アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(termAttributes)
final termAttributesProvider = TermAttributesProvider._();

/// Term アトリビュート一覧（コース作成フォームの候補）

final class TermAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          Stream<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $StreamProvider<List<CourseAttribute>> {
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
  $StreamProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CourseAttribute>> create(Ref ref) {
    return termAttributes(ref);
  }
}

String _$termAttributesHash() => r'c304e681e2e5cbefd4b7f9688887665fb6a5d72c';

/// Professor アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(professorAttributes)
final professorAttributesProvider = ProfessorAttributesProvider._();

/// Professor アトリビュート一覧（コース作成フォームの候補）

final class ProfessorAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          Stream<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $StreamProvider<List<CourseAttribute>> {
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
  $StreamProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CourseAttribute>> create(Ref ref) {
    return professorAttributes(ref);
  }
}

String _$professorAttributesHash() =>
    r'2cc91f45578fe19e1779629485bcddbe68be01d9';

/// School アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(schoolAttributes)
final schoolAttributesProvider = SchoolAttributesProvider._();

/// School アトリビュート一覧（コース作成フォームの候補）

final class SchoolAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          Stream<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $StreamProvider<List<CourseAttribute>> {
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
  $StreamProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CourseAttribute>> create(Ref ref) {
    return schoolAttributes(ref);
  }
}

String _$schoolAttributesHash() => r'0f386e193c3c68b831ebc54434fe8ae6ac393684';

/// Subject アトリビュート一覧（コース作成フォームの候補）

@ProviderFor(subjectAttributes)
final subjectAttributesProvider = SubjectAttributesProvider._();

/// Subject アトリビュート一覧（コース作成フォームの候補）

final class SubjectAttributesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<CourseAttribute>>,
          List<CourseAttribute>,
          Stream<List<CourseAttribute>>
        >
    with
        $FutureModifier<List<CourseAttribute>>,
        $StreamProvider<List<CourseAttribute>> {
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
  $StreamProviderElement<List<CourseAttribute>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<CourseAttribute>> create(Ref ref) {
    return subjectAttributes(ref);
  }
}

String _$subjectAttributesHash() => r'3ad2e48c5d7e5a5dcf75586b3aa4718c94ec8901';
