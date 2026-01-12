import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    // ★ ダブルタップ判定用に「最後にタップした時間」を記録する変数
    // useStateだと再描画が走ってしまうので、裏で値を持つだけの useRef が最適です
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
      return browseChainAsync.when(
        loading: () => BreadcrumbBar(
            crumbs: const ['Home'],
            onTapCrumb: (_) {
              browseId.value = null;
              selectedId.value = null;
              log('Home tapped');
            }),
        error: (_, __) => BreadcrumbBar(
            crumbs: const ['Home'],
            onTapCrumb: (_) {
              browseId.value = null;
              selectedId.value = null;
            }),
        data: (chain) {
          final labels = <String>['Home', ...chain.map((r) => r.name)];
          final ids = <String?>[null, ...chain.map((r) => r.id)];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BreadcrumbBar(
                  crumbs: labels,
                  onTapCrumb: (index) {
                    browseId.value = ids[index];
                    selectedId.value = ids[index];
                    log('Breadcrumb tapped: ${labels[index]}');
                  }),
            ],
          );
        },
      );
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Select folder',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context)
                        .pop(FolderPickerResult.cancelled),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildBreadcrumb(),
            ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: foldersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (folders) {
                  return ListView(
                    children: [
                      ...folders.map((f) {
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(f.name),
                          selected: selectedId.value == f.id,
                          // ★ ここで自前ダブルタップ判定
                          onTap: () {
                            final now = DateTime.now();
                            final lastTime = lastTapTime.value;
                            
                            // 「選択中のIDと同じ」かつ「前回タップから500ms以内」ならダブルタップとみなす
                            if (selectedId.value == f.id &&
                                lastTime != null &&
                                now.difference(lastTime) < const Duration(milliseconds: 500)) {
                              
                              // ダブルタップ成立：潜る
                              browseId.value = f.id;
                              selectedId.value = f.id; 
                              lastTapTime.value = null; // リセット
                              log('Double tap detected: Entering ${f.name}');
                              
                            } else {
                              // シングルタップ（または間隔が空いた）：即座に選択
                              selectedId.value = f.id;
                              lastTapTime.value = now; // 時間を記録
                            }
                          },
                          trailing: IconButton(
                              tooltip: 'Enter',
                              icon: const Icon(Icons.chevron_right),
                              onPressed: () {
                                selectedId.value = f.id;
                                browseId.value = f.id;
                              }),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),

            const Divider(height: 1),

            // Footer buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .pop(FolderPickerResult.cancelled),
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
                        log('Select confirmed: ${selectedId.value}');
                      },
                      child: const Text('Select'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}