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