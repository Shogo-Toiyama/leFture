import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lefture/app/router.dart';
import 'package:lefture/l10n/generated/app_localizations.dart';
import 'package:lefture/application/profile/display_language_controller.dart';
import 'package:lefture/application/recording/upload_manager.dart';
import 'package:lefture/application/sync/app_lifecycle_sync_watcher.dart';
import 'package:lefture/application/tutorial/tutorial_lecture_seed_provider.dart';
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

    // ★ UploadManagerはkeepAlive:trueだが、誰かがこのProviderをwatch/readする
    // までRiverpodはインスタンス自体を作らない(=initialize()内の接続監視・
    // DB監視リスナーが一切登録されない)。以前は録音/アップロード操作を
    // 実際に行った時(recording_controller.dartの遅延getter)だけ間接的に
    // 生成されていたため、「講義を見るだけで録音はしていないセッション」では
    // UploadManagerが一度も起動せず、保留中のアップロードジョブが接続復帰
    // イベントを受け取れず永久に再試行されないバグになっていた。
    // アプリ起動と同時に必ず生成されるよう、ここで明示的にwatchしておく。
    ref.watch(uploadManagerProvider);

    // 起動時に一度だけ、ローカルのみのチュートリアル講義をシード(既にあれば何もしない)。
    // EmptyHomeContentの代わりに、ログイン中であれば常に最低1件の講義が手元に
    // ある状態を保証する。ここでwatchしない場合、この処理自体がどこからも
    // トリガーされない(uploadManagerProviderと同じ理由)。
    ref.watch(tutorialLectureSeedProvider);

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