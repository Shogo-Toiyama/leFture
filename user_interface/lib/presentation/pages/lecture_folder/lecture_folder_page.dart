// lib/presentation/pages/lecture_folder/lecture_folder_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/routes.dart';

import 'package:lecture_companion_ui/application/lecture_folders/folder_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_breadcrumb_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/lecture_folder_controller.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';

import 'widgets/breadcrumb_bar.dart';
import 'widgets/delete_confirm_dialog.dart';
import 'widgets/empty_state.dart';
import 'widgets/folder_tile.dart';
import 'widgets/name_dialog.dart';

class LectureFolderPage extends HookConsumerWidget {
  const LectureFolderPage({super.key, required this.folderId});

  /// nullならHome
  final String? folderId;

  static const _folderSvgPath = 'assets/images/lecture_folder_test.svg';

  int _calcCrossAxisCount(double width) {
    const minTileWidth = 140.0;
    final count = (width / minTileWidth).floor();
    return count < 1 ? 1 : count;
  }

  String? _getParentFromBreadcrumb(
  BuildContext context,
  AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) {
    final chain = breadcrumbAsync.value;
    if (chain == null || chain.isEmpty || chain.length == 1) return null;

    return chain[chain.length - 2].id;
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(() {
      Future.microtask(() async {
        await ref.read(lectureFolderControllerProvider.notifier).bootstrapIfNeeded();
      });
      return null;
    }, const []);

    final foldersAsync = ref.watch(folderListStreamProvider(folderId));
    final breadcrumbAsync = ref.watch(folderBreadcrumbProvider(folderId));
    final nav = ref.read(navStateStoreProvider);
    final bool canPop = false;  //folderId == null;

    return PopScope(
      canPop: canPop,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final vx = details.primaryVelocity ?? 0;
          if (vx > 200) {
            final parentId = _getParentFromBreadcrumb(context, breadcrumbAsync);
            if (parentId == null) {
              if (folderId != AppRoutes.notesHome) {
                unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                context.go(AppRoutes.notesHome);
              }
            }
            else {
              unawaited(nav.setLastNotesLocation('/notes/f/$parentId'));
              context.go('/notes/f/$parentId');
            }
          }
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
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

                  await ref.read(lectureFolderControllerProvider.notifier).createFolder(
                        name: name.trim(),
                        parentId: folderId, // ✅ URLが正
                        type: 'binder',
                      );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // ✅ パンくずは DBから導出して表示。タップはURL変更だけ。
              breadcrumbAsync.when(
                loading: () => BreadcrumbBar(
                crumbs: const ['Home'],
                onTapCrumb: (_) async {
                  unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                  context.go(AppRoutes.notesHome);
                },
              ),
              error: (e, _) => BreadcrumbBar(
                crumbs: const ['Home'],
                onTapCrumb: (_) async {
                  unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                  context.go(AppRoutes.notesHome);
                },
              ),
                data: (chain) {
                  // Home + chain
                  final labels = <String>['Home', ...chain.map((r) => r.name)];
                  final ids = <String?>[null, ...chain.map((r) => r.id)];

                  return BreadcrumbBar(
                    crumbs: labels,
                    onTapCrumb: (index) {
                      final targetId = ids[index];

                      if (targetId == null) {
                        unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                        context.go(AppRoutes.notesHome);
                      } else {
                        unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$targetId'));
                        context.go('${AppRoutes.notesHome}/f/$targetId');
                      }
                    },
                  );
                },
              ),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = _calcCrossAxisCount(constraints.maxWidth);

                    return foldersAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (rows) {
                        // rowsはLocalLectureFolderのはず。Domainに寄せたいなら変換Providerを作るのが綺麗。
                        // ここでは最短で LocalLectureFolder から必要値だけ使う。
                        if (rows.isEmpty) {
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
                          },
                          child: CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverGrid(
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.1,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final row = rows[index];

                                      return FolderTile(
                                        name: row.name,
                                        svgAssetPath: _folderSvgPath,
                                        isFavorite: row.isFavorite,
                                        onTap: () {
                                          unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/${row.id}'));
                                          context.go('${AppRoutes.notesHome}/f/${row.id}');
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
                                          if (ok != true) return;

                                          await ref.read(lectureFolderControllerProvider.notifier).deleteFolder(
                                                folderId: row.id,
                                              );
                                          if (!context.mounted) return;

                                          // ✅ もし今見てるフォルダを消したらHomeへ戻す（保険）
                                          if (folderId == row.id) {
                                            unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                                            context.go(AppRoutes.notesHome);
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
                                    childCount: rows.length,
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 24)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      )
    );
  }
}
