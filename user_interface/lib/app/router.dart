import 'package:go_router/go_router.dart';
import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/goal_tree/goal_tree_page.dart';
import 'package:lecture_companion_ui/presentation/pages/dashboard/dashboard_page.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_folder/lecture_folder_page.dart';
import 'package:lecture_companion_ui/presentation/pages/note_detail/note_detail_page.dart';
import 'package:lecture_companion_ui/presentation/pages/plan/plan_page.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/profile_page.dart';
import 'package:lecture_companion_ui/presentation/pages/recording/recording_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lecture_companion_ui/presentation/pages/welcome/welcome_page.dart';
import 'package:lecture_companion_ui/presentation/widgets/layouts/main_layout.dart';

final router = GoRouter(
  initialLocation: AppRoutes.welcome,
  debugLogDiagnostics: true,

  redirect: (context, state) {
    final session = supabase.auth.currentSession;
    final isLoggedIn = session != null;

    final path = state.uri.path;

    if (isLoggedIn && (path == AppRoutes.signIn || path == AppRoutes.signUp || path == AppRoutes.welcome)) {
      return AppRoutes.dashboard;
    }

    if (!isLoggedIn && path != AppRoutes.signIn && path != AppRoutes.signUp && path != AppRoutes.welcome) {
      return AppRoutes.signIn;
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
      builder: (context, state, child) {
        return MainLayout(currentPath: state.uri.path, child: child);
      },

      routes: [
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) => const DashboardPage(),
        ),

        GoRoute(
          path: AppRoutes.lectureFolder,
          builder: (context, state) => const LectureFolderPage(),
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
      path: AppRoutes.recording,
      builder: (context, state) => const RecordingPage(),
    ),

    GoRoute(
      path: AppRoutes.noteDetail,
      builder: (context, state) => const NoteDetailPage(),
    ),

  ],
);