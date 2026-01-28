import 'dart:async';
// import 'dart:developer';
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

import 'widgets/breadcrumb_bar.dart';
import '../../widgets/delete_confirm_dialog.dart';
import 'widgets/empty_state.dart';
import 'widgets/folder_tile.dart';
import 'widgets/lecture_tile.dart';
import 'widgets/name_dialog.dart';

class LectureFolderPage extends HookConsumerWidget {
  const LectureFolderPage({super.key, required this.folderId});

  /// nullならHome
  final String? folderId;

  static const _folderSvgPath = 'assets/images/lecture_folder_test.svg';

  /// グリッドのカラム数を計算
  int _calcCrossAxisCount(double width) {
    const minTileWidth = 140.0;
    final count = (width / minTileWidth).floor();
    return count < 1 ? 1 : count;
  }

  /// パンくずリストから「論理的な親ID」を取得
  String? _getParentFromBreadcrumb(
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) {
    final chain = breadcrumbAsync.value;
    if (chain == null || chain.isEmpty || chain.length == 1) return null;
    return chain[chain.length - 2].id;
  }

  String? _getCurrentFolderIdFromBreadcrumb(
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) {
    final chain = breadcrumbAsync.value;
    if (chain == null || chain.isEmpty) return null;
    return chain[chain.length - 1].id;
  }

  /// 共通の「戻る」処理
  Future<void> _navigateBack(
    BuildContext context,
    WidgetRef ref,
    NavStateStore nav,
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) async {
    final currentId = _getCurrentFolderIdFromBreadcrumb(breadcrumbAsync);
    final parentId = _getParentFromBreadcrumb(breadcrumbAsync);

    if (currentId == null) {
      // Homeなら何もしない
      return;
    }

    // LastLocation更新
    if (parentId == null) {
      unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
    } else {
      unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$parentId'));
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      // 履歴再構築ロジック
      if (parentId == null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LectureFolderPage(folderId: null),
            settings: const RouteSettings(name: '/'),
          ),
          (route) => false,
        );
      } else {
        final parentCrumbs = await ref.read(folderBreadcrumbProvider(parentId).future);
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => const LectureFolderPage(folderId: null),
              settings: const RouteSettings(name: '/'),
            ),
            (route) => false,
          );
        }

        for (final crumb in parentCrumbs) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LectureFolderPage(folderId: crumb.id),
                settings: RouteSettings(name: 'f/${crumb.id}'),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(() async {
        await ref.read(lectureFolderControllerProvider.notifier).bootstrapIfNeeded();
        await ref.read(lectureControllerProvider.notifier).bootstrapIfNeeded();
      });
      return null;
    }, const []);

    // 2つのデータソースを監視
    final foldersAsync = ref.watch(folderListStreamProvider(folderId));
    final lecturesAsync = ref.watch(lectureListStreamProvider(folderId));
    
    final breadcrumbAsync = ref.watch(folderBreadcrumbProvider(folderId));
    final nav = ref.read(navStateStoreProvider);

    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          if (vx > 200) {
            _navigateBack(context, ref, nav, breadcrumbAsync);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Notes'),
            actions: [
              // フォルダ作成ボタン
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
                      if (targetId == null) {
                        unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      } else {
                        unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$targetId'));
                        Navigator.of(context).popUntil((route) {
                          return route.settings.name == 'f/$targetId' || route.isFirst;
                        });
                      }
                    },
                  );
                },
              ),

              // 2. メインコンテンツ (Grid + List)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final folders = foldersAsync.value ?? [];
                    final lectures = lecturesAsync.value ?? [];
                    
                    // まだロード中でデータが空の場合
                    if ((foldersAsync.isLoading && folders.isEmpty) || 
                        (lecturesAsync.isLoading && lectures.isEmpty)) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // 両方とも空ならEmptyState
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

                          // --- Section A: Folders (Grid) ---
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
                                        // フォルダ遷移
                                        unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/${row.id}'));
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

                          // --- Section B: Lectures (List) ---
                          if (lectures.isNotEmpty) ...[
                            // セパレーター & ヘッダー (フォルダがある時だけ入れると綺麗)
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
                            
                            // リスト本体
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final lecture = lectures[index];
                                    return LectureTile(
                                      lecture: lecture,
                                      onTap: () {
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

                          // 下部余白
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
      ),
    );
  }
}