import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart'; 

import '../../../../application/lecture_folders/folder_breadcrumb_provider.dart';
import '../../../../application/lecture_folders/folder_list_provider.dart';
import '../../../pages/lecture_folder/widgets/breadcrumb_bar.dart';

class FolderPickerResult {
  final bool confirmed;
  final String? folderId; // null = Home
  const FolderPickerResult._(this.confirmed, this.folderId);

  static const cancelled = FolderPickerResult._(false, null);
  static FolderPickerResult selectConfirmed(String? folderId) =>
      FolderPickerResult._(true, folderId);
}

class FolderPickerSheet extends HookConsumerWidget {
  const FolderPickerSheet({
    super.key,
    required this.initialSelectedFolderId,
  });

  final String? initialSelectedFolderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = useState<String?>(initialSelectedFolderId);
    final browseId = useState<String?>(null);
    final initialized = useState(false);
    final lastTapTime = useRef<DateTime?>(null);

    final selectedChainAsync =
        ref.watch(folderBreadcrumbProvider(initialSelectedFolderId));

    useEffect(() {
      if (initialized.value) return null;
      selectedChainAsync.whenData((chain) {
        String? parent;
        if (initialSelectedFolderId == null) {
          parent = null;
        } else if (chain.length <= 1) {
          parent = null;
        } else {
          parent = chain[chain.length - 2].id;
        }
        browseId.value = parent;
        selectedId.value = initialSelectedFolderId;
        initialized.value = true;
      });
      return null;
    }, [selectedChainAsync]);

    final browseChainAsync = ref.watch(folderBreadcrumbProvider(browseId.value));
    final foldersAsync = ref.watch(folderListStreamProvider(browseId.value));

    Widget buildBreadcrumb() {
      // 共通のデザインロジック
      return browseChainAsync.when(
        loading: () => BreadcrumbBar(
            crumbs: const ['Home'],
            onTapCrumb: (_) {
              browseId.value = null;
              selectedId.value = null;
            }),
        error: (_, __) => BreadcrumbBar(
            crumbs: const ['Home'],
            onTapCrumb: (_) {}),
        data: (chain) {
          final labels = <String>['Home', ...chain.map((r) => r.name)];
          final ids = <String?>[null, ...chain.map((r) => r.id)];

          return BreadcrumbBar(
            crumbs: labels,
            onTapCrumb: (index) {
              browseId.value = ids[index];
              selectedId.value = ids[index];
            },
          );
        },
      );
    }

    return Container(
      // シート全体の背景 (宇宙の黒)
      decoration: BoxDecoration(
        color: AppColors.universe.voidBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, color: AppColors.starGold),
                    const SizedBox(width: 8),
                    Text(
                      'Select folder',
                      style: TextStyle(
                        color: AppColors.universe.textStarlight,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context)
                          .pop(FolderPickerResult.cancelled),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: buildBreadcrumb(), // BreadcrumbBarは既に透明対応済み
              ),
              Divider(height: 1, color: AppColors.universe.glassBorder),

              // List
              Expanded(
                child: foldersAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: AppColors.starGold)),
                  error: (e, _) => Center(child: Text('Error: $e')),
                  data: (folders) {
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: folders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final f = folders[index];
                        final isSelected = selectedId.value == f.id;

                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppColors.starGold.withOpacity(0.2) 
                                : AppColors.universe.glassWhiteLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppColors.starGold : Colors.transparent
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(
                              Icons.folder_outlined, 
                              color: isSelected ? AppColors.starGold : AppColors.universe.textComet
                            ),
                            title: Text(
                              f.name,
                              style: TextStyle(
                                color: isSelected ? AppColors.starGold : AppColors.universe.textStarlight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // ダブルタップロジック
                            onTap: () {
                              final now = DateTime.now();
                              final lastTime = lastTapTime.value;
                              if (selectedId.value == f.id &&
                                  lastTime != null &&
                                  now.difference(lastTime) < const Duration(milliseconds: 500)) {
                                browseId.value = f.id;
                                selectedId.value = f.id;
                                lastTapTime.value = null;
                              } else {
                                selectedId.value = f.id;
                                lastTapTime.value = now;
                              }
                            },
                            trailing: IconButton(
                                icon: Icon(Icons.chevron_right, color: AppColors.universe.textComet),
                                onPressed: () {
                                  selectedId.value = f.id;
                                  browseId.value = f.id;
                                }),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              Divider(height: 1, color: AppColors.universe.glassBorder),

              // Footer buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pop(FolderPickerResult.cancelled),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.universe.textComet),
                          foregroundColor: AppColors.universe.textComet,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            FolderPickerResult.selectConfirmed(selectedId.value),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.starGold,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Select'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}