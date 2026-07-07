// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

// Pages
import 'package:lecture_companion_ui/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lecture_companion_ui/presentation/pages/welcome/welcome_page.dart';
import 'package:lecture_companion_ui/presentation/pages/home/home_page.dart';
import 'package:lecture_companion_ui/presentation/pages/recording/recording_page.dart';
import 'package:lecture_companion_ui/presentation/pages/learning_galaxy/learning_galaxy_page.dart';
import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/profile_page.dart';
import 'package:lecture_companion_ui/presentation/pages/course/course_page.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/lecture_viewer_page.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    // ★ 常にHomeからスタート！復元ロジックなし！
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),

    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final path = state.uri.path;

      // Auth関連のパスかどうか
      final isAuthRoute = path == AppRoutes.welcome ||
          path == AppRoutes.signIn ||
          path == AppRoutes.signUp;

      // 1. 未ログインならサインインへ強制移動
      if (session == null && !isAuthRoute) return AppRoutes.signIn;
      
      // 2. ログイン済みなのにAuth画面に来たらホームへ飛ばす
      if (session != null && isAuthRoute) return AppRoutes.home;

      // ★ 保存ロジックも削除しました。シンプル！
      return null;
    },

    routes: [
      // =================================================================
      // Auth Routes
      // =================================================================
      GoRoute(path: AppRoutes.welcome, builder: (context, state) => const WelcomePage()),
      GoRoute(path: AppRoutes.signIn, builder: (context, state) => const SignInPage()),
      GoRoute(path: AppRoutes.signUp, builder: (context, state) => const SignUpPage()),

      // =================================================================
      // Main Routes (Single Stack)
      // =================================================================
      
      // 1. Home (Dashboard) - 宇宙のコックピット
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
      ),

      // 2. Notes System
      GoRoute(
        path: AppRoutes.notesRoot,
        builder: (context, state) => const CoursePage(),
        routes: [
          // コース内: /notes/c/:courseId
          GoRoute(
            path: AppRoutes.noteCourse,
            builder: (context, state) {
              final id = state.pathParameters['courseId'];
              return CoursePage(courseId: id);
            },
          ),
          // 授業ビューワー: /notes/v/:lectureId
          GoRoute(
            path: AppRoutes.noteViewer,
            builder: (context, state) {
              final id = state.pathParameters['lectureId'];
              return LectureViewerPage(lectureId: id!);
            },
          ),
        ],
      ),

      // 3. Features
      GoRoute(
        path: AppRoutes.aiChat,
        builder: (context, state) => const AiChatPage(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: AppRoutes.learningGalaxy,
        pageBuilder: (context, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const LearningGalaxyPage(),
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        ),
      ),
      
      // =================================================================
      // Modals (Fullscreen)
      // =================================================================
      GoRoute(
        path: AppRoutes.recording,
        parentNavigatorKey: _rootKey,
        pageBuilder: (context, state) {
          // ★ クエリパラメータを受け取る例
          // /recording?tab=note で呼ばれたら、Noteタブを開くように渡す
          final initialTab = state.uri.queryParameters['tab'];
          
          return MaterialPage(
            fullscreenDialog: true, // これで下から出てくるモーダルになります
            child: RecordingPage(initialTab: initialTab),
          );
        },
      ),
    ],
  );
});

/// 認証状態の監視用（変更なし）
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}