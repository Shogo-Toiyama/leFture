import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/announcement/announcement_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';

import 'all_announcements_sheet.dart';

// アナウンスメントが1件も無いときにランダムで表示する言葉たち。
const List<String> _kEmptyAnnouncementMessages = [
  'Keep exploring the universe!',
  'Every star started as stardust. Keep going.',
  'Your galaxy is quiet for now — the next lecture will light it up.',
  'No news is good news. Time to learn something new?',
  'The universe is patient. So can you be.',
];

class AnnouncementBar extends HookConsumerWidget {
  const AnnouncementBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final announcement = ref.watch(latestAnnouncementProvider).asData?.value;

    // 空状態メッセージは、この画面がビルドされた（マウントされた）タイミングで1回だけランダムに選ぶ。
    final emptyMessage = useMemoized(
      () =>
          _kEmptyAnnouncementMessages[Random().nextInt(
            _kEmptyAnnouncementMessages.length,
          )],
    );

    final icon = announcement != null
        ? iconForAnnouncementType(announcement.type)
        : Icons.star;
    final title = announcement?.title?.trim();
    final description = announcement?.description?.trim();

    final String text;
    if (announcement != null) {
      if (title != null && title.isNotEmpty) {
        if (description != null && description.isNotEmpty) {
          text = '$title : $description';
        } else {
          text = title;
        }
      } else if (description != null && description.isNotEmpty) {
        text = description;
      } else {
        text = emptyMessage;
      }
    } else {
      text = emptyMessage;
    }

    return GestureDetector(
      // タップで全アナウンス一覧シートを開く
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AllAnnouncementsSheet(),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // グラスモーフィズム
          color: AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.universe.glassBorder),
        ),
        child: Row(
          children: [
            // アイコン
            Icon(icon, color: AppColors.starGold, size: 20),
            const SizedBox(width: 12),
            // テキスト
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 矢印
            Icon(
              Icons.arrow_forward_ios,
              color: AppColors.universe.textComet,
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}
