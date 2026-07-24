import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

/// コースの詳細情報 (コード/教授/学校/科目/年度・学期/概要) を一覧表示するボトムシート。
class CourseDetailsSheet extends StatelessWidget {
  const CourseDetailsSheet({super.key, required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <(IconData, String, String)>[
      if (course.courseCode?.trim().isNotEmpty == true)
        (Icons.tag, l10n.courseCreateSheetCodeLabel, course.courseCode!.trim()),
      if (course.professor != null)
        (Icons.person_outline, l10n.courseCreateSheetProfessorLabel, course.professor!.attributeName),
      if (course.school != null)
        (Icons.account_balance_outlined, l10n.courseCreateSheetSchoolLabel, course.school!.attributeName),
      if (course.subject != null)
        (Icons.category_outlined, l10n.courseCreateSheetSubjectLabel, course.subject!.attributeName),
      if (course.year != null || course.term != null)
        (
          Icons.calendar_today_outlined,
          l10n.courseCreateSheetTermLabel,
          [course.term?.attributeName, course.year?.attributeName]
              .whereType<String>()
              .join(' '),
        ),
      (Icons.schedule, l10n.courseDetailsSheetCreatedLabel, DateFormat.yMMMd(l10n.localeName).format(course.createdAt.toLocal())),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 20),
          Text(
            course.displayTitle,
            style: TextStyle(
              color: AppColors.universe.textStarlight,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...rows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(row.$1, color: AppColors.starGold, size: 18),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: Text(
                        row.$2,
                        style: TextStyle(color: AppColors.universe.textComet, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$3,
                        style: TextStyle(
                          color: AppColors.universe.textStarlight,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          if (course.summary?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              l10n.courseCreateSheetSummaryLabel,
              style: TextStyle(
                color: AppColors.universe.textComet,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              course.summary!.trim(),
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
