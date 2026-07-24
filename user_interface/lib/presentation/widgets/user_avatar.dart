import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/domain/entities/user_profile.dart';

class UserAvatar extends ConsumerWidget {
  const UserAvatar({
    super.key,
    required this.profile,
    this.size = 72,
  });

  final UserProfile? profile;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = profile?.avatarUrl?.trim();
    final displayName = profile?.username ?? 'Explorer';

    final initials = displayName.trim().isEmpty
        ? 'EX'
        : displayName
            .trim()
            .split(' ')
            .where((e) => e.isNotEmpty)
            .map((e) => e[0].toUpperCase())
            .take(2)
            .join('');

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF7C83FD), Color(0xFFFFB300)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: size * 0.33,
            ),
          ),
        ),
      );
    }

    if (avatarUrl == null || avatarUrl.isEmpty) {
      return fallbackAvatar();
    }

    // Direct HTTP/HTTPS URL (e.g. Google OAuth Avatar)
    if (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          avatarUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallbackAvatar(),
        ),
      );
    }

    // R2 storage path (e.g. "uid/avatar.jpg") -> Fetch & Cache via artifactFileProvider
    final fileAsync = ref.watch(artifactFileProvider(avatarUrl));

    return fileAsync.when(
      data: (file) {
        if (!file.existsSync() || file.lengthSync() == 0) {
          return fallbackAvatar();
        }
        return Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallbackAvatar(),
          ),
        );
      },
      loading: () => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        ),
      ),
      error: (error, stackTrace) => fallbackAvatar(),
    );
  }
}
