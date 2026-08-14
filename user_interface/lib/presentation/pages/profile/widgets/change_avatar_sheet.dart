import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lefture/application/lecture/lecture_controller.dart';
import 'package:lefture/domain/entities/avatar_preset_helper.dart';
import 'package:lefture/domain/entities/user_profile.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';

/// プリセットの20個のクレイアバター一覧
const List<String> kPresetAvatarAssets = [
  'assets/images/avatars/clay_bear.png',
  'assets/images/avatars/clay_books.png',
  'assets/images/avatars/clay_boy.png',
  'assets/images/avatars/clay_burger.png',
  'assets/images/avatars/clay_camera.png',
  'assets/images/avatars/clay_cat.png',
  'assets/images/avatars/clay_coffee.png',
  'assets/images/avatars/clay_dog.png',
  'assets/images/avatars/clay_earth.png',
  'assets/images/avatars/clay_galaxy.png',
  'assets/images/avatars/clay_gamepad.png',
  'assets/images/avatars/clay_girl.png',
  'assets/images/avatars/clay_headphones.png',
  'assets/images/avatars/clay_owl.png',
  'assets/images/avatars/clay_palette.png',
  'assets/images/avatars/clay_penguin.png',
  'assets/images/avatars/clay_robot.png',
  'assets/images/avatars/clay_rocket.png',
  'assets/images/avatars/clay_suitcase.png',
  'assets/images/avatars/clay_unicorn.png',
];

