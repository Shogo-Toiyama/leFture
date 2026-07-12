// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fun_fact_list_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 最新のFunFact一覧（最大5件、ローカルDB経由でオフライン優先)

@ProviderFor(recentFunFacts)
final recentFunFactsProvider = RecentFunFactsProvider._();

/// 最新のFunFact一覧（最大5件、ローカルDB経由でオフライン優先)

final class RecentFunFactsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FunFact>>,
          List<FunFact>,
          Stream<List<FunFact>>
        >
    with $FutureModifier<List<FunFact>>, $StreamProvider<List<FunFact>> {
  /// 最新のFunFact一覧（最大5件、ローカルDB経由でオフライン優先)
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
  $StreamProviderElement<List<FunFact>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<FunFact>> create(Ref ref) {
    return recentFunFacts(ref);
  }
}

String _$recentFunFactsHash() => r'cfde53d87c594e891153f61e37291565aa889d64';
