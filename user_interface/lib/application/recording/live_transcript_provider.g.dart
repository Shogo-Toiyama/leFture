// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_transcript_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(liveTranscriptRepository)
final liveTranscriptRepositoryProvider = LiveTranscriptRepositoryProvider._();

final class LiveTranscriptRepositoryProvider
    extends
        $FunctionalProvider<
          LiveTranscriptRepository,
          LiveTranscriptRepository,
          LiveTranscriptRepository
        >
    with $Provider<LiveTranscriptRepository> {
  LiveTranscriptRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'liveTranscriptRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$liveTranscriptRepositoryHash();

  @$internal
  @override
  $ProviderElement<LiveTranscriptRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LiveTranscriptRepository create(Ref ref) {
    return liveTranscriptRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LiveTranscriptRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LiveTranscriptRepository>(value),
    );
  }
}

String _$liveTranscriptRepositoryHash() =>
    r'885286d508542724b8f9bc11caca475d6e850ad0';

@ProviderFor(liveTranscript)
final liveTranscriptProvider = LiveTranscriptFamily._();

final class LiveTranscriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LiveTranscriptSentence>>,
          List<LiveTranscriptSentence>,
          Stream<List<LiveTranscriptSentence>>
        >
    with
        $FutureModifier<List<LiveTranscriptSentence>>,
        $StreamProvider<List<LiveTranscriptSentence>> {
  LiveTranscriptProvider._({
    required LiveTranscriptFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'liveTranscriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$liveTranscriptHash();

  @override
  String toString() {
    return r'liveTranscriptProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LiveTranscriptSentence>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LiveTranscriptSentence>> create(Ref ref) {
    final argument = this.argument as String;
    return liveTranscript(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LiveTranscriptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$liveTranscriptHash() => r'9b8ae8bb5cd9383db9de712a5ef064a1bb28690e';

final class LiveTranscriptFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<LiveTranscriptSentence>>,
          String
        > {
  LiveTranscriptFamily._()
    : super(
        retry: null,
        name: r'liveTranscriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LiveTranscriptProvider call(String lectureId) =>
      LiveTranscriptProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'liveTranscriptProvider';
}
