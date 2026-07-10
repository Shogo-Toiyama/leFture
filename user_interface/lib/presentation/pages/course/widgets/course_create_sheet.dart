import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/course_attribute.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_attribute_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// コース作成/編集ボトムシート。成功時に作成/更新した [Course] を返す。
/// [existingCourse] を渡すと編集モードになる。
class CourseCreateSheet extends HookConsumerWidget {
  const CourseCreateSheet({
    super.key,
    this.preselectedYearName,
    this.preselectedTermName,
    this.existingCourse,
  });

  /// 親フォルダから自動入力（例: "2026 / Fall" 配下で作成する場合）
  final String? preselectedYearName;
  final String? preselectedTermName;

  /// 指定すると編集モードになり、フォームがこのコースの内容で初期化される。
  final Course? existingCourse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEditing = existingCourse != null;

    final titleCtl = useTextEditingController(
      text: existingCourse?.courseTitle ?? '',
    );
    final yearCtl = useTextEditingController(
      text: existingCourse?.year?.attributeName ?? preselectedYearName ?? '',
    );
    final termCtl = useTextEditingController(
      text: existingCourse?.term?.attributeName ?? preselectedTermName ?? '',
    );
    // More Info (アコーディオン内) の項目
    final codeCtl = useTextEditingController(
      text: existingCourse?.courseCode ?? '',
    );
    final professorCtl = useTextEditingController(
      text: existingCourse?.professor?.attributeName ?? '',
    );
    final schoolCtl = useTextEditingController(
      text: existingCourse?.school?.attributeName ?? '',
    );
    final subjectCtl = useTextEditingController(
      text: existingCourse?.subject?.attributeName ?? '',
    );
    final summaryCtl = useTextEditingController(
      text: existingCourse?.summary ?? '',
    );

    // 編集時にMore Info項目が既に入力されていれば、最初から開いておく
    final showMoreInfo = useState(
      (existingCourse?.courseCode?.isNotEmpty ?? false) ||
          existingCourse?.professor != null ||
          existingCourse?.school != null ||
          existingCourse?.subject != null ||
          (existingCourse?.summary?.isNotEmpty ?? false),
    );

    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    final existingYears = ref.watch(yearAttributesProvider).asData?.value ?? [];
    final existingTerms = ref.watch(termAttributesProvider).asData?.value ?? [];
    final existingProfessors =
        ref.watch(professorAttributesProvider).asData?.value ?? [];
    final existingSchools =
        ref.watch(schoolAttributesProvider).asData?.value ?? [];
    final existingSubjects =
        ref.watch(subjectAttributesProvider).asData?.value ?? [];

