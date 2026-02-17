import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/application/lecture_folders/folder_breadcrumb_provider.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_folder/lecture_folder_page.dart';
import 'dart:developer' as dev; // ログ用

class NotesTab extends HookConsumerWidget {
  const NotesTab({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. 履歴の復元ロジック
    final navigatorKey = useMemoized(() => GlobalKey<NavigatorState>());
    final initialRoutesFuture = useMemoized(() async {
      // dev.log('🔍 [NotesTab] History restoration started...');
      dev.log('🏗️ [NotesTab] Build. isActive: $isActive');
      
      // Storeの読み込みを少し待つ（SharedPreferencesの初期化待ち対策）
      // 本来は NavStateStore 側で await init() するのがベストですが、
      // ここでは簡易的に現在の値を取得します。
      final nav = ref.read(navStateStoreProvider);
      final lastLocation = nav.lastNotesLocation;

      // dev.log('📍 [NotesTab] Loaded lastLocation: $lastLocation');

      // A. Homeの場合
      if (lastLocation == null || !lastLocation.contains('/f/')) {
        // dev.log('🏠 [NotesTab] Decided: Start at HOME');
        return [null]; 
      }

      // B. フォルダの場合
      final parts = lastLocation.split('/notes/f/');
      if (parts.length <= 1) {
        return [null];
      }
      
      final targetFolderId = parts[1];
      // dev.log('📂 [NotesTab] Target Folder ID: $targetFolderId');

      try {
        final crumbs = await ref.read(folderBreadcrumbProvider(targetFolderId).future);
        
        final folderIds = <String?>[null];
        for (final crumb in crumbs) {
          folderIds.add(crumb.id);
        }
        
        // dev.log('✅ [NotesTab] Stack constructed: $folderIds');
        return folderIds;
      } catch (e) {
        // dev.log('⚠️ [NotesTab] Error building stack: $e');
        return [null];
      }
    });

    final snapshot = useFuture(initialRoutesFuture);

    // 2. まだ履歴計算中なら、変な画面を出さずに待つ！
    if (snapshot.connectionState == ConnectionState.waiting) {
      // dev.log('⏳ [NotesTab] Waiting for history...');
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final initialFolderIds = snapshot.data ?? [null];

    // 3. Navigator構築
    return PopScope(
      canPop: true, 
      onPopInvokedWithResult: (didPop, result) {
        
        final nav = navigatorKey.currentState;
        final canPopNav = nav?.canPop() ?? false;
        
        if (isActive) {
           if (canPopNav) {
             dev.log('   -> 内部NavigatorをPopします');
             nav?.pop();
           }
        }
      },
      child: Navigator(
      key: navigatorKey, // ★ ここに鍵をセットするのを忘れずに！
      onGenerateInitialRoutes: (navigator, initialRoute) {
        return initialFolderIds.map((id) {
          return MaterialPageRoute(
            builder: (_) => LectureFolderPage(folderId: id),
            settings: RouteSettings(name: id == null ? '/' : 'f/$id'),
          );
        }).toList();
      },
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
      },),
    );
  }
}