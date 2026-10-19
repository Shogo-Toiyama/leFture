// lib/domain/entities/self_portrait.dart

// 自分像プロフィール(ロードマップ9章)と、AIのメモの値。webappの lib/selfPortrait.ts と同じ形。
// 日時はサーバーが返したISO文字列のまま持ち、表示のときに shortDate で整える。

/// 表紙(いまのわたし)の3つの欄。値はバックエンドの列名と同じ。
enum CoverField {
  bio('bio'),
  interests('interests'),
  futureGoals('future_goals');

  const CoverField(this.wire);

  final String wire;

  static CoverField? fromWire(String? value) {
    for (final f in values) {
      if (f.wire == value) return f;
    }
    return null;
  }
}

String? _str(Object? v) => v is String ? v : null;

class CoverValue {
  const CoverValue({this.text, this.writtenBy});

  final String? text;

  /// 'ai' | 'user' | null
  final String? writtenBy;

  bool get writtenByAi => writtenBy == 'ai';

  factory CoverValue.fromMap(Map<String, dynamic> m) =>
      CoverValue(text: _str(m['text']), writtenBy: _str(m['written_by']));
}

class CoverProposal {
  const CoverProposal({
    required this.id,
    required this.field,
    required this.proposedText,
    required this.createdAt,
  });

  final String id;
  final CoverField field;
  final String proposedText;
  final String createdAt;

  static CoverProposal? tryFromMap(Map<String, dynamic> m) {
    final field = CoverField.fromWire(_str(m['field']));
    final id = _str(m['id']);
    if (field == null || id == null) return null;
    return CoverProposal(
      id: id,
      field: field,
      proposedText: _str(m['proposed_text']) ?? '',
      createdAt: _str(m['created_at']) ?? '',
    );
  }
}

class ProfileCategory {
  const ProfileCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    this.parentId,
  });

  final String id;
  final String name;
  final String description;

  /// 'trait' | 'record'
  final String kind;
  final String? parentId;

  factory ProfileCategory.fromMap(Map<String, dynamic> m) => ProfileCategory(
    id: m['id'] as String,
    name: _str(m['name']) ?? '',
    description: _str(m['description']) ?? '',
    kind: _str(m['kind']) ?? 'trait',
    parentId: _str(m['parent_id']),
  );
}

class ProfileItem {
  const ProfileItem({
    required this.id,
    required this.kind,
    required this.content,
    required this.origin,
    required this.status,
    required this.sensitive,
    required this.isNew,
    required this.changedAt,
    required this.evidenceThreads,
    this.categoryId,
    this.firstSeenAt,
    this.lastSeenAt,
    this.occurredAt,
  });

  final String id;
  final String? categoryId;

  /// 'trait' | 'record'
  final String kind;
  final String content;

  /// 'ai' | 'user'
  final String origin;

  /// 'active' | 'pending_confirm'
  final String status;
  final String sensitive;
  final String? firstSeenAt;
  final String? lastSeenAt;
  final String? occurredAt;
  final bool isNew;

  /// 作られた日か、最後に書き直された日の新しいほう
  final String changedAt;
  final int evidenceThreads;

  bool get isPending => status == 'pending_confirm';
  bool get isActive => status == 'active';

  factory ProfileItem.fromMap(Map<String, dynamic> m) => ProfileItem(
    id: m['id'] as String,
    categoryId: _str(m['category_id']),
    kind: _str(m['kind']) ?? 'trait',
    content: _str(m['content']) ?? '',
    origin: _str(m['origin']) ?? 'ai',
    status: _str(m['status']) ?? 'active',
    sensitive: _str(m['sensitive']) ?? 'none',
    firstSeenAt: _str(m['first_seen_at']),
    lastSeenAt: _str(m['last_seen_at']),
    occurredAt: _str(m['occurred_at']),
    isNew: m['is_new'] == true,
    changedAt: _str(m['changed_at']) ?? '',
    evidenceThreads: (m['evidence_threads'] as num?)?.toInt() ?? 0,
  );
}

