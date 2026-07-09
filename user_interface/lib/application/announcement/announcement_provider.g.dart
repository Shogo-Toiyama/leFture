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

/// 未完了のアナウンスメント全件（新しい順）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

@ProviderFor(ActiveAnnouncements)
final activeAnnouncementsProvider = ActiveAnnouncementsProvider._();

/// 未完了のアナウンスメント全件（新しい順）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
final class ActiveAnnouncementsProvider
    extends $AsyncNotifierProvider<ActiveAnnouncements, List<Announcement>> {
  /// 未完了のアナウンスメント全件（新しい順）。
  /// AsyncNotifier として管理することで、Done/Undo 操作後も
  /// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
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
  ActiveAnnouncements create() => ActiveAnnouncements();
}

String _$activeAnnouncementsHash() =>
    r'7dbab5b5ff6b57988c6aa7eed00b1d92f772daa5';

/// 未完了のアナウンスメント全件（新しい順）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

abstract class _$ActiveAnnouncements
    extends $AsyncNotifier<List<Announcement>> {
  FutureOr<List<Announcement>> build();
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
    element.handleCreate(ref, build);
  }
}
