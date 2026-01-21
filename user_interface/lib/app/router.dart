// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/application/navigation/nav_state_store.dart';

import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/dashboard/dashboard_page.dart';
import 'package:lecture_companion_ui/presentation/pages/goal_tree/goal_tree_page.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_folder/lecture_folder_page.dart';
import 'package:lecture_companion_ui/presentation/pages/note_detail/note_detail_page.dart';
import 'package:lecture_companion_ui/presentation/pages/plan/plan_page.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/profile_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lecture_companion_ui/presentation/pages/welcome/welcome_page.dart';
import 'package:lecture_companion_ui/presentation/widgets/layouts/main_layout.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');
final routerProvider = Provider<GoRouter>((ref) {
  final nav = ref.read(navStateStoreProvider);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.welcome,
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),

    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final path = state.uri.path;

      // 未ログインなら sign-in へ
      if (!isLoggedIn &&
          path != AppRoutes.signIn &&
          path != AppRoutes.signUp &&
          path != AppRoutes.welcome) {
        return AppRoutes.signIn;
      }

      // ログイン済みなら welcome/signin/signup を dashboard へ
      if (isLoggedIn &&
          (path == AppRoutes.signIn ||
              path == AppRoutes.signUp ||
              path == AppRoutes.welcome)) {
        return AppRoutes.dashboard;
      }

      return null;
    },

    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: AppRoutes.plans,
        builder: (context, state) => const PlanPage(),
      ),

      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) {
          return MainLayout(currentPath: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            builder: (context, state) => const DashboardPage(),
          ),

          GoRoute(
            path: AppRoutes.notesEntry,
            builder: (context, state) => const SizedBox.shrink(), // ここは必ずredirectされる想定
            redirect: (context, state) {
              final last = nav.lastNotesLocation;
              if (last == null || last.isEmpty || last == AppRoutes.notesEntry || last == '/notes/home') return AppRoutes.notesHome;
              return last;
            },
          ),

          GoRoute(
            path: AppRoutes.notesHome,
            builder: (context, state) => const LectureFolderPage(folderId: null),
            routes: [
              GoRoute(
                path: 'f/:folderId',
                builder: (context, state) {
                  final folderId = state.pathParameters['folderId'];
                  return LectureFolderPage(folderId: folderId);
                },
              ),
            ],
          ),

          GoRoute(
            path: AppRoutes.aiChat,
            builder: (context, state) => const AiChatPage(),
          ),
          GoRoute(
            path: AppRoutes.goalTree,
            builder: (context, state) => const GoalTreePage(),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.noteDetail,
        builder: (context, state) => const NoteDetailPage(),
      ),
    ],
  );
});

/// Supabase auth stream → GoRouterのrefreshに使う
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