/// 1. ビビッド (鮮やか - 12色スペクトル)
const List<LinearGradient> kVividGradients = [
  LinearGradient(colors: [Color(0xFFFF2D55), Color(0xFFFF3B30)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 1. 赤
  LinearGradient(colors: [Color(0xFFFF3B30), Color(0xFFFF9500)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 2. 赤橙
  LinearGradient(colors: [Color(0xFFFF9500), Color(0xFFFFCC00)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 3. 橙黄 (3と4を統合)
  LinearGradient(colors: [Color(0xFFFFCC00), Color(0xFFA3E635)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 4. 黄ライム
  LinearGradient(colors: [Color(0xFF84CC16), Color(0xFF34C759)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 5. ライムグリーン
  LinearGradient(colors: [Color(0xFF34C759), Color(0xFF10B981)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 6. フレッシュグリーン
  LinearGradient(colors: [Color(0xFF10B981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 7. ディープエメラルド (新追加)
  LinearGradient(colors: [Color(0xFF00C7BE), Color(0xFF30B0C7)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 8. ミ field/Teal
  LinearGradient(colors: [Color(0xFF30B0C7), Color(0xFF007AFF)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 9. シアンブルー
  LinearGradient(colors: [Color(0xFF007AFF), Color(0xFF5856D6)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 10. ブルーインディゴ
  LinearGradient(colors: [Color(0xFF5856D6), Color(0xFFAF52DE)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 11. インディゴパープル
  LinearGradient(colors: [Color(0xFFAF52DE), Color(0xFFFF2D55)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 12. パープルマゼンタ
];

/// 2. パステル (やわらか・淡い - 12色スペクトル)
const List<LinearGradient> kPastelGradients = [
  LinearGradient(colors: [Color(0xFFFFC3D0), Color(0xFFFFF0F5)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 1
  LinearGradient(colors: [Color(0xFFFFB7C5), Color(0xFFFFE4E1)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 2
  LinearGradient(colors: [Color(0xFFFFE4E1), Color(0xFFFFD8B1)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 3
  LinearGradient(colors: [Color(0xFFFFD8B1), Color(0xFFFFE5B4)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 4
  LinearGradient(colors: [Color(0xFFFFF59D), Color(0xFFFFFDE7)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 5
  LinearGradient(colors: [Color(0xFFD9F99D), Color(0xFFECFDF5)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 6
  LinearGradient(colors: [Color(0xFFA7F3D0), Color(0xFFE0F2F1)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 7
  LinearGradient(colors: [Color(0xFFE0F2F1), Color(0xFFBAE6FD)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 8
  LinearGradient(colors: [Color(0xFFBAE6FD), Color(0xFFE1F5FE)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 9
  LinearGradient(colors: [Color(0xFFC7D2FE), Color(0xFFF0F4FF)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 10
  LinearGradient(colors: [Color(0xFFDDD6FE), Color(0xFFF5F3FF)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 11
  LinearGradient(colors: [Color(0xFFFDF2F8), Color(0xFFFCE7F3)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 12 (淡く優しいパウダーピンクへ修正)
];

/// パステル各背景に対応するVivid文字色 (12色)
const List<Color> kPastelTextColors = [
  Color(0xFFE11D48), // 1. サクラ -> ビビッドローズ
  Color(0xFFE11D48), // 2. コーラル -> ビビッドローズ
  Color(0xFFEA580C), // 3. ピーチ -> ビビッドオレンジ
  Color(0xFFD97706), // 4. アプリコット -> ビビッドアンバー
  Color(0xFFCA8A04), // 5. レモン -> ビビッドゴールド
  Color(0xFF65A30D), // 6. ライムミント -> ビビッドライム
  Color(0xFF059669), // 7. ミント -> ビビッドエメラルド
  Color(0xFF0891B2), // 8. アイス -> ビビッドシアン
  Color(0xFF2563EB), // 9. スカイ -> ビビッドブルー
  Color(0xFF4F46E5), // 10. ペリウィンクル -> ビビッドインディゴ
  Color(0xFF334155), // 11. パール -> ビビッドダークスレート
  Color(0xFFDB2777), // 12. パウダーピンク -> ビビッドマゼンタ
];

/// 3. ダーク (深み・シック - 12色スペクトル)
const List<LinearGradient> kDarkGradients = [
  LinearGradient(colors: [Color(0xFF450A0A), Color(0xFF881337)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 1
  LinearGradient(colors: [Color(0xFF881337), Color(0xFF991B1B)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 2
  LinearGradient(colors: [Color(0xFF7C2D12), Color(0xFF9A3412)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 3
  LinearGradient(colors: [Color(0xFF451A03), Color(0xFF78350F)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 4
  LinearGradient(colors: [Color(0xFF3F6212), Color(0xFF65A30D)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 5
  LinearGradient(colors: [Color(0xFF022C22), Color(0xFF064E3B)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 6
  LinearGradient(colors: [Color(0xFF064E3B), Color(0xFF047857)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 7
  LinearGradient(colors: [Color(0xFF0F4C81), Color(0xFF1E3E62)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 8
  LinearGradient(colors: [Color(0xFF0B192C), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 9 (ナイトサファイア)
  LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF312E81)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 10
  LinearGradient(colors: [Color(0xFF2E1065), Color(0xFF581C87)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 11
  LinearGradient(colors: [Color(0xFF05070A), Color(0xFF141722)], begin: Alignment.topLeft, end: Alignment.bottomRight), // 12 (ディープオブシディアンブラックへ修正)
];

class ChangeAvatarSheet extends HookConsumerWidget {
  const ChangeAvatarSheet({
    super.key,
    required this.profile,
  });

  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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

    final initialParsed = useMemoized(
      () => AvatarPresetHelper.parse(profile?.avatarUrl),
      [profile?.avatarUrl],
    );

    final selectedIconIndex = useState<int>(() {
      if (initialParsed.type == ParsedAvatarType.preset) {
        if (initialParsed.iconAsset == null || initialParsed.iconAsset == 'initials') {
          return 0;
        }
        final idx = kPresetAvatarAssets.indexOf(initialParsed.iconAsset!);
        return idx >= 0 ? idx + 1 : 0;
      }
      return 0;
    }());

    final selectedBgStyleIndex = useState<int>(initialParsed.bgStyleIndex ?? 0);
    final selectedBgIndex = useState<int>(initialParsed.bgIndex ?? 0);
    final viewingBgStyleIndex = useState<int>(initialParsed.bgStyleIndex ?? 0);
    final isSaving = useState<bool>(false);

    final currentGradients = selectedBgStyleIndex.value == 0
        ? kVividGradients
        : (selectedBgStyleIndex.value == 1 ? kPastelGradients : kDarkGradients);

    final viewingGradients = viewingBgStyleIndex.value == 0
        ? kVividGradients
        : (viewingBgStyleIndex.value == 1 ? kPastelGradients : kDarkGradients);

    final selectedGradient =
        currentGradients[selectedBgIndex.value % currentGradients.length];

    final isPastel = selectedBgStyleIndex.value == 1;
    final initialsTextColor = isPastel
        ? kPastelTextColors[selectedBgIndex.value % kPastelTextColors.length]
        : Colors.white;

    final userMetadata = supabase.auth.currentUser?.userMetadata;
    final socialAvatarUrl = (userMetadata?['avatar_url'] ?? userMetadata?['picture']) as String?;

    Future<void> savePresetAvatar() async {
      isSaving.value = true;
      try {
        final serialized = AvatarPresetHelper.serialize(
          iconIndex: selectedIconIndex.value,
          bgStyleIndex: selectedBgStyleIndex.value,
          bgIndex: selectedBgIndex.value,
          presetIconAssets: kPresetAvatarAssets,
        );
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.updateProfile(avatarUrl: serialized);
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.changeAvatarSavedSuccess)),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (context.mounted) {
          AppErrorDialog.show(
            context,
            actionName: 'saving your avatar',
            rawError: e,
          );
        }
      } finally {
        isSaving.value = false;
      }
    }

    Future<void> pickAndUploadLibraryPhoto() async {
      try {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: ImageSource.gallery);
        if (pickedFile == null || pickedFile.path.isEmpty) {
          return;
        }

        isSaving.value = true;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.changeAvatarUploading)),
          );
        }

        final file = File(pickedFile.path);
        final repo = ref.read(userProfileRepositoryProvider);
        final remotePath = await repo.uploadAvatarImage(file);
        await repo.updateProfile(avatarUrl: remotePath);
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.changeAvatarSavedSuccess)),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (context.mounted) {
          AppErrorDialog.show(
            context,
            actionName: 'uploading your avatar',
            rawError: e,
          );
        }
      } finally {
        isSaving.value = false;
      }
    }

    Future<void> restoreSocialAvatar() async {
      if (socialAvatarUrl == null || socialAvatarUrl.isEmpty) return;
      isSaving.value = true;
      try {
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.updateProfile(avatarUrl: socialAvatarUrl);
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.changeAvatarSavedSuccess)),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (context.mounted) {
          AppErrorDialog.show(
            context,
            actionName: 'restoring your social avatar',
            rawError: e,
          );
        }
      } finally {
        isSaving.value = false;
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: AppColors.universe.voidBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: AppColors.universe.glassBorder),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── ドラッグハンドル ────────────────────────────────────
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.universe.glassBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── ヘッダー ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_circle_rounded,
                      color: AppColors.starGold,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    l10n.changeAvatarSheetTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (isSaving.value)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.starGold,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: savePresetAvatar,
                      child: Text(
                        l10n.changeAvatarSave,
                        style: const TextStyle(
                          color: AppColors.starGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.universe.textComet,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 上部プレビュー (現在選択中のアバター + 背景) ────────
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selectedGradient,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: selectedIconIndex.value == 0
                    ? Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: initialsTextColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 34,
                            shadows: isPastel
                                ? [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          kPresetAvatarAssets[selectedIconIndex.value - 1],
                          fit: BoxFit.contain,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ── 「ライブラリから選択」ボタン & ソーシャル復元 ────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: isSaving.value ? null : pickAndUploadLibraryPhoto,
                      icon: Icon(
                        Icons.photo_library_rounded,
                        size: 20,
                        color: AppColors.universe.textStarlight,
                      ),
                      label: Text(
                        l10n.changeAvatarSelectFromLibrary,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppColors.universe.glassBorder),
                        ),
                      ),
                    ),
                  ),
                  if (socialAvatarUrl != null && socialAvatarUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: isSaving.value ? null : restoreSocialAvatar,
                      icon: const Icon(Icons.history_rounded, size: 18, color: Colors.white70),
                      label: Text(
                        l10n.changeAvatarRestoreSocialAccount,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── メインタブ選択 (アイコン vs 背景) ───────────────────
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.universe.glassBorder),
                        ),
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          dividerHeight: 0,
                          indicator: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: AppColors.starGold.withValues(alpha: 0.2),
                            border: Border.all(color: AppColors.starGold),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: AppColors.starGold,
                          unselectedLabelColor: AppColors.universe.textComet,
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          tabs: [
                            Tab(text: l10n.changeAvatarTabIcons),
                            Tab(text: l10n.changeAvatarTabBackgrounds),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Expanded(
                      child: TabBarView(
                        children: [
                          // ── TAB 1: アイコン (全21個: イニシャル + クレイ20個) ──
                          GridView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: 21,
                            itemBuilder: (context, index) {
                              final isSelected = selectedIconIndex.value == index;
                              return GestureDetector(
                                onTap: () => selectedIconIndex.value = index,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.starGold
                                          : AppColors.universe.glassBorder,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (index == 0)
                                        // イニシャル
                                        Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: selectedGradient,
                                          ),
                                          child: Center(
                                            child: Text(
                                              initials,
                                              style: TextStyle(
                                                color: initialsTextColor,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 18,
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
                                          ),
                                        )
                                      else
                                        // クレイアバター画像
                                        Padding(
                                          padding: const EdgeInsets.all(10.0),
                                          child: Image.asset(
                                            kPresetAvatarAssets[index - 1],
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      if (isSelected)
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: AppColors.starGold,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.check_rounded,
                                              size: 14,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                          // ── TAB 2: 背景 (3サブスタイル切り替え + 12色スペクトル) ──
                          Column(
                            children: [
                              // ── サブスタイル切り替えチップ (Vivid / Pastel / Dark) ──
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _SubStyleChip(
                                        label: l10n.changeAvatarBgStyleVivid,
                                        isSelected: viewingBgStyleIndex.value == 0,
                                        onTap: () => viewingBgStyleIndex.value = 0,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _SubStyleChip(
                                        label: l10n.changeAvatarBgStylePastel,
                                        isSelected: viewingBgStyleIndex.value == 1,
                                        onTap: () => viewingBgStyleIndex.value = 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _SubStyleChip(
                                        label: l10n.changeAvatarBgStyleDark,
                                        isSelected: viewingBgStyleIndex.value == 2,
                                        onTap: () => viewingBgStyleIndex.value = 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // ── 12色グラデーション Grid ──
                              Expanded(
                                child: GridView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 4,
                                  ),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 16,
                                    crossAxisSpacing: 16,
                                    childAspectRatio: 1.2,
                                  ),
                                  itemCount: viewingGradients.length,
                                  itemBuilder: (context, index) {
                                    final gradient = viewingGradients[index];
                                    final isSelected =
                                        viewingBgStyleIndex.value == selectedBgStyleIndex.value &&
                                            selectedBgIndex.value == index;

                                    return GestureDetector(
                                      onTap: () {
                                        selectedBgStyleIndex.value = viewingBgStyleIndex.value;
                                        selectedBgIndex.value = index;
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: gradient,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.starGold
                                                : Colors.transparent,
                                            width: isSelected ? 2.5 : 0,
                                          ),
                                          boxShadow: [
                                            if (isSelected)
                                              BoxShadow(
                                                color: AppColors.starGold
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 8,
                                              ),
                                          ],
                                        ),
                                        child: isSelected
                                            ? Center(
                                                child: Container(
                                                  padding: const EdgeInsets.all(5),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.starGold,
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.35),
                                                        blurRadius: 6,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: const ThickCheckIcon(
                                                    color: Colors.white,
                                                    size: 14,
                                                    strokeWidth: 3.0,
                                                  ),
                                                ),
                                              )
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// サブスタイル切り替えチップ Widget
class _SubStyleChip extends StatelessWidget {
  const _SubStyleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.starGold.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.starGold : AppColors.universe.glassBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.starGold : AppColors.universe.textComet,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 太さを自由に調整可能なチェックマーク Widget
class ThickCheckIcon extends StatelessWidget {
  const ThickCheckIcon({
    super.key,
    this.color = Colors.white,
    this.size = 14,
    this.strokeWidth = 3.0,
  });

  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ThickCheckPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _ThickCheckPainter extends CustomPainter {
  _ThickCheckPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.74)
      ..lineTo(size.width * 0.82, size.height * 0.24);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ThickCheckPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

