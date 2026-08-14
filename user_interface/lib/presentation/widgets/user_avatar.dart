import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/lecture/lecture_providers.dart';
import 'package:lefture/domain/entities/avatar_preset_helper.dart';
import 'package:lefture/domain/entities/user_profile.dart';
import 'package:lefture/presentation/pages/profile/widgets/change_avatar_sheet.dart';

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

    final parsed = profile?.parsedAvatar ?? AvatarPresetHelper.parse(avatarUrl);

    if (parsed.type == ParsedAvatarType.preset) {
      final bgStyle = parsed.bgStyleIndex ?? 0;
      final bgIndex = parsed.bgIndex ?? 0;
      final gradients = bgStyle == 0
          ? kVividGradients
          : (bgStyle == 1 ? kPastelGradients : kDarkGradients);
      final gradient = gradients[bgIndex % gradients.length];
      final isPastel = bgStyle == 1;
      final initialsTextColor = isPastel
          ? kPastelTextColors[bgIndex % kPastelTextColors.length]
          : Colors.white;

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
        ),
        child: (parsed.iconAsset == null || parsed.iconAsset == 'initials')
            ? Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: initialsTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: size * 0.33,
                    shadows: isPastel
                        ? [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              )
            : Padding(
                padding: EdgeInsets.all(size * 0.10),
                child: Image.asset(
                  parsed.iconAsset!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => fallbackAvatar(),
                ),
              ),
      );
    }

    // Direct HTTP/HTTPS URL (e.g. Google OAuth Avatar)
    if (parsed.type == ParsedAvatarType.network && parsed.url != null) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          parsed.url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallbackAvatar(),
        ),
      );
    }

    // R2 storage path (e.g. "uid/avatar.jpg") -> Fetch & Cache via artifactFileProvider
    final storagePath = parsed.url ?? avatarUrl;
    if (storagePath == null || storagePath.isEmpty) return fallbackAvatar();

    final fileAsync = ref.watch(artifactFileProvider(storagePath));

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
