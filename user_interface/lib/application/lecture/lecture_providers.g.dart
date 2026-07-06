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

@ProviderFor(lecture)
final lectureProvider = LectureFamily._();

final class LectureProvider
    extends
        $FunctionalProvider<AsyncValue<Lecture?>, Lecture?, Stream<Lecture?>>
    with $FutureModifier<Lecture?>, $StreamProvider<Lecture?> {
  LectureProvider._({
    required LectureFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lectureProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureHash();

  @override
  String toString() {
    return r'lectureProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<Lecture?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Lecture?> create(Ref ref) {
    final argument = this.argument as String;
    return lecture(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureHash() => r'db41e0468b2cd7844d10f75425ce7f9f1329696b';

final class LectureFamily extends $Family
    with $FunctionalFamilyOverride<Stream<Lecture?>, String> {
  LectureFamily._()
    : super(
        retry: null,
        name: r'lectureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  LectureProvider call(String id) =>
      LectureProvider._(argument: id, from: this);

  @override
  String toString() => r'lectureProvider';
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

@ProviderFor(artifactFile)
final artifactFileProvider = ArtifactFileFamily._();

final class ArtifactFileProvider
    extends $FunctionalProvider<AsyncValue<File?>, File?, FutureOr<File?>>
    with $FutureModifier<File?>, $FutureProvider<File?> {
  ArtifactFileProvider._({
    required ArtifactFileFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'artifactFileProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$artifactFileHash();

  @override
  String toString() {
    return r'artifactFileProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<File?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<File?> create(Ref ref) {
    final argument = this.argument as String;
    return artifactFile(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ArtifactFileProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$artifactFileHash() => r'b103c348bcf17a3b0afcd1d660c82898f2586e15';

final class ArtifactFileFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<File?>, String> {
  ArtifactFileFamily._()
    : super(
        retry: null,
        name: r'artifactFileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ArtifactFileProvider call(String storagePath) =>
      ArtifactFileProvider._(argument: storagePath, from: this);

  @override
  String toString() => r'artifactFileProvider';
}
