// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_conversation.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 今開いている会話の表示と送信(webappのuseChatConversationと同じ役割)。
///
/// シートは1つしか開かないので、アプリで1つだけ持つ。シートを閉じても受信は続けるので、
/// 開き直せば生成途中の返答がそのまま見える。裏に回って接続が切れたときは、返答の生成・保存・課金は
/// サーバー側で最後まで走り切るので、戻ってきたとき([onAppResumed])にDBから読み直す。

@ProviderFor(ChatConversation)
final chatConversationProvider = ChatConversationProvider._();

/// 今開いている会話の表示と送信(webappのuseChatConversationと同じ役割)。
///
/// シートは1つしか開かないので、アプリで1つだけ持つ。シートを閉じても受信は続けるので、
/// 開き直せば生成途中の返答がそのまま見える。裏に回って接続が切れたときは、返答の生成・保存・課金は
/// サーバー側で最後まで走り切るので、戻ってきたとき([onAppResumed])にDBから読み直す。
final class ChatConversationProvider
    extends $NotifierProvider<ChatConversation, ChatConversationState> {
  /// 今開いている会話の表示と送信(webappのuseChatConversationと同じ役割)。
  ///
  /// シートは1つしか開かないので、アプリで1つだけ持つ。シートを閉じても受信は続けるので、
  /// 開き直せば生成途中の返答がそのまま見える。裏に回って接続が切れたときは、返答の生成・保存・課金は
  /// サーバー側で最後まで走り切るので、戻ってきたとき([onAppResumed])にDBから読み直す。
  ChatConversationProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatConversationProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatConversationHash();

  @$internal
  @override
  ChatConversation create() => ChatConversation();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatConversationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatConversationState>(value),
    );
  }
}

String _$chatConversationHash() => r'68e9a98e01d93850ac2752a3b53bf3a3959e5487';

/// 今開いている会話の表示と送信(webappのuseChatConversationと同じ役割)。
///
/// シートは1つしか開かないので、アプリで1つだけ持つ。シートを閉じても受信は続けるので、
/// 開き直せば生成途中の返答がそのまま見える。裏に回って接続が切れたときは、返答の生成・保存・課金は
/// サーバー側で最後まで走り切るので、戻ってきたとき([onAppResumed])にDBから読み直す。

abstract class _$ChatConversation extends $Notifier<ChatConversationState> {
  ChatConversationState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChatConversationState, ChatConversationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChatConversationState, ChatConversationState>,
              ChatConversationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
