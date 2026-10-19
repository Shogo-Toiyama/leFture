// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_cache_drift.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatCacheDrift)
final chatCacheDriftProvider = ChatCacheDriftProvider._();

final class ChatCacheDriftProvider
    extends $FunctionalProvider<ChatCacheDrift, ChatCacheDrift, ChatCacheDrift>
    with $Provider<ChatCacheDrift> {
  ChatCacheDriftProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatCacheDriftProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatCacheDriftHash();

  @$internal
  @override
  $ProviderElement<ChatCacheDrift> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChatCacheDrift create(Ref ref) {
    return chatCacheDrift(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatCacheDrift value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatCacheDrift>(value),
    );
  }
}

String _$chatCacheDriftHash() => r'33c8d9aeacdbe622c0e34d323bd2e66d4afb4932';
