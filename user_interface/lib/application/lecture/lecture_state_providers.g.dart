// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_state_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

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

String _$lectureStateHash() => r'b3023137e9794b331a2e288513f46f47f074df0d';

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
