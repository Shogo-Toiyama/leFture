import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/router.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/sync/app_lifecycle_sync_watcher.dart';
import 'package:lefture/presentation/pages/dev_tools/dev_log_overlay.dart';
import 'package:lefture/presentation/pages/dev_tools/test_mode_flag.dart';
import 'package:lefture/presentation/themes/app_theme.dart';
import 'package:lefture/presentation/widgets/offline_banner.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // アプリ起動中ずっとバックグラウンド復帰/オンライン復帰を監視させる
    ref.watch(appLifecycleSyncWatcherProvider);

    final router = ref.watch(routerProvider);
    final displayLanguageCode = ref.watch(displayLanguageControllerProvider);

    return MaterialApp.router(
      title: 'leFture',
      theme: AppTheme.main,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: Locale(displayLanguageCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // builder内はDirectionality/Localizations等が既に確立された後なので、
      // DevLogOverlayのStackをここでラップする(MaterialAppの外側で
      // ラップするとDirectionalityが無くエラーになる)。
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        final unfocusedChild = GestureDetector(
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
          },
          behavior: HitTestBehavior.translucent,
          child: child,
        );

        final wrapped = OfflineBanner(child: unfocusedChild);
        return isTestMode ? DevLogOverlay(child: wrapped) : wrapped;
      },
    );
  }
}