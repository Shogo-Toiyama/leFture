import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lecture_companion_ui/presentation/pages/recording/widgets/course_picker_sheet.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:intl/intl.dart';
import 'package:lecture_companion_ui/l10n/generated/app_localizations.dart';


class LectureEditSheet extends HookConsumerWidget {
  const LectureEditSheet({
    super.key,
    required this.lecture,
  });

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final titleCtl = useTextEditingController(
      text: lecture.title ?? '',
    );
    final selectedCourseId = useState<String?>(lecture.courseId);
    final selectedDateTime = useState<DateTime>(lecture.lectureDatetime.toLocal());
    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    final coursesAsync = ref.watch(courseListProvider);
    final courses = coursesAsync.asData?.value ?? const <Course>[];

    Future<void> submit() async {
      final title = titleCtl.text.trim();
      final courseId = selectedCourseId.value;

      if (courseId != lecture.courseId) {
        // 所属コースの変更を警告する
        final confirm = await showCustomDialog(
          context: context,
          title: l10n.lectureEditSheetChangeCourseDialogTitle,
          message: l10n.lectureEditSheetChangeCourseDialogMessage,
          confirmLabel: l10n.lectureEditSheetProceedButton,
          icon: Icons.swap_horiz,
        );
        if (confirm != true) return;
      }

      isSubmitting.value = true;
      errorMsg.value = null;

      try {
        await ref.read(lectureControllerProvider.notifier).updateLecture(
              lectureId: lecture.id,
              title: title.isEmpty ? null : title,
              courseId: courseId,
              previousCourseId: lecture.courseId,
              lectureDatetime: selectedDateTime.value,
            );
        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        errorMsg.value = e.toString();
      } finally {
        isSubmitting.value = false;
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(color: AppColors.universe.glassBorder),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
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

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.lectureEditSheetTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: isSubmitting.value ? null : submit,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.starGold,
                      disabledForegroundColor: AppColors.universe.textComet.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: isSubmitting.value
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.starGold,
                            ),
                          )
                        : Text(
                            l10n.courseSheetSaveButton,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 1. Course Selection Dropdown
              Text(
                l10n.lectureEditSheetCourseLabel,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final result = await showModalBottomSheet<CoursePickerResult>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => CoursePickerSheet(
                      initialSelectedCourseId: selectedCourseId.value,
                    ),
                  );
                  if (result != null && result.confirmed) {
                    selectedCourseId.value = result.courseId;
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final currentId = selectedCourseId.value;
                            if (currentId == null) {
                              return Text(
                                l10n.lectureEditSheetNoCourseLabel,
                                style: TextStyle(color: AppColors.universe.textComet),
                              );
                            }
                            final selectedCourse = courses.firstWhere(
                              (c) => c.id == currentId,
                              orElse: () => Course(
                                id: currentId,
                                userId: '',
                                courseTitle: l10n.lectureEditSheetUnknownCourseFallback,
                                metadata: const {
                                  'color': '#E5A93B',
                                  'icon': 'school',
                                },
                                createdAt: DateTime.now(),
                                updatedAt: DateTime.now(),
                              ),
                            );
                            return Row(
                              children: [
                                Icon(
                                  CourseStyleHelper.getIcon(selectedCourse.icon),
                                  color: CourseStyleHelper.hexToColor(selectedCourse.color, fallback: AppColors.starGold),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    selectedCourse.displayTitle,
                                    style: TextStyle(color: AppColors.universe.textStarlight),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: AppColors.universe.textComet),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Lecture Date & Time (DatePicker / TimePicker)
              Text(
                l10n.lectureEditSheetDateTimeLabel,
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // TODO: 将来的にはかっこいいカスタムカレンダーUIに置き換える
              GestureDetector(
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: selectedDateTime.value,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (pickedDate == null) return;
                  if (!context.mounted) return;
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDateTime.value),
                  );
                  if (pickedTime == null) return;
                  selectedDateTime.value = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.universe.glassBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat.yMMMd(l10n.localeName).add_jm().format(selectedDateTime.value),
                        style: TextStyle(color: AppColors.universe.textStarlight),
                      ),
                      Icon(Icons.calendar_today, color: AppColors.universe.textComet, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. Title Field
              TextField(
                controller: titleCtl,
                style: TextStyle(color: AppColors.universe.textStarlight),
                decoration: InputDecoration(
                  labelText: l10n.lectureEditSheetTitleFieldLabel,
                  hintText: lecture.titleGenerated?.trim().isNotEmpty == true
                      ? l10n.lectureEditSheetTitleFieldDefaultSuffix(lecture.titleGenerated!)
                      : l10n.lectureViewerUntitledLecture,
                  labelStyle: TextStyle(color: AppColors.universe.textComet),
                  hintStyle: TextStyle(
                    color: AppColors.universe.textComet.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Icon(Icons.title, color: AppColors.universe.textComet),
                  filled: true,
                  fillColor: AppColors.universe.glassWhiteLow,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.universe.glassBorder),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: AppColors.starGold),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (errorMsg.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorMsg.value!,
                  style: const TextStyle(
                    color: AppColors.correctionRed,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
