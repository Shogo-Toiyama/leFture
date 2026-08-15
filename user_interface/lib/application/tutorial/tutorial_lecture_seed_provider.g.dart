// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tutorial_lecture_seed_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(ローカル限定)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// 既定コースの確保はSupabaseへのネットワーク呼び出しを伴うため、オフライン時は
/// 今回の起動では諦める(DefaultCourseServiceがnullを返す)。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。

@ProviderFor(tutorialLectureSeed)
final tutorialLectureSeedProvider = TutorialLectureSeedProvider._();

/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(ローカル限定)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// 既定コースの確保はSupabaseへのネットワーク呼び出しを伴うため、オフライン時は
/// 今回の起動では諦める(DefaultCourseServiceがnullを返す)。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。

final class TutorialLectureSeedProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
  /// 講義(ローカル限定)が揃っているか確認し、無ければ用意する。
  /// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
  /// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
  ///
  /// 既定コースの確保はSupabaseへのネットワーク呼び出しを伴うため、オフライン時は
  /// 今回の起動では諦める(DefaultCourseServiceがnullを返す)。この場合チュートリアル
  /// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
  /// 再試行する。
  TutorialLectureSeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tutorialLectureSeedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tutorialLectureSeedHash();

  @$internal
  @override
  $FutureProviderElement<void> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<void> create(Ref ref) {
    return tutorialLectureSeed(ref);
  }
}

String _$tutorialLectureSeedHash() =>
    r'd07e9dc5daa624a97b2e39869593f8c266fcb3df';
