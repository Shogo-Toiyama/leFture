// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_ping_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 「ユーザーがアプリを使っている」ことをSupabaseに記録する(ping)。
///
/// ■ なぜこれが要るのか
/// アクティブユーザーを auth.users.last_sign_in_at から測ることはできない。
/// GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)の
/// ときだけで、リフレッシュトークンによるセッション更新では更新されないため、
/// 「毎日使っているのに最終ログインは3ヶ月前」が普通に起きる。
/// かといって lectures や review_cards の updated_at から推測すると、機能が
/// 増えるたびに集計の定義を更新し続けることになり、更新し忘れた機能は静かに
/// 計測から漏れる。だから「使っている」を明示的に1経路で記録する。
///
/// ■ なぜ10分おきなのか
/// サーバー側(user_activity_hours)は (user_id, 時, platform) が主キーなので、
/// 10分おきに打っても同じ1時間の行にUPSERTで畳み込まれる —— つまり行数は
/// 「実際に触った時間数」しか増えない。増えるのは ping_count で、これが
/// 「その1時間をどれだけ使ったか」(最大6)を表す。起動時だけのpingだと
/// 2時間の授業が「開始時刻の1行」に潰れてしまう。
///
/// ■ フォアグラウンドのときだけ打つ
/// バックグラウンドに退避したアプリを「使っている」と数えると、利用時間帯の
/// 分布が意味を失う。AppLifecycleListenerでresume/pauseに追従する
/// (app_lifecycle_sync_watcher.dart と同じパターン)。

@ProviderFor(activityPingService)
final activityPingServiceProvider = ActivityPingServiceProvider._();

/// 「ユーザーがアプリを使っている」ことをSupabaseに記録する(ping)。
///
/// ■ なぜこれが要るのか
/// アクティブユーザーを auth.users.last_sign_in_at から測ることはできない。
/// GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)の
/// ときだけで、リフレッシュトークンによるセッション更新では更新されないため、
/// 「毎日使っているのに最終ログインは3ヶ月前」が普通に起きる。
/// かといって lectures や review_cards の updated_at から推測すると、機能が
/// 増えるたびに集計の定義を更新し続けることになり、更新し忘れた機能は静かに
/// 計測から漏れる。だから「使っている」を明示的に1経路で記録する。
///
/// ■ なぜ10分おきなのか
/// サーバー側(user_activity_hours)は (user_id, 時, platform) が主キーなので、
/// 10分おきに打っても同じ1時間の行にUPSERTで畳み込まれる —— つまり行数は
/// 「実際に触った時間数」しか増えない。増えるのは ping_count で、これが
/// 「その1時間をどれだけ使ったか」(最大6)を表す。起動時だけのpingだと
/// 2時間の授業が「開始時刻の1行」に潰れてしまう。
///
/// ■ フォアグラウンドのときだけ打つ
/// バックグラウンドに退避したアプリを「使っている」と数えると、利用時間帯の
/// 分布が意味を失う。AppLifecycleListenerでresume/pauseに追従する
/// (app_lifecycle_sync_watcher.dart と同じパターン)。

final class ActivityPingServiceProvider
    extends
        $FunctionalProvider<
          ActivityPingService,
          ActivityPingService,
          ActivityPingService
        >
    with $Provider<ActivityPingService> {
  /// 「ユーザーがアプリを使っている」ことをSupabaseに記録する(ping)。
  ///
  /// ■ なぜこれが要るのか
  /// アクティブユーザーを auth.users.last_sign_in_at から測ることはできない。
  /// GoTrueがあれを更新するのは明示的なサインイン(パスワード/OAuth/OTP)の
  /// ときだけで、リフレッシュトークンによるセッション更新では更新されないため、
  /// 「毎日使っているのに最終ログインは3ヶ月前」が普通に起きる。
  /// かといって lectures や review_cards の updated_at から推測すると、機能が
  /// 増えるたびに集計の定義を更新し続けることになり、更新し忘れた機能は静かに
  /// 計測から漏れる。だから「使っている」を明示的に1経路で記録する。
  ///
  /// ■ なぜ10分おきなのか
  /// サーバー側(user_activity_hours)は (user_id, 時, platform) が主キーなので、
  /// 10分おきに打っても同じ1時間の行にUPSERTで畳み込まれる —— つまり行数は
  /// 「実際に触った時間数」しか増えない。増えるのは ping_count で、これが
  /// 「その1時間をどれだけ使ったか」(最大6)を表す。起動時だけのpingだと
  /// 2時間の授業が「開始時刻の1行」に潰れてしまう。
  ///
  /// ■ フォアグラウンドのときだけ打つ
  /// バックグラウンドに退避したアプリを「使っている」と数えると、利用時間帯の
  /// 分布が意味を失う。AppLifecycleListenerでresume/pauseに追従する
  /// (app_lifecycle_sync_watcher.dart と同じパターン)。
  ActivityPingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activityPingServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activityPingServiceHash();

  @$internal
  @override
  $ProviderElement<ActivityPingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ActivityPingService create(Ref ref) {
    return activityPingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActivityPingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActivityPingService>(value),
    );
  }
}

String _$activityPingServiceHash() =>
    r'2294f427eb4f5dbb2037e72fc1e786c852da9688';
