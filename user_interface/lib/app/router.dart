// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';

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
      if (session != null && isAuthRoute) return AppRoutes.home;

      return null;
    },

    routes: [
      // 1. ログイン前
      GoRoute(path: AppRoutes.welcome, builder: (_, _) => const WelcomePage()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInPage()),
      GoRoute(path: AppRoutes.signUp, builder: (_, _) => const SignUpPage()),

      GoRoute(
        path: AppRoutes.home, 
        builder: (context, state) => const MainLayout(), // childを渡さない
        routes: [
           // MainLayoutの上に乗っかる詳細ページなどはここに定義してもOK
           // GoRoute(path: 'detail', builder: ...),
        ]
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
