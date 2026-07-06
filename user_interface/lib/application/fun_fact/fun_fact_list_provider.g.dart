// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fun_fact_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 最新のFunFact一覧（最大5件）

@ProviderFor(recentFunFacts)
final recentFunFactsProvider = RecentFunFactsProvider._();

/// 最新のFunFact一覧（最大5件）

final class RecentFunFactsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FunFact>>,
          List<FunFact>,
          FutureOr<List<FunFact>>
        >
    with $FutureModifier<List<FunFact>>, $FutureProvider<List<FunFact>> {
  /// 最新のFunFact一覧（最大5件）
  RecentFunFactsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentFunFactsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentFunFactsHash();

  @$internal
  @override
  $FutureProviderElement<List<FunFact>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FunFact>> create(Ref ref) {
    return recentFunFacts(ref);
  }
}

String _$recentFunFactsHash() => r'4923dfc9f25e67afe03220da1f714803a77e8280';
