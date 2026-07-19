// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:lecture_companion_ui/app/routes.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/supabase_client.dart';
import 'package:lecture_companion_ui/infrastructure/supabase/pending_auth_action.dart';

// Pages
import 'package:lecture_companion_ui/presentation/pages/auth_result/auth_result_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lecture_companion_ui/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lecture_companion_ui/presentation/pages/forgot_password/forgot_password_page.dart';
import 'package:lecture_companion_ui/presentation/pages/reset_password/reset_password_page.dart';
import 'package:lecture_companion_ui/presentation/pages/legal/legal_document_page.dart';
import 'package:lecture_companion_ui/presentation/pages/welcome/welcome_page.dart';
import 'package:lecture_companion_ui/presentation/pages/home/home_page.dart';
import 'package:lecture_companion_ui/presentation/pages/recording/recording_page.dart';
import 'package:lecture_companion_ui/presentation/pages/learning_galaxy/learning_galaxy_page.dart';
import 'package:lecture_companion_ui/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/profile_page.dart';
import 'package:lecture_companion_ui/presentation/pages/contact/contact_page.dart';
import 'package:lecture_companion_ui/presentation/pages/course/course_page.dart';
import 'package:lecture_companion_ui/presentation/pages/lecture_viewer/lecture_viewer_page.dart';
import 'package:lecture_companion_ui/presentation/pages/review_cards/review_cards_dashboard_page.dart';
import 'package:lecture_companion_ui/presentation/pages/review_cards/review_cards_viewer_page.dart';
import 'package:lecture_companion_ui/presentation/pages/deep_notes/deep_notes_list_page.dart';
import 'package:lecture_companion_ui/presentation/pages/deep_notes/deep_notes_detail_page.dart';
import 'package:lecture_companion_ui/presentation/pages/transcript/transcript_page.dart';
import 'package:lecture_companion_ui/presentation/pages/topic_map/topic_map_page.dart';
import 'package:lecture_companion_ui/application/profile/activity_records_provider.dart';
import 'package:lecture_companion_ui/presentation/pages/profile/activity_records_page.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    // ★ 常にHomeからスタート！復元ロジックなし！
    initialLocation: AppRoutes.home,
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(supabase.auth.onAuthStateChange),

    redirect: (context, state) async {
      final uri = state.uri;

      // Supabaseのメール確認/OAuthコールバック(com.lefture.app://login-callback/,
      // lefture://reset-password)はdetectSessionInUriが既にセッション処理を済ませている。
      // go_routerはこの完全なURI文字列をそのままロケーションとして受け取ってしまい、
      // 対応するGoRouteが無いため GoException: no routes for location で落ちる。
      // ルートマッチングされる前にここで横取りして、適切な画面へ逃がす。

      // パスワードリセット(recovery)専用スキーム: 実際のパスワード入力は
      // ResetPasswordPage で行うので、そちらへ誘導する。エラー時はクエリ経由で伝える。
      if (uri.scheme == 'lefture') {
        final fragmentParams = uri.fragment.isNotEmpty
            ? Uri.splitQueryString(uri.fragment)
            : const <String, String>{};
        final errorText = fragmentParams['error_description'];
        return errorText != null
            ? '${AppRoutes.resetPassword}?error=${Uri.encodeComponent(errorText)}'
            : AppRoutes.resetPassword;
      }

      if (uri.scheme == 'com.lefture.app') {
        final fragmentParams = uri.fragment.isNotEmpty
            ? Uri.splitQueryString(uri.fragment)
            : const <String, String>{};
        final errorText =
            fragmentParams['error_description']?.replaceAll('+', ' ');
        final messageText = fragmentParams['message']?.replaceAll('+', ' ');

        // どの操作を待っていたコールバックかは、読み取りと同時に必ず消費する
        // (残り続けると後続の無関係なコールバックを誤判定するため)。
        final pending = await consumePendingAuthAction();

        String? resultLocation;

        if (errorText != null) {
          switch (pending?.kind) {
            case PendingAuthActionKind.emailChange:
              resultLocation =
                  '${AppRoutes.authResult}?kind=email_change_error&detail=${Uri.encodeComponent(errorText)}';
            case PendingAuthActionKind.providerLink:
              resultLocation =
                  '${AppRoutes.authResult}?kind=provider_link_error&detail=${Uri.encodeComponent(errorText)}';
            case null:
              // 通常のサインイン等、追跡対象外のエラーは従来どおりSnackBarのみ。
              _showRootSnackBar(errorText);
          }
        } else if (messageText != null) {
          // Secure Email Change: 1通目の確認完了。もう一方の確認を促す案内。
          resultLocation =
              '${AppRoutes.authResult}?kind=email_change_pending&detail=${Uri.encodeComponent(messageText)}';
        } else if (fragmentParams['type'] == 'email_change') {
          // Secure Email Change: 2通目の確認でメール変更が確定した完了コールバック。
          // 完了セッションがローカルに反映されず currentUser が古いままになる
          // ケースがあるため、refreshSession で最新化してから完了画面へ渡す。
          try {
            await supabase.auth.refreshSession();
          } catch (_) {
            // リフレッシュ失敗は致命的ではないため握りつぶす
          }
          final email = supabase.auth.currentUser?.email ?? '';
          resultLocation =
              '${AppRoutes.authResult}?kind=email_changed&detail=${Uri.encodeComponent(email)}';
        } else if (pending?.kind == PendingAuthActionKind.providerLink) {
          // ログイン方法(OAuthプロバイダー)連携の完了コールバック。
          // このコールバック自体にはリンク操作だという印が無いため、
          // 直前に保存しておいたpendingマーカーだけが判断材料になる。
          resultLocation =
              '${AppRoutes.authResult}?kind=provider_linked&detail=${Uri.encodeComponent(pending!.detail)}';
        }

        if (resultLocation != null) return resultLocation;

        return supabase.auth.currentSession != null
            ? AppRoutes.home
            : AppRoutes.signIn;
      }

      final session = supabase.auth.currentSession;
      final path = state.uri.path;

      // Auth関連のパスかどうか（ログイン済みならホームへ飛ばす対象）
      final isAuthRoute = path == AppRoutes.welcome ||
          path == AppRoutes.signIn ||
          path == AppRoutes.signUp ||
          path == AppRoutes.forgotPassword ||
          path == AppRoutes.resetPassword;

      // ログイン状態に関わらず見られるページ（例: サインアップ画面やプロフィール画面からのリンク、
      // アカウント削除完了画面はセッションが既に無い状態で表示するため公開扱いが必要）
      final isPublicRoute = isAuthRoute ||
          path == AppRoutes.privacyPolicy ||
          path == AppRoutes.termsOfService ||
          path == AppRoutes.accountDeleted;

      // 1. 未ログインならサインインへ強制移動
      if (session == null && !isPublicRoute) return AppRoutes.signIn;
      
      // 2. ログイン済みなのにAuth画面に来たらホームへ飛ばす（ただしパスワード再設定画面は除く）
      if (session != null && isAuthRoute && path != AppRoutes.resetPassword) {
        return AppRoutes.home;
      }

      // ★ 保存ロジックも削除しました。シンプル！
      return null;
    },

    // go_routerの標準エラー画面は「Home」ボタンが常に '/' へ遷移するが、
    // このアプリの実際のホームは '/home' で '/' 自体にはルートが無いため、
    // 未定義のルートを踏むと同じエラー画面に戻り続ける無限ループになる。
    // ボタンの遷移先を実際のホームルートに固定する。
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ページが見つかりませんでした'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go(AppRoutes.home),
              child: const Text('ホームに戻る'),
            ),
          ],
        ),
      ),
    ),

    routes: [
      // =================================================================
      // Auth Routes
      // =================================================================
      GoRoute(path: AppRoutes.welcome, builder: (context, state) => const WelcomePage()),
      GoRoute(path: AppRoutes.signIn, builder: (context, state) => const SignInPage()),
      GoRoute(path: AppRoutes.signUp, builder: (context, state) => const SignUpPage()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (context, state) => const ForgotPasswordPage()),
      GoRoute(path: AppRoutes.resetPassword, builder: (context, state) => const ResetPasswordPage()),
      GoRoute(
        path: AppRoutes.authResult,
        builder: (context, state) => AuthResultPage(
          kind: state.uri.queryParameters['kind'] ?? '',
          detail: state.uri.queryParameters['detail'],
        ),
      ),
      GoRoute(
        path: AppRoutes.accountDeleted,
        builder: (context, state) => const AuthResultPage(kind: 'account_deleted'),
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        builder: (context, state) => const LegalDocumentPage(
          slug: 'privacy_policy',
          fallbackTitle: 'Privacy Policy',
        ),
      ),
      GoRoute(
        path: AppRoutes.termsOfService,
        builder: (context, state) => const LegalDocumentPage(
          slug: 'terms_of_service',
          fallbackTitle: 'Terms of Service',
        ),
      ),

      // =================================================================
      // Main Routes (Single Stack)
      // =================================================================
      
      // 1. Home (Dashboard) - 宇宙のコックピット
      // 1. Home (Dashboard) - 宇宙のコックピット
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomePage(),
        routes: [
          // 2. Courses System (Nested under /home)
          GoRoute(
            path: AppRoutes.coursesRoot, // 'courses' -> /home/courses
            builder: (context, state) => const CoursePage(),
            routes: [
              // コース内: /home/notes/c/:courseId
              GoRoute(
                path: AppRoutes.noteCourse, // 'c/:courseId' -> /home/notes/c/:courseId
                builder: (context, state) {
                  final id = state.pathParameters['courseId'];
                  return CoursePage(courseId: id);
                },
                routes: [
                  // 授業ビューワー: /home/notes/c/:courseId/v/:lectureId
                  GoRoute(
                    path: AppRoutes.noteViewer, // 'v/:lectureId' -> /home/notes/c/:courseId/v/:lectureId
                    builder: (context, state) {
                      final id = state.pathParameters['lectureId'];
                      return LectureViewerPage(lectureId: id!);
                    },
                    routes: [
                      // Transcript: /home/notes/c/:courseId/v/:lectureId/transcript
                      GoRoute(
                        path: AppRoutes.transcript, // 'transcript'
                        builder: (context, state) {
                          final id = state.pathParameters['lectureId']!;
                          final startSid = state.uri.queryParameters['start_sid'];
                          final endSid = state.uri.queryParameters['end_sid'];
                          final highlightSidsStr = state.uri.queryParameters['highlight_sids'];
                          final highlightSids = highlightSidsStr?.split(',');
                          return TranscriptPage(
                            lectureId: id,
                            startSid: startSid,
                            endSid: endSid,
                            highlightSids: highlightSids,
                          );
                        },
                      ),
                    ],
                  ),

                  // Review Cards: /home/notes/c/:courseId/rc/:lectureId
                  GoRoute(
                    path: AppRoutes.reviewCardsDashboard, // 'rc/:lectureId'
                    builder: (context, state) {
                      final id = state.pathParameters['lectureId']!;
                      return ReviewCardsDashboardPage(lectureId: id);
                    },
                  ),

                  // Review Cards Viewer: /home/notes/c/:courseId/rcv/:lectureId
                  GoRoute(
                    path: AppRoutes.reviewCardsViewer, // 'rcv/:lectureId'
                    builder: (context, state) {
                      final id = state.pathParameters['lectureId']!;
                      final indexStr = state.uri.queryParameters['index'];
                      final initialIndex = indexStr != null ? int.tryParse(indexStr) : null;
                      return ReviewCardsViewerPage(
                        lectureId: id,
                        initialIndex: initialIndex ?? 0,
                      );
                    },
                  ),

                  // Deep Notes List: /home/notes/c/:courseId/dn/:lectureId
                  GoRoute(
                    path: AppRoutes.deepNotesList, // 'dn/:lectureId'
                    builder: (context, state) {
                      final id = state.pathParameters['lectureId']!;
                      return DeepNotesListPage(lectureId: id);
                    },
                  ),

                  // Deep Notes Detail: /home/notes/c/:courseId/dnd/:topicIndex
                  GoRoute(
                    path: AppRoutes.deepNotesDetail, // 'dnd/:lectureId/:topicIndex'
                    builder: (context, state) {
                      final id    = state.pathParameters['lectureId']!;
                      final index = int.tryParse(
                              state.pathParameters['topicIndex'] ?? '0') ??
                          0;
                      final topics =
                          (state.extra as List<DeepNoteTopic>?) ?? const [];
                      return DeepNotesDetailPage(
                        lectureId: id,
                        topicIndex: index,
                        topics: topics,
                      );
                    },
                  ),



                  // Topic Map: /home/notes/c/:courseId/topic-map
                  GoRoute(
                    path: AppRoutes.topicMap, // 'topic-map'
                    builder: (context, state) {
                      final id = state.pathParameters['courseId']!;
                      return TopicMapPage(courseId: id);
                    },
                  ),
                ],
              ),
            ],
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
        path: AppRoutes.contact,
        builder: (context, state) => const ContactPage(),
      ),
      GoRoute(
        path: AppRoutes.activityDetails,
        builder: (context, state) {
          final typeStr = state.pathParameters['type'] ?? 'saved';
          final type = ActivityType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => ActivityType.saved,
          );
          return ActivityRecordsPage(type: type);
        },
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
          final initialCourseId = state.uri.queryParameters['courseId'];
          
          return MaterialPage(
            fullscreenDialog: true, // これで下から出てくるモーダルになります
            child: RecordingPage(
              initialTab: initialTab,
              initialCourseId: initialCourseId,
            ),
          );
        },
      ),
    ],
  );
});

/// ルートNavigatorのcontext経由でSnackBarを表示する。
/// redirect内から呼ばれるため、フレーム描画後に実行する。
void _showRootSnackBar(String text) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = _rootKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(text)));
    }
  });
}


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