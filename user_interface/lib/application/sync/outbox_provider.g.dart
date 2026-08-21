// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outbox_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
/// 新しいエンティティ種別のOutbox対応を追加するときは、ハンドラ実装を
/// 足した上でここにも登録すること。

@ProviderFor(outboxSyncService)
final outboxSyncServiceProvider = OutboxSyncServiceProvider._();

/// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
/// 新しいエンティティ種別のOutbox対応を追加するときは、ハンドラ実装を
/// 足した上でここにも登録すること。

final class OutboxSyncServiceProvider
    extends
        $FunctionalProvider<
          OutboxSyncService,
          OutboxSyncService,
          OutboxSyncService
        >
    with $Provider<OutboxSyncService> {
  /// entityTypeごとのPushハンドラを登録した汎用Outbox送信サービス。
  /// 新しいエンティティ種別のOutbox対応を追加するときは、ハンドラ実装を
  /// 足した上でここにも登録すること。
  OutboxSyncServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'outboxSyncServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$outboxSyncServiceHash();

  @$internal
  @override
  $ProviderElement<OutboxSyncService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  OutboxSyncService create(Ref ref) {
    return outboxSyncService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OutboxSyncService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OutboxSyncService>(value),
    );
  }
}

String _$outboxSyncServiceHash() => r'cc8ef318b872026885da6a7649ac20e1c1d67d67';
