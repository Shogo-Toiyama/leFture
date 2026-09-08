// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_notification_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリ起動中ずっとFCMのトークン登録・受信・タップ遷移を監視するサービス。
/// AppLifecycleSyncWatcherと同じく、MyApp.buildでref.watchされることで
/// 初めて生成・起動する(誰も参照しなければ何もリスナー登録されない)。

@ProviderFor(pushNotificationService)
final pushNotificationServiceProvider = PushNotificationServiceProvider._();

/// アプリ起動中ずっとFCMのトークン登録・受信・タップ遷移を監視するサービス。
/// AppLifecycleSyncWatcherと同じく、MyApp.buildでref.watchされることで
/// 初めて生成・起動する(誰も参照しなければ何もリスナー登録されない)。

final class PushNotificationServiceProvider
    extends
        $FunctionalProvider<
          PushNotificationService,
          PushNotificationService,
          PushNotificationService
        >
    with $Provider<PushNotificationService> {
  /// アプリ起動中ずっとFCMのトークン登録・受信・タップ遷移を監視するサービス。
  /// AppLifecycleSyncWatcherと同じく、MyApp.buildでref.watchされることで
  /// 初めて生成・起動する(誰も参照しなければ何もリスナー登録されない)。
  PushNotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pushNotificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pushNotificationServiceHash();

  @$internal
  @override
  $ProviderElement<PushNotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PushNotificationService create(Ref ref) {
    return pushNotificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PushNotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PushNotificationService>(value),
    );
  }
}

String _$pushNotificationServiceHash() =>
    r'54350b7ded58592300e3e088460348ff8bbf4675';