    Future<void> submit() async {
      final title = titleCtl.text.trim();
      if (title.isEmpty) {
        errorMsg.value = 'Course title is required';
        return;
      }
      isSubmitting.value = true;
      errorMsg.value = null;
      try {
        final attrRepo = ref.read(courseAttributeRepositoryProvider);
        final courseRepo = ref.read(courseRepositoryProvider);

        // 空欄でなければgetOrCreateしてIDを得る (空欄はnull=未設定)
        Future<CourseAttribute?> resolveAttr(String type, String name) async {
          final trimmed = name.trim();
          if (trimmed.isEmpty) return null;
          return attrRepo.getOrCreate(
            attributeType: type,
            attributeName: trimmed,
          );
        }

        final year = await resolveAttr('year', yearCtl.text);
        final term = await resolveAttr('term', termCtl.text);
        final professor = await resolveAttr('professor', professorCtl.text);
        final school = await resolveAttr('school', schoolCtl.text);
        final subject = await resolveAttr('subject', subjectCtl.text);

        final code = codeCtl.text.trim();
        final summary = summaryCtl.text.trim();

        final course = isEditing
            ? await courseRepo.updateCourse(
                courseId: existingCourse!.id,
                courseTitle: title,
                courseCode: code.isEmpty ? null : code,
                summary: summary.isEmpty ? null : summary,
                yearId: year?.id,
                termId: term?.id,
                professorId: professor?.id,
                schoolId: school?.id,
                subjectId: subject?.id,
              )
            : await courseRepo.createCourse(
                courseTitle: title,
                courseCode: code.isEmpty ? null : code,
                summary: summary.isEmpty ? null : summary,
                yearId: year?.id,
                termId: term?.id,
                professorId: professor?.id,
                schoolId: school?.id,
                subjectId: subject?.id,
              );

        // 関連Providerを再フェッチ
        ref.invalidate(courseListProvider);
        ref.invalidate(yearAttributesProvider);
        ref.invalidate(termAttributesProvider);
        ref.invalidate(professorAttributesProvider);
        ref.invalidate(schoolAttributesProvider);
        ref.invalidate(subjectAttributesProvider);

        if (context.mounted) {
          Navigator.of(context).pop(course);
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
                    isEditing ? 'Edit Course' : 'New Course',
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

              // Year
              _AttributeField(
                controller: yearCtl,
                label: 'Year',
                hint: 'e.g. 2026',
                icon: Icons.calendar_today_outlined,
                suggestions: existingYears.map((a) => a.attributeName).toList(),
              ),
              const SizedBox(height: 12),

              // Term
              _AttributeField(
                controller: termCtl,
                label: 'Term',
                hint: 'e.g. Fall',
                icon: Icons.bookmark_border,
                suggestions: existingTerms.map((a) => a.attributeName).toList(),
              ),
              const SizedBox(height: 12),

              // Course Title
              _GlassTextField(
                controller: titleCtl,
                label: 'Course Title *',
                hint: 'e.g. Introduction to Computer Science',
                icon: Icons.school_outlined,
              ),
              const SizedBox(height: 16),

              // More Info アコーディオン
              InkWell(
                onTap: () => showMoreInfo.value = !showMoreInfo.value,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        showMoreInfo.value
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: AppColors.universe.textComet,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'More Info',
                        style: TextStyle(
                          color: AppColors.universe.textComet,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: showMoreInfo.value
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    const SizedBox(height: 8),
                    _GlassTextField(
                      controller: codeCtl,
                      label: 'Course Code',
                      hint: 'e.g. CS101',
                      icon: Icons.tag,
                    ),
                    const SizedBox(height: 12),
                    _AttributeField(
                      controller: professorCtl,
                      label: 'Professor',
                      hint: 'e.g. Dr. Smith',
                      icon: Icons.person_outline,
                      suggestions: existingProfessors
                          .map((a) => a.attributeName)
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    _AttributeField(
                      controller: schoolCtl,
                      label: 'School',
                      hint: 'e.g. UCLA',
                      icon: Icons.account_balance_outlined,
                      suggestions: existingSchools
                          .map((a) => a.attributeName)
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    _AttributeField(
                      controller: subjectCtl,
                      label: 'Subject',
                      hint: 'e.g. Computer Science',
                      icon: Icons.category_outlined,
                      suggestions: existingSubjects
                          .map((a) => a.attributeName)
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    _GlassTextField(
                      controller: summaryCtl,
                      label: 'Summary',
                      hint: 'What is this course about?',
                      icon: Icons.notes_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),

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

/// 既存の値を候補として表示する Autocomplete 付きテキストフィールド
class _AttributeField extends StatelessWidget {
  const _AttributeField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.suggestions,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return suggestions;
        return suggestions.where((s) => s.toLowerCase().contains(query));
      },
      onSelected: (value) => controller.text = value,
      fieldViewBuilder: (context, fieldCtl, focusNode, onFieldSubmitted) {
        // Autocomplete が独自の controller を持つため同期させる
        fieldCtl.addListener(() {
          if (controller.text != fieldCtl.text) {
            controller.text = fieldCtl.text;
          }
        });
        return _GlassTextField(
          controller: fieldCtl,
          focusNode: focusNode,
          label: label,
          hint: hint,
          icon: icon,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 220),
              decoration: BoxDecoration(
                color: const Color(0xFF252740),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.universe.glassBorder),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(
                      option,
                      style: TextStyle(color: AppColors.universe.textStarlight),
                    ),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: maxLines,
      style: TextStyle(color: AppColors.universe.textStarlight),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        hintStyle: TextStyle(
          color: AppColors.universe.textComet.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(icon, color: AppColors.universe.textComet),
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
    );
  }
}
