import 'package:flutter_test/flutter_test.dart';
import 'package:lefture/domain/entities/self_portrait.dart';

void main() {
  group('SelfPortrait.fromMap', () {
    test('表紙・提案・カテゴリ・項目・最近わかったことを読む', () {
      final p = SelfPortrait.fromMap({
        'cover': {
          'bio': {'text': 'こんにちは', 'written_by': 'ai'},
          'interests': {'text': null, 'written_by': null},
        },
        'proposals': [
          {
            'id': 'p1',
            'field': 'future_goals',
            'proposed_text': '教師になる',
            'created_at': '2026-10-01T00:00:00Z',
          },
          // 知らない欄の提案は読み飛ばす
          {'id': 'p2', 'field': 'unknown', 'proposed_text': 'x'},
        ],
        'categories': [
          {
            'id': 'c1',
            'name': '学び方',
            'description': '',
            'kind': 'trait',
            'parent_id': null,
          },
        ],
        'items': [
          {
            'id': 'i1',
            'category_id': 'c1',
            'kind': 'trait',
            'content': '図で考えるのが得意',
            'origin': 'ai',
            'status': 'active',
            'sensitive': 'none',
            'is_new': true,
            'changed_at': '2026-10-02T00:00:00Z',
            'evidence_threads': 2,
          },
          {
            'id': 'i2',
            'kind': 'trait',
            'content': 'ある信仰を持っている',
            'status': 'pending_confirm',
            'sensitive': 'religion',
            'changed_at': '2026-10-03T00:00:00Z',
          },
        ],
        'recent': [
          {
            'item_id': 'i1',
            'topics': ['ヒープ', '木'],
            'quote': null,
          },
        ],
      });

      expect(p.cover[CoverField.bio]!.text, 'こんにちは');
      expect(p.cover[CoverField.bio]!.writtenByAi, isTrue);
      // 無い欄は空の値で埋まる
      expect(p.cover[CoverField.futureGoals]!.text, isNull);
      expect(p.proposals.map((e) => e.field), [CoverField.futureGoals]);
      expect(p.items.first.isNew, isTrue);
      expect(p.items.first.evidenceThreads, 2);
      expect(p.active.map((e) => e.id), ['i1']);
      expect(p.pending.map((e) => e.id), ['i2']);
      expect(p.recent.single.topics, ['ヒープ', '木']);
    });

    test('空の応答でも落ちない', () {
      final p = SelfPortrait.fromMap({});
      expect(p.items, isEmpty);
      expect(p.cover.length, CoverField.values.length);
    });
  });

  group('ItemDetail.fromMap', () {
    test('根拠と変化を読み、自分で直した文を見分ける', () {
      final d = ItemDetail.fromMap({
        'item': {'content': '直した文', 'origin': 'user'},
        'evidence': [
          {
            'observation_id': 'o1',
            'thread_id': 't1',
            'thread_title': 'ヒープの話',
            'note': 'メモ',
            'quote': '図にすると分かる',
            'observed_at': '2026-10-01T00:00:00Z',
          },
        ],
        'versions': [
          {'content': '前の文', 'replaced_at': '2026-10-02T00:00:00Z'},
        ],
      });
      expect(d.editedByUser, isTrue);
      expect(d.evidence.single.quote, '図にすると分かる');
      expect(d.versions.single.content, '前の文');
    });
  });

  group('AiMemory', () {
    AiMemory sample() => AiMemory.fromMap({
      'memos': [
        {'id': 'm1', 'kind': 'answer_style', 'content': '簡潔に'},
        {
          'id': 'm2',
          'kind': 'situation',
          'content': '試験前',
          'expires_at': '2026-11-01',
        },
      ],
      'observation_groups': [
        {
          'thread_id': 't1',
          'thread_title': 'A',
          'last_observed_at': '2026-10-01T00:00:00Z',
          'observations': [
            {'id': 'o1', 'note': 'x', 'observed_at': '2026-10-01T00:00:00Z'},
            {'id': 'o2', 'note': 'y', 'observed_at': '2026-10-01T00:00:00Z'},
          ],
        },
        {
          'thread_id': 't2',
          'thread_title': 'B',
          'last_observed_at': '2026-10-02T00:00:00Z',
          'observations': [
            {'id': 'o3', 'note': 'z', 'observed_at': '2026-10-02T00:00:00Z'},
          ],
        },
      ],
      'observation_count': 3,
    });

    test('話し方と今の状況に分かれる', () {
      final m = sample();
      expect(m.styles.map((e) => e.id), ['m1']);
      expect(m.situations.map((e) => e.id), ['m2']);
    });

    test('メモを消すと件数が減り、空になった会話は消える', () {
      final m = sample().withoutObservation('o3');
      expect(m.observationCount, 2);
      expect(m.observationGroups.map((g) => g.threadId), ['t1']);
      final m2 = sample().withoutObservation('o1');
      expect(m2.observationGroups.first.observations.map((o) => o.id), ['o2']);
    });

    test('覚え書きを消す・メモを全部忘れる', () {
      expect(sample().withoutMemo('m1').memos.map((e) => e.id), ['m2']);
      final cleared = sample().withoutObservations();
      expect(cleared.observationCount, 0);
      expect(cleared.observationGroups, isEmpty);
      // 覚え書きは残る
      expect(cleared.memos.length, 2);
    });
  });
}