class RecentItem {
  const RecentItem({required this.itemId, required this.topics, this.quote});

  final String itemId;

  /// 別々の会話から来た話題(2つ以上のときだけ入る)
  final List<String> topics;
  final String? quote;

  factory RecentItem.fromMap(Map<String, dynamic> m) => RecentItem(
    itemId: m['item_id'] as String,
    topics: [
      for (final t in (m['topics'] as List? ?? const []))
        if (t is String) t,
    ],
    quote: _str(m['quote']),
  );
}

class SelfPortrait {
  const SelfPortrait({
    required this.cover,
    required this.proposals,
    required this.categories,
    required this.items,
    required this.recent,
  });

  final Map<CoverField, CoverValue> cover;
  final List<CoverProposal> proposals;
  final List<ProfileCategory> categories;
  final List<ProfileItem> items;
  final List<RecentItem> recent;

  List<ProfileItem> get pending => [
    for (final i in items)
      if (i.isPending) i,
  ];

  List<ProfileItem> get active => [
    for (final i in items)
      if (i.isActive) i,
  ];

  factory SelfPortrait.fromMap(Map<String, dynamic> m) {
    final coverRaw = Map<String, dynamic>.from(m['cover'] as Map? ?? const {});
    return SelfPortrait(
      cover: {
        for (final f in CoverField.values)
          f: coverRaw[f.wire] is Map
              ? CoverValue.fromMap(
                  Map<String, dynamic>.from(coverRaw[f.wire] as Map),
                )
              : const CoverValue(),
      },
      proposals: [
        for (final p in (m['proposals'] as List? ?? const []))
          ?CoverProposal.tryFromMap(Map<String, dynamic>.from(p as Map)),
      ],
      categories: [
        for (final c in (m['categories'] as List? ?? const []))
          ProfileCategory.fromMap(Map<String, dynamic>.from(c as Map)),
      ],
      items: [
        for (final i in (m['items'] as List? ?? const []))
          ProfileItem.fromMap(Map<String, dynamic>.from(i as Map)),
      ],
      recent: [
        for (final r in (m['recent'] as List? ?? const []))
          RecentItem.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
    );
  }
}

class ItemEvidence {
  const ItemEvidence({
    required this.observationId,
    required this.threadId,
    required this.threadTitle,
    required this.note,
    required this.observedAt,
    this.quote,
  });

  final String observationId;
  final String threadId;
  final String threadTitle;
  final String note;
  final String? quote;
  final String observedAt;

  factory ItemEvidence.fromMap(Map<String, dynamic> m) => ItemEvidence(
    observationId: m['observation_id'] as String,
    threadId: m['thread_id'] as String,
    threadTitle: _str(m['thread_title']) ?? '',
    note: _str(m['note']) ?? '',
    quote: _str(m['quote']),
    observedAt: _str(m['observed_at']) ?? '',
  );
}

class ItemVersion {
  const ItemVersion({required this.content, required this.replacedAt});

  final String content;
  final String replacedAt;

  factory ItemVersion.fromMap(Map<String, dynamic> m) => ItemVersion(
    content: _str(m['content']) ?? '',
    replacedAt: _str(m['replaced_at']) ?? '',
  );
}

class ItemDetail {
  const ItemDetail({
    required this.content,
    required this.origin,
    required this.evidence,
    required this.versions,
  });

  final String content;

  /// 'ai' | 'user'
  final String origin;
  final List<ItemEvidence> evidence;
  final List<ItemVersion> versions;

  bool get editedByUser => origin == 'user';

