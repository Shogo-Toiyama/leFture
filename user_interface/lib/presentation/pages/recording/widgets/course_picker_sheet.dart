import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/application/course/course_list_provider.dart';
import 'package:lefture/domain/entities/course.dart';
import 'package:lefture/presentation/pages/course/widgets/course_style_helper.dart';
import 'package:lefture/presentation/pages/course/widgets/course_create_sheet.dart';
import 'package:lefture/presentation/themes/app_colors.dart';
import 'package:lefture/presentation/widgets/app_error_dialog.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';


class CoursePickerResult {
  const CoursePickerResult({this.courseId, required this.confirmed});
  final String? courseId;
  final bool confirmed;
}

/// 録音画面からコースを選択するボトムシート
class CoursePickerSheet extends HookConsumerWidget {
  const CoursePickerSheet({super.key, this.initialSelectedCourseId});

  final String? initialSelectedCourseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedId = useState<String?>(initialSelectedCourseId);
    final searchCtl = useTextEditingController();
    useListenable(searchCtl);
    final isRefreshingCourses = useState(false);

    final coursesAsync = ref.watch(courseListProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.universe.glassBorder)),
      ),
      child: Column(
        children: [
          // ハンドル
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.universe.glassBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    l10n.coursePickerTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const CoursePickerResult(confirmed: false),
                  ),
                  child: Text(
                    l10n.coursePickerCancelButton,
                    style: TextStyle(
                      color: AppColors.universe.textComet,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 検索バー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchCtl,
                    style: TextStyle(color: AppColors.universe.textStarlight),
                    decoration: InputDecoration(
                      hintText: l10n.coursePickerSearchHint,
                      hintStyle: TextStyle(color: AppColors.universe.textComet),
                      prefixIcon: Icon(Icons.search, color: AppColors.universe.textComet),
                      filled: true,
                      fillColor: AppColors.universe.glassWhiteLow,
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppColors.universe.glassWhiteLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isRefreshingCourses.value
                          ? null
                          : () async {
                              final newCourse = await showModalBottomSheet<Course>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (_) => const CourseCreateSheet(),
                              );
                              if (newCourse == null) return;
                              selectedId.value = newCourse.id;

                              // コース作成自体はCourseCreateSheet内でSupabaseへ
                              // 書き込み済み。ここでローカルDBへのPull(反映)を
                              // 1回だけ行う — 呼び出し元がここだけなので他の
                              // Pullと競合しない。失敗時はローカルにまだ
                              // 反映されていないので、ユーザーに見える形で
                              // エラーを出す(黙って失敗させない)。
                              isRefreshingCourses.value = true;
                              try {
                                await refreshCoursesAfterEdit(ref);
                              } catch (e) {
                                if (context.mounted) {
                                  AppErrorDialog.showSmart(
                                    context,
                                    e,
                                    actionName: 'refreshing your courses',
                                  );
                                }
                              } finally {
                                isRefreshingCourses.value = false;
                              }
                            },
                      child: isRefreshingCourses.value
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.starGold,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.add,
                              color: AppColors.starGold,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // コース一覧
          Expanded(
            child: coursesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.starGold)),
              error: (e, _) => Center(
                child: Text(l10n.coursePickerErrorLoading(e.toString()), style: const TextStyle(color: AppColors.correctionRed)),
              ),
              data: (courses) {
                final query = searchCtl.text.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? courses
                    : courses.where((c) {
                        final title = c.displayTitle.toLowerCase();
                        final year = c.year?.attributeName.toLowerCase() ?? '';
                        final term = c.term?.attributeName.toLowerCase() ?? '';
                        return title.contains(query) || year.contains(query) || term.contains(query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      courses.isEmpty ? l10n.coursePickerEmptyNoCourses : l10n.coursePickerEmptySearchResults,
                      style: TextStyle(color: AppColors.universe.textComet),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, i) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final course = filtered[index];
                    final isSelected = course.id == selectedId.value;
                    return _CoursePickerTile(
                      course: course,
                      isSelected: isSelected,
                      onTap: () => selectedId.value = course.id,
                    );
                  },
                );
              },
            ),
          ),

          // 確定ボタン
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  CoursePickerResult(courseId: selectedId.value, confirmed: true),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.starGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  selectedId.value != null ? l10n.coursePickerConfirmButton : l10n.coursePickerContinueWithoutCourseButton,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursePickerTile extends StatelessWidget {
  const _CoursePickerTile({
    required this.course,
    required this.isSelected,
    required this.onTap,
  });

  final Course course;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (course.year != null) course.year!.attributeName,
      if (course.term != null) course.term!.attributeName,
    ];
    final subtitle = parts.isEmpty ? null : parts.join(' / ');

    final courseColor = CourseStyleHelper.hexToColor(course.color, fallback: AppColors.deepGold);
    final iconData = CourseStyleHelper.getIcon(course.icon);

    // Adjust color for dark mode sheet contrast
    final HSLColor hsl = HSLColor.fromColor(courseColor);
    final displayIconColor = hsl.lightness < 0.45 ? hsl.withLightness(0.55).toColor() : courseColor;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.starGold.withValues(alpha: 0.15)
              : AppColors.universe.glassWhiteLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.starGold : AppColors.universe.glassBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.starGold.withValues(alpha: 0.2)
                    : displayIconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                iconData,
                color: displayIconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    course.displayTitle,
                    style: TextStyle(
                      color: AppColors.universe.textStarlight,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: AppColors.universe.textComet, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: AppColors.starGold, size: 20),
          ],
        ),
      ),
    );
  }
}
