// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/note_detail/note_detail_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lecture_companion_ui/presentation/pages/welcome/welcome_page.dart';
import 'package:lecture_companion_ui/presentation/widgets/layouts/main_layout.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.welcome,
    debugLogDiagnostics: true, 
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),

    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final path = state.uri.path;
      final isAuthRoute = path == AppRoutes.welcome || path == AppRoutes.signIn || path == AppRoutes.signUp;
      
      if (session == null && !isAuthRoute) return AppRoutes.signIn;
      if (session != null && isAuthRoute && path != AppRoutes.welcome) return AppRoutes.home;

      return null;
    },

    routes: [
      // 1. ログイン前
      GoRoute(path: AppRoutes.welcome, builder: (_, __) => const WelcomePage()),
      GoRoute(path: AppRoutes.signIn, builder: (_, __) => const SignInPage()),
      GoRoute(path: AppRoutes.signUp, builder: (_, __) => const SignUpPage()),

      // 2. ログイン後（ここを単純化！）
      // ShellRouteをやめて、単一の「ホーム画面」にする
      GoRoute(
        path: AppRoutes.home, 
        builder: (context, state) => const MainLayout(), // childを渡さない
        routes: [
           // MainLayoutの上に乗っかる詳細ページなどはここに定義してもOK
           // GoRoute(path: 'detail', builder: ...),
        ]
      ),

      // 3. 全画面系（BottomNavを隠したいやつ）
      GoRoute(
        path: AppRoutes.noteDetail,
        builder: (_, __) => const NoteDetailPage(),
      ),
      GoRoute(
        path: AppRoutes.aiChat,
        builder: (_, __) => const AiChatPage(),
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
