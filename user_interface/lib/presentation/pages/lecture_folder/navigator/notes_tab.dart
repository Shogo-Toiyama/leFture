// lib/presentation/pages/lecture_folder/notes_tab.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_breadcrumb_provider.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_folder/lecture_folder_page.dart';

class NotesTab extends ConsumerWidget {
  const NotesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.read(navStateStoreProvider);
    final lastLocation = nav.lastNotesLocation;

    // 1. LastLocationからフォルダIDを抽出
    String? targetFolderId;
    if (lastLocation != null && lastLocation.contains('/f/')) {
      final parts = lastLocation.split('/notes/f/');
      if (parts.length > 1) {
        targetFolderId = parts[1];
      }
    }

    // 2. ターゲットまでの階層データを取得（これが履歴の設計図になります）
    // targetFolderIdがnull(Home)の場合は、空リストなどが返ってくる想定
    final breadcrumbAsync = ref.watch(folderBreadcrumbProvider(targetFolderId));

    return breadcrumbAsync.when(
      // データのロード中はローディングを表示
      // （アプリ起動時の一瞬だけです。これが履歴構築の待ち時間になります）
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // エラー時はとりあえずHomeを表示
      error: (e, s) => _buildNavigator([null]),
      
      data: (crumbs) {
        // 3. スタックを構築するためのIDリストを作成
        // 必ず [Home(null), ...親フォルダたち, ターゲット] という順序にする
        
        final folderIds = <String?>[null]; // 最初は必ずHome

        if (targetFolderId != null) {
          // crumbsにはHomeが含まれていない想定なので、それを追加
          // crumbsが [Parent, Target] の順だと仮定
          for (final crumb in crumbs) {
            folderIds.add(crumb.id);
          }
        }

        return _buildNavigator(folderIds);
      },
    );
  }

  // IDリストからNavigatorを作るヘルパーメソッド
  Widget _buildNavigator(List<String?> folderIds) {
    return Navigator(
      // onGenerateInitialRoutes を使うと、起動時に複数のページを積んだ状態で始められます！
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return folderIds.map((id) {
          return MaterialPageRoute(
            builder: (_) => LectureFolderPage(folderId: id),
            // 設定名は履歴操作で重要なのでしっかり付ける
            settings: RouteSettings(name: id == null ? '/' : 'f/$id'),
          );
        }).toList();
      },
      
      // その後の遷移用
      onGenerateRoute: (settings) {
        Widget page;
        if (settings.name != null && settings.name!.startsWith('f/')) {
          final folderId = settings.name!.replaceFirst('f/', '');
          page = LectureFolderPage(folderId: folderId);
        } else {
          page = const LectureFolderPage(folderId: null);
        }
        return MaterialPageRoute(
          builder: (_) => page,
          settings: settings,
        );
      },
    );
  }
}