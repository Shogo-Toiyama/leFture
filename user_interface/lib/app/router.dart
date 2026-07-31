// lib/app/router.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lefture/app/routes.dart';
import 'package:lefture/application/auth/auth_provider.dart';
import 'package:lefture/core/services/recording_preferences.dart';
import 'package:lefture/core/utils/dev_log.dart';
import 'package:lefture/infrastructure/supabase/supabase_client.dart';
import 'package:lefture/infrastructure/supabase/pending_auth_action.dart';

// Pages
import 'package:lefture/presentation/pages/auth_result/auth_result_page.dart';
import 'package:lefture/presentation/pages/introduction/introduction_page.dart';
import 'package:lefture/presentation/pages/sign_in/sign_in_page.dart';
import 'package:lefture/presentation/pages/sign_up/sign_up_page.dart';
import 'package:lefture/presentation/pages/forgot_password/forgot_password_page.dart';
import 'package:lefture/presentation/pages/reset_password/reset_password_page.dart';
import 'package:lefture/presentation/pages/legal/legal_document_page.dart';
import 'package:lefture/presentation/pages/welcome/welcome_page.dart';
import 'package:lefture/presentation/pages/onboarding/onboarding_page.dart';
import 'package:lefture/presentation/pages/home/home_page.dart';
import 'package:lefture/presentation/pages/recording/recording_page.dart';
import 'package:lefture/presentation/pages/learning_galaxy/learning_galaxy_page.dart';
import 'package:lefture/presentation/pages/ai_chat/ai_chat_page.dart';
import 'package:lefture/presentation/pages/profile/my_account_page.dart';
import 'package:lefture/presentation/pages/profile/credit_detail_page.dart';
import 'package:lefture/presentation/pages/profile/plans_page.dart';
import 'package:lefture/presentation/pages/profile/user_profile_detail_page.dart';
import 'package:lefture/presentation/pages/contact/contact_page.dart';
import 'package:lefture/presentation/pages/profile/permissions_settings_page.dart';
import 'package:lefture/presentation/pages/course/course_page.dart';
import 'package:lefture/presentation/pages/lecture_viewer/lecture_viewer_page.dart';
import 'package:lefture/presentation/pages/review_cards/review_cards_dashboard_page.dart';
import 'package:lefture/presentation/pages/review_cards/review_cards_viewer_page.dart';
import 'package:lefture/presentation/pages/deep_notes/deep_notes_list_page.dart';
import 'package:lefture/presentation/pages/deep_notes/deep_notes_detail_page.dart';
import 'package:lefture/presentation/pages/transcript/transcript_page.dart';
import 'package:lefture/presentation/pages/topic_map/topic_map_page.dart';
import 'package:lefture/application/profile/activity_records_provider.dart';
import 'package:lefture/infrastructure/supabase/repositories/user_profile_repository_supabase.dart';
import 'package:lefture/presentation/pages/profile/activity_records_page.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Welcomeのタイトル演出からそのまま繋がるように、既定のプラットフォーム
/// 遷移(スライド等)ではなくフェードで入ってくるページ。
CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 420),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(supabase.auth.onAuthStateChange);

  return GoRouter(
    navigatorKey: _rootKey,
    // ★ 常にWelcome(タイトル演出)からスタート！復元ロジックなし！
    // WelcomePageはアニメーション再生後に自分でAppRoutes.homeへgo()し、
    // そこで改めてredirectがログイン状態を見て本当の行き先を決める。
    initialLocation: AppRoutes.welcome,
    debugLogDiagnostics: true,
    refreshListenable: refreshStream,

    redirect: (context, state) async {
      final uri = state.uri;

      // パスワードリカバリーの完了は、redirect_toが実際にどのスキームに
      // なったか(lefture://reset-password が期待値だが、SupabaseのRedirect
      // URLs許可リストに登録漏れがあるとSite URL経由でcom.lefture.app://の
      // 方に飛んでくる)、PKCE/implicitどちらのフロー形式か、に一切左右されない
      // SDK自身のイベント(AuthChangeEvent.passwordRecovery)で判定する。
      // これがURL側の解析より確実なので、他のどの分岐よりも先に見る。
      if (refreshStream.consumePasswordRecoveryFlag()) {
        DevLog.add('[AuthCallback] passwordRecovery event -> resetPassword');
        return AppRoutes.resetPassword;
      }

      // Supabaseのメール確認/OAuthコールバック(com.lefture.app://login-callback/,
      // lefture://reset-password)はdetectSessionInUriが既にセッション処理を済ませている。
      // go_routerはこの完全なURI文字列をそのままロケーションとして受け取ってしまい、
      // 対応するGoRouteが無いため GoException: no routes for location で落ちる。
      // ルートマッチングされる前にここで横取りして、適切な画面へ逃がす。

      // パスワードリセット(recovery)専用スキーム: 実際のパスワード入力は
      // ResetPasswordPage で行うので、そちらへ誘導する。エラー時はクエリ経由で伝える。
      // (redirect_toが正しく登録されていれば、上のイベント判定より前にここへ来ることもある)
      if (uri.scheme == 'lefture') {
        return refreshStream.resolveAuthCallbackOnce(uri.toString(), () async {
          _logAuthCallback(uri);
          final errorText = _mergedCallbackParams(uri)['error_description'];
          final target = errorText != null
              ? '${AppRoutes.resetPassword}?error=${Uri.encodeComponent(errorText)}'
              : AppRoutes.resetPassword;
          DevLog.add('[AuthCallback] lefture scheme -> $target');
          return target;
        });
      }

      if (uri.scheme == 'com.lefture.app') {
        return refreshStream.resolveAuthCallbackOnce(uri.toString(), () async {
          _logAuthCallback(uri);
          // OAuth(PKCE)のエラーはクエリ側(?error=...)に、メール確認(implicit)の
          // エラー/メッセージはフラグメント側(#error=...)に来るため、両方を
          // マージして判定する(片方しか見ないとOAuthキャンセルを取りこぼす)。
          final params = _mergedCallbackParams(uri);
          final errorText = params['error_description']?.replaceAll('+', ' ');
          final messageText = params['message']?.replaceAll('+', ' ');

          // どの操作を待っていたコールバックかは、読み取りと同時に必ず消費する
          // (残り続けると後続の無関係なコールバックを誤判定するため)。
          final pending = await consumePendingAuthAction();
          DevLog.add(
            '[AuthCallback] pending='
            '${pending == null ? 'none' : '${pending.kind.name}(${pending.detail})'}',
          );

          String? resultLocation;

          if (errorText != null) {
            DevLog.add('[AuthCallback] error branch: $errorText');
            switch (pending?.kind) {
              case PendingAuthActionKind.emailChange:
                resultLocation =
                    '${AppRoutes.authResult}?kind=email_change_error&detail=${Uri.encodeComponent(errorText)}';
              case PendingAuthActionKind.providerLink:
                resultLocation =
                    '${AppRoutes.authResult}?kind=provider_link_error&detail=${Uri.encodeComponent(errorText)}';
              case PendingAuthActionKind.accountSwitch:
                resultLocation =
                    '${AppRoutes.authResult}?kind=account_switch_error&detail=${Uri.encodeComponent(errorText)}';
              case null:
                // 通常のサインイン等、追跡対象外のエラーは従来どおりSnackBarのみ。
                _showRootSnackBar(errorText);
            }
          } else if (messageText != null) {
            // Secure Email Change: 1通目の確認完了。もう一方の確認を促す案内。
            DevLog.add('[AuthCallback] email_change_pending branch');
            resultLocation =
                '${AppRoutes.authResult}?kind=email_change_pending&detail=${Uri.encodeComponent(messageText)}';
          } else if (params['type'] == 'email_change') {
            // Secure Email Change: 2通目の確認でメール変更が確定した完了コールバック。
            // 完了セッションがローカルに反映されず currentUser が古いままになる
            // ケースがあるため、refreshSession で最新化してから完了画面へ渡す。
            DevLog.add(
              '[AuthCallback] email_changed branch (refreshing session)',
            );
            try {
              await supabase.auth.refreshSession();
            } catch (e) {
              // リフレッシュ失敗は致命的ではないため握りつぶす
              DevLog.add('[AuthCallback] refreshSession failed: $e');
            }
            final email = supabase.auth.currentUser?.email ?? '';
            resultLocation =
                '${AppRoutes.authResult}?kind=email_changed&detail=${Uri.encodeComponent(email)}';
          } else if (pending?.kind == PendingAuthActionKind.providerLink ||
              pending?.kind == PendingAuthActionKind.accountSwitch) {
            // ログイン方法(OAuthプロバイダー)連携、または同一プロバイダー内での
            // アカウント切り替えの完了コールバック。このコールバック自体には
            // どちらの操作だったかという印が無いため、直前に保存しておいた
            // pendingマーカーだけが判断材料になる。複数プロバイダー/複数アカウント
            // の同時有効化はサポートしないため、新しいidentityのリンクに成功した
            // タイミングで、それ以外のidentityを確実にアンリンクする(同一provider
            // 内の新旧の判別も含め、ロジックはどちらの場合も同じ)。
            final isAccountSwitch =
                pending!.kind == PendingAuthActionKind.accountSwitch;
            DevLog.add(
              '[AuthCallback] ${isAccountSwitch ? 'account_switch' : 'provider_linked'} '
              'branch: keep=${pending.detail}',
            );
            await _unlinkOtherIdentities(
              keepProvider: pending.detail.toLowerCase(),
            );
            final kind = isAccountSwitch ? 'account_switched' : 'provider_linked';
            resultLocation =
                '${AppRoutes.authResult}?kind=$kind&detail=${Uri.encodeComponent(pending.detail)}';
          } else {
            DevLog.add(
              '[AuthCallback] no matching branch (plain session callback)',
            );
          }

          if (resultLocation != null) {
            DevLog.add('[AuthCallback] -> $resultLocation');
            return resultLocation;
          }

          final fallback = supabase.auth.currentSession != null
              ? AppRoutes.home
              : AppRoutes.signIn;
          DevLog.add('[AuthCallback] -> fallback $fallback');
          return fallback;
        });
      }

      final session = supabase.auth.currentSession;
      final path = state.uri.path;

      // Auth関連のパスかどうか（ログイン済みならホームへ飛ばす対象）
      // ★ welcome/introductionはここに含めない：ログイン状態に関わらず演出を
      //   見せたい・マイアカウントからいつでも閲覧可能にするため。
      final isAuthRoute =
          path == AppRoutes.signIn ||
          path == AppRoutes.signUp ||
          path == AppRoutes.forgotPassword ||
          path == AppRoutes.resetPassword;

      // メール確認待ち(サインアップ直後、まだセッションが無い状態)の
      // 案内画面。/auth_resultの他のkind(email_changed等)はログイン済みで
      // しか到達しないが、これだけは未ログインのまま表示する必要があるため、
      // 個別に公開扱いにする(でないとredirectがサインイン画面へ差し戻してしまい、
      // 「メールを送信しました」の案内が一切表示されない)。
      final isEmailSignupPendingResult =
          path == AppRoutes.authResult &&
          state.uri.queryParameters['kind'] == 'email_signup_pending';

      // ログイン状態に関わらず見られるページ（例: サインアップ画面やプロフィール画面からのリンク、
      // アカウント削除完了画面はセッションが既に無い状態で表示するため公開扱いが必要）
      // welcome/introductionもここでは公開扱いにする。
      final isPublicRoute =
          isAuthRoute ||
          path == AppRoutes.introduction ||
          path == AppRoutes.welcome ||
          path == AppRoutes.privacyPolicy ||
          path == AppRoutes.termsOfService ||
          path == AppRoutes.accountDeleted ||
          isEmailSignupPendingResult;

      // 1. 未ログインなら基本サインインへ強制移動。ただしこの端末でまだ
      //    Introduction(3枚のスライド)を見せていなければ、サインインより
      //    先にそちらへ誘導する(新規インストール限定の一度きりの導線)。
      if (session == null && !isPublicRoute) {
        // アカウント削除によるsignOut()直後の場合、まだこの画面(ダイアログ表示中)
        // へ到達した状態でredirectが割り込むことがある。このケースだけは通常の
        // /sign_inではなく削除完了画面へ誘導する(一度使ったらフラグは消費する)。
        if (isAccountBeingDeleted) {
          isAccountBeingDeleted = false;
          return AppRoutes.accountDeleted;
        }
        final hasSeenIntro = RecordingPreferences().getHasSeenIntroduction();
        return hasSeenIntro ? AppRoutes.signIn : AppRoutes.introduction;
      }

      // 2. ログイン済みなのにAuth画面に来たらホームへ飛ばす（ただしパスワード再設定画面は除く）
      if (session != null && isAuthRoute && path != AppRoutes.resetPassword) {
        return AppRoutes.home;
      }

      // 3. ログイン済みでオンボーディング未完了なら、オンボーディング画面以外への
      //    遷移をすべて差し戻す(オンボーディング自体・公開ルートは素通しする)。
      if (session != null && !isPublicRoute && path != AppRoutes.onboarding) {
        DevLog.add('[Router] checking onboarding status for path=$path...');
        final completed =
            await ref.read(userProfileRepositoryProvider).hasCompletedOnboarding();
        DevLog.add('[Router] completed=$completed');
        if (!completed) {
          DevLog.add('[Router] redirecting to AppRoutes.onboarding');
          return AppRoutes.onboarding;
        }
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
            const Text(
              'Page Not Found',
              style: TextStyle(
                color: Color(0xFFF2F2F2),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300), // AppColors.starGold hex
                foregroundColor: Colors.white,
              ),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    ),

    routes: [
      // =================================================================
      // Auth Routes
      // =================================================================
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomePage(),
      ),
      GoRoute(
        path: AppRoutes.introduction,
        pageBuilder: (context, state) =>
            _fadePage(state, const IntroductionPage()),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        pageBuilder: (context, state) => _fadePage(state, const SignInPage()),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        pageBuilder: (context, state) => _fadePage(state, const SignUpPage()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordPage(),
      ),
      GoRoute(
        path: AppRoutes.authResult,
        builder: (context, state) => AuthResultPage(
          kind: state.uri.queryParameters['kind'] ?? '',
          detail: state.uri.queryParameters['detail'],
        ),
      ),
      GoRoute(
        path: AppRoutes.accountDeleted,
        builder: (context, state) =>
            const AuthResultPage(kind: 'account_deleted'),
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
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) =>
            _fadePage(state, const OnboardingPage()),
      ),

      // =================================================================
      // Main Routes (Single Stack)
      // =================================================================

      // 1. Home (Dashboard) - 宇宙のコックピット
      // 1. Home (Dashboard) - 宇宙のコックピット
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => _fadePage(state, const HomePage()),
        routes: [
          // 2. Courses System (Nested under /home)
          GoRoute(
            path: AppRoutes.coursesRoot, // 'courses' -> /home/courses
            builder: (context, state) => const CoursePage(),
            routes: [
              // コース内: /home/notes/c/:courseId
              GoRoute(
                path: AppRoutes
                    .noteCourse, // 'c/:courseId' -> /home/notes/c/:courseId
                builder: (context, state) {
                  final id = state.pathParameters['courseId'];
                  return CoursePage(courseId: id);
                },
                routes: [
                  // 授業ビューワー: /home/notes/c/:courseId/v/:lectureId
                  GoRoute(
                    path: AppRoutes
                        .noteViewer, // 'v/:lectureId' -> /home/notes/c/:courseId/v/:lectureId
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
                          final startSid =
                              state.uri.queryParameters['start_sid'];
                          final endSid = state.uri.queryParameters['end_sid'];
                          final highlightSidsStr =
                              state.uri.queryParameters['highlight_sids'];
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
                      final initialIndex = indexStr != null
                          ? int.tryParse(indexStr)
                          : null;
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
                    path: AppRoutes
                        .deepNotesDetail, // 'dnd/:lectureId/:topicIndex'
                    builder: (context, state) {
                      final id = state.pathParameters['lectureId']!;
                      final index =
                          int.tryParse(
                            state.pathParameters['topicIndex'] ?? '0',
                          ) ??
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
        path: AppRoutes.account,
        builder: (context, state) => const MyAccountPage(),
      ),
      GoRoute(
        path: AppRoutes.creditDetail,
        builder: (context, state) => const CreditDetailPage(),
      ),
      GoRoute(
        path: AppRoutes.plans,
        builder: (context, state) => const PlansPage(),
      ),
      GoRoute(
        path: AppRoutes.profile,
        builder: (context, state) => const UserProfileDetailPage(),
      ),
      GoRoute(
        path: AppRoutes.contact,
        builder: (context, state) => const ContactPage(),
      ),
      GoRoute(
        path: AppRoutes.permissionsSettings,
        builder: (context, state) => const PermissionsSettingsPage(),
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
            return FadeTransition(opacity: animation, child: child);
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

/// deep linkコールバックのクエリとフラグメントの両方を1つに統合して返す。
/// (OAuth PKCEはクエリ、メール確認のimplicitはフラグメントにパラメータを
///  載せてくるため、どちらの形式でも同じロジックで扱えるようにする)
Map<String, String> _mergedCallbackParams(Uri uri) {
  final fragment = uri.fragment.isNotEmpty
      ? Uri.splitQueryString(uri.fragment)
      : const <String, String>{};
  return {...uri.queryParameters, ...fragment};
}

// 認証コード/トークン等、ログに出すべきでないパラメータ名。
const _sensitiveCallbackKeys = {
  'code',
  'access_token',
  'refresh_token',
  'provider_token',
  'provider_refresh_token',
  'token',
  'token_hash',
};

/// 受信したコールバックの構造をログに残す。secret(コード/トークン)は値を
/// 伏せ、長さだけ出す(何が届いたかは分かるが漏洩はしない)。
void _logAuthCallback(Uri uri) {
  final params = _mergedCallbackParams(uri);
  final redacted = params.map(
    (k, v) => MapEntry(
      k,
      _sensitiveCallbackKeys.contains(k) ? '<redacted:${v.length}>' : v,
    ),
  );
  DevLog.add('[AuthCallback] received scheme=${uri.scheme} params=$redacted');
}

/// ログイン方法/アカウントの切り替え後、新しくリンクされたidentity **1つだけ**
/// を残して、それ以外のidentityをすべてアンリンクする(複数プロバイダー・
/// 複数アカウントの同時有効化を許容しない仕様のため)。
///
/// 「別のプロバイダーへ切り替え」だけでなく「同じプロバイダー内で別アカウント
/// へ切り替え」もサポートするため、[keepProvider] だけでは新旧を区別できない
/// (どちらも provider は同じ文字列になる)。そのため、[keepProvider] に
/// 一致するidentityが複数ある場合は createdAt が最も新しいものだけを残す。
///
/// ローカルにキャッシュされた currentUser は直後だとまだ新しいidentityの
/// 反映が間に合っていないことがあるため、getUser() でサーバーから
/// 最新のidentity一覧を取得してから判定する。
Future<void> _unlinkOtherIdentities({required String keepProvider}) async {
  try {
    final response = await supabase.auth.getUser();
    final identities = response.user?.identities ?? [];
    DevLog.add(
      '[Unlink] server identities='
      '${identities.map((i) => '${i.provider}/${i.identityId}/${i.createdAt}').toList()} '
      'keep=$keepProvider',
    );

    final matching = identities
        .where((identity) => identity.provider == keepProvider)
        .toList();
    if (matching.isEmpty) {
      // 新しいidentityがまだ反映されていない場合は、何もせず次回に委ねる
      // (誤って全部消してしまうことを避けるための安全策)。
      DevLog.add(
        '[Unlink] SKIP: new provider "$keepProvider" not yet present '
        'on server (avoiding accidental removal). Nothing unlinked.',
      );
      return;
    }

    // 同じprovider内に複数ある(=同一プロバイダーでのアカウント切り替え)場合は、
    // 作成日時が最も新しいもの = 今回新しくリンクされた方だけを残す。
    matching.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    final keepIdentity = matching.first;
    DevLog.add(
      '[Unlink] keeping identityId=${keepIdentity.identityId} '
      '(provider=$keepProvider, createdAt=${keepIdentity.createdAt})',
    );

    for (final identity in identities) {
      if (identity.identityId != keepIdentity.identityId) {
        DevLog.add(
          '[Unlink] unlinking "${identity.provider}" '
          '(identityId=${identity.identityId})...',
        );
        await supabase.auth.unlinkIdentity(identity);
        DevLog.add('[Unlink] unlinked "${identity.provider}" OK');
      }
    }

    // unlinkIdentity() はサーバー側では正しく削除するが、ローカルに
    // キャッシュされたセッション/ユーザー情報(identities一覧)を更新せず、
    // 変更通知も発行しない。そのままだと currentUserProvider 等が古い
    // identity一覧を持ち続け、Profile画面のタイル表示等が反映されない
    // ままになるため、明示的にセッションを再取得して同期する。
    try {
      await supabase.auth.refreshSession();
      DevLog.add(
        '[Unlink] session refreshed, '
        'local identities=${supabase.auth.currentUser?.identities?.map((i) => i.provider).toList()}',
      );
    } catch (e) {
      DevLog.add('[Unlink] refreshSession after unlink failed: $e');
    }

    DevLog.add('[Unlink] done');
  } catch (e) {
    // アンリンクに失敗しても、プロバイダーのリンク自体は成功しているため
    // ここでは握りつぶす(古いidentityが残るだけで、致命的ではない)。
    DevLog.add(
      '[Unlink] ERROR (link itself is fine, old identity may remain): $e',
    );
  }
}

/// 認証状態の監視用（変更なし）
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    _sub = stream.asBroadcastStream().listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecoveryPending = true;
      }
      notifyListeners();
    });
  }
  late final StreamSubscription<AuthState> _sub;
  bool _passwordRecoveryPending = false;
  String? _inFlightCallbackUri;
  Future<String>? _inFlightCallbackResult;

  /// 一度読んだら消費してクリアする(以降の無関係なナビゲーションで
  /// 誤って再度リセットパスワード画面へ飛ばさないようにするため)。
  bool consumePasswordRecoveryFlag() {
    final wasPending = _passwordRecoveryPending;
    _passwordRecoveryPending = false;
    return wasPending;
  }

  /// deep linkコールバック(lefture://, com.lefture.app://)は、
  /// detectSessionInUriの処理完了によるauth状態変化がrefreshListenableを
  /// 再度発火させ、同じ着信URLに対してredirectが複数回呼ばれることがある。
  ///
  /// 最初は「2回目以降は判定をスキップして安全なフォールバックを返す」
  /// 実装にしていたが、[compute] はサーバーとの通信(getUser/unlinkIdentity/
  /// refreshSession等)を含み数百ms〜数秒かかるため、1回目の処理が完了する
  /// 前に2回目の(即座に終わる)フォールバックが先に確定してしまい、
  /// 正しい遷移先を上書きするレースが発生した。
  ///
  /// そのため同一URIに対する呼び出しは、進行中の[compute]の結果を
  /// **共有して待つ**ようにする(2回目以降は新たにcomputeを実行しない)。
  /// これで、何回呼ばれても最終的に同じ結果に収束する。
  Future<String> resolveAuthCallbackOnce(
    String uriString,
    Future<String> Function() compute,
  ) {
    if (_inFlightCallbackUri == uriString && _inFlightCallbackResult != null) {
      DevLog.add(
        '[AuthCallback] duplicate redirect pass for same URI, '
        'awaiting in-flight result instead of reprocessing',
      );
      return _inFlightCallbackResult!;
    }
    _inFlightCallbackUri = uriString;
    final future = compute();
    _inFlightCallbackResult = future;
    return future;
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
