// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'announcement_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 未完了のうち最新のアナウンスメント（無ければnull）。ローカルDB経由でオフライン優先。

@ProviderFor(latestAnnouncement)
final latestAnnouncementProvider = LatestAnnouncementProvider._();

/// 未完了のうち最新のアナウンスメント（無ければnull）。ローカルDB経由でオフライン優先。

final class LatestAnnouncementProvider
    extends
        $FunctionalProvider<
          AsyncValue<Announcement?>,
          Announcement?,
          Stream<Announcement?>
        >
    with $FutureModifier<Announcement?>, $StreamProvider<Announcement?> {
  /// 未完了のうち最新のアナウンスメント（無ければnull）。ローカルDB経由でオフライン優先。
  LatestAnnouncementProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'latestAnnouncementProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$latestAnnouncementHash();

  @$internal
  @override
  $StreamProviderElement<Announcement?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Announcement?> create(Ref ref) {
    return latestAnnouncement(ref);
  }
}

String _$latestAnnouncementHash() =>
    r'bc0bfee6f5c921de7db85912c361bfdfb0237cdf';

/// 未完了、または直近5分以内に完了したアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// 30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

@ProviderFor(activeAnnouncements)
final activeAnnouncementsProvider = ActiveAnnouncementsProvider._();

/// 未完了、または直近5分以内に完了したアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// 30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。

final class ActiveAnnouncementsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          Stream<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $StreamProvider<List<Announcement>> {
  /// 未完了、または直近5分以内に完了したアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
  /// 30秒ごとに再評価し、5分経過した完了済みアナウンスメントを自動消去する。
  ActiveAnnouncementsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeAnnouncementsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeAnnouncementsHash();

  @$internal
  @override
  $StreamProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Announcement>> create(Ref ref) {
    return activeAnnouncements(ref);
  }
}

String _$activeAnnouncementsHash() =>
    r'f11edfe148a0819df299e5b5b7c220f75786ac3f';

/// 全アナウンスメント（完了・未完了問わず全件、新しい順）。

@ProviderFor(allAnnouncements)
final allAnnouncementsProvider = AllAnnouncementsProvider._();

/// 全アナウンスメント（完了・未完了問わず全件、新しい順）。

final class AllAnnouncementsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          Stream<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $StreamProvider<List<Announcement>> {
  /// 全アナウンスメント（完了・未完了問わず全件、新しい順）。
  AllAnnouncementsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allAnnouncementsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allAnnouncementsHash();

  @$internal
  @override
  $StreamProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Announcement>> create(Ref ref) {
    return allAnnouncements(ref);
  }
}

String _$allAnnouncementsHash() => r'fa69da6ba084194f72eece5afef09e9977fd4286';

/// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
/// ページ単位(20件ずつ)で読み込む。
///
/// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
/// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
/// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
/// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
/// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。

@ProviderFor(AnnouncementsPage)
final announcementsPageProvider = AnnouncementsPageFamily._();

/// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
/// ページ単位(20件ずつ)で読み込む。
///
/// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
/// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
/// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
/// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
/// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。
final class AnnouncementsPageProvider
    extends $AsyncNotifierProvider<AnnouncementsPage, List<Announcement>> {
  /// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
  /// ページ単位(20件ずつ)で読み込む。
  ///
  /// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
  /// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
  /// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
  ///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
  /// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
  ///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
  /// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
  ///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。
  AnnouncementsPageProvider._({
    required AnnouncementsPageFamily super.from,
    required ({String status, AnnouncementType? type}) super.argument,
  }) : super(
         retry: null,
         name: r'announcementsPageProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$announcementsPageHash();

  @override
  String toString() {
    return r'announcementsPageProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AnnouncementsPage create() => AnnouncementsPage();

  @override
  bool operator ==(Object other) {
    return other is AnnouncementsPageProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$announcementsPageHash() => r'f97ae739699a9f01d0d5e225d749f58fdde1f2e5';

/// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
/// ページ単位(20件ずつ)で読み込む。
///
/// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
/// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
/// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
/// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
/// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。

final class AnnouncementsPageFamily extends $Family
    with
        $ClassFamilyOverride<
          AnnouncementsPage,
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          FutureOr<List<Announcement>>,
          ({String status, AnnouncementType? type})
        > {
  AnnouncementsPageFamily._()
    : super(
        retry: null,
        name: r'announcementsPageProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
  /// ページ単位(20件ずつ)で読み込む。
  ///
  /// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
  /// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
  /// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
  ///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
  /// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
  ///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
  /// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
  ///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。

  AnnouncementsPageProvider call({
    String status = 'active',
    AnnouncementType? type,
  }) => AnnouncementsPageProvider._(
    argument: (status: status, type: type),
    from: this,
  );

  @override
  String toString() => r'announcementsPageProvider';
}

/// ホーム画面(全コース横断)のアナウンス一覧を、状態/種類フィルターごとに
/// ページ単位(20件ずつ)で読み込む。
///
/// [allAnnouncements]と違い全件を1本のストリームで購読するのではなく、
/// フィルター済みのデータをDBから直接ページ取得するAsyncNotifier。
/// - 1講義に10件前後アナウンスが溜まることも珍しくなく、それが何年も
///   積み重なると際限なく肥大化するため、初期表示は20件までに制限する。
/// - フィルター後の該当件数が少ないケース(例: 完了済みのみ)でも、絞り込み
///   済みのクエリ結果をそのままページングするため、正しく追加読み込みできる。
/// - `loadMore()`は既存のstateへ追記するだけで置き換えないため、
///   ListViewの位置(スクロール量)を保ったまま件数だけ増える。

abstract class _$AnnouncementsPage extends $AsyncNotifier<List<Announcement>> {
  late final _$args = ref.$arg as ({String status, AnnouncementType? type});
  String get status => _$args.status;
  AnnouncementType? get type => _$args.type;

  FutureOr<List<Announcement>> build({
    String status = 'active',
    AnnouncementType? type,
  });
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
    element.handleCreate(
      ref,
      () => build(status: _$args.status, type: _$args.type),
    );
  }
}
