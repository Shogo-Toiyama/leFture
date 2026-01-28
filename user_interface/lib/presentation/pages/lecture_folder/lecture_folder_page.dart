import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_controller.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture/lecture_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_breadcrumb_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/lecture_folder_controller.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/lecture_viewer_page.dart';
import 'dart:developer' as dev; // ログ用

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
    // デバッグログ: どのIDでビルドされたか
    // dev.log('🎨 [Page] Build: ${folderId ?? "HOME"}');

    useEffect(() {
      // 画面が表示されたタイミングで実行
      Future.microtask(() {
        // dev.log('💾 [Page] useEffect for: ${folderId ?? "HOME"}');
        
        final nav = ref.read(navStateStoreProvider);
        
        // 【上書き防止チェック】
        // もし直前のロケーションと全然違うものを保存しようとしていたらログで警告
        if (folderId == null) {
          nav.setLastNotesLocation(AppRoutes.notesHome);
          // dev.log('📝 [Page] Saved: HOME');
        } else {
          nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$folderId');
          // dev.log('📝 [Page] Saved: f/$folderId');
        }
        
        // データ同期
        // ※ここはUI操作ではないので await しなくてもクラッシュしませんが、
        // 念のためエラーハンドリングしておくと安全です。
        try {
          ref.read(lectureFolderControllerProvider.notifier).bootstrapIfNeeded();
          ref.read(lectureControllerProvider.notifier).bootstrapIfNeeded();
        } catch (e) {
           dev.log('⚠️ [Page] Bootstrap error: $e');
        }
      });
      return null;
    }, [folderId]);

    final foldersAsync = ref.watch(folderListStreamProvider(folderId));
    final lecturesAsync = ref.watch(lectureListStreamProvider(folderId));
    final breadcrumbAsync = ref.watch(folderBreadcrumbProvider(folderId));

    return PopScope( 
      canPop: false,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: 'Add folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () async {
              final name = await showFolderNameDialog(
                context: context,
                title: 'Create folder',
                initialValue: 'New Folder',
                saveLabel: 'Save',
              );
              if (name == null) return;
              
              if (!context.mounted) return; // クラッシュ対策

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
                  final targetId = ids[index];
                  // PopUntilの条件をログ出力
                  // dev.log('🔙 [Breadcrumb] Pop until: ${targetId ?? "HOME"}');
                  
                  Navigator.of(context).popUntil((route) {
                    if (targetId == null) {
                      return route.isFirst;
                    }
                    return route.settings.name == 'f/$targetId';
                  });
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
                
                if ((foldersAsync.isLoading && folders.isEmpty) || 
                    (lecturesAsync.isLoading && lectures.isEmpty)) {
                  return const Center(child: CircularProgressIndicator());
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
                      if (name == null) return;
                      if (!context.mounted) return; // クラッシュ対策

                      await ref.read(lectureFolderControllerProvider.notifier).createFolder(
                            name: name.trim(),
                            parentId: folderId,
                            type: 'binder',
                          );
                    },
                  );
                }

                return RefreshIndicator(
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
                                    // ★ クラッシュ対策: Pushする前にログ
                                    // dev.log('➡ [Tile] Push folder: ${row.id}');
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LectureFolderPage(folderId: row.id),
                                        settings: RouteSettings(name: 'f/${row.id}'),
                                      ),
                                    );
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
                                    if (ok == true) {
                                      if (!context.mounted) return;
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
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Text(
                                'Lectures',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
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
                                    // dev.log('➡ [Tile] Push lecture: ${lecture.id}');
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LectureViewerPage(lecture: lecture),
                                      ),
                                    );
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
      ),),
    );
  }
}