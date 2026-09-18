import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AuthProvider } from './auth/AuthProvider';
import { LanguageProvider } from './i18n/LanguageContext';
import { ProtectedRoute } from './auth/ProtectedRoute';
import { RequireOnboarding } from './auth/RequireOnboarding';
import { Layout } from './components/Layout';
import { SignInPage } from './pages/sign-in/SignInPage';
import { SignUpPage } from './pages/sign-up/SignUpPage';
import { ForgotPasswordPage } from './pages/forgot-password/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/reset-password/ResetPasswordPage';
import { AccountDeletedPage } from './pages/account/AccountDeletedPage';
import { HomePage } from './pages/home/HomePage';
import { CourseListPage } from './pages/courses/CourseListPage';
import { CourseDetailPage } from './pages/courses/CourseDetailPage';
import { UploadPage } from './pages/lectures/UploadPage';
import { LectureViewerPage } from './pages/lectures/LectureViewerPage';
import { ReviewCardsPage } from './pages/lectures/ReviewCardsPage';
import { DeepNotesDetailPage } from './pages/lectures/DeepNotesDetailPage';
import { TranscriptPage } from './pages/lectures/TranscriptPage';
import { TopicMapPage } from './pages/courses/TopicMapPage';
import { OnboardingWizard } from './pages/onboarding/OnboardingWizard';
import { AccountPage } from './pages/account/AccountPage';
import { ProfilePage } from './pages/account/ProfilePage';
import { CreditsPage } from './pages/account/CreditsPage';
import { PurchaseCreditsPage } from './pages/account/PurchaseCreditsPage';
import { PlansPage } from './pages/account/PlansPage';
import { ActivityRecordsPlaceholderPage } from './pages/account/ActivityRecordsPlaceholderPage';

import { UploadModalProvider } from './context/UploadModalContext';

export const App: React.FC = () => {
  return (
    <LanguageProvider>
      <AuthProvider>
        <UploadModalProvider>
          <BrowserRouter>
            <Routes>
              <Route path="/sign-in" element={<SignInPage />} />
              <Route path="/sign-up" element={<SignUpPage />} />
              <Route path="/forgot-password" element={<ForgotPasswordPage />} />
              <Route path="/reset-password" element={<ResetPasswordPage />} />
              <Route path="/account-deleted" element={<AccountDeletedPage />} />

              <Route element={<ProtectedRoute />}>
                <Route path="onboarding" element={<OnboardingWizard />} />
                <Route element={<RequireOnboarding />}>
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
                  <Route path="account/credits" element={<CreditsPage />} />
                  <Route path="account/credits/purchase" element={<PurchaseCreditsPage />} />
                  <Route path="account/plans" element={<PlansPage />} />
                  <Route path="account/activity/:type" element={<ActivityRecordsPlaceholderPage />} />
                </Route>

                {/* 紙面のビューアはアプリシェル(ダーク)の外に出す全画面ページ */}
                <Route path="lectures/:lectureId/review-cards" element={<ReviewCardsPage />} />
                <Route path="lectures/:lectureId/deep-notes" element={<DeepNotesDetailPage />} />
                <Route path="lectures/:lectureId/deep-notes/:topicIndex" element={<DeepNotesDetailPage />} />
                <Route path="lectures/:lectureId/transcript" element={<TranscriptPage />} />
              </Route>
            </Route>

            {/* Catch-all redirect to root */}
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </BrowserRouter>
        </UploadModalProvider>
      </AuthProvider>
    </LanguageProvider>
  );
};
