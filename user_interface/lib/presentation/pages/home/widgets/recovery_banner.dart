// lib/presentation/pages/home/widgets/recovery_banner.dart
//
// Home画面で「保存されていない録音がある」ことに気づける唯一の入口。
// 講義は普段から録音する習慣が無いユーザーが多く、終了操作を忘れる/
// アプリがキルされることは日常的に起きるため、講義一覧を偶然開かない限り
// 一生気づかれない、という事態を避けるためにHomeへ明示的に置く。
//
// 孤児が0件ならSizedBox.shrink()で何も描画しない(スクロール領域内の
// SliverToBoxAdapterとして置いているので、高さの出入りはレイアウトに
// 影響しない)。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/recording/recovery/recovery_providers.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/presentation/pages/home/widgets/recovery_list_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';

class RecoveryBanner extends ConsumerWidget {
  const RecoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orphans = ref.watch(orphanRecordingsProvider).value ?? const [];
    if (orphans.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final target = orphans.first;
    final lecture = ref.watch(recoveryLectureProvider(target.lectureId)).value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () {
          if (orphans.length == 1) {
            context.push(
              '${AppRoutes.coursesRootPath}/c/${lecture?.courseId}/v/${target.lectureId}',
            );
            return;
          }
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const RecoveryListSheet(),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.growthGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.growthGreen.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.growthGreen.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic_none_rounded, color: AppColors.growthGreen, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.recoveryBannerTitle(orphans.length),
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.recoveryBannerSubtitle,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.universe.textComet, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
