// lib/presentation/pages/lecture_folder/lecture_folder_page.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../application/lecture_folders/lecture_folder_providers.dart';
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
  List<LectureFolder> folders = [];

  // パンくず: Home -> A -> B ...
  final List<_Crumb> crumbs = [const _Crumb(id: null, name: 'Home')];

  String? get currentFolderId => crumbs.last.id;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => loading = true);
    try {
      final repo = ref.read(folderRepositoryProvider);
      final data = (currentFolderId == null)
          ? await repo.listRootFolders()
          : await repo.listChildren(parentId: currentFolderId!);

      setState(() => folders = data);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // フォルダに入る
  Future<void> _enterFolder(LectureFolder folder) async {
    setState(() {
      crumbs.add(_Crumb(id: folder.id, name: folder.name));
    });
    await _loadFolders();
  }

  // パンくず移動
  Future<void> _goToCrumbIndex(int index) async {
    if (index < 0 || index >= crumbs.length) return;
    setState(() {
      crumbs.removeRange(index + 1, crumbs.length);
    });
    await _loadFolders();
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
      final repo = ref.read(folderRepositoryProvider);
      final created = await repo.createFolder(
        name: name.trim(),
        parentId: currentFolderId,
        type: 'binder',
      );
      setState(() => folders = [created, ...folders]);
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
      final repo = ref.read(folderRepositoryProvider);
      await repo.renameFolder(folderId: folder.id, newName: trimmed);

      setState(() {
        folders = folders
            .map((f) => f.id == folder.id ? f.copyWith(name: trimmed) : f)
            .toList();
      });
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
      final repo = ref.read(folderRepositoryProvider);
      await repo.softDeleteFolder(folderId: folder.id);
      setState(() => folders = folders.where((f) => f.id != folder.id).toList());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _toggleFavorite(LectureFolder folder, bool newValue) async {
  setState(() => loading = true);
  try {
    final repo = ref.read(folderRepositoryProvider);

    // Repoに toggleFavorite がある想定（後で追加する）
    await repo.setFavorite(folderId: folder.id, isFavorite: newValue);

    setState(() {
      folders = folders
          .map((f) => f.id == folder.id ? f.copyWith(isFavorite: newValue) : f)
          .toList();
    });
  } finally {
    if (mounted) setState(() => loading = false);
  }
}

int _calcCrossAxisCount(double width) {
  const minTileWidth = 140.0;
  final count = (width / minTileWidth).floor();
  return count;
}

  Future<void> _showFolderMenu({
    required LectureFolder folder,
    required Offset globalPosition,
  }) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );

    if (selected == 'rename') {
      await _renameFolder(folder);
    } else if (selected == 'delete') {
      await _deleteFolder(folder);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

                return RefreshIndicator(
                  onRefresh: _loadFolders,
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
              },
            ),
          ),
        ],
      ),
    );
  }
}
