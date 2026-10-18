// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_threads.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// スレッド一覧(最近動いた順)。端末のキャッシュを監視するので、開いた瞬間に前回の一覧が出る。
/// サーバーの最新に追いつくのは[ChatThreadActions.refresh]。

@ProviderFor(chatThreadList)
final chatThreadListProvider = ChatThreadListProvider._();

/// スレッド一覧(最近動いた順)。端末のキャッシュを監視するので、開いた瞬間に前回の一覧が出る。
/// サーバーの最新に追いつくのは[ChatThreadActions.refresh]。

final class ChatThreadListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChatThread>>,
          List<ChatThread>,
          Stream<List<ChatThread>>
        >
    with $FutureModifier<List<ChatThread>>, $StreamProvider<List<ChatThread>> {
  /// スレッド一覧(最近動いた順)。端末のキャッシュを監視するので、開いた瞬間に前回の一覧が出る。
  /// サーバーの最新に追いつくのは[ChatThreadActions.refresh]。
  ChatThreadListProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatThreadListProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatThreadListHash();

  @$internal
  @override
  $StreamProviderElement<List<ChatThread>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ChatThread>> create(Ref ref) {
    return chatThreadList(ref);
  }
}

String _$chatThreadListHash() => r'ab7bc7ba8cb9d94b6dc958ed40557eaea030c94e';

/// スレッド一覧の操作。書き込みはバックエンド経由で、成功してからキャッシュに反映する。

@ProviderFor(ChatThreadActions)
final chatThreadActionsProvider = ChatThreadActionsProvider._();

/// スレッド一覧の操作。書き込みはバックエンド経由で、成功してからキャッシュに反映する。
final class ChatThreadActionsProvider
    extends $NotifierProvider<ChatThreadActions, void> {
  /// スレッド一覧の操作。書き込みはバックエンド経由で、成功してからキャッシュに反映する。
  ChatThreadActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatThreadActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatThreadActionsHash();

  @$internal
  @override
  ChatThreadActions create() => ChatThreadActions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$chatThreadActionsHash() => r'00eb945e80009b24e88c220d9fd50ca04c272844';

/// スレッド一覧の操作。書き込みはバックエンド経由で、成功してからキャッシュに反映する。

abstract class _$ChatThreadActions extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
