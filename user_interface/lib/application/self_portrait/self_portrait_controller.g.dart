// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'self_portrait_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。
/// ページを閉じたら捨てる(開くたびに最新を読む)。

@ProviderFor(SelfPortraitController)
final selfPortraitControllerProvider = SelfPortraitControllerProvider._();

/// 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。
/// ページを閉じたら捨てる(開くたびに最新を読む)。
final class SelfPortraitControllerProvider
    extends $AsyncNotifierProvider<SelfPortraitController, SelfPortrait> {
  /// 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。
  /// ページを閉じたら捨てる(開くたびに最新を読む)。
  SelfPortraitControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selfPortraitControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selfPortraitControllerHash();

  @$internal
  @override
  SelfPortraitController create() => SelfPortraitController();
}

String _$selfPortraitControllerHash() =>
    r'30a37d21c1f7fa606be6393a1bb7506861cef00a';

/// 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。
/// ページを閉じたら捨てる(開くたびに最新を読む)。

abstract class _$SelfPortraitController extends $AsyncNotifier<SelfPortrait> {
  FutureOr<SelfPortrait> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SelfPortrait>, SelfPortrait>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SelfPortrait>, SelfPortrait>,
              AsyncValue<SelfPortrait>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// 項目を開いたときの根拠・変化。項目ごとに読む。

@ProviderFor(selfPortraitItemDetail)
final selfPortraitItemDetailProvider = SelfPortraitItemDetailFamily._();

/// 項目を開いたときの根拠・変化。項目ごとに読む。

final class SelfPortraitItemDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<ItemDetail>,
          ItemDetail,
          FutureOr<ItemDetail>
        >
    with $FutureModifier<ItemDetail>, $FutureProvider<ItemDetail> {
  /// 項目を開いたときの根拠・変化。項目ごとに読む。
  SelfPortraitItemDetailProvider._({
    required SelfPortraitItemDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'selfPortraitItemDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$selfPortraitItemDetailHash();

  @override
  String toString() {
    return r'selfPortraitItemDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ItemDetail> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<ItemDetail> create(Ref ref) {
    final argument = this.argument as String;
    return selfPortraitItemDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SelfPortraitItemDetailProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$selfPortraitItemDetailHash() =>
    r'dd629d71b59513b32ca83ad4e8b3acad4c9f10a2';

/// 項目を開いたときの根拠・変化。項目ごとに読む。

final class SelfPortraitItemDetailFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ItemDetail>, String> {
  SelfPortraitItemDetailFamily._()
    : super(
        retry: null,
        name: r'selfPortraitItemDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 項目を開いたときの根拠・変化。項目ごとに読む。

  SelfPortraitItemDetailProvider call(String itemId) =>
      SelfPortraitItemDetailProvider._(argument: itemId, from: this);

  @override
  String toString() => r'selfPortraitItemDetailProvider';
}

/// AIのメモ(話し方・今の状況・観察)。消す操作は先に画面から消し、失敗したら読み直す。

@ProviderFor(AiMemoryController)
final aiMemoryControllerProvider = AiMemoryControllerProvider._();

/// AIのメモ(話し方・今の状況・観察)。消す操作は先に画面から消し、失敗したら読み直す。
final class AiMemoryControllerProvider
    extends $AsyncNotifierProvider<AiMemoryController, AiMemory> {
  /// AIのメモ(話し方・今の状況・観察)。消す操作は先に画面から消し、失敗したら読み直す。
  AiMemoryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiMemoryControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiMemoryControllerHash();

  @$internal
  @override
  AiMemoryController create() => AiMemoryController();
}

String _$aiMemoryControllerHash() =>
    r'9325548d184d2c50bd08111803e2df1d82403740';

/// AIのメモ(話し方・今の状況・観察)。消す操作は先に画面から消し、失敗したら読み直す。

abstract class _$AiMemoryController extends $AsyncNotifier<AiMemory> {
  FutureOr<AiMemory> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AiMemory>, AiMemory>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AiMemory>, AiMemory>,
              AsyncValue<AiMemory>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
