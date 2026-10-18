// lib/application/self_portrait/self_portrait_controller.dart
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/self_portrait/self_portrait_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'self_portrait_controller.g.dart';

/// 自分像ページのデータ。操作のたびに丸ごと取り直す(件数が小さいので部分更新はしない)。
/// ページを閉じたら捨てる(開くたびに最新を読む)。
@riverpod
class SelfPortraitController extends _$SelfPortraitController {
  @override
  Future<SelfPortrait> build() => ref.read(selfPortraitRepositoryProvider).get();

  /// 取り直す。失敗したら、手元の内容はそのままにして投げる。
  Future<void> refresh() async {
    final fresh = await ref.read(selfPortraitRepositoryProvider).get();
    state = AsyncData(fresh);
  }

  /// 項目を操作して、取り直す(操作が失敗したら投げる)。
  Future<void> act(Future<void> Function(SelfPortraitRepository repo) action) async {
    final repo = ref.read(selfPortraitRepositoryProvider);
    await action(repo);
    await refresh();
  }

  /// 「新しい」印を消す。開いたときに一度だけ呼ぶ(失敗しても困らない)。
  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      await ref.read(selfPortraitRepositoryProvider).markSeen(ids);
    } catch (_) {}
  }
}

/// 項目を開いたときの根拠・変化。項目ごとに読む。
@riverpod
Future<ItemDetail> selfPortraitItemDetail(Ref ref, String itemId) =>
    ref.read(selfPortraitRepositoryProvider).item(itemId);

/// AIのメモ(話し方・今の状況・観察)。消す操作は先に画面から消し、失敗したら読み直す。
@riverpod
class AiMemoryController extends _$AiMemoryController {
  @override
  Future<AiMemory> build() => ref.read(selfPortraitRepositoryProvider).aiMemory();

  Future<void> _optimistic(
    AiMemory Function(AiMemory) apply,
    Future<void> Function(SelfPortraitRepository repo) action,
  ) async {
    final current = state.asData?.value;
    if (current != null) state = AsyncData(apply(current));
    try {
      await action(ref.read(selfPortraitRepositoryProvider));
    } catch (_) {
      // 失敗した: 画面を本当の状態に戻す
      try {
        state = AsyncData(
          await ref.read(selfPortraitRepositoryProvider).aiMemory(),
        );
      } catch (_) {
        if (current != null) state = AsyncData(current);
      }
      rethrow;
    }
  }

  Future<void> removeMemo(String id) =>
      _optimistic((m) => m.withoutMemo(id), (r) => r.deleteMemo(id));

  Future<void> removeObservation(String id) => _optimistic(
    (m) => m.withoutObservation(id),
    (r) => r.deleteObservation(id),
  );

  Future<void> forgetAll() =>
      _optimistic((m) => m.withoutObservations(), (r) => r.forgetAiNotes());
}
