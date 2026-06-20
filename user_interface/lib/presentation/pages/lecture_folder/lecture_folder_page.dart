import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_breadcrumb_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/lecture_folder_controller.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/infrastructure/local_db/app_database_provider.dart';
import 'package:lecture_companion_ui/presentation/themes/app_colors.dart';

import 'widgets/breadcrumb_bar.dart';
import '../../widgets/delete_confirm_dialog.dart';
import 'widgets/empty_state.dart';
import 'widgets/folder_tile.dart';
import 'widgets/lecture_tile.dart';
import 'widgets/name_dialog.dart';

class LectureFolderPage extends HookConsumerWidget {
  const LectureFolderPage({super.key, required this.folderId});

  final String? folderId;

  static const _folderSvgPath = 'assets/images/lecture_folder_test.svg';

  int _calcCrossAxisCount(double width) {
    const minTileWidth = 140.0;
    final count = (width / minTileWidth).floor();
    return count < 1 ? 1 : count;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(() async {
        final nav = ref.read(navStateStoreProvider);
        if (folderId == null) {
          nav.setLastNotesLocation(AppRoutes.notesRoot);
        } else {
          nav.setLastNotesLocation('${AppRoutes.notesRoot}/f/$folderId');
        }
        try {
          await ref.read(lectureFolderControllerProvider.notifier).bootstrapIfNeeded();
          await ref.read(lectureControllerProvider.notifier).bootstrapIfNeeded();
        } catch (e, st) {
           print('❌ bootstrap error: $e\n$st');
        }
      });
      return null;
    }, [folderId]);

    final foldersAsync = ref.watch(folderListStreamProvider(folderId));
    final lecturesAsync = ref.watch(lectureListStreamProvider(folderId));
    final breadcrumbAsync = ref.watch(folderBreadcrumbProvider(folderId));

    return PopScope( 
      canPop: true,
      child: Scaffold(
        // ★ 背景を宇宙の黒に！
        backgroundColor: AppColors.universe.voidBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // タイトルも星屑の色に
          title: Text(
            'Notes', 
            style: TextStyle(color: AppColors.universe.textStarlight),
          ),
          iconTheme: const IconThemeData(color: Colors.white), // 戻るボタン等
          actions: [
            IconButton(
              tooltip: 'Dump DB Log',
              icon: const Icon(Icons.bug_report, color: Colors.amber),
              onPressed: () async {
                print('🚀 Manually triggering Drift DB Dump...');
                await ref.read(appDatabaseProvider).dumpDatabaseLog();
              },
            ),
            IconButton(
              tooltip: 'Add folder',
              icon: const Icon(Icons.create_new_folder_outlined, color: Colors.white),
              onPressed: () async {
                final name = await showFolderNameDialog(
                  context: context,
                  title: 'Create folder',
                  initialValue: 'New Folder',
                  saveLabel: 'Save',
                );
                if (name == null || !context.mounted) return;

                await ref.read(lectureFolderControllerProvider.notifier).createFolder(
                      name: name.trim(),
                      parentId: folderId,
                      type: 'binder',
                    );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // 1. パンくずリスト
            breadcrumbAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => const SizedBox.shrink(),
              data: (chain) {
                final labels = <String>['Home', ...chain.map((r) => r.name)];
                final ids = <String?>[null, ...chain.map((r) => r.id)];

                return BreadcrumbBar(
                  crumbs: labels,
                  onTapCrumb: (index) {
                    final currentDepth = labels.length - 1;
                    final popCount = currentDepth - index;
                    if (popCount > 0) {
                      for (int i = 0; i < popCount; i++) {
                        if (context.canPop()) {
                          context.pop();
                        }
                      }
                    }
                  },
                );
              },
            ),

            // 2. メインコンテンツ
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final folders = foldersAsync.value ?? [];
                  final lectures = lecturesAsync.value ?? [];
                  
                  if (foldersAsync.hasError) {
                    print('❌ foldersAsync Error: ${foldersAsync.error}\n${foldersAsync.stackTrace}');
                  }
                  if (lecturesAsync.hasError) {
                    print('❌ lecturesAsync Error: ${lecturesAsync.error}\n${lecturesAsync.stackTrace}');
                  }

                  if ((foldersAsync.isLoading && folders.isEmpty) || 
                      (lecturesAsync.isLoading && lectures.isEmpty)) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (foldersAsync.hasError || lecturesAsync.hasError) {
                    final error = foldersAsync.error ?? lecturesAsync.error;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              'Database Error Occurred',
                              style: TextStyle(
                                color: AppColors.universe.textStarlight,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              error.toString(),
                              style: const TextStyle(color: Colors.redAccent),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (folders.isEmpty && lectures.isEmpty) {
                    return EmptyState(
                      onCreate: () async {
                        final name = await showFolderNameDialog(
                          context: context,
                          title: 'Create folder',
                          initialValue: 'New Folder',
                          saveLabel: 'Save',
                        );
                        if (name == null || !context.mounted) return;

                        await ref.read(lectureFolderControllerProvider.notifier).createFolder(
                              name: name.trim(),
                              parentId: folderId,
                              type: 'binder',
                            );
                      },
                    );
                  }

                  return RefreshIndicator(
                    // RefreshIndicatorの色調整
                    color: AppColors.starGold,
                    backgroundColor: AppColors.universe.glassWhiteHigh,
                    onRefresh: () async {
                      await ref.read(lectureFolderControllerProvider.notifier).bootstrapFolders();
                      await ref.read(lectureControllerProvider.notifier).bootstrapLectures();
                    },
                    child: CustomScrollView(
                      slivers: [
                        const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        if (folders.isNotEmpty) ...[
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverGrid(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _calcCrossAxisCount(constraints.maxWidth),
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.1,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final row = folders[index];
                                  return FolderTile(
                                    name: row.name,
                                    svgAssetPath: _folderSvgPath,
                                    isFavorite: row.isFavorite,
                                    onTap: () {
                                      context.push('${AppRoutes.notesRoot}/f/${row.id}');
                                    },
                                    onRename: () async {
                                      final newName = await showFolderNameDialog(
                                        context: context,
                                        title: 'Rename folder',
                                        initialValue: row.name,
                                        saveLabel: 'Save',
                                      );
                                      if (newName == null) return;
                                      final trimmed = newName.trim();
                                      if (trimmed.isEmpty || trimmed == row.name) return;
                                      if (!context.mounted) return;

                                      await ref.read(lectureFolderControllerProvider.notifier).renameFolder(
                                            folderId: row.id,
                                            newName: trimmed,
                                          );
                                    },
                                    onDelete: () async {
                                      final ok = await showConfirmDialog(
                                        context: context,
                                        title: 'Delete folder',
                                        message: 'Are you sure you want to delete "${row.name}"?',
                                        confirmLabel: 'Delete',
                                      );
                                      if (ok == true && context.mounted) {
                                        await ref.read(lectureFolderControllerProvider.notifier).deleteFolder(folderId: row.id);
                                      }
                                    },
                                    onToggleFavorite: (newValue) async {
                                      await ref.read(lectureFolderControllerProvider.notifier).setFavorite(
                                            folderId: row.id,
                                            isFavorite: newValue,
                                          );
                                    },
                                  );
                                },
                                childCount: folders.length,
                              ),
                            ),
                          ),
                        ],
                        if (lectures.isNotEmpty) ...[
                          if (folders.isNotEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                child: Text(
                                  'Lectures',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    // 見出しは少し暗めのグレー（Comet）
                                    color: AppColors.universe.textComet,
                                  ),
                                ),
                              ),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final lecture = lectures[index];
                                  return LectureTile(
                                    lecture: lecture,
                                    onTap: () {
                                      context.push('${AppRoutes.notesRoot}/v/${lecture.id}');
                                    },
                                  );
                                },
                                childCount: lectures.length,
                              ),
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}