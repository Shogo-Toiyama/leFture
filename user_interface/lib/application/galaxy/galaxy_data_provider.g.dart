// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'galaxy_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(galaxyData)
final galaxyDataProvider = GalaxyDataFamily._();

final class GalaxyDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<GalaxyData>,
          GalaxyData,
          FutureOr<GalaxyData>
        >
    with $FutureModifier<GalaxyData>, $FutureProvider<GalaxyData> {
  GalaxyDataProvider._({
    required GalaxyDataFamily super.from,
    required GalaxyConfig super.argument,
  }) : super(
         retry: null,
         name: r'galaxyDataProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$galaxyDataHash();

  @override
  String toString() {
    return r'galaxyDataProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<GalaxyData> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<GalaxyData> create(Ref ref) {
    final argument = this.argument as GalaxyConfig;
    return galaxyData(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is GalaxyDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$galaxyDataHash() => r'ce469cfe0b33859916894ea46f2f69097ed29867';

final class GalaxyDataFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<GalaxyData>, GalaxyConfig> {
  GalaxyDataFamily._()
    : super(
        retry: null,
        name: r'galaxyDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  GalaxyDataProvider call(GalaxyConfig config) =>
      GalaxyDataProvider._(argument: config, from: this);

  @override
  String toString() => r'galaxyDataProvider';
}
