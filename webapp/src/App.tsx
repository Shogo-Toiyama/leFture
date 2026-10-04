import React, { Suspense, lazy } from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { LanguageProvider } from './i18n/LanguageContext';
import { ProtectedRoute } from './auth/ProtectedRoute';
import { RequireOnboarding } from './auth/RequireOnboarding';
import { Layout } from './components/Layout';
import { PageState } from './components/PageState';
import { ChatHost } from './components/chat/ChatHost';

import { UploadModalProvider } from './context/UploadModalContext';

// ルート単位でchunk分割する(vite buildが「1チャンクが500kB超」と警告していた
// 単一index.jsを、ページごとの動的importに割る)。ページコンポーネントは
// 名前付きexportのため、default exportへの詰め替えが必要。
const SignInPage = lazy(() => import('./pages/sign-in/SignInPage').then((m) => ({ default: m.SignInPage })));
const SignUpPage = lazy(() => import('./pages/sign-up/SignUpPage').then((m) => ({ default: m.SignUpPage })));
const ForgotPasswordPage = lazy(() =>
  import('./pages/forgot-password/ForgotPasswordPage').then((m) => ({ default: m.ForgotPasswordPage }))
);
const ResetPasswordPage = lazy(() =>
  import('./pages/reset-password/ResetPasswordPage').then((m) => ({ default: m.ResetPasswordPage }))
);
const AccountDeletedPage = lazy(() =>
  import('./pages/account/AccountDeletedPage').then((m) => ({ default: m.AccountDeletedPage }))
);
const HomePage = lazy(() => import('./pages/home/HomePage').then((m) => ({ default: m.HomePage })));
const CourseListPage = lazy(() =>
  import('./pages/courses/CourseListPage').then((m) => ({ default: m.CourseListPage }))
);
const CourseDetailPage = lazy(() =>
  import('./pages/courses/CourseDetailPage').then((m) => ({ default: m.CourseDetailPage }))
);
const UploadPage = lazy(() => import('./pages/lectures/UploadPage').then((m) => ({ default: m.UploadPage })));
const LectureViewerPage = lazy(() =>
  import('./pages/lectures/LectureViewerPage').then((m) => ({ default: m.LectureViewerPage }))
);
const ReviewCardsPage = lazy(() =>
  import('./pages/lectures/ReviewCardsPage').then((m) => ({ default: m.ReviewCardsPage }))
);
const DeepNotesDetailPage = lazy(() =>
  import('./pages/lectures/DeepNotesDetailPage').then((m) => ({ default: m.DeepNotesDetailPage }))
);
const TranscriptPage = lazy(() =>
  import('./pages/lectures/TranscriptPage').then((m) => ({ default: m.TranscriptPage }))
);
const TopicMapPage = lazy(() => import('./pages/courses/TopicMapPage').then((m) => ({ default: m.TopicMapPage })));
const OnboardingWizard = lazy(() =>
  import('./pages/onboarding/OnboardingWizard').then((m) => ({ default: m.OnboardingWizard }))
);
const AccountPage = lazy(() => import('./pages/account/AccountPage').then((m) => ({ default: m.AccountPage })));
const ProfilePage = lazy(() => import('./pages/account/ProfilePage').then((m) => ({ default: m.ProfilePage })));
const AiMemoryPage = lazy(() => import('./pages/account/AiMemoryPage').then((m) => ({ default: m.AiMemoryPage })));
const CreditsPage = lazy(() => import('./pages/account/CreditsPage').then((m) => ({ default: m.CreditsPage })));
const PurchaseCreditsPage = lazy(() =>
  import('./pages/account/PurchaseCreditsPage').then((m) => ({ default: m.PurchaseCreditsPage }))
);
const PlansPage = lazy(() => import('./pages/account/PlansPage').then((m) => ({ default: m.PlansPage })));
const ChatPage = lazy(() => import('./pages/chat/ChatPage').then((m) => ({ default: m.ChatPage })));
const AdminLayout = lazy(() => import('./pages/admin/AdminLayout').then((m) => ({ default: m.AdminLayout })));
const AdminOverviewPage = lazy(() =>
  import('./pages/admin/AdminOverviewPage').then((m) => ({ default: m.AdminOverviewPage }))
);
const AdminUsagePage = lazy(() => import('./pages/admin/AdminUsagePage').then((m) => ({ default: m.AdminUsagePage })));
const AdminPipelinePage = lazy(() =>
  import('./pages/admin/AdminPipelinePage').then((m) => ({ default: m.AdminPipelinePage }))
);
const AdminUsersPage = lazy(() => import('./pages/admin/AdminUsersPage').then((m) => ({ default: m.AdminUsersPage })));
const AdminSupportPage = lazy(() =>
  import('./pages/admin/AdminSupportPage').then((m) => ({ default: m.AdminSupportPage }))
);
const AdminAuditPage = lazy(() => import('./pages/admin/AdminAuditPage').then((m) => ({ default: m.AdminAuditPage })));
const ActivityRecordsPlaceholderPage = lazy(() =>
  import('./pages/account/ActivityRecordsPlaceholderPage').then((m) => ({
    default: m.ActivityRecordsPlaceholderPage,
  }))
);

