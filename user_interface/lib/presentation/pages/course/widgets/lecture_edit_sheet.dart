import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/lecture.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/custom_dialog.dart';
import 'package:intl/intl.dart';


class LectureEditSheet extends HookConsumerWidget {
  const LectureEditSheet({
    super.key,
    required this.lecture,
  });

  final Lecture lecture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleCtl = useTextEditingController(
      text: lecture.title ?? '',
    );
    final selectedCourseId = useState<String?>(lecture.courseId);
    final selectedDateTime = useState<DateTime>(lecture.lectureDatetime);
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
          title: 'Change Course?',
          message: 'Changing the course of this lecture will modify Topic Map structures and might affect synchronization. Are you sure you want to proceed?',
          confirmLabel: 'Proceed',
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
                    'Edit Lecture',
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
                        : const Text(
                            'Save',
                            style: TextStyle(
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
                'Course',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.universe.glassWhiteLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.universe.glassBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: selectedCourseId.value,
                    dropdownColor: const Color(0xFF1E2038),
                    style: TextStyle(color: AppColors.universe.textStarlight),
                    icon: Icon(Icons.arrow_drop_down, color: AppColors.universe.textComet),
                    isExpanded: true,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'No Course (Unassigned)',
                          style: TextStyle(color: AppColors.universe.textComet),
                        ),
                      ),
                      ...courses.map((course) {
                        return DropdownMenuItem<String?>(
                          value: course.id,
                          child: Text(course.displayTitle),
                        );
                      }),
                    ],
                    onChanged: (value) => selectedCourseId.value = value,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Lecture Date & Time (DatePicker / TimePicker)
              Text(
                'Lecture Date & Time',
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
                        DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime.value),
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
                  labelText: 'Title',
                  hintText: lecture.titleGenerated?.trim().isNotEmpty == true
                      ? '${lecture.titleGenerated} (Default)'
                      : 'Untitled Lecture',
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
