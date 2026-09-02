import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/domain/entities/course_attribute.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_attribute_repository_supabase.dart';
import 'package:lefture/infrastructure/supabase/repositories/course_repository_supabase.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    final isEditing = existingCourse != null;

    final titleCtl = useTextEditingController(
      text: existingCourse?.courseTitle ?? '',
    );
    useListenable(titleCtl);

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

    final selectedColor = useState<Color>(
      existingCourse?.color != null
          ? CourseStyleHelper.hexToColor(existingCourse!.color)
          : AppColors.starGold,
    );
    final selectedIconName = useState<String>(existingCourse?.icon ?? 'school');
    final selectedCategoryIndex = useState<int>(0);

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
    final scrollController = useScrollController();

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
        errorMsg.value = l10n.courseCreateSheetTitleRequiredError;
        if (scrollController.hasClients) {
          scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
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

        final metadata = {
          ...?existingCourse?.metadata,
          'color': CourseStyleHelper.colorToHex(selectedColor.value),
          'icon': selectedIconName.value,
        };

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
                metadata: metadata,
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
                metadata: metadata,
              );

        if (context.mounted) {
          // ローカルDBへの反映(Pull)は呼び出し元(このシートをshowModalBottomSheetで
          // 開いた画面)の責務。ここで呼ぶと、呼び出し元によっては呼び出し元自身も
          // 同じPullを行っていて二重に走り、Pull同士が競合するおそれがあるため
          // 呼ばない([refreshCoursesAfterEdit]を参照)。
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
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 固定ヘッダー (Top Header) - スクロールしても保存ボタンが常時固定
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
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isEditing
                        ? l10n.courseCreateSheetEditTitle
                        : l10n.courseCreateSheetNewTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: isSubmitting.value ? null : submit,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.starGold,
                    disabledForegroundColor: AppColors.universe.textComet
                        .withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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

            if (errorMsg.value != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.correctionRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.correctionRed.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppColors.correctionRed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMsg.value!,
                        style: const TextStyle(
                          color: AppColors.correctionRed,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            Container(
              height: 1,
              color: AppColors.universe.glassBorder.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),

            // スクロール可能なフォームコンテンツ
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Design - Live Preview Card
                    Text(
                      l10n.courseCreateSheetDesignPreviewLabel,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selectedColor.value.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selectedColor.value.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: selectedColor.value.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: selectedColor.value.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedColor.value.withValues(
                                  alpha: 0.4,
                                ),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              CourseStyleHelper.getIcon(selectedIconName.value),
                              color: selectedColor.value,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: titleCtl,
                              maxLines: 1,
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.only(bottom: 6),
                                border: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.universe.glassBorder,
                                    width: 1.0,
                                  ),
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.universe.glassBorder
                                        .withValues(alpha: 0.6),
                                    width: 1.0,
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: selectedColor.value,
                                    width: 1.5,
                                  ),
                                ),
                                hintText: l10n
                                    .courseCreateSheetPreviewTitlePlaceholder,
                                hintStyle: TextStyle(
                                  color: AppColors.universe.textStarlight
                                      .withValues(alpha: 0.4),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.edit_outlined,
                            color: AppColors.universe.textComet,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Course Color Selector
                    Text(
                      l10n.courseCreateSheetColorLabel,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ...CourseStyleHelper.presetColors.map((color) {
                            final isSelected = selectedColor.value == color;
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: GestureDetector(
                                onTap: () => selectedColor.value = color,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.transparent,
                                      width: 2.5,
                                    ),
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 18,
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                          // If custom color is selected, show it as selected
                          if (!CourseStyleHelper.presetColors.contains(
                            selectedColor.value,
                          )) ...[
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: selectedColor.value,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: selectedColor.value.withValues(
                                        alpha: 0.5,
                                      ),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                          // Custom Color Picker Button
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () async {
                                final Color? picked = await showDialog<Color>(
                                  context: context,
                                  builder: (context) =>
                                      _CustomColorPickerDialog(
                                        initialColor: selectedColor.value,
                                      ),
                                );
                                if (picked != null) {
                                  selectedColor.value = picked;
                                }
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.universe.glassBorder,
                                    width: 1.5,
                                  ),
                                  gradient: const SweepGradient(
                                    colors: [
                                      Colors.red,
                                      Colors.yellow,
                                      Colors.green,
                                      Colors.cyan,
                                      Colors.blue,
                                      Colors.purple,
                                      Colors.red,
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.colorize,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Course Icon Selector
                    Text(
                      l10n.courseCreateSheetIconLabel,
                      style: TextStyle(
                        color: AppColors.universe.textComet,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: getCourseIconCategories(l10n).length,
                        itemBuilder: (context, index) {
                          final cat = getCourseIconCategories(l10n)[index];
                          final isSelected =
                              selectedCategoryIndex.value == index;
                          final firstIconName = cat.iconNames.isNotEmpty
                              ? cat.iconNames.first
                              : '';
                          final firstIconData =
                              CourseStyleHelper.iconMap[firstIconName] ??
                              Icons.category;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              avatar: Icon(
                                firstIconData,
                                size: 16,
                                color: isSelected
                                    ? Colors.black
                                    : AppColors.universe.textStarlight,
                              ),
                              label: Text(cat.title),
                              selected: isSelected,
                              onSelected: (val) {
                                if (val) selectedCategoryIndex.value = index;
                              },
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : AppColors.universe.textStarlight,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              selectedColor: selectedColor.value,
                              backgroundColor: AppColors.universe.glassWhiteLow,
                              checkmarkColor: Colors.black,
                              showCheckmark: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSelected
                                      ? selectedColor.value
                                      : AppColors.universe.glassBorder,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.universe.glassWhiteLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.universe.glassBorder,
                        ),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final categories = getCourseIconCategories(l10n);
                          final currentCategory =
                              categories[selectedCategoryIndex.value];
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.start,
                            children: currentCategory.iconNames.map((iconName) {
                              final isSelected =
                                  selectedIconName.value == iconName;
                              final iconData =
                                  CourseStyleHelper.iconMap[iconName] ??
                                  Icons.help;
                              return GestureDetector(
                                onTap: () => selectedIconName.value = iconName,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? selectedColor.value.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? selectedColor.value
                                          : AppColors.universe.glassBorder
                                                .withValues(alpha: 0.3),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Icon(
                                    iconData,
                                    color: isSelected
                                        ? selectedColor.value
                                        : AppColors.universe.textComet,
                                    size: 22,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    Container(
                      height: 1,
                      color: AppColors.universe.glassBorder.withValues(
                        alpha: 0.2,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Year
                    _AttributeField(
                      controller: yearCtl,
                      label: l10n.courseCreateSheetYearLabel,
                      hint: l10n.courseCreateSheetYearHint,
                      icon: Icons.calendar_today_outlined,
                      suggestions: existingYears
                          .map((a) => a.attributeName)
                          .toList(),
                    ),
                    const SizedBox(height: 12),

                    // Term
                    _AttributeField(
                      controller: termCtl,
                      label: l10n.courseCreateSheetTermLabel,
                      hint: l10n.courseCreateSheetTermHint,
                      icon: Icons.bookmark_border,
                      suggestions: existingTerms
                          .map((a) => a.attributeName)
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    // More Info アコーディオン
                    InkWell(
                      onTap: () {
                        final willExpand = !showMoreInfo.value;
                        showMoreInfo.value = willExpand;
                        if (willExpand) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (scrollController.hasClients) {
                              scrollController.animateTo(
                                scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              showMoreInfo.value
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: showMoreInfo.value
                                  ? AppColors.starGold
                                  : AppColors.universe.textComet,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.courseCreateSheetMoreInfoLabel,
                              style: TextStyle(
                                color: showMoreInfo.value
                                    ? AppColors.starGold
                                    : AppColors.universe.textComet,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 250),
                      crossFadeState: showMoreInfo.value
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(top: 8, bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: showMoreInfo.value
                              ? AppColors.starGold.withValues(alpha: 0.05)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: showMoreInfo.value
                                ? AppColors.starGold.withValues(alpha: 0.5)
                                : AppColors.universe.glassBorder,
                            width: 1.5,
                          ),
                          boxShadow: [
                            if (showMoreInfo.value)
                              BoxShadow(
                                color: AppColors.starGold.withValues(
                                  alpha: 0.15,
                                ),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _GlassTextField(
                              controller: codeCtl,
                              label: l10n.courseCreateSheetCodeLabel,
                              hint: l10n.courseCreateSheetCodeHint,
                              icon: Icons.tag,
                            ),
                            const SizedBox(height: 12),
                            _AttributeField(
                              controller: professorCtl,
                              label: l10n.courseCreateSheetProfessorLabel,
                              hint: l10n.courseCreateSheetProfessorHint,
                              icon: Icons.person_outline,
                              suggestions: existingProfessors
                                  .map((a) => a.attributeName)
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            _AttributeField(
                              controller: schoolCtl,
                              label: l10n.courseCreateSheetSchoolLabel,
                              hint: l10n.courseCreateSheetSchoolHint,
                              icon: Icons.account_balance_outlined,
                              suggestions: existingSchools
                                  .map((a) => a.attributeName)
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            _AttributeField(
                              controller: subjectCtl,
                              label: l10n.courseCreateSheetSubjectLabel,
                              hint: l10n.courseCreateSheetSubjectHint,
                              icon: Icons.category_outlined,
                              suggestions: existingSubjects
                                  .map((a) => a.attributeName)
                                  .toList(),
                            ),
                            const SizedBox(height: 12),
                            _GlassTextField(
                              controller: summaryCtl,
                              label: l10n.courseCreateSheetSummaryLabel,
                              hint: l10n.courseCreateSheetSummaryHint,
                              icon: Icons.notes_outlined,
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                  ],
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

class _CustomColorPickerDialog extends HookWidget {
  const _CustomColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hsl = HSLColor.fromColor(initialColor);
    final hue = useState(hsl.hue);
    final lightness = useState(hsl.lightness.clamp(0.4, 1.0));

    // Force saturation to 0.8 to keep custom colors vibrant and visually cohesive
    final currentColor = HSLColor.fromAHSL(
      1.0,
      hue.value,
      0.8,
      lightness.value,
    ).toColor();

    final hexController = useTextEditingController(
      text: CourseStyleHelper.colorToHex(currentColor),
    );

    void updateHexField(Color color) {
      final hex = CourseStyleHelper.colorToHex(color);
      if (hexController.text != hex) {
        hexController.text = hex;
      }
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF1E203C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.universe.glassBorder),
      ),
      title: Text(
        l10n.courseCreateSheetCustomColorDialogTitle,
        style: TextStyle(color: AppColors.universe.textStarlight),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: currentColor.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.courseCreateSheetHueLabel,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                trackHeight: 12,
              ),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
                child: Slider(
                  value: hue.value,
                  min: 0.0,
                  max: 360.0,
                  onChanged: (val) {
                    hue.value = val;
                    updateHexField(
                      HSLColor.fromAHSL(
                        1.0,
                        val,
                        0.8,
                        lightness.value,
                      ).toColor(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.courseCreateSheetLightnessLabel,
                style: TextStyle(
                  color: AppColors.universe.textComet,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                trackHeight: 12,
              ),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    colors: [
                      HSLColor.fromAHSL(1.0, hue.value, 0.8, 0.4).toColor(),
                      HSLColor.fromAHSL(1.0, hue.value, 0.8, 0.7).toColor(),
                      Colors.white,
                    ],
                  ),
                ),
                child: Slider(
                  value: lightness.value,
                  min: 0.4,
                  max: 1.0,
                  onChanged: (val) {
                    lightness.value = val;
                    updateHexField(
                      HSLColor.fromAHSL(1.0, hue.value, 0.8, val).toColor(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: hexController,
              style: TextStyle(color: AppColors.universe.textStarlight),
              decoration: InputDecoration(
                labelText: l10n.courseCreateSheetHexLabel,
                labelStyle: TextStyle(color: AppColors.universe.textComet),
                hintText: '#FFB300',
                hintStyle: TextStyle(
                  color: AppColors.universe.textComet.withValues(alpha: 0.5),
                ),
                prefixIcon: Icon(
                  Icons.tag,
                  color: AppColors.universe.textComet,
                ),
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
              onChanged: (text) {
                final cleanText = text.replaceFirst('#', '').trim();
                if (cleanText.length == 6 || cleanText.length == 8) {
                  try {
                    final parsedColor = CourseStyleHelper.hexToColor(
                      '#$cleanText',
                    );
                    final newHsl = HSLColor.fromColor(parsedColor);
                    hue.value = newHsl.hue;
                    lightness.value = newHsl.lightness.clamp(0.4, 1.0);
                  } catch (_) {
                    // Ignore parsing errors while typing
                  }
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.courseCreateSheetCancelButton,
            style: TextStyle(color: AppColors.universe.textComet),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.starGold,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(currentColor),
          child: Text(l10n.courseCreateSheetOkButton),
        ),
      ],
    );
  }
}
