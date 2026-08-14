import 'avatar_preset_helper.dart';

class UserProfile {
  const UserProfile({
    required this.id,
    this.username,
    this.avatarUrl,
    this.bio,
    this.interests,
    this.futureGoals,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final String? interests;
  final String? futureGoals;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  ParsedAvatar get parsedAvatar => AvatarPresetHelper.parse(avatarUrl);

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: map['username'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      bio: map['bio'] as String?,
      interests: map['interests'] as String?,
      futureGoals: map['future_goals'] as String?,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse((map['updated_at'] ?? map['created_at']) as String),
    );
  }
}
