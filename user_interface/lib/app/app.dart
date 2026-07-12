import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lecture_companion_ui/app/router.dart';
import 'package:lecture_companion_ui/application/sync/app_lifecycle_sync_watcher.dart';
import 'package:lecture_companion_ui/presentation/pages/dev_tools/dev_log_overlay.dart';
import 'package:lecture_companion_ui/presentation/pages/dev_tools/test_mode_flag.dart';
import 'package:lecture_companion_ui/presentation/themes/app_theme.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // アプリ起動中ずっとバックグラウンド復帰/オンライン復帰を監視させる
    ref.watch(appLifecycleSyncWatcherProvider);

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'leFture',
      theme: AppTheme.main,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // builder内はDirectionality/Localizations等が既に確立された後なので、
      // DevLogOverlayのStackをここでラップする(MaterialAppの外側で
      // ラップするとDirectionalityが無くエラーになる)。
      builder: (context, child) {
        if (isTestMode && child != null) {
          return DevLogOverlay(child: child);
        }
        return child!;
      },
    );
  }
}