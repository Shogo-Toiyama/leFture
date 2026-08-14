import 'dart:math';

enum ParsedAvatarType {
  preset,
  network,
  r2Path,
}

class ParsedAvatar {
  const ParsedAvatar.preset({
    required this.iconAsset,
    required this.bgStyleIndex,
    required this.bgIndex,
  })  : type = ParsedAvatarType.preset,
        url = null;

  const ParsedAvatar.network(this.url)
      : type = ParsedAvatarType.network,
        iconAsset = null,
        bgStyleIndex = null,
        bgIndex = null;

  const ParsedAvatar.r2Path(this.url)
      : type = ParsedAvatarType.r2Path,
        iconAsset = null,
        bgStyleIndex = null,
        bgIndex = null;

  final ParsedAvatarType type;
  final String? url;
  final String? iconAsset;
  final int? bgStyleIndex;
  final int? bgIndex;
}

class AvatarPresetHelper {
  /// プリセットフォーマット文字列を生成
  /// 例: `preset:icon=clay_cat.png;bg_style=0;bg_index=3`
  /// 例: `preset:icon=initials;bg_style=1;bg_index=5`
  static String serialize({
    required int iconIndex, // 0=initials, 1..20=clay PNG
    required int bgStyleIndex, // 0=vivid, 1=pastel, 2=dark
    required int bgIndex, // 0..11
    List<String> presetIconAssets = const [],
  }) {
    final iconName = (iconIndex == 0 || iconIndex - 1 >= presetIconAssets.length)
        ? 'initials'
        : presetIconAssets[iconIndex - 1].split('/').last;

    return 'preset:icon=$iconName;bg_style=$bgStyleIndex;bg_index=$bgIndex';
  }

  /// メールアドレス新規登録時用のランダムプリセット文字列を生成
  /// アイコンはイニシャル、背景はランダム (vivid/pastel/dark 0..2, bg_index 0..11)
  static String generateRandomEmailDefaultPreset() {
    final random = Random();
    final bgStyle = random.nextInt(3);
    final bgIndex = random.nextInt(12);
    return 'preset:icon=initials;bg_style=$bgStyle;bg_index=$bgIndex';
  }

  /// `avatar_url` 文字列を解析
  static ParsedAvatar parse(String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.trim().isEmpty) {
      return const ParsedAvatar.preset(
        iconAsset: 'initials',
        bgStyleIndex: 0,
        bgIndex: 2,
      );
    }

    final trimmed = avatarUrl.trim();

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return ParsedAvatar.network(trimmed);
    }

    if (trimmed.startsWith('preset:')) {
      try {
        final payload = trimmed.substring(7); // remove 'preset:'
        final parts = payload.split(';');
        String? iconName;
        int bgStyle = 0;
        int bgIndex = 0;

        for (final part in parts) {
          final kv = part.split('=');
          if (kv.length != 2) continue;
          final key = kv[0].trim();
          final val = kv[1].trim();

          if (key == 'icon') {
            iconName = val;
          } else if (key == 'bg_style') {
            bgStyle = int.tryParse(val) ?? 0;
          } else if (key == 'bg_index') {
            bgIndex = int.tryParse(val) ?? 0;
          }
        }

        final iconAsset = (iconName == null || iconName == 'initials')
            ? 'initials'
            : 'assets/images/avatars/$iconName';

        return ParsedAvatar.preset(
          iconAsset: iconAsset,
          bgStyleIndex: bgStyle.clamp(0, 2),
          bgIndex: bgIndex.clamp(0, 11),
        );
      } catch (_) {
        return const ParsedAvatar.preset(
          iconAsset: 'initials',
          bgStyleIndex: 0,
          bgIndex: 0,
        );
      }
    }

    // 他の相対パス (R2 storage path)
    return ParsedAvatar.r2Path(trimmed);
  }
}
