class AppRoutes {
  // Auth
  static const welcome = '/welcome';
  static const signIn = '/sign_in';
  static const signUp = '/sign_up';

  // Main
  static const home = '/home'; // Dashboard (宇宙のコックピット)
  
  // Recording (Modal)
  static const recording = '/recording';

  // Features
  static const learningGalaxy = '/learning_galaxy';
  static const aiChat = '/ai_chat';
  static const profile = '/profile';
  static const study = '/study';

  // Notes (Nested)
  static const notesRoot = '/notes';
  static const noteCourse = 'c/:courseId'; // 例: /notes/c/123
  static const noteViewer = 'v/:lectureId'; // 例: /notes/v/456
}