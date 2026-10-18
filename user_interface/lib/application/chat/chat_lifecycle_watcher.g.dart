// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_lifecycle_watcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// アプリが前面に戻ったとき、受信中だったチャットの返答をサーバーの内容で読み直す。
///
/// 裏に回っている間に受信の接続が切れても、iOSはエラーにせず止まったままになることがある。サーバー側の
/// 生成・保存・課金は最後まで走るので、戻ってきたとき([ChatConversation.onAppResumed])にDBから追いつく。
/// シートを閉じていても受信は続くので、シートの表示ではなくアプリ全体で見張る。

@ProviderFor(chatLifecycleWatcher)
final chatLifecycleWatcherProvider = ChatLifecycleWatcherProvider._();

/// アプリが前面に戻ったとき、受信中だったチャットの返答をサーバーの内容で読み直す。
///
/// 裏に回っている間に受信の接続が切れても、iOSはエラーにせず止まったままになることがある。サーバー側の
/// 生成・保存・課金は最後まで走るので、戻ってきたとき([ChatConversation.onAppResumed])にDBから追いつく。
/// シートを閉じていても受信は続くので、シートの表示ではなくアプリ全体で見張る。

final class ChatLifecycleWatcherProvider
    extends
        $FunctionalProvider<
          AppLifecycleListener,
          AppLifecycleListener,
          AppLifecycleListener
        >
    with $Provider<AppLifecycleListener> {
  /// アプリが前面に戻ったとき、受信中だったチャットの返答をサーバーの内容で読み直す。
  ///
  /// 裏に回っている間に受信の接続が切れても、iOSはエラーにせず止まったままになることがある。サーバー側の
  /// 生成・保存・課金は最後まで走るので、戻ってきたとき([ChatConversation.onAppResumed])にDBから追いつく。
  /// シートを閉じていても受信は続くので、シートの表示ではなくアプリ全体で見張る。
  ChatLifecycleWatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatLifecycleWatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatLifecycleWatcherHash();

  @$internal
  @override
  $ProviderElement<AppLifecycleListener> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppLifecycleListener create(Ref ref) {
    return chatLifecycleWatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppLifecycleListener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppLifecycleListener>(value),
    );
  }
}

String _$chatLifecycleWatcherHash() =>
    r'3929dae30ae210fb5c4f795c3eaaceeb768f68f8';
