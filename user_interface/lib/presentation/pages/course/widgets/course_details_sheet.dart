import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// コースの詳細情報 (コード/教授/学校/科目/年度・学期/概要) を一覧表示するボトムシート。
class CourseDetailsSheet extends StatelessWidget {
  const CourseDetailsSheet({super.key, required this.course});

  final Course course;

  static final _dateFmt = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      if (course.courseCode?.trim().isNotEmpty == true)
        (Icons.tag, 'Course Code', course.courseCode!.trim()),
      if (course.professor != null)
        (Icons.person_outline, 'Professor', course.professor!.attributeName),
      if (course.school != null)
        (Icons.account_balance_outlined, 'School', course.school!.attributeName),
      if (course.subject != null)
        (Icons.category_outlined, 'Subject', course.subject!.attributeName),
      if (course.year != null || course.term != null)
        (
          Icons.calendar_today_outlined,
          'Term',
          [course.term?.attributeName, course.year?.attributeName]
              .whereType<String>()
              .join(' '),
        ),
      (Icons.schedule, 'Created', _dateFmt.format(course.createdAt.toLocal())),
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
              'Summary',
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
