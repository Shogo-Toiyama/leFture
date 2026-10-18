import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/self_portrait.dart';
import 'package:lefture/infrastructure/self_portrait/self_portrait_repository.dart';

/// 自分像・AIのメモの通信の偽物。手元の値を返し、呼ばれた操作を覚える。
/// 操作は手元の値にも反映する(サーバーが取り直しで返す値の代わり)。
class FakeSelfPortraitRepository extends Fake implements SelfPortraitRepository {
  FakeSelfPortraitRepository({required this.portrait, required this.memory});

  SelfPortrait portrait;
  AiMemory memory;

  final calls = <String>[];
  Map<String, ItemDetail> details = {};

  /// trueの間、書き込みは失敗する。
  bool failWrites = false;

  /// 失敗する書き込みでも、サーバーには届いている(消えている)ことにする。
  void _write(String call, void Function() apply) {
    calls.add(call);
    if (failWrites) throw const SelfPortraitRequestException(500);
    apply();
  }

  @override
  Future<SelfPortrait> get() async {
    calls.add('get');
    return portrait;
  }

  @override
  Future<ItemDetail> item(String id) async {
    calls.add('item:$id');
    return details[id] ??
        ItemDetail(content: '', origin: 'ai', evidence: const [], versions: const []);
  }

  @override
  Future<void> edit(String id, String content) async =>
      _write('edit:$id:$content', () {});

  @override
  Future<void> reject(String id, {String? reason}) async =>
      _write('reject:$id:${reason ?? ''}', () {});

  @override
  Future<void> discard(String id) async => _write('discard:$id', () {
    portrait = _without(id);
  });

  @override
  Future<void> keep(String id) async => _write('keep:$id', () {
    portrait = SelfPortrait(
      cover: portrait.cover,
      proposals: portrait.proposals,
      categories: portrait.categories,
      recent: portrait.recent,
      items: [
        for (final i in portrait.items)
          if (i.id == id)
            ProfileItem(
              id: i.id,
              kind: i.kind,
              content: i.content,
              origin: i.origin,
              status: 'active',
              sensitive: i.sensitive,
              isNew: i.isNew,
              changedAt: i.changedAt,
              evidenceThreads: i.evidenceThreads,
              categoryId: i.categoryId,
            )
          else
            i,
      ],
    );
  });

  @override
  Future<void> markSeen(List<String> ids) async =>
      calls.add('seen:${ids.join(',')}');

  @override
  Future<void> decideProposal(String id, {required bool accept}) async =>
      _write('proposal:$id:${accept ? 'accept' : 'reject'}', () {
        portrait = SelfPortrait(
          cover: portrait.cover,
          proposals: [
            for (final p in portrait.proposals)
              if (p.id != id) p,
          ],
          categories: portrait.categories,
          items: portrait.items,
          recent: portrait.recent,
        );
      });

  @override
  Future<AiMemory> aiMemory() async {
    calls.add('aiMemory');
    return memory;
  }

  @override
  Future<void> deleteMemo(String id) async =>
      _write('deleteMemo:$id', () => memory = memory.withoutMemo(id));

  @override
  Future<void> deleteObservation(String id) async => _write(
    'deleteObservation:$id',
    () => memory = memory.withoutObservation(id),
  );

  @override
  Future<void> forgetAiNotes() async =>
      _write('forget', () => memory = memory.withoutObservations());

  SelfPortrait _without(String id) => SelfPortrait(
    cover: portrait.cover,
    proposals: portrait.proposals,
    categories: portrait.categories,
    recent: portrait.recent,
    items: [
      for (final i in portrait.items)
        if (i.id != id) i,
    ],
  );
}
