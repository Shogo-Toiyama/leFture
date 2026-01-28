// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_state_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(audioStatus)
final audioStatusProvider = AudioStatusFamily._();

final class AudioStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<AudioStatus>,
          AudioStatus,
          FutureOr<AudioStatus>
        >
    with $FutureModifier<AudioStatus>, $FutureProvider<AudioStatus> {
  AudioStatusProvider._({
    required AudioStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'audioStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$audioStatusHash();

  @override
  String toString() {
    return r'audioStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AudioStatus> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AudioStatus> create(Ref ref) {
    final argument = this.argument as String;
    return audioStatus(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AudioStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$audioStatusHash() => r'702392b458c75711fac94c5e517d1b58918df007';

final class AudioStatusFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AudioStatus>, String> {
  AudioStatusFamily._()
    : super(
        retry: null,
        name: r'audioStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AudioStatusProvider call(String lectureId) =>
      AudioStatusProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'audioStatusProvider';
}

@ProviderFor(lectureState)
final lectureStateProvider = LectureStateFamily._();

final class LectureStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<LectureUIState>,
          LectureUIState,
          Stream<LectureUIState>
        >
    with $FutureModifier<LectureUIState>, $StreamProvider<LectureUIState> {
  LectureStateProvider._({
    required LectureStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lectureStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureStateHash();

  @override
  String toString() {
    return r'lectureStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<LectureUIState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LectureUIState> create(Ref ref) {
    final argument = this.argument as String;
    return lectureState(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureStateHash() => r'1a87f1471c72dd6b254fbb77658cc820479d1703';

final class LectureStateFamily extends $Family
    with $FunctionalFamilyOverride<Stream<LectureUIState>, String> {
  LectureStateFamily._()
    : super(
        retry: null,
        name: r'lectureStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LectureStateProvider call(String lectureId) =>
      LectureStateProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureStateProvider';
}