  factory ItemDetail.fromMap(Map<String, dynamic> m) {
    final item = Map<String, dynamic>.from(m['item'] as Map? ?? const {});
    return ItemDetail(
      content: _str(item['content']) ?? '',
      origin: _str(item['origin']) ?? 'ai',
      evidence: [
        for (final e in (m['evidence'] as List? ?? const []))
          ItemEvidence.fromMap(Map<String, dynamic>.from(e as Map)),
      ],
      versions: [
        for (final v in (m['versions'] as List? ?? const []))
          ItemVersion.fromMap(Map<String, dynamic>.from(v as Map)),
      ],
    );
  }
}

/// AIの覚え書き。話し方('answer_style')と今の状況('situation')の2種類。
class AiMemo {
  const AiMemo({
    required this.id,
    required this.kind,
    required this.content,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;

  /// 'answer_style' | 'situation'
  final String kind;
  final String content;
  final String? expiresAt;
  final String createdAt;

  bool get isStyle => kind == 'answer_style';

  factory AiMemo.fromMap(Map<String, dynamic> m) => AiMemo(
    id: m['id'] as String,
    kind: _str(m['kind']) ?? 'answer_style',
    content: _str(m['content']) ?? '',
    expiresAt: _str(m['expires_at']),
    createdAt: _str(m['created_at']) ?? '',
  );
}

class Observation {
  const Observation({
    required this.id,
    required this.note,
    required this.observedAt,
  });

  final String id;
  final String note;
  final String observedAt;

  factory Observation.fromMap(Map<String, dynamic> m) => Observation(
    id: m['id'] as String,
    note: _str(m['note']) ?? '',
    observedAt: _str(m['observed_at']) ?? '',
  );
}

class ObservationGroup {
  const ObservationGroup({
    required this.threadId,
    required this.threadTitle,
    required this.lastObservedAt,
    required this.observations,
  });

  final String threadId;
  final String threadTitle;
  final String lastObservedAt;
  final List<Observation> observations;

  ObservationGroup withoutObservation(String id) => ObservationGroup(
    threadId: threadId,
    threadTitle: threadTitle,
    lastObservedAt: lastObservedAt,
    observations: [
      for (final o in observations)
        if (o.id != id) o,
    ],
  );

  factory ObservationGroup.fromMap(Map<String, dynamic> m) => ObservationGroup(
    threadId: m['thread_id'] as String,
    threadTitle: _str(m['thread_title']) ?? '',
    lastObservedAt: _str(m['last_observed_at']) ?? '',
    observations: [
      for (final o in (m['observations'] as List? ?? const []))
        Observation.fromMap(Map<String, dynamic>.from(o as Map)),
    ],
  );
}

class AiMemory {
  const AiMemory({
    required this.memos,
    required this.observationGroups,
    required this.observationCount,
  });

  final List<AiMemo> memos;
  final List<ObservationGroup> observationGroups;
  final int observationCount;

  List<AiMemo> get styles => [
    for (final m in memos)
      if (m.isStyle) m,
  ];

  List<AiMemo> get situations => [
    for (final m in memos)
      if (!m.isStyle) m,
  ];

  AiMemory withoutMemo(String id) => AiMemory(
    memos: [
      for (final m in memos)
        if (m.id != id) m,
    ],
    observationGroups: observationGroups,
    observationCount: observationCount,
  );

  AiMemory withoutObservation(String id) => AiMemory(
    memos: memos,
    observationGroups: [
      for (final g in observationGroups)
        if (g.withoutObservation(id).observations.isNotEmpty)
          g.withoutObservation(id),
    ],
    observationCount: observationCount - 1,
  );

  AiMemory withoutObservations() => AiMemory(
    memos: memos,
    observationGroups: const [],
    observationCount: 0,
  );

  factory AiMemory.fromMap(Map<String, dynamic> m) => AiMemory(
    memos: [
      for (final x in (m['memos'] as List? ?? const []))
        AiMemo.fromMap(Map<String, dynamic>.from(x as Map)),
    ],
    observationGroups: [
      for (final g in (m['observation_groups'] as List? ?? const []))
        ObservationGroup.fromMap(Map<String, dynamic>.from(g as Map)),
    ],
    observationCount: (m['observation_count'] as num?)?.toInt() ?? 0,
  );
}
