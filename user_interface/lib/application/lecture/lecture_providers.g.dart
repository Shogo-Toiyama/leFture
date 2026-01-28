// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(lectureArtifactRepository)
final lectureArtifactRepositoryProvider = LectureArtifactRepositoryProvider._();

final class LectureArtifactRepositoryProvider
    extends
        $FunctionalProvider<
          LectureArtifactRepository,
          LectureArtifactRepository,
          LectureArtifactRepository
        >
    with $Provider<LectureArtifactRepository> {
  LectureArtifactRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lectureArtifactRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lectureArtifactRepositoryHash();

  @$internal
  @override
  $ProviderElement<LectureArtifactRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LectureArtifactRepository create(Ref ref) {
    return lectureArtifactRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LectureArtifactRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LectureArtifactRepository>(value),
    );
  }
}

String _$lectureArtifactRepositoryHash() =>
    r'bd716409738b2114684a5442b088d34e9f2b5fc0';

@ProviderFor(lectureCompleteData)
final lectureCompleteDataProvider = LectureCompleteDataFamily._();

final class LectureCompleteDataProvider
    extends
        $FunctionalProvider<
          AsyncValue<LectureCompleteData?>,
          LectureCompleteData?,
          FutureOr<LectureCompleteData?>
        >
    with
        $FutureModifier<LectureCompleteData?>,
        $FutureProvider<LectureCompleteData?> {
  LectureCompleteDataProvider._({
    required LectureCompleteDataFamily super.from,
    required ({String uid, String lectureId}) super.argument,
  }) : super(
         retry: null,
         name: r'lectureCompleteDataProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureCompleteDataHash();

  @override
  String toString() {
    return r'lectureCompleteDataProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<LectureCompleteData?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LectureCompleteData?> create(Ref ref) {
    final argument = this.argument as ({String uid, String lectureId});
    return lectureCompleteData(
      ref,
      uid: argument.uid,
      lectureId: argument.lectureId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LectureCompleteDataProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureCompleteDataHash() =>
    r'a5b4c02397ad93a254bc5524bf94b52b0add45e5';

final class LectureCompleteDataFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<LectureCompleteData?>,
          ({String uid, String lectureId})
        > {
  LectureCompleteDataFamily._()
    : super(
        retry: null,
        name: r'lectureCompleteDataProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LectureCompleteDataProvider call({
    required String uid,
    required String lectureId,
  }) => LectureCompleteDataProvider._(
    argument: (uid: uid, lectureId: lectureId),
    from: this,
  );

  @override
  String toString() => r'lectureCompleteDataProvider';
}

@ProviderFor(transcript)
final transcriptProvider = TranscriptFamily._();

final class TranscriptProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TranscriptSentence>?>,
          List<TranscriptSentence>?,
          FutureOr<List<TranscriptSentence>?>
        >
    with
        $FutureModifier<List<TranscriptSentence>?>,
        $FutureProvider<List<TranscriptSentence>?> {
  TranscriptProvider._({
    required TranscriptFamily super.from,
    required ({String uid, String lectureId}) super.argument,
  }) : super(
         retry: null,
         name: r'transcriptProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$transcriptHash();

  @override
  String toString() {
    return r'transcriptProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<TranscriptSentence>?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<TranscriptSentence>?> create(Ref ref) {
    final argument = this.argument as ({String uid, String lectureId});
    return transcript(ref, uid: argument.uid, lectureId: argument.lectureId);
  }

  @override
  bool operator ==(Object other) {
    return other is TranscriptProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$transcriptHash() => r'b1b5d54d48f1f3f7cfaebaac389dab221d1eef59';

final class TranscriptFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<TranscriptSentence>?>,
          ({String uid, String lectureId})
        > {
  TranscriptFamily._()
    : super(
        retry: null,
        name: r'transcriptProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TranscriptProvider call({required String uid, required String lectureId}) =>
      TranscriptProvider._(
        argument: (uid: uid, lectureId: lectureId),
        from: this,
      );

  @override
  String toString() => r'transcriptProvider';
}
