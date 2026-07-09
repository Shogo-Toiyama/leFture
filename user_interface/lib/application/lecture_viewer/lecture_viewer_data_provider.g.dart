// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lecture_viewer_data_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 講義のトピック一覧（index昇順）

@ProviderFor(lectureTopics)
final lectureTopicsProvider = LectureTopicsFamily._();

/// 講義のトピック一覧（index昇順）

final class LectureTopicsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LectureTopic>>,
          List<LectureTopic>,
          FutureOr<List<LectureTopic>>
        >
    with
        $FutureModifier<List<LectureTopic>>,
        $FutureProvider<List<LectureTopic>> {
  /// 講義のトピック一覧（index昇順）
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
  $FutureProviderElement<List<LectureTopic>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LectureTopic>> create(Ref ref) {
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

String _$lectureTopicsHash() => r'5bcbcfae132991f7cfa0032474b126230afffeeb';

/// 講義のトピック一覧（index昇順）

final class LectureTopicsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<LectureTopic>>, String> {
  LectureTopicsFamily._()
    : super(
        retry: null,
        name: r'lectureTopicsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のトピック一覧（index昇順）

  LectureTopicsProvider call(String lectureId) =>
      LectureTopicsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureTopicsProvider';
}

/// 講義のDeep Note一覧（topic_number昇順）

@ProviderFor(deepNotes)
final deepNotesProvider = DeepNotesFamily._();

/// 講義のDeep Note一覧（topic_number昇順）

final class DeepNotesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DeepNote>>,
          List<DeepNote>,
          FutureOr<List<DeepNote>>
        >
    with $FutureModifier<List<DeepNote>>, $FutureProvider<List<DeepNote>> {
  /// 講義のDeep Note一覧（topic_number昇順）
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
  $FutureProviderElement<List<DeepNote>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DeepNote>> create(Ref ref) {
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

String _$deepNotesHash() => r'd1ef02fe0dad1b18043f4299e7a5350db63bcd83';

/// 講義のDeep Note一覧（topic_number昇順）

final class DeepNotesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<DeepNote>>, String> {
  DeepNotesFamily._()
    : super(
        retry: null,
        name: r'deepNotesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のDeep Note一覧（topic_number昇順）

  DeepNotesProvider call(String lectureId) =>
      DeepNotesProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'deepNotesProvider';
}

/// 講義のキーワード一覧

@ProviderFor(lectureKeywords)
final lectureKeywordsProvider = LectureKeywordsFamily._();

/// 講義のキーワード一覧

final class LectureKeywordsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Keyword>>,
          List<Keyword>,
          FutureOr<List<Keyword>>
        >
    with $FutureModifier<List<Keyword>>, $FutureProvider<List<Keyword>> {
  /// 講義のキーワード一覧
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
  $FutureProviderElement<List<Keyword>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Keyword>> create(Ref ref) {
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

String _$lectureKeywordsHash() => r'bc73a407549a49a5ce9e6ccd0019d2b80725b828';

/// 講義のキーワード一覧

final class LectureKeywordsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Keyword>>, String> {
  LectureKeywordsFamily._()
    : super(
        retry: null,
        name: r'lectureKeywordsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のキーワード一覧

  LectureKeywordsProvider call(String lectureId) =>
      LectureKeywordsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'lectureKeywordsProvider';
}

/// 講義のレビューカード一覧

@ProviderFor(reviewCards)
final reviewCardsProvider = ReviewCardsFamily._();

/// 講義のレビューカード一覧

final class ReviewCardsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ReviewCard>>,
          List<ReviewCard>,
          FutureOr<List<ReviewCard>>
        >
    with $FutureModifier<List<ReviewCard>>, $FutureProvider<List<ReviewCard>> {
  /// 講義のレビューカード一覧
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
  $FutureProviderElement<List<ReviewCard>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ReviewCard>> create(Ref ref) {
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

String _$reviewCardsHash() => r'e2e0fbe885428513653aa63a037143a03b41624d';

/// 講義のレビューカード一覧

final class ReviewCardsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ReviewCard>>, String> {
  ReviewCardsFamily._()
    : super(
        retry: null,
        name: r'reviewCardsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のレビューカード一覧

  ReviewCardsProvider call(String lectureId) =>
      ReviewCardsProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'reviewCardsProvider';
}

/// 講義のFunFact一覧

@ProviderFor(funFactsForLecture)
final funFactsForLectureProvider = FunFactsForLectureFamily._();

/// 講義のFunFact一覧

final class FunFactsForLectureProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<FunFact>>,
          List<FunFact>,
          FutureOr<List<FunFact>>
        >
    with $FutureModifier<List<FunFact>>, $FutureProvider<List<FunFact>> {
  /// 講義のFunFact一覧
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
  $FutureProviderElement<List<FunFact>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<FunFact>> create(Ref ref) {
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
    r'e9b9f9a9ca16da18876f1251edb297eb86a150d0';

/// 講義のFunFact一覧

final class FunFactsForLectureFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<FunFact>>, String> {
  FunFactsForLectureFamily._()
    : super(
        retry: null,
        name: r'funFactsForLectureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のFunFact一覧

  FunFactsForLectureProvider call(String lectureId) =>
      FunFactsForLectureProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'funFactsForLectureProvider';
}

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

@ProviderFor(AnnouncementsForLecture)
final announcementsForLectureProvider = AnnouncementsForLectureFamily._();

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
final class AnnouncementsForLectureProvider
    extends
        $AsyncNotifierProvider<AnnouncementsForLecture, List<Announcement>> {
  /// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
  /// AsyncNotifier として管理することで、Done/Undo 操作後も
  /// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。
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
  AnnouncementsForLecture create() => AnnouncementsForLecture();

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
    r'ade9203750620a65c0d0751fbd0df4ff72852f0e';

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

final class AnnouncementsForLectureFamily extends $Family
    with
        $ClassFamilyOverride<
          AnnouncementsForLecture,
          AsyncValue<List<Announcement>>,
          List<Announcement>,
          FutureOr<List<Announcement>>,
          String
        > {
  AnnouncementsForLectureFamily._()
    : super(
        retry: null,
        name: r'announcementsForLectureProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
  /// AsyncNotifier として管理することで、Done/Undo 操作後も
  /// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

  AnnouncementsForLectureProvider call(String lectureId) =>
      AnnouncementsForLectureProvider._(argument: lectureId, from: this);

  @override
  String toString() => r'announcementsForLectureProvider';
}

/// 講義のアナウンスメント一覧（全件・completed_atを問わず）。
/// AsyncNotifier として管理することで、Done/Undo 操作後も
/// プロバイダを invalidate せずローカル状態だけを更新（シート閉じるまで表示維持）。

abstract class _$AnnouncementsForLecture
    extends $AsyncNotifier<List<Announcement>> {
  late final _$args = ref.$arg as String;
  String get lectureId => _$args;

  FutureOr<List<Announcement>> build(String lectureId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<Announcement>>, List<Announcement>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Announcement>>, List<Announcement>>,
              AsyncValue<List<Announcement>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
