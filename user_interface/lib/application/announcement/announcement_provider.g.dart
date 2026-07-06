// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'announcement_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 未完了のうち最新のアナウンスメント（無ければnull）

@ProviderFor(latestAnnouncement)
final latestAnnouncementProvider = LatestAnnouncementProvider._();

/// 未完了のうち最新のアナウンスメント（無ければnull）

final class LatestAnnouncementProvider
    extends
        $FunctionalProvider<
          AsyncValue<Announcement?>,
          Announcement?,
          FutureOr<Announcement?>
        >
    with $FutureModifier<Announcement?>, $FutureProvider<Announcement?> {
  /// 未完了のうち最新のアナウンスメント（無ければnull）
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
  $FutureProviderElement<Announcement?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Announcement?> create(Ref ref) {
    return latestAnnouncement(ref);
  }
}

String _$latestAnnouncementHash() =>
    r'c2934070e6b7306b3dc3e834f5d64d402e4433cf';

/// 未完了のアナウンスメント全件（新しい順）

@ProviderFor(activeAnnouncements)
final activeAnnouncementsProvider = ActiveAnnouncementsProvider._();

/// 未完了のアナウンスメント全件（新しい順）

final class ActiveAnnouncementsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          FutureOr<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $FutureProvider<List<Announcement>> {
  /// 未完了のアナウンスメント全件（新しい順）
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
  $FutureProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Announcement>> create(Ref ref) {
    return activeAnnouncements(ref);
  }
}

String _$activeAnnouncementsHash() =>
    r'97fb6617b00658bb936abff9459ed1ef7ff2edb5';
