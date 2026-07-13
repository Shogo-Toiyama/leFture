// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_map_reconstruct_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
/// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
/// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
/// 再取得させて画面を最新のマップに更新する。

@ProviderFor(TopicMapReconstructController)
final topicMapReconstructControllerProvider =
    TopicMapReconstructControllerFamily._();

/// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
/// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
/// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
/// 再取得させて画面を最新のマップに更新する。
final class TopicMapReconstructControllerProvider
    extends $AsyncNotifierProvider<TopicMapReconstructController, void> {
  /// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
  /// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
  /// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
  /// 再取得させて画面を最新のマップに更新する。
  TopicMapReconstructControllerProvider._({
    required TopicMapReconstructControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'topicMapReconstructControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$topicMapReconstructControllerHash();

  @override
  String toString() {
    return r'topicMapReconstructControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  TopicMapReconstructController create() => TopicMapReconstructController();

  @override
  bool operator ==(Object other) {
    return other is TopicMapReconstructControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$topicMapReconstructControllerHash() =>
    r'5d6722fb69271e2f523557f945149e7de0280b2e';

/// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
/// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
/// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
/// 再取得させて画面を最新のマップに更新する。

final class TopicMapReconstructControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          TopicMapReconstructController,
          AsyncValue<void>,
          void,
          FutureOr<void>,
          String
        > {
  TopicMapReconstructControllerFamily._()
    : super(
        retry: null,
        name: r'topicMapReconstructControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
  /// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
  /// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
  /// 再取得させて画面を最新のマップに更新する。

  TopicMapReconstructControllerProvider call(String courseId) =>
      TopicMapReconstructControllerProvider._(argument: courseId, from: this);

  @override
  String toString() => r'topicMapReconstructControllerProvider';
}

/// 「Recreate Topic Map」操作の状態管理。Lectureの削除・移動でstaleになった
/// Courseに対して、Phase A(決定的除去)+Phase B(LLMによる修復)の一括再構成
/// (数秒かかりうる)を実行し、完了したらtopicMapForCourseProviderを
/// 再取得させて画面を最新のマップに更新する。

abstract class _$TopicMapReconstructController extends $AsyncNotifier<void> {
  late final _$args = ref.$arg as String;
  String get courseId => _$args;

  FutureOr<void> build(String courseId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
