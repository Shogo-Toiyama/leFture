class AppTransmission {
  final String id;
  final String? category;
  final String title;
  final String content;
  final String? imagePath;
  final String? actionLabel;
  final String? actionUrl;
  final int priority;
  final DateTime publishedAt;

  const AppTransmission({
    required this.id,
    this.category,
    required this.title,
    required this.content,
    this.imagePath,
    this.actionLabel,
    this.actionUrl,
    required this.priority,
    required this.publishedAt,
  });

  factory AppTransmission.fromMap(Map<String, dynamic> map) {
    final rawCategory = map['category'] as String?;
    return AppTransmission(
      id: map['id'] as String,
      category: (rawCategory != null && rawCategory.trim().isNotEmpty)
          ? rawCategory.trim()
          : null,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      imagePath: map['image_path'] as String?,
      actionLabel: map['action_label'] as String?,
      actionUrl: map['action_url'] as String?,
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      publishedAt: map['published_at'] != null
          ? DateTime.parse(map['published_at'] as String).toLocal()
          : DateTime.now(),
    );
  }

  /// R2などの完全な画像URLを取得（相対パスの場合はベースURLと補完）
  String? get resolvedImageUrl {
    if (imagePath == null || imagePath!.trim().isEmpty) return null;
    final path = imagePath!.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    // R2 または Supabase Storage などの構成に応じたベースURLプレフィックス
    const r2BaseUrl = String.fromEnvironment(
      'R2_PUBLIC_BASE_URL',
      defaultValue: 'https://pub-r2.orbit-app.com', // 既定プレフィックス
    );
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$r2BaseUrl/$cleanPath';
  }
}
