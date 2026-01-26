import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';

class LectureTile extends StatelessWidget {
  const LectureTile({
    super.key,
    required this.lecture,
    required this.onTap,
  });

  final Lecture lecture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 日付フォーマット (例: Oct 24, 2023)
    // 端末のロケールに合わせるなら DateFormat.yMMMd(Localizations.localeOf(context).toString())
    final dateStr = DateFormat.yMMMd().format(lecture.lectureDatetime);

    return Card(
      elevation: 0,
      // 表面の色を少し変えて階層感を出す (Theme依存)
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // アイコン部分
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              
              // テキスト情報
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lecture.title ?? 'Untitled Lecture',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              
              // 右端の矢印
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}