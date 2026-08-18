// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_polling_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(creditPolling)
final creditPollingProvider = CreditPollingProvider._();

final class CreditPollingProvider
    extends
        $FunctionalProvider<
          CreditPollingService,
          CreditPollingService,
          CreditPollingService
        >
    with $Provider<CreditPollingService> {
  CreditPollingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'creditPollingProvider',
        isAutoDispose: false,
        dependencies: <ProviderOrFamily>[recordingControllerProvider],
        $allTransitiveDependencies: <ProviderOrFamily>[
          CreditPollingProvider.$allTransitiveDependencies0,
          CreditPollingProvider.$allTransitiveDependencies1,
        ],
      );

  static final $allTransitiveDependencies0 = recordingControllerProvider;
  static final $allTransitiveDependencies1 =
      RecordingControllerProvider.$allTransitiveDependencies0;

  @override
  String debugGetCreateSourceHash() => _$creditPollingHash();

  @$internal
  @override
  $ProviderElement<CreditPollingService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  CreditPollingService create(Ref ref) {
    return creditPolling(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CreditPollingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CreditPollingService>(value),
    );
  }
}

String _$creditPollingHash() => r'4062d1b2dafa1f1f4825d75489f20532dc40b4ad';
