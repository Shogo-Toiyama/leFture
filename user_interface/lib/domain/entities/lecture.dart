// lib/domain/entities/lecture.dart
class Lecture {
  final String id;
  final String ownerId;

  /// 録音開始直後は未分類でも良い設計にしたいなら nullable にする
  final String? folderId;

  /// タイトル未入力でも開始できるなら nullable or '' でOK
  final String? title;

  final bool isDeleted;

  /// DB側で採番するなら nullable か、0 を許容して trigger に任せる
  final int sortOrder;

  final DateTime lectureDatetime;
  final DateTime createdAt;
  final DateTime updatedAt;

  Lecture({
    required this.id,
    required this.ownerId,
    required this.folderId,
    required this.title,
    required this.isDeleted,
    required this.sortOrder,
    required this.lectureDatetime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lecture.fromMap(Map<String, dynamic> map) {
    return Lecture(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      folderId: map['folder_id'] as String?,
      title: map['title'] as String?,
      isDeleted: (map['is_deleted'] as bool?) ?? false,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      lectureDatetime: DateTime.parse(map['lecture_datetime'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// insert, upsert 用
  /// DBに任せたいものは “送らない” のが一番安全
  Map<String, dynamic> toUpsertMap() {
    final m = <String, dynamic>{
      'id': id,
      'owner_id': ownerId,
      'is_deleted': isDeleted,
      'lecture_datetime': lectureDatetime.toIso8601String(),
      'title': title,
    };

    if (folderId != null) {
      m['folder_id'] = folderId;
    }

    // sort_order はDBで決めるなら送らない
    // m['sort_order'] = sortOrder;

    return m;
  }
}
