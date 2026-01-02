class LectureFolder {
  final String id;
  final String ownerId;
  final String name;
  final String? parentId;
  final String type;
  final String? icon;
  final String? color;
  final bool isFavorite;
  final bool isDeleted;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  LectureFolder({
    required this.id,
    required this.ownerId,
    required this.name,
    this.parentId,
    required this.type,
    this.icon,
    this.color,
    required this.isFavorite,
    required this.isDeleted,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  LectureFolder copyWith({
    String? name,
    String? parentId,
    String? type,
    String? icon,
    String? color,
    bool? isFavorite,
    bool? isDeleted,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LectureFolder(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isFavorite: isFavorite ?? this.isFavorite,
      isDeleted: isDeleted ?? this.isDeleted,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }


  factory LectureFolder.fromMap(Map<String, dynamic> map) {
    return LectureFolder(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: (map['name'] as String?) ?? '',
      parentId: map['parent_id'] as String?,
      type: (map['type'] as String?) ?? 'binder',
      icon: map['icon'] as String?,
      color: map['color'] as String?,
      isFavorite: (map['is_favorite'] as bool?) ?? false,
      isDeleted: (map['is_deleted'] as bool?) ?? false,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'name': name,
      'parent_id': parentId,
      'type': type,
      'icon': icon,
      'color': color,
      'is_favorite': isFavorite,
      'is_deleted': isDeleted,
      'sort_order': sortOrder,
    };
  }
}