export const App: React.FC = () => {
  return (
    <LanguageProvider>
      <AuthProvider>
        <UploadModalProvider>
          <BrowserRouter>
            <Suspense fallback={<PageState kind="loading" />}>
              <Routes>
                <Route path="/sign-in" element={<SignInPage />} />
                <Route path="/sign-up" element={<SignUpPage />} />
                <Route path="/forgot-password" element={<ForgotPasswordPage />} />
                <Route path="/reset-password" element={<ResetPasswordPage />} />
                <Route path="/account-deleted" element={<AccountDeletedPage />} />

                <Route element={<ProtectedRoute />}>
                  <Route path="onboarding" element={<OnboardingWizard />} />
                  {/* 表示可否はAdminLayoutが GET /admin/me で決める(境界はバックエンド側) */}
                  <Route path="admin" element={<AdminLayout />}>
                    <Route index element={<AdminOverviewPage />} />
                    <Route path="usage" element={<AdminUsagePage />} />
                    <Route path="pipeline" element={<AdminPipelinePage />} />
                    <Route path="users" element={<AdminUsersPage />} />
                    <Route path="support" element={<AdminSupportPage />} />
                    <Route path="audit" element={<AdminAuditPage />} />
                  </Route>
                  <Route element={<RequireOnboarding />}>
                    {/* 右下のチャットボタンと右側パネル。全画面の読み物(Layoutの外)にも出すため、ここで包む */}
                    <Route element={<ChatHost />}>
                      <Route element={<Layout />}>
                        <Route index element={<HomePage />} />
                        <Route path="upload" element={<UploadPage />} />
                        <Route path="courses" element={<CourseListPage />} />
                        <Route path="courses/:courseId" element={<CourseDetailPage />} />
                        <Route path="courses/:courseId/upload" element={<UploadPage />} />
                        <Route path="courses/:courseId/topic-map" element={<TopicMapPage />} />
                        <Route path="lectures/:lectureId" element={<LectureViewerPage />} />
                        <Route path="account" element={<AccountPage />} />
                        <Route path="account/profile" element={<ProfilePage />} />
                        <Route path="account/ai-memory" element={<AiMemoryPage />} />
                        <Route path="account/credits" element={<CreditsPage />} />
                        <Route path="account/credits/purchase" element={<PurchaseCreditsPage />} />
                        <Route path="account/plans" element={<PlansPage />} />
                        <Route path="account/activity/:type" element={<ActivityRecordsPlaceholderPage />} />
                      </Route>

                      {/* 紙面のビューア・チャットはアプリシェル(ダーク)の外に出す全画面ページ */}
                      <Route path="chat" element={<ChatPage />} />
                      <Route path="chat/:threadId" element={<ChatPage />} />
                      <Route path="lectures/:lectureId/review-cards" element={<ReviewCardsPage />} />
                      <Route path="lectures/:lectureId/deep-notes" element={<DeepNotesDetailPage />} />
                      <Route path="lectures/:lectureId/deep-notes/:topicIndex" element={<DeepNotesDetailPage />} />
                      <Route path="lectures/:lectureId/transcript" element={<TranscriptPage />} />
                    </Route>
                  </Route>
                </Route>

                {/* Catch-all redirect to root */}
                <Route path="*" element={<Navigate to="/" replace />} />
              </Routes>
            </Suspense>
          </BrowserRouter>
        </UploadModalProvider>
      </AuthProvider>
    </LanguageProvider>
  );
};
