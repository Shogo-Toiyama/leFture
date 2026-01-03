// lib/presentation/pages/lecture_folder/lecture_folder_page.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_list_provider.dart';
import 'package:lecture_companion_ui/application/lecture_folders/lecture_folder_controller.dart';
import '../../../domain/entities/lecture_folder.dart';

import 'widgets/breadcrumb_bar.dart';
import 'widgets/delete_confirm_dialog.dart';
import 'widgets/empty_state.dart';
import 'widgets/folder_tile.dart';
import 'widgets/name_dialog.dart';

class LectureFolderPage extends ConsumerStatefulWidget {
  const LectureFolderPage({super.key});

  @override
  ConsumerState<LectureFolderPage> createState() => _LectureFolderPageState();
}

class _Crumb {
  const _Crumb({required this.id, required this.name});
  final String? id; // null = Home
  final String name;
}

class _LectureFolderPageState extends ConsumerState<LectureFolderPage> {
  static const _folderSvgPath = 'assets/images/lecture_folder_test.svg';

  bool loading = false;

  // パンくず: Home -> A -> B ...
  final List<_Crumb> crumbs = [const _Crumb(id: null, name: 'Home')];

  String? get currentFolderId => crumbs.last.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(lectureFolderControllerProvider.notifier).bootstrapFolders();
    });
  }
  // フォルダに入る
  Future<void> _enterFolder(LectureFolder folder) async {
    setState(() {
      crumbs.add(_Crumb(id: folder.id, name: folder.name));
    });
  }

  // パンくず移動
  Future<void> _goToCrumbIndex(int index) async {
    if (index < 0 || index >= crumbs.length) return;
    setState(() {
      crumbs.removeRange(index + 1, crumbs.length);
    });
  }

  Future<void> _createFolder() async {
    final name = await showFolderNameDialog(
      context: context,
      title: 'Create folder',
      initialValue: 'New Folder',
      saveLabel: 'Save',
    );
    if (name == null) return;

    setState(() => loading = true);
    try {
      await ref.read(lectureFolderControllerProvider.notifier).createFolder(
        name: name.trim(),
        parentId: currentFolderId,
        type: 'binder',
      );

    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _renameFolder(LectureFolder folder) async {
    final newName = await showFolderNameDialog(
      context: context,
      title: 'Rename folder',
      initialValue: folder.name,
      saveLabel: 'Save',
    );
    if (newName == null) return;

    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == folder.name) return;

    setState(() => loading = true);
    try {
      await ref.read(lectureFolderControllerProvider.notifier).renameFolder(
        folderId: folder.id,
        newName: trimmed,
      );

    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _deleteFolder(LectureFolder folder) async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Delete folder',
      message: 'Are you sure you want to delete "${folder.name}"?',
      confirmLabel: 'Delete',
    );
    if (ok != true) return;

    setState(() => loading = true);
    try {
      await ref.read(lectureFolderControllerProvider.notifier).deleteFolder(
        folderId: folder.id,
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }


  Future<void> _toggleFavorite(LectureFolder folder, bool newValue) async {
    setState(() => loading = true);
    try {
      await ref.read(lectureFolderControllerProvider.notifier).setFavorite(
        folderId: folder.id,
        isFavorite: newValue,
      );

    } finally {
      if (mounted) setState(() => loading = false);
    }
  }


int _calcCrossAxisCount(double width) {
  const minTileWidth = 140.0;
  final count = (width / minTileWidth).floor();
  return count < 1 ? 1 : count;
}

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(folderListStreamProvider(currentFolderId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            tooltip: 'Add folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: loading ? null : _createFolder,
          ),
        ],
      ),
      body: Column(
        children: [
          // パンくずバー（AppBarの下）
          BreadcrumbBar(
            crumbs: crumbs.map((c) => c.name).toList(),
            onTapCrumb: (index) => _goToCrumbIndex(index),
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = _calcCrossAxisCount(constraints.maxWidth);

                return foldersAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),

                  error: (e, _) => Center(child: Text('Error: $e')),

                  data: (folders) {return RefreshIndicator(
                    onRefresh: () async {
                      await ref.read(lectureFolderControllerProvider.notifier).bootstrapFolders();
                    },
                    child: loading && folders.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : folders.isEmpty
                        ? EmptyState(onCreate: _createFolder)
                        : CustomScrollView(
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
                                    final folder = folders[index];
                                    return FolderTile(
                                      name: folder.name,
                                      svgAssetPath: _folderSvgPath,
                                      isFavorite: folder.isFavorite,
                                      onTap: () => _enterFolder(folder),
                                      onRename: () => _renameFolder(folder),
                                      onDelete: () => _deleteFolder(folder),
                                      onToggleFavorite: (newValue) =>
                                          _toggleFavorite(folder, newValue),
                                    );
                                  },
                                  childCount: folders.length,
                                ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 24)),
                          ],
                        ),
                    );
                  }
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
