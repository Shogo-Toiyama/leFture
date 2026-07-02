// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'galaxy_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(galaxyData)
final galaxyDataProvider = GalaxyDataProvider._();

final class GalaxyDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<GalaxyData>,
          GalaxyData,
          FutureOr<GalaxyData>
        >
    with $FutureModifier<GalaxyData>, $FutureProvider<GalaxyData> {
  GalaxyDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'galaxyDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$galaxyDataHash();

  @$internal
  @override
  $FutureProviderElement<GalaxyData> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<GalaxyData> create(Ref ref) {
    return galaxyData(ref);
  }
}

String _$galaxyDataHash() => r'92ff0766912682d013c306bca049dda613dfe394';
