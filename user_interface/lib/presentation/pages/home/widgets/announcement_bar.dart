import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/announcement/announcement_provider.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/announcement_type_icon.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

import 'all_announcements_sheet.dart';

// アナウンスメントが1件も無いときにランダムで表示する言葉たち。
List<String> emptyAnnouncementMessages(AppLocalizations l10n) => [
  l10n.homeEmptyAnnouncementMessage1,
  l10n.homeEmptyAnnouncementMessage2,
  l10n.homeEmptyAnnouncementMessage3,
  l10n.homeEmptyAnnouncementMessage4,
  l10n.homeEmptyAnnouncementMessage5,
];

class AnnouncementBar extends HookConsumerWidget {
  const AnnouncementBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final announcement = ref.watch(latestAnnouncementProvider).asData?.value;

    // 空状態メッセージは、この画面がビルドされた（マウントされた）タイミングで1回だけランダムに選ぶ。
    final messages = emptyAnnouncementMessages(l10n);
    final emptyMessage = useMemoized(
      () => messages[Random().nextInt(messages.length)],
      [l10n],
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
