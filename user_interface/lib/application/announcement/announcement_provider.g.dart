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
    r'7449ea611cde331e4b8f70db8d638e17a7714c54';

/// 未完了のアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// Streamなので、完了/未完了のトグル(Drift経由の即時ローカル更新)がそのまま
/// 反映される — 以前のような楽観的UI用の手動state書き換えは不要。

@ProviderFor(activeAnnouncements)
final activeAnnouncementsProvider = ActiveAnnouncementsProvider._();

/// 未完了のアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
/// Streamなので、完了/未完了のトグル(Drift経由の即時ローカル更新)がそのまま
/// 反映される — 以前のような楽観的UI用の手動state書き換えは不要。

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
  /// 未完了のアナウンスメント全件（新しい順）。ローカルDB経由でオフライン優先。
  /// Streamなので、完了/未完了のトグル(Drift経由の即時ローカル更新)がそのまま
  /// 反映される — 以前のような楽観的UI用の手動state書き換えは不要。
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
    r'36bf20006850676efdb424e8d2587809fb71d5f7';
