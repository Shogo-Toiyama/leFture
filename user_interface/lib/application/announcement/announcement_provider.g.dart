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
