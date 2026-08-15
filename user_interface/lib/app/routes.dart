class AppRoutes {
  // Auth
  static const welcome = '/welcome';
  // 新規インストール端末限定で、サインイン/サインアップより先に一度だけ見せる
  // 3枚のイントロダクション(Hero/3つの価値/CTA)。
  static const introduction = '/introduction';
  static const signIn = '/sign_in';
  static const signUp = '/sign_up';
  static const forgotPassword = '/forgot_password';
  static const resetPassword = '/reset_password';
  static const privacyPolicy = '/privacy_policy';
  static const termsOfService = '/terms_of_service';

  // Auth action results (email change / login method change / account deletion)
  static const authResult = '/auth_result'; // ログイン状態を保ったまま見せる結果画面
  static const accountDeleted = '/account_deleted'; // セッション外(未ログイン)で見せる結果画面

  // Onboarding (初回サインアップ直後、プロフィール・Recording Language・
  // Realtime Recording設定を必須で行わせる画面)
  static const onboarding = '/onboarding';
  // 新端末セットアップ (既存ユーザーが新端末でログインした際の言語設定・権限許可)
  static const deviceSetup = '/device_setup';

  // Main
  static const home = '/home'; // Dashboard (宇宙のコックピット)
  
  // Recording (Modal)
  static const recording = '/recording';

  // Features
  static const learningGalaxy = '/learning_galaxy';
  static const aiChat = '/ai_chat';
  static const account = '/account';
  static const profile = '/profile';
  static const contact = '/contact';
  static const permissionsSettings = '/account/permissions';
  static const activityDetails = '/account/activity/:type';
  static const creditDetail = '/account/credits';
  static const plans = '/account/plans';
  static const study = '/study';

  // Courses (Nested relative paths for GoRouter configuration)
  static const coursesRoot = 'courses';
  static const noteCourse = 'c/:courseId'; // 例: c/123
  static const noteViewer = 'v/:lectureId'; // 例: v/456

  // Review Cards (Nested under /home/courses/c/:courseId)
  static const reviewCardsDashboard = 'rc/:lectureId';        // rc/:lectureId
  static const reviewCardsViewer    = 'rcv/:lectureId';       // rcv/:lectureId

  // Deep Notes (Nested under /home/courses/c/:courseId)
  static const deepNotesList   = 'dn/:lectureId';             // dn/:lectureId
  static const deepNotesDetail = 'dnd/:lectureId/:topicIndex';// dnd/:lectureId/:topicIndex

  // Transcript (Nested under /home/courses/c/:courseId/v/:lectureId)
  static const transcript = 'transcript';          // transcript

  // Topic Map (Nested under /home/courses/c/:courseId)
  static const topicMap = 'topic-map';                        // topic-map

  // Absolute Navigation Paths
  static const coursesRootPath = '/home/courses';
}