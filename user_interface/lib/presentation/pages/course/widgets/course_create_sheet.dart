import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/course/course_list_provider.dart';
import 'package:lecture_companion_ui/domain/entities/course.dart';
import 'package:lecture_companion_ui/domain/entities/course_attribute.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_attribute_repository_supabase.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

/// コース作成ボトムシート。成功時に作成した [Course] を返す。
class CourseCreateSheet extends HookConsumerWidget {
  const CourseCreateSheet({
    super.key,
    this.preselectedYearName,
    this.preselectedTermName,
  });

  /// 親フォルダから自動入力（例: "2026 / Fall" 配下で作成する場合）
  final String? preselectedYearName;
  final String? preselectedTermName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleCtl = useTextEditingController();
    final yearCtl = useTextEditingController(text: preselectedYearName ?? '');
    final termCtl = useTextEditingController(text: preselectedTermName ?? '');
    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    final yearsAsync = ref.watch(yearAttributesProvider);
    final termsAsync = ref.watch(termAttributesProvider);

    final existingYears = yearsAsync.asData?.value ?? [];
    final existingTerms = termsAsync.asData?.value ?? [];

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

        CourseAttribute? year;
        CourseAttribute? term;

        final yearName = yearCtl.text.trim();
        final termName = termCtl.text.trim();

        if (yearName.isNotEmpty) {
          year = await attrRepo.getOrCreate(
            attributeType: 'year',
            attributeName: yearName,
          );
        }
        if (termName.isNotEmpty) {
          term = await attrRepo.getOrCreate(
            attributeType: 'term',
            attributeName: termName,
          );
        }

        final course = await courseRepo.createCourse(
          courseTitle: title,
          yearId: year?.id,
          termId: term?.id,
        );

        // courseListProvider を再フェッチ
        ref.invalidate(courseListProvider);
        ref.invalidate(yearAttributesProvider);
        ref.invalidate(termAttributesProvider);

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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1C2E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
        ),
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

            Text(
              'New Course',
              style: TextStyle(
                color: AppColors.universe.textStarlight,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
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

            if (errorMsg.value != null) ...[
              const SizedBox(height: 12),
              Text(
                errorMsg.value!,
                style: const TextStyle(color: AppColors.correctionRed, fontSize: 13),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSubmitting.value ? null : submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.starGold,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.universe.glassWhiteLow,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSubmitting.value
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Create Course',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
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
              constraints: const BoxConstraints(maxHeight: 180),
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      style: TextStyle(color: AppColors.universe.textStarlight),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: AppColors.universe.textComet),
        hintStyle: TextStyle(color: AppColors.universe.textComet.withValues(alpha: 0.5)),
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
