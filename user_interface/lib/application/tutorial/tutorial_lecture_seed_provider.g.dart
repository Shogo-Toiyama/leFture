// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tutorial_lecture_seed_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(Cloud生成、Supabase同期)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// チュートリアル講義の実体は`/seed-tutorial`(lefture_backend)がユーザーの
/// 最初のDisplay言語に合わせてSupabaseへ投入する。既存ユーザー(移行前から
/// このアプリを使っている、またはローカルに旧ローカル生成方式のチュートリアル
/// を持つ)には新規作成しない — 判定方法は下記コメント参照。
///
/// 既定コースの確保・チュートリアル投入・Pull同期はいずれもネットワーク呼び
/// 出しを伴うため、オフライン時は今回の起動では諦める。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。

@ProviderFor(tutorialLectureSeed)
final tutorialLectureSeedProvider = TutorialLectureSeedProvider._();

/// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
/// 講義(Cloud生成、Supabase同期)が揃っているか確認し、無ければ用意する。
/// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
/// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
///
/// チュートリアル講義の実体は`/seed-tutorial`(lefture_backend)がユーザーの
/// 最初のDisplay言語に合わせてSupabaseへ投入する。既存ユーザー(移行前から
/// このアプリを使っている、またはローカルに旧ローカル生成方式のチュートリアル
/// を持つ)には新規作成しない — 判定方法は下記コメント参照。
///
/// 既定コースの確保・チュートリアル投入・Pull同期はいずれもネットワーク呼び
/// 出しを伴うため、オフライン時は今回の起動では諦める。この場合チュートリアル
/// 講義のシード自体もスキップし、次回起動時(オンラインになったタイミング)に
/// 再試行する。

final class TutorialLectureSeedProvider
    extends $FunctionalProvider<AsyncValue<void>, void, FutureOr<void>>
    with $FutureModifier<void>, $FutureProvider<void> {
  /// ログイン中ユーザーに、既定コース(本物のSupabase同期コース)とチュートリアル
  /// 講義(Cloud生成、Supabase同期)が揃っているか確認し、無ければ用意する。
  /// currentUserProviderをwatchしているため、ログイン/ログアウト/ユーザー
  /// 切り替えのたびに再評価され、冪等チェックも都度やり直される。
  ///
  /// チュートリアル講義の実体は`/seed-tutorial`(lefture_backend)がユーザーの
  /// 最初のDisplay言語に合わせてSupabaseへ投入する。既存ユーザー(移行前から
  /// このアプリを使っている、またはローカルに旧ローカル生成方式のチュートリアル
  /// を持つ)には新規作成しない — 判定方法は下記コメント参照。
  ///
  /// 既定コースの確保・チュートリアル投入・Pull同期はいずれもネットワーク呼び
  /// 出しを伴うため、オフライン時は今回の起動では諦める。この場合チュートリアル
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
    r'da3824325968166ca85ce5972ea631e4b69bbd41';
