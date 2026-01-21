// lib/presentation/pages/lecture_folder/lecture_folder_page.dart
import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
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

  /// パンくずリストから「論理的な親ID」を取得するヘルパー
  String? _getParentFromBreadcrumb(
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) {
    final chain = breadcrumbAsync.value;
    // chainがない、またはHome(0個)か直下(1個)の場合は親はHome(null)
    if (chain == null || chain.isEmpty || chain.length == 1) return null;
    // 後ろから2番目が親
    return chain[chain.length - 2].id;
  }

  String? _getCurrentFolderIdFromBreadcrumb(
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) {
    final chain = breadcrumbAsync.value;
    if (chain == null || chain.isEmpty) return null;
    // 一番後ろが現在のフォルダ
    return chain[chain.length - 1].id;
  }

  /// 共通の「戻る（親へ移動）」処理
  /// スワイプ時と左上アイコンタップ時で共用
  Future<void> _navigateBack(
    BuildContext context,
    WidgetRef ref, // refを追加
    NavStateStore nav,
    AsyncValue<List<FolderCrumb>> breadcrumbAsync,
  ) async {
    // 1. 親IDを特定
    final currentId = _getCurrentFolderIdFromBreadcrumb(breadcrumbAsync);
    final parentId = _getParentFromBreadcrumb(breadcrumbAsync);

    if (currentId == null) {
      log('Already at Home, cannot navigate back further.');
      return; // Homeなら戻れない
    }

    // 2. LastLocationを更新
    if (parentId == null) {
      unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
    } else {
      unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$parentId'));
    }

    // 3. 画面遷移
    if (Navigator.of(context).canPop()) {
      // A. 履歴があるなら普通にPop (自然な戻る)
      log('Navigating back to parent folder: $parentId');
      Navigator.of(context).pop();
    } else {
      // B. 履歴がない（アプリ起動直後など）場合の「再構築」処理
      
      if (parentId == null) {
        // 親がHomeなら、HomeをPushReplacement（または全消しPush）で開く
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LectureFolderPage(folderId: null),
            settings: const RouteSettings(name: '/'),
          ),
          (route) => false, // 履歴を全消去
        );
      } else {
        // 親がフォルダの場合：
        // 「Home」から「親フォルダ」までの道のりを再構築してスタックに積む！
        
        // ローディングを出すか、一瞬待つ（非同期で親のパンくずを取得）
        // ※ folderBreadcrumbProvider は「そのフォルダまでのパス（自分含む）」を返すと想定
        final parentCrumbs = await ref.read(folderBreadcrumbProvider(parentId).future);
        
        // 1. まずHomeを置いて履歴をリセット
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const LectureFolderPage(folderId: null),
            settings: const RouteSettings(name: '/'),
          ),
          (route) => false,
        );

        // 2. 親までの経路（Home直下〜親自身）を順番にPush
        // これで [Home, FolderA, FolderB(親)] というスタックが完成する
        for (final crumb in parentCrumbs) {
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

    return PopScope(
      canPop: false, 
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          
          final vx = details.primaryVelocity ?? 0;
          if (vx > 200) { // 右スワイプ判定
            _navigateBack(context, ref, nav, breadcrumbAsync);
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
                        parentId: folderId,
                        type: 'binder',
                      );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // パンくずリスト
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

                      // 1. LastLocationを明示的に更新
                      if (targetId == null) {
                        unawaited(nav.setLastNotesLocation(AppRoutes.notesHome));
                        // Homeに戻る -> スタック全消し
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      } else {
                        unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/$targetId'));
                        // 特定フォルダに戻る -> popUntilでその名前のルートまで戻る
                        // (名前が一致するルートがなければ何もしないので、保険でPushを入れる手もあり)
                        Navigator.of(context).popUntil((route) {
                          return route.settings.name == 'f/$targetId' || route.isFirst;
                        });
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
                                        
                                        // ✅ フォルダタップ時の遷移
                                        onTap: () {
                                          // 1. LastLocationを明示的に更新
                                          unawaited(nav.setLastNotesLocation('${AppRoutes.notesHome}/f/${row.id}'));
                                          
                                          // 2. 画面遷移 (Navigator.push)
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
                                          if (ok != true) return;

                                          await ref.read(lectureFolderControllerProvider.notifier).deleteFolder(
                                                folderId: row.id,
                                              );
                                          
                                          // 削除時のケアはリストがリアクティブなら不要ですが
                                          // 必要なら親に戻る処理を追加
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
      ),
    );
  }
}