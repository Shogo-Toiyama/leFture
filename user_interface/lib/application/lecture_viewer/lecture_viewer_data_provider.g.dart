// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_viewer_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）

@ProviderFor(lectureTopics)
final lectureTopicsProvider = LectureTopicsFamily._();

/// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）

final class LectureTopicsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LectureTopic>>,
          List<LectureTopic>,
          Stream<List<LectureTopic>>
        >
    with
        $FutureModifier<List<LectureTopic>>,
        $StreamProvider<List<LectureTopic>> {
  /// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）
  LectureTopicsProvider._({
    required LectureTopicsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lectureTopicsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureTopicsHash();

  @override
  String toString() {
    return r'lectureTopicsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LectureTopic>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LectureTopic>> create(Ref ref) {
    final argument = this.argument as String;
    return lectureTopics(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureTopicsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureTopicsHash() => r'05affb2cbabad7dd0814aeec1023abb85bc553d2';

/// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）

final class LectureTopicsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<LectureTopic>>, String> {
  LectureTopicsFamily._()
    : super(
        retry: null,
        name: r'lectureTopicsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のトピック一覧（index昇順、ローカルDB経由でオフライン優先）

  LectureTopicsProvider call(String lectureId) =>
      LectureTopicsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureTopicsProvider';
}

/// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）

@ProviderFor(deepNotes)
final deepNotesProvider = DeepNotesFamily._();

/// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）

final class DeepNotesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeepNote>>,
          List<DeepNote>,
          Stream<List<DeepNote>>
        >
    with $FutureModifier<List<DeepNote>>, $StreamProvider<List<DeepNote>> {
  /// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）
  DeepNotesProvider._({
    required DeepNotesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'deepNotesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deepNotesHash();

  @override
  String toString() {
    return r'deepNotesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<DeepNote>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<DeepNote>> create(Ref ref) {
    final argument = this.argument as String;
    return deepNotes(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DeepNotesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deepNotesHash() => r'0dcfe1befd577b036b328a0ba3e90f8513378624';

/// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）

final class DeepNotesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<DeepNote>>, String> {
  DeepNotesFamily._()
    : super(
        retry: null,
        name: r'deepNotesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のDeep Note一覧（topic_number昇順、ローカルDB経由でオフライン優先）

  DeepNotesProvider call(String lectureId) =>
      DeepNotesProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'deepNotesProvider';
}

/// 講義のキーワード一覧（ローカルDB経由でオフライン優先）

@ProviderFor(lectureKeywords)
final lectureKeywordsProvider = LectureKeywordsFamily._();

/// 講義のキーワード一覧（ローカルDB経由でオフライン優先）

final class LectureKeywordsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Keyword>>,
          List<Keyword>,
          Stream<List<Keyword>>
        >
    with $FutureModifier<List<Keyword>>, $StreamProvider<List<Keyword>> {
  /// 講義のキーワード一覧（ローカルDB経由でオフライン優先）
  LectureKeywordsProvider._({
    required LectureKeywordsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'lectureKeywordsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$lectureKeywordsHash();

  @override
  String toString() {
    return r'lectureKeywordsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Keyword>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Keyword>> create(Ref ref) {
    final argument = this.argument as String;
    return lectureKeywords(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LectureKeywordsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$lectureKeywordsHash() => r'ab1290bf9028bcf4058a3d1358f6c3909e188c03';

/// 講義のキーワード一覧（ローカルDB経由でオフライン優先）

final class LectureKeywordsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Keyword>>, String> {
  LectureKeywordsFamily._()
    : super(
        retry: null,
        name: r'lectureKeywordsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のキーワード一覧（ローカルDB経由でオフライン優先）

  LectureKeywordsProvider call(String lectureId) =>
      LectureKeywordsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureKeywordsProvider';
}

/// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）

@ProviderFor(reviewCards)
final reviewCardsProvider = ReviewCardsFamily._();

/// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）

final class ReviewCardsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReviewCard>>,
          List<ReviewCard>,
          Stream<List<ReviewCard>>
        >
    with $FutureModifier<List<ReviewCard>>, $StreamProvider<List<ReviewCard>> {
  /// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）
  ReviewCardsProvider._({
    required ReviewCardsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reviewCardsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reviewCardsHash();

  @override
  String toString() {
    return r'reviewCardsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ReviewCard>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ReviewCard>> create(Ref ref) {
    final argument = this.argument as String;
    return reviewCards(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReviewCardsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reviewCardsHash() => r'9294b8904f4149e4083fccf78a5ae32e4ecbbf85';

/// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）

final class ReviewCardsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ReviewCard>>, String> {
  ReviewCardsFamily._()
    : super(
        retry: null,
        name: r'reviewCardsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のレビューカード一覧（ローカルDB経由でオフライン優先）

  ReviewCardsProvider call(String lectureId) =>
      ReviewCardsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'reviewCardsProvider';
}

/// 講義のFunFact一覧(ローカルDB経由でオフライン優先)

@ProviderFor(funFactsForLecture)
final funFactsForLectureProvider = FunFactsForLectureFamily._();

/// 講義のFunFact一覧(ローカルDB経由でオフライン優先)

final class FunFactsForLectureProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FunFact>>,
          List<FunFact>,
          Stream<List<FunFact>>
        >
    with $FutureModifier<List<FunFact>>, $StreamProvider<List<FunFact>> {
  /// 講義のFunFact一覧(ローカルDB経由でオフライン優先)
  FunFactsForLectureProvider._({
    required FunFactsForLectureFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'funFactsForLectureProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$funFactsForLectureHash();

  @override
  String toString() {
    return r'funFactsForLectureProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<FunFact>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<FunFact>> create(Ref ref) {
    final argument = this.argument as String;
    return funFactsForLecture(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is FunFactsForLectureProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$funFactsForLectureHash() =>
    r'6cf3b22cea80bef05ab9d7d443cf5ac036a7f288';

/// 講義のFunFact一覧(ローカルDB経由でオフライン優先)

final class FunFactsForLectureFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<FunFact>>, String> {
  FunFactsForLectureFamily._()
    : super(
        retry: null,
        name: r'funFactsForLectureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のFunFact一覧(ローカルDB経由でオフライン優先)

  FunFactsForLectureProvider call(String lectureId) =>
      FunFactsForLectureProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'funFactsForLectureProvider';
}

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

@ProviderFor(announcementsForLecture)
final announcementsForLectureProvider = AnnouncementsForLectureFamily._();

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

final class AnnouncementsForLectureProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          Stream<List<Announcement>>
        >
    with
        $FutureModifier<List<Announcement>>,
        $StreamProvider<List<Announcement>> {
  /// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
  /// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
  /// そのまま反映される。
  AnnouncementsForLectureProvider._({
    required AnnouncementsForLectureFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'announcementsForLectureProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$announcementsForLectureHash();

  @override
  String toString() {
    return r'announcementsForLectureProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Announcement>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Announcement>> create(Ref ref) {
    final argument = this.argument as String;
    return announcementsForLecture(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AnnouncementsForLectureProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$announcementsForLectureHash() =>
    r'871b43a04aee216e2e20d97dc6d5db16cd9c7dcd';

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
/// そのまま反映される。

final class AnnouncementsForLectureFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Announcement>>, String> {
  AnnouncementsForLectureFamily._()
    : super(
        retry: null,
        name: r'announcementsForLectureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
  /// ローカルDB経由でオフライン優先。Streamなので、完了/未完了のトグルが
  /// そのまま反映される。

  AnnouncementsForLectureProvider call(String lectureId) =>
      AnnouncementsForLectureProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'announcementsForLectureProvider';
}
