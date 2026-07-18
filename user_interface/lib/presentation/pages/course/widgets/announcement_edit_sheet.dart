import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/domain/entities/announcement.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/repositories/announcement_repository_drift.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';
import 'package:lecture_companion_ui/presentation/widgets/announcement_type_icon.dart';

class AnnouncementEditSheet extends HookConsumerWidget {
  const AnnouncementEditSheet({
    super.key,
    required this.announcement,
  });

  final Announcement announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleCtl = useTextEditingController(
      text: announcement.title?.trim() ?? '',
    );
    final descriptionCtl = useTextEditingController(
      text: announcement.description?.trim() ?? '',
    );
    final selectedType = useState<AnnouncementType>(announcement.type);
    final isSubmitting = useState(false);
    final errorMsg = useState<String?>(null);

    Future<void> submit() async {
      final title = titleCtl.text.trim();
      if (title.isEmpty) {
        errorMsg.value = 'Title cannot be empty.';
        return;
      }

      isSubmitting.value = true;
      errorMsg.value = null;

      try {
        await ref.read(announcementRepositoryDriftProvider).updateAnnouncement(
              id: announcement.id,
              title: title,
              description: descriptionCtl.text.trim().isEmpty ? null : descriptionCtl.text.trim(),
              type: selectedType.value,
            );
        ref.read(lectureControllerProvider.notifier).pushOutboxNow();
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

              // タイトル行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Announcement',
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

              // 1. タイプ選択
              Text(
                'Type',
                style: TextStyle(
                  color: AppColors.universe.textStarlight,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _TypeSelector(
                selected: selectedType.value,
                onChanged: (t) => selectedType.value = t,
              ),
              const SizedBox(height: 20),

              // 2. タイトル
              TextField(
                controller: titleCtl,
                style: TextStyle(color: AppColors.universe.textStarlight),
                decoration: InputDecoration(
                  labelText: 'Title',
                  hintText: 'Announcement title',
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
              const SizedBox(height: 16),

              // 3. 説明
              TextField(
                controller: descriptionCtl,
                style: TextStyle(color: AppColors.universe.textStarlight),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Additional details (optional)',
                  alignLabelWithHint: true,
                  labelStyle: TextStyle(color: AppColors.universe.textComet),
                  hintStyle: TextStyle(
                    color: AppColors.universe.textComet.withValues(alpha: 0.5),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Icon(Icons.notes, color: AppColors.universe.textComet),
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

/// タイプ選択チップ群
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.onChanged,
  });

  final AnnouncementType selected;
  final ValueChanged<AnnouncementType> onChanged;

  static const _types = [
    AnnouncementType.todo,
    AnnouncementType.event,
    AnnouncementType.hint,
    AnnouncementType.info,
  ];

  static const _labels = {
    AnnouncementType.todo: 'Todo',
    AnnouncementType.event: 'Event',
    AnnouncementType.hint: 'Hint',
    AnnouncementType.info: 'Info',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((type) {
        final isSelected = type == selected;
        return GestureDetector(
          onTap: () => onChanged(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.starGold.withValues(alpha: 0.15)
                  : AppColors.universe.glassWhiteLow,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.starGold.withValues(alpha: 0.6)
                    : AppColors.universe.glassBorder,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  iconForAnnouncementType(type),
                  size: 16,
                  color: isSelected ? AppColors.starGold : AppColors.universe.textComet,
                ),
                const SizedBox(width: 6),
                Text(
                  _labels[type] ?? type.name,
                  style: TextStyle(
                    color: isSelected ? AppColors.starGold : AppColors.universe.textComet,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
