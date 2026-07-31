// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get signInWelcomeTitle => 'Welcome back';

  @override
  String get signInSubtitle => 'Sign in to continue your learning journey';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signInErrorEmailEmpty => 'Please enter your email address.';

  @override
  String get signInErrorPasswordEmpty => 'Please enter your password.';

  @override
  String get forgotPasswordLink => 'Forgot password?';

  @override
  String get signInButton => 'Sign In';

  @override
  String get authDividerOr => 'or';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithEmail => 'Continue with email';

  @override
  String get signInNoAccountPrompt => 'Don\'t have an account? ';

  @override
  String get createAccountLink => 'Create Account';

  @override
  String get signUpSuccessSnackbar =>
      'Account created! Please check your email to verify.';

  @override
  String get signUpErrorAgreeTerms =>
      'Please agree to the Terms and Conditions';

  @override
  String get signUpTitle => 'Join leFture';

  @override
  String get signUpSubtitle => 'Start your learning journey today';

  @override
  String get usernameLabel => 'Username';

  @override
  String get signUpErrorUsernameEmpty => 'Please enter a username';

  @override
  String get signUpErrorUsernameTooShort =>
      'Username must be at least 3 characters';

  @override
  String get authErrorEmailRequired => 'Please enter your email';

  @override
  String get authErrorEmailInvalid => 'Please enter a valid email';

  @override
  String get confirmPasswordLabel => 'Confirm Password';

  @override
  String get signUpErrorPasswordEmpty => 'Please enter a password';

  @override
  String get passwordErrorTooShort => 'Password must be at least 8 characters';

  @override
  String get confirmPasswordErrorEmpty => 'Please confirm your password';

  @override
  String get passwordsMismatchError => 'Passwords do not match';

  @override
  String get signUpAgreementPrefix => 'I agree to the ';

  @override
  String get termsAndConditionsLink => 'Terms and Conditions';

  @override
  String get signUpAgreementMiddle => ' and ';

  @override
  String get privacyPolicyLink => 'Privacy Policy';

  @override
  String get signUpAgreementSuffix => '';

  @override
  String get signUpSubmitButton => 'Create Account';

  @override
  String get signUpHasAccountPrompt => 'Already have an account? ';

  @override
  String get signInLink => 'Sign In';

  @override
  String get forgotPasswordStatusWaking => 'Waking up email service...';

  @override
  String get forgotPasswordStatusSending => 'Sending reset link...';

  @override
  String get forgotPasswordErrorSlowServer =>
      'The email service is taking longer than usual to start.';

  @override
  String get forgotPasswordSuccessTitle => 'Check your email';

  @override
  String get forgotPasswordTitle => 'Forgot password?';

  @override
  String forgotPasswordSuccessMessage(String email) {
    return 'We\'ve sent a password reset link to $email';
  }

  @override
  String get forgotPasswordSubtitle =>
      'No worries, enter your email and we\'ll send you a reset link';

  @override
  String get forgotPasswordRetryButton => 'Didn\'t get it? Try again';

  @override
  String get forgotPasswordHaveLinkButton => 'I have a reset link';

  @override
  String get sendResetLinkButton => 'Send Reset Link';

  @override
  String get rememberedPasswordPrompt => 'Remembered your password? ';

  @override
  String get resetPasswordLinkInvalidTitle => 'Link invalid or expired';

  @override
  String get requestNewLinkButton => 'Request a New Link';

  @override
  String get resetPasswordSuccessTitle => 'Password updated';

  @override
  String get resetPasswordSuccessMessage =>
      'Your password has been updated successfully. You\'re all set!';

  @override
  String get goToDashboardButton => 'Go to Dashboard';

  @override
  String get resetPasswordTitle => 'Set a new password';

  @override
  String get resetPasswordSubtitle =>
      'Your new password must be different from previously used passwords';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get resetPasswordErrorEmpty => 'Please enter a new password';

  @override
  String get confirmNewPasswordLabel => 'Confirm New Password';

  @override
  String get confirmNewPasswordErrorEmpty => 'Please confirm your new password';

  @override
  String get resetPasswordButton => 'Reset Password';

  @override
  String get passwordReqMinLength => 'At least 8 characters';

  @override
  String get passwordReqUpperLower => 'Upper & lowercase letters';

  @override
  String get passwordReqDigit => 'At least one number';

  @override
  String get passwordReqSymbol => 'At least one symbol';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthFair => 'Fair';

  @override
  String get passwordStrengthGood => 'Good';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String get recordingCourseLabel => 'Course';

  @override
  String get recordingNoCourseSelected => 'No course selected';

  @override
  String get recordingRealtimeOnBadge => 'Realtime ON';

  @override
  String get recordingRealtimeOffBadge => 'Realtime OFF';

  @override
  String get recordingNoCourseWarning =>
      'No course selected. Automated AI analysis will not start unless a course is assigned. Please select a course before or after uploading to start analysis.';

  @override
  String get recordingOrDivider => 'OR';

  @override
  String get recordingFileAccessError =>
      'Unable to access the selected file. Please try another file.';

  @override
  String recordingFileSelectError(String error) {
    return 'Failed to select file: $error';
  }

  @override
  String get recordingProcessingAudioFile => 'Processing audio file...';

  @override
  String get recordingFileSelected => 'File selected';

  @override
  String get recordingSelectAudioFile => 'Select audio file';

  @override
  String get recordingDiscardDialogTitle => 'Discard Recording?';

  @override
  String get recordingDiscardDialogMessage =>
      'This will delete the current recording. This action cannot be undone.';

  @override
  String get recordingCancelButton => 'Cancel';

  @override
  String get recordingDiscardConfirmButton => 'Discard';

  @override
  String get recordingDiscardButtonLabel => 'Discard Recording';

  @override
  String get recordingSettingsSectionTitle => 'Settings';

  @override
  String get recordingTitleFieldLabel => 'Lecture title (Optional)';

  @override
  String get recordingTitleFieldHint => '✨ Auto (AI will generate title)';

  @override
  String get recordingAutoStartAnalysisTitle => 'Auto-start analysis';

  @override
  String get recordingAutoStartAnalysisSubtitle =>
      'Automatically start processing tasks after upload completes.';

  @override
  String get recordingRealtimeTranscribeTitle => 'Realtime transcribe';

  @override
  String get recordingRealtimeTranscribeSubtitle =>
      'Transcribe audio stream in realtime as you record.';

  @override
  String get recordingSpeechModelDialogTitle => 'Speech model required';

  @override
  String get recordingSpeechModelDialogMessage =>
      'Realtime transcription needs this language\'s on-device speech model. Download it now?';

  @override
  String get recordingSpeechModelDownloadConfirm => 'Download';

  @override
  String get recordingSelectCourseBeforeUploadSnackbar =>
      'Please select a course before uploading';

  @override
  String get recordingUploadingStatus => 'Uploading...';

  @override
  String get recordingUploadButtonLabel => 'Upload Recording';

  @override
  String get recordingDoneOverlayTitle => 'Recording Done!';

  @override
  String get recordingRequestingPermissionStatus =>
      'Requesting microphone permission...';

  @override
  String get recordingGenericErrorFallback => 'Error';

  @override
  String get recordingOpenSettingsButton => 'Open Settings';

  @override
  String get recordingTryAgainButton => 'Try Again';

  @override
  String get recordingStatusPaused => 'Paused';

  @override
  String get recordingStatusRecording => 'Recording...';

  @override
  String get recordingStatusReady => 'Ready to record';

  @override
  String get recordingLanguageRowTitle => 'Recording language';

  @override
  String recordingAsrModelErrorPrefix(String message) {
    return '⚠️ $message';
  }

  @override
  String get recordingOnDeviceModelSubtitle =>
      'On-device speech model used for live captions.';

  @override
  String get recordingMomentFunLabel => 'Fun moment';

  @override
  String get recordingMomentDifficultLabel => 'Difficult';

  @override
  String get recordingMomentRevisitLabel => 'Revisit later';

  @override
  String get recordingMomentNoteLabel => 'Note';

  @override
  String get recordingLiveTranscriptHeader => 'LIVE TRANSCRIPT';

  @override
  String get recordingWaitingForAudio => 'Waiting for audio...';

  @override
  String get recordingRealtimeOffHint =>
      'Turn on Realtime Transcribe (More Settings, Voice tab) to see live captions and ask AI here.';

  @override
  String get recordingReactionFunLabel => 'Fun';

  @override
  String get recordingReactionDifficultLabel => 'Difficult';

  @override
  String get recordingReactionRevisitLabel => 'Revisit';

  @override
  String get recordingNoteInputHint => 'Jot a quick note...';

  @override
  String get recordingMomentsEmptyHint =>
      'Tap a reaction or add a note below — it\'ll show up here.';

  @override
  String get coursePickerTitle => 'Select Course';

  @override
  String get coursePickerCancelButton => 'Cancel';

  @override
  String get coursePickerSearchHint => 'Search courses...';

  @override
  String coursePickerErrorLoading(String error) {
    return 'Error: $error';
  }

  @override
  String get coursePickerEmptyNoCourses => 'No courses yet';

  @override
  String get coursePickerEmptySearchResults => 'No results';

  @override
  String get coursePickerConfirmButton => 'Confirm';

  @override
  String get coursePickerContinueWithoutCourseButton =>
      'Continue without Course';

  @override
  String lectureViewerErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get lectureViewerLectureNotFound => 'Lecture not found';

  @override
  String get lectureViewerUntitledLecture => 'Untitled Lecture';

  @override
  String get lectureViewerCourseCodeFallback => 'N/A';

  @override
  String get lectureViewerSummaryPlaceholder =>
      'This lecture is still being analyzed. The summary will appear here once it\'s ready.';

  @override
  String lectureViewerAnnouncementsChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count announcements',
      one: '$count announcement',
    );
    return '$_temp0';
  }

  @override
  String lectureViewerKeywordsChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keywords',
      one: '$count keyword',
    );
    return '$_temp0';
  }

  @override
  String lectureViewerTopicsChip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count topics',
      one: '$count topic',
    );
    return '$_temp0';
  }

  @override
  String get lectureViewerReviewCardsTitle => 'Review Cards';

  @override
  String get lectureViewerDeepNotesTitle => 'Deep Notes';

  @override
  String get lectureViewerFunFactHeader => 'FUN FACT';

  @override
  String get lectureViewerTranscriptButtonLabel => 'Transcript';

  @override
  String lectureViewerReactionUpdateFailedSnackbar(String error) {
    return 'Failed to update reaction: $error';
  }

  @override
  String get lectureViewerUntitledTerm => 'Untitled term';

  @override
  String get lectureViewerAnnouncementsSheetTitle => 'Announcements';

  @override
  String get lectureViewerKeywordsSheetTitle => 'Keywords';

  @override
  String get lectureViewerInfoSheetEmptyState => 'Nothing here yet';

  @override
  String get pipelineStepsCancelledLabel => 'Cancelled';

  @override
  String get pipelineStepsRetryingAutomaticallyLabel =>
      'Retrying automatically…';

  @override
  String get pipelineStepsInProgressLabel => 'In progress';

  @override
  String pipelineStepsRetryConfirmMessageSimple(String step) {
    return 'This will redo \"$step\".';
  }

  @override
  String pipelineStepsRetryConfirmMessageWithDownstream(
    String step,
    String downstreamSteps,
  ) {
    return 'This will redo \"$step\" and re-run everything that depends on it:\n$downstreamSteps.';
  }

  @override
  String get pipelineStepsRetryDialogTitle => 'Retry from here?';

  @override
  String get pipelineStepsRetryConfirmButton => 'Retry';

  @override
  String pipelineStepsRetryFailedSnackbar(String error) {
    return 'Retry failed: $error';
  }

  @override
  String get pipelineStepsRetryTooltip => 'Retry from here';

  @override
  String get pipelineStepsRetryingLabel => 'Retrying...';

  @override
  String get pipelineStepsRetryThisStepButton => 'Retry this step';

  @override
  String get notStartedNoActivePlanTitle => 'No Active Plan';

  @override
  String get notStartedOutOfCreditsTitle => 'Out of Credits';

  @override
  String get notStartedNoAllocationMessage =>
      'You need to select a plan before you can analyze lectures.';

  @override
  String get notStartedOutOfCreditsMessage =>
      'You\'ve used up your credits for this period. Check your balance or wait for your next renewal.';

  @override
  String get notStartedCancelButton => 'Cancel';

  @override
  String get notStartedViewCreditsButton => 'View Credits';

  @override
  String get notStartedReadyTitle => 'Ready to Analyze';

  @override
  String get notStartedReadySubtitle =>
      'The audio is ready. Generate transcript, summary, and notes with AI.';

  @override
  String get notStartedNoCourseWarning =>
      'This lecture isn\'t assigned to a course yet. Analysis can\'t start until it is.';

  @override
  String get notStartedChooseCourseButton => 'Choose Course';

  @override
  String get notStartedStartingLabel => 'Starting...';

  @override
  String get notStartedStartAnalysisButton => 'Start Analysis';

  @override
  String notStartedErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String notStartedAutoStartFailedWarning(String error) {
    return 'We tried to start analysis automatically after upload, but it failed and will keep retrying in the background: $error\nYou can also start it manually below.';
  }

  @override
  String get topicPreviewSaveTooltip => 'Save';

  @override
  String get topicPreviewLikeTooltip => 'Like';

  @override
  String get topicPreviewReadNoteButton => 'Read Note';

  @override
  String get processingViewStartOverDialogTitle => 'Start Over?';

  @override
  String get processingViewStartOverDialogMessage =>
      'This restarts the whole analysis from scratch. Progress that\'s already completed will be discarded.';

  @override
  String get processingViewStartOverConfirmButton => 'Start Over';

  @override
  String get processingViewFailedTitle => 'Analysis Failed';

  @override
  String get processingViewAnalyzingTitle => 'Analyzing Lecture...';

  @override
  String processingViewStepsCompletedLabel(int completed, int total) {
    return '$completed / $total steps completed';
  }

  @override
  String get processingViewHoldToRestartHint =>
      'Hold the icon above to start over from scratch.';

  @override
  String get processingViewStartingOverLabel => 'Starting over...';

  @override
  String get processingViewStartOverFromScratchButton =>
      'Start over from scratch';

  @override
  String get statusViewProcessingLabel => 'Processing...';

  @override
  String statusScaffoldErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get statusScaffoldSyncingTitle => 'Syncing Audio...';

  @override
  String get statusScaffoldSyncingMessage =>
      'Please wait for the upload to complete.';

  @override
  String get creditDetailTitle => 'Credits';

  @override
  String get creditDetailRefreshTooltip => 'Refresh';

  @override
  String get creditDetailLoadErrorMessage =>
      'Could not load credit info. Check your connection and try again.';

  @override
  String get creditDetailRetryButton => 'Retry';

  @override
  String get creditDetailCurrentPlanTitle => 'Current Plan';

  @override
  String get creditDetailActiveBadge => 'ACTIVE';

  @override
  String get creditDetailActivePlanFallback => 'Active Plan';

  @override
  String creditDetailCreditsPerMonth(int credits) {
    return '$credits credits / month';
  }

  @override
  String get creditDetailFullAccessSubtitle =>
      'Enjoy full access to your lecture companion features.';

  @override
  String get creditDetailMonthlyCreditsTitle => 'Monthly Credits';

  @override
  String creditDetailResetsOn(String date) {
    return 'Resets on $date';
  }

  @override
  String get creditDetailNoActivePlanTitle => 'No active plan';

  @override
  String get creditDetailNoActivePlanSubtitle =>
      'Choose a plan below to start generating lecture materials.';

  @override
  String get creditDetailPlansLoadError =>
      'Could not load plans. Pull to refresh and try again.';

  @override
  String creditDetailPlanActivatedSnackbar(String planName) {
    return '$planName activated!';
  }

  @override
  String get creditDetailActivateErrorTitle => 'Could not activate plan';

  @override
  String get creditDetailOkButton => 'OK';

  @override
  String creditDetailPlanSubtitle(int credits, int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '/ $months months',
      one: '/ month',
    );
    return '$credits credits $_temp0';
  }

  @override
  String get creditDetailPriceFree => 'Free';

  @override
  String get creditDetailUsageHistoryTitle => 'Usage History';

  @override
  String get creditDetailHourlySummaryLabel => 'Hourly summary';

  @override
  String get creditDetailUsageHistoryLoadError =>
      'Could not load usage history.';

  @override
  String get creditDetailNoUsageActivity =>
      'No recent usage activity recorded.';

  @override
  String creditDetailViewMoreButton(int count) {
    return 'View More ($count more)';
  }

  @override
  String creditDetailCreditsSuffix(String delta) {
    return '$delta credits';
  }

  @override
  String get activityRecordsTitleSaved => 'Saved';

  @override
  String get activityRecordsTitleLikes => 'Likes';

  @override
  String get activityRecordsTitleDislikes => 'Dislikes';

  @override
  String get activityRecordsTitleAnnouncements => 'Announcements';

  @override
  String get activityRecordsTitleTrash => 'Trash';

  @override
  String get activityRecordsEmptyTrashLabel => 'Empty Trash';

  @override
  String get activityRecordsTrashRetentionBanner =>
      'Items in Trash will be permanently deleted after 30 days.';

  @override
  String get activityRecordsFilterAll => 'All';

  @override
  String get activityRecordsFilterReviewCards => 'Review Cards';

  @override
  String get activityRecordsFilterDeepNotes => 'Deep Notes';

  @override
  String get activityRecordsFilterKeywords => 'Keywords';

  @override
  String get activityRecordsFilterFunFacts => 'Fun Facts';

  @override
  String get activityRecordsFilterActive => 'Active';

  @override
  String get activityRecordsFilterCompleted => 'Completed';

  @override
  String get activityRecordsFilterCourses => 'Courses';

  @override
  String get activityRecordsFilterLectures => 'Lectures';

  @override
  String activityRecordsItemsFoundCount(int count) {
    return '$count items found';
  }

  @override
  String get activityRecordsNoFilterMatch => 'No items match this filter.';

  @override
  String activityRecordsLoadFailed(String error) {
    return 'Failed to load records: $error';
  }

  @override
  String activityRecordsDeletedOnLabel(String date, String type) {
    return 'Deleted on $date · $type';
  }

  @override
  String get activityRecordsRestoredSnackbar => 'Item restored successfully.';

  @override
  String activityRecordsDeleteItemDialogTitle(String title) {
    return 'Delete $title?';
  }

  @override
  String get activityRecordsDeleteItemDialogMessage =>
      'This item will be permanently deleted from both the local database and the cloud. This action cannot be undone.';

  @override
  String get activityRecordsCancelButton => 'Cancel';

  @override
  String get activityRecordsDeleteButton => 'Delete';

  @override
  String get activityRecordsItemDeletedSnackbar => 'Item permanently deleted.';

  @override
  String get activityRecordsEmptyTrashDialogTitle => 'Empty Trash?';

  @override
  String get activityRecordsEmptyTrashDialogMessage =>
      'All soft-deleted lectures, courses, and announcements will be permanently deleted from both the local database and the cloud. This action cannot be undone.';

  @override
  String get activityRecordsEmptyTrashSuccessSnackbar =>
      'Trash emptied successfully.';

  @override
  String activityRecordsEmptyTrashPartialFailureSnackbar(
    int deletedCount,
    int failedCount,
  ) {
    return '$deletedCount item(s) deleted, $failedCount failed and remain in trash for retry.';
  }

  @override
  String get activityRecordsTypeLabelCourse => 'Course';

  @override
  String get activityRecordsTypeLabelLecture => 'Lecture';

  @override
  String get activityRecordsTypeLabelAnnouncement => 'Announcement';

  @override
  String get activityRecordsTypeLabelItem => 'Item';

  @override
  String get activityRecordsUndoUnsaved => 'Unsaved • Tap to undo';

  @override
  String get activityRecordsUndoUnreacted => 'Unreacted • Tap to undo';

  @override
  String get activityRecordsContentTypeReviewCard => 'Review Card';

  @override
  String get activityRecordsContentTypeDeepNote => 'Deep Note';

  @override
  String get activityRecordsContentTypeKeyword => 'Keyword';

  @override
  String get activityRecordsContentTypeFunFact => 'Fun Fact';

  @override
  String get activityRecordsContentTypeDefault => 'Content';

  @override
  String get myAccountTitle => 'My Account';

  @override
  String get myAccountSectionProfile => 'Profile';

  @override
  String get myAccountSectionActivity => 'Activity';

  @override
  String get myAccountSectionApplication => 'Application';

  @override
  String get myAccountSectionSettings => 'Settings';

  @override
  String get myAccountDefaultDisplayName => 'Explorer';

  @override
  String get myAccountSaveNameTooltip => 'Save';

  @override
  String get myAccountCancelEditTooltip => 'Cancel';

  @override
  String get myAccountEditNameTooltip => 'Edit Name';

  @override
  String get myAccountAboutYouLabel => 'ABOUT YOU';

  @override
  String get myAccountAboutYouPlaceholder => 'No description set yet.';

  @override
  String get myAccountInterestsLabel => 'INTERESTS';

  @override
  String get myAccountInterestsPlaceholder => 'No interests set yet.';

  @override
  String get myAccountFutureDreamsLabel => 'FUTURE DREAMS';

  @override
  String get myAccountFutureDreamsPlaceholder => 'No future dream set yet.';

  @override
  String get myAccountCreditsUnavailable => 'Credits unavailable';

  @override
  String get myAccountLoadingCredits => 'Loading credits…';

  @override
  String get myAccountTransmissionsTitle => 'Transmissions';

  @override
  String get myAccountTransmissionsSubtitle => 'What\'s new & updates';

  @override
  String get myAccountIntroductionTitle => 'App Introduction';

  @override
  String get myAccountIntroductionSubtitle => 'Replay introduction slides';

  @override
  String get myAccountTutorialTitle => 'Tutorial';

  @override
  String get myAccountTutorialSubtitle => 'Interactive guide';

  @override
  String get myAccountTutorialComingSoonSnackbar =>
      'Tutorial will be available in a future update.';

  @override
  String get myAccountNewBadge => 'NEW';

  @override
  String get myAccountNoTransmissionsSnackbar =>
      'No transmissions available at this time.';

  @override
  String get myAccountSavedSubtitle => 'Review Cards · Deep Notes · Keywords';

  @override
  String get myAccountLikesDislikesSubtitle =>
      'Review Cards · Deep Notes · Fun Facts';

  @override
  String get myAccountAnnouncementsSubtitle => 'Including completed ones';

  @override
  String get myAccountTrashSubtitle => 'Deleted courses & lectures';

  @override
  String get myAccountRecordingLanguageTitle => 'Recording Language';

  @override
  String get myAccountDisplayLanguageTitle => 'Display Language';

  @override
  String get myAccountPrivacyPolicyTitle => 'Privacy Policy';

  @override
  String get myAccountTermsOfServiceTitle => 'Terms of Service';

  @override
  String get myAccountContactUsTitle => 'Contact Us';

  @override
  String get myAccountChangeEmailTitle => 'Change Email';

  @override
  String get myAccountChangePasswordTitle => 'Change Password';

  @override
  String get myAccountChangeLoginMethodTitle => 'Change Login Method';

  @override
  String get myAccountChangeAccountTitle => 'Change Account';

  @override
  String get myAccountSignOutTitle => 'Sign Out';

  @override
  String get myAccountDeleteAccountTitle => 'Delete Account';

  @override
  String get deleteAccountDialogTitle => 'Delete Account?';

  @override
  String get deleteAccountDialogWarningMessage =>
      'Are you absolutely sure you want to delete your account? All your recorded lectures, transcripts, and personal profile data will be permanently deleted. This action cannot be undone.';

  @override
  String get deleteAccountDialogWakingBackendStatus =>
      'Waking up backend service...';

  @override
  String get deleteAccountDialogDeletingStatus => 'Deleting account...';

  @override
  String get deleteAccountDialogSlowBackendError =>
      'The backend service is taking longer than usual to start. Please try again in a moment.';

  @override
  String get deleteAccountDialogPasswordPrompt =>
      'Enter your password to confirm:';

  @override
  String get deleteAccountDialogPasswordLabel => 'Password';

  @override
  String deleteAccountDialogEmailPrompt(String email) {
    return 'Type your email to confirm ($email):';
  }

  @override
  String get deleteAccountDialogEmailLabel => 'Email Address';

  @override
  String get deleteAccountDialogCancelButton => 'Cancel';

  @override
  String get deleteAccountDialogConfirmButton => 'Delete Account';

  @override
  String get plansTitle => 'Plans & Pricing';

  @override
  String get plansHeadline => 'Supercharge your learning journey';

  @override
  String get plansSubheadline =>
      'Choose the plan that fits your study pace. Upgrade or downgrade anytime.';

  @override
  String get plansBillingToggleMonthly => 'Monthly';

  @override
  String get plansBillingToggleYearly => 'Yearly';

  @override
  String get plansBillingToggleSaveBadge => 'SAVE 20%';

  @override
  String get plansStarterTitle => 'Starter';

  @override
  String get plansStarterSubtitle => 'Essential tools for casual learners';

  @override
  String get plansStarterBillingPeriod => 'forever free';

  @override
  String get plansCurrentPlanBadge => 'CURRENT PLAN';

  @override
  String get plansStarterButtonCurrent => 'Current Active Plan';

  @override
  String get plansStarterButtonDowngrade => 'Downgrade to Starter';

  @override
  String get plansStarterFeature1 => '100 Monthly Credits';

  @override
  String get plansStarterFeature2 => 'Standard AI Lecture Transcripts';

  @override
  String get plansStarterFeature3 => 'Core Topic Map Generation';

  @override
  String get plansStarterFeature4 => 'Basic AI Q&A Chat';

  @override
  String get plansStarterAlreadyOnSnackbar =>
      'You are already on the Starter plan.';

  @override
  String get plansProTitle => 'Orbit Pro';

  @override
  String get plansProSubtitle => 'Maximum speed, unlimited insights';

  @override
  String get plansProBillingPeriodAnnual => 'per month, billed yearly';

  @override
  String get plansBillingPeriodMonthly => 'per month';

  @override
  String get plansMostPopularBadge => '🔥 MOST POPULAR';

  @override
  String get plansProButton => 'Upgrade to Pro';

  @override
  String get plansProFeature1 => '1,200 Monthly Credits (12x boost)';

  @override
  String get plansProFeature2 => 'Realtime On-Device & Whisper ASR';

  @override
  String get plansProFeature3 => 'Unlimited Deep Notes & Review Cards';

  @override
  String get plansProFeature4 => 'High-Priority AI Model Speed';

  @override
  String get plansProFeature5 => 'Export Transcripts (PDF & Markdown)';

  @override
  String get plansProFeature6 => 'Full Galaxy Knowledge Graph';

  @override
  String get plansMaxTitle => 'Orbit Max';

  @override
  String get plansMaxSubtitle => 'For heavy researchers & power users';

  @override
  String get plansBestValueBadge => '⚡ BEST VALUE';

  @override
  String get plansMaxButton => 'Get Orbit Max';

  @override
  String get plansMaxFeature1 => '3,500 Monthly Credits';

  @override
  String get plansMaxFeature2 => 'All Pro Features Included';

  @override
  String get plansMaxFeature3 => 'Advanced Galaxy Knowledge Graph';

  @override
  String get plansMaxFeature4 => 'Custom AI Model Context & Fine-tuning';

  @override
  String get plansMaxFeature5 => 'Dedicated 24/7 Priority Support';

  @override
  String get plansMaxFeature6 => 'Early Access to New Experimental Features';

  @override
  String get plansFooterNote => 'Cancel anytime. Encrypted & secure.';

  @override
  String plansSelectDialogTitle(String planName) {
    return 'Select $planName';
  }

  @override
  String plansSelectDialogMessage(String planName) {
    return '$planName purchasing flow is coming soon in the next update!';
  }

  @override
  String get plansSelectDialogConfirmButton => 'Got it';

  @override
  String get changePasswordResetSentTitle => 'Reset Link Sent';

  @override
  String changePasswordResetSentMessage(String email) {
    return 'We have sent a password reset link to your email address ($email). Please check your inbox and click the link to set your new password.';
  }

  @override
  String get changePasswordCloseButton => 'Close';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get changePasswordSubtitle =>
      'Enter your current password to verify your identity and send a reset link to your email.';

  @override
  String get changePasswordSlowServerError =>
      'The email service is taking longer than usual to start. Please try again in a moment.';

  @override
  String get changePasswordCurrentPasswordLabel => 'Current Password';

  @override
  String get changePasswordCurrentPasswordRequiredError =>
      'Please enter your current password';

  @override
  String get changeEmailDifferentRequiredError =>
      'New email must be different from current email';

  @override
  String get changeEmailSendingVerificationStatus =>
      'Sending verification email...';

  @override
  String get changeEmailVerificationSentTitle => 'Verification Email Sent';

  @override
  String get changeEmailVerificationSentMessage =>
      'A verification link has been sent to both your current email and new email. Please verify the change from both boxes to complete the update.';

  @override
  String get changeEmailTitle => 'Change Email';

  @override
  String changeEmailCurrentEmailLabel(String email) {
    return 'Your current email address is $email';
  }

  @override
  String get changeEmailNewLabel => 'New Email Address';

  @override
  String get changeEmailRequiredError => 'Please enter a new email';

  @override
  String get changeEmailInvalidError => 'Please enter a valid email address';

  @override
  String get changeEmailConfirmButton => 'Confirm Change';

  @override
  String get userProfileDetailTitle => 'Profile';

  @override
  String get userProfileDetailEditTooltip => 'Edit Profile';

  @override
  String changeAuthProviderCurrentLabel(String provider) {
    return 'Current: $provider';
  }

  @override
  String get changeAuthProviderUnknownProvider => 'Unknown';

  @override
  String get changeAuthProviderFooterNote =>
      '※ Changing your login method will update your authentication settings. You can switch back anytime.';

  @override
  String changeAccountCurrentLabel(String value) {
    return 'Current: $value';
  }

  @override
  String changeAccountButtonLabel(String provider) {
    return 'Choose a different $provider account';
  }

  @override
  String get courseSheetSaveButton => 'Save';

  @override
  String get courseNoAnnouncementsLabel => 'No announcements yet';

  @override
  String get coursePageTitle => 'Courses';

  @override
  String get coursePageNewCourseButton => 'New Course';

  @override
  String coursePageLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get coursePageEmptyTitle => 'No courses yet';

  @override
  String get coursePageEmptySubtitle =>
      'Create your first course to get started';

  @override
  String get coursePageNoYearLabel => 'No Year';

  @override
  String get coursePageNoTermLabel => 'No Term';

  @override
  String get coursePageTopicMapTitle => 'Topic Map';

  @override
  String get coursePageTopicMapRecreatingLabel => 'Recreating…';

  @override
  String get coursePageTopicMapRecreateLabel => 'Recreate Topic Map';

  @override
  String get coursePageTopicMapOpenLabel => 'Open Topic Map';

  @override
  String get coursePageTopicMapNotGeneratedLabel => 'Not generated yet';

  @override
  String get coursePageLecturesTitle => 'Lectures';

  @override
  String get coursePageNoLecturesYet => 'No lectures recorded yet';

  @override
  String get coursePageNewLectureButton => 'New Lecture';

  @override
  String get coursePageRecreateTopicMapDialogTitle => 'Recreate Topic Map?';

  @override
  String get coursePageRecreateTopicMapDialogMessage =>
      'Do you want to recreate the topic map? This repairs it after recent lecture changes and may take a few minutes.';

  @override
  String get coursePageRecreateConfirmButton => 'Recreate';

  @override
  String get coursePageRecreateErrorTitle => 'Could not recreate topic map';

  @override
  String get coursePageOkButton => 'OK';

  @override
  String get coursePageOfflineSnackbar =>
      'You\'re offline. Showing cached data.';

  @override
  String get courseCreateSheetEditTitle => 'Edit Course';

  @override
  String get courseCreateSheetNewTitle => 'New Course';

  @override
  String get courseCreateSheetDesignPreviewLabel => 'Design Preview';

  @override
  String get courseCreateSheetPreviewTitlePlaceholder => 'New Course Title';

  @override
  String get courseCreateSheetPreviewSubtitle => 'Visual Representation';

  @override
  String get courseCreateSheetColorLabel => 'Course Color';

  @override
  String get courseCreateSheetIconLabel => 'Course Icon';

  @override
  String get courseCreateSheetYearLabel => 'Year';

  @override
  String get courseCreateSheetYearHint => 'e.g. 2026';

  @override
  String get courseCreateSheetTermLabel => 'Term';

  @override
  String get courseCreateSheetTermHint => 'e.g. Fall';

  @override
  String get courseCreateSheetTitleLabel => 'Course Title *';

  @override
  String get courseCreateSheetTitleHint =>
      'e.g. Introduction to Computer Science';

  @override
  String get courseCreateSheetMoreInfoLabel => 'More Info';

  @override
  String get courseCreateSheetCodeLabel => 'Course Code';

  @override
  String get courseCreateSheetCodeHint => 'e.g. CS101';

  @override
  String get courseCreateSheetProfessorLabel => 'Professor';

  @override
  String get courseCreateSheetProfessorHint => 'e.g. Dr. Smith';

  @override
  String get courseCreateSheetSchoolLabel => 'School';

  @override
  String get courseCreateSheetSchoolHint => 'e.g. UCLA';

  @override
  String get courseCreateSheetSubjectLabel => 'Subject';

  @override
  String get courseCreateSheetSubjectHint => 'e.g. Computer Science';

  @override
  String get courseCreateSheetSummaryLabel => 'Summary';

  @override
  String get courseCreateSheetSummaryHint => 'What is this course about?';

  @override
  String get courseCreateSheetTitleRequiredError => 'Course title is required';

  @override
  String get courseCreateSheetCustomColorDialogTitle => 'Custom Color';

  @override
  String get courseCreateSheetHueLabel => 'Hue';

  @override
  String get courseCreateSheetLightnessLabel => 'Lightness';

  @override
  String get courseCreateSheetHexLabel => 'Hex Color Code';

  @override
  String get courseCreateSheetCancelButton => 'Cancel';

  @override
  String get courseCreateSheetOkButton => 'OK';

  @override
  String get lectureEditSheetChangeCourseDialogTitle => 'Change Course?';

  @override
  String get lectureEditSheetChangeCourseDialogMessage =>
      'Changing the course of this lecture will modify Topic Map structures and might affect synchronization. Are you sure you want to proceed?';

  @override
  String get lectureEditSheetProceedButton => 'Proceed';

  @override
  String get lectureEditSheetTitle => 'Edit Lecture';

  @override
  String get lectureEditSheetCourseLabel => 'Course';

  @override
  String get lectureEditSheetNoCourseLabel => 'No Course (Unassigned)';

  @override
  String get lectureEditSheetUnknownCourseFallback => 'Unknown Course';

  @override
  String get lectureEditSheetDateTimeLabel => 'Lecture Date & Time';

  @override
  String get lectureEditSheetTitleFieldLabel => 'Title';

  @override
  String lectureEditSheetTitleFieldDefaultSuffix(String title) {
    return '$title (Default)';
  }

  @override
  String get announcementEditSheetTitleRequiredError =>
      'Title cannot be empty.';

  @override
  String get announcementEditSheetTitle => 'Edit Announcement';

  @override
  String get announcementEditSheetTypeLabel => 'Type';

  @override
  String get announcementEditSheetTitleFieldLabel => 'Title';

  @override
  String get announcementEditSheetTitleFieldHint => 'Announcement title';

  @override
  String get announcementEditSheetDescriptionFieldLabel => 'Description';

  @override
  String get announcementEditSheetDescriptionFieldHint =>
      'Additional details (optional)';

  @override
  String get announcementEditSheetTypeTodo => 'Todo';

  @override
  String get announcementEditSheetTypeEvent => 'Event';

  @override
  String get announcementEditSheetTypeHint => 'Hint';

  @override
  String get announcementEditSheetTypeInfo => 'Info';

  @override
  String get courseDetailsSheetCreatedLabel => 'Created';

  @override
  String courseAnnouncementsSheetLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get audioPlayerBarTopicIndexTitle => 'Topic Index';

  @override
  String audioPlayerBarTopicLabel(int index) {
    return 'Topic $index';
  }

  @override
  String get audioPlayerBarDownloadingMessage =>
      'Downloading audio from storage…';

  @override
  String audioPlayerBarLoadErrorMessage(String error) {
    return 'Failed to load audio: $error';
  }

  @override
  String get audioPlayerBarPreparingMessage => 'Preparing audio player…';

  @override
  String get audioPlayerBarPreviousTopicTooltip =>
      'Previous Topic / Restart Topic';

  @override
  String get audioPlayerBarRewindTooltip => 'Rewind 10s';

  @override
  String get audioPlayerBarForwardTooltip => 'Forward 10s';

  @override
  String get audioPlayerBarNextTopicTooltip => 'Next Topic';

  @override
  String get audioPlayerBarTopicIndexMenuTooltip => 'Topic Index Menu';

  @override
  String announcementTranscriptModalErrorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get announcementTranscriptModalLectureNotFound => 'Lecture not found';

  @override
  String get announcementTranscriptModalAutoScrollOnTooltip =>
      'Auto-scroll Mode (5s Resume)';

  @override
  String get announcementTranscriptModalAutoScrollOffTooltip =>
      'Auto-scroll Disabled (OFF)';

  @override
  String get announcementTranscriptModalOfflineMessage =>
      'You\'re offline. Transcript will load once you\'re back online.';

  @override
  String announcementTranscriptModalUnavailableError(String error) {
    return 'Transcript unavailable: $error';
  }

  @override
  String get announcementTranscriptModalGeneratingMessage =>
      'Transcript is being generated…';

  @override
  String announcementTranscriptModalTopicLabel(int index) {
    return 'Topic $index';
  }

  @override
  String get announcementTranscriptModalLectureFallbackTitle => 'Lecture';

  @override
  String get announcementTranscriptModalOfflineErrorShort => 'You\'re offline';

  @override
  String transcriptPageLectureLoadError(String error) {
    return 'Error loading lecture: $error';
  }

  @override
  String get transcriptPageLectureNotFound => 'Lecture not found';

  @override
  String get transcriptPageTitle => 'Transcript';

  @override
  String get transcriptPageAutoScrollOnTooltip =>
      'Auto-scroll Mode (5s Resume)';

  @override
  String get transcriptPageAutoScrollOffTooltip => 'Auto-scroll Disabled (OFF)';

  @override
  String get transcriptPageOfflineMessage =>
      'You\'re offline. Transcript will load once you\'re back online.';

  @override
  String transcriptPageUnavailableError(String error) {
    return 'Transcript unavailable: $error';
  }

  @override
  String get transcriptPageGeneratingMessage =>
      'Transcript is being generated…';

  @override
  String transcriptPageTopicLabel(int index) {
    return 'Topic $index';
  }

  @override
  String get transcriptPageOfflineErrorShort => 'You\'re offline';

  @override
  String get cardSelectionToolbarHighlightLabel => 'Highlight';

  @override
  String get cardSelectionToolbarNoteLabel => 'Note';

  @override
  String get cardSelectionToolbarCopyLabel => 'Copy';

  @override
  String get cardSelectionToolbarSourceLabel => 'Source';

  @override
  String get cardSelectionToolbarLikeLabel => 'Like';

  @override
  String get cardSelectionToolbarDislikeLabel => 'Dislike';

  @override
  String get cardSelectionToolbarSaveLabel => 'Save';

  @override
  String get noteToolbarHintText => 'Add a note...';

  @override
  String get cardSelectionToolbarSourceNotFoundMessage =>
      'No source found for the selection.';

  @override
  String get cardSelectionToolbarCopiedToClipboardMessage =>
      'Copied to clipboard';

  @override
  String get reviewCardsViewerNoCardsYet => 'No review cards yet';

  @override
  String get reviewCardsViewerViewListTooltip => 'View List';

  @override
  String reviewCardsViewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get reviewCardsViewerListSheetTitle => 'Review Cards List';

  @override
  String get reviewCardsViewerNavigationHint =>
      'Tap left / right  •  Swipe to change topic';

  @override
  String get reviewCardsDashboardGeneratingMessage =>
      'Review cards are being generated…';

  @override
  String get reviewCardsDashboardTitle => 'Review Cards';

  @override
  String get deepNotesListTitle => 'Deep Notes';

  @override
  String get deepNotesDetailNoNotesAvailable => 'No notes available';

  @override
  String get deepNotesDetailViewListTooltip => 'View List';

  @override
  String deepNotesDetailPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get deepNotesDetailListSheetTitle => 'Deep Notes List';

  @override
  String get deepNotesDetailPullPrevHint => 'Pull or tap to previous note';

  @override
  String get deepNotesDetailPullNextHint => 'Pull or tap to next note';

  @override
  String get deepNotesDetailContentGeneratingPlaceholder =>
      'Deep notes for this topic are still being generated…';

  @override
  String get deepNotesListGeneratingMessage =>
      'Deep notes are being generated…';

  @override
  String lectureNotePageTopicLabel(int index) {
    return 'Topic $index';
  }

  @override
  String get homeOfflineSnackBarMessage =>
      'You\'re offline. Showing cached data.';

  @override
  String get homeRecordLectureButton => 'Record Lecture';

  @override
  String get homeAnnouncementsSheetTitle => 'Announcements';

  @override
  String get homeAnnouncementsEmptyMessage =>
      'No announcements — you\'re all caught up!';

  @override
  String homeAnnouncementsSheetLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get homeEmptyAnnouncementMessage1 => 'Keep exploring the universe!';

  @override
  String get homeEmptyAnnouncementMessage2 =>
      'Every star started as stardust. Keep going.';

  @override
  String get homeEmptyAnnouncementMessage3 =>
      'Your galaxy is quiet for now — the next lecture will light it up.';

  @override
  String get homeEmptyAnnouncementMessage4 =>
      'No news is good news. Time to learn something new?';

  @override
  String get homeEmptyAnnouncementMessage5 =>
      'The universe is patient. So can you be.';

  @override
  String get homeCoursesSectionTitle => 'Courses';

  @override
  String get homeRecentLecturesSectionTitle => 'RECENT LECTURES';

  @override
  String get emptyHomeDefaultName => 'Explorer';

  @override
  String emptyHomeWelcomeGreeting(String name) {
    return 'Welcome to leFture, $name.';
  }

  @override
  String get emptyHomeStartBuilding => 'Start building your future.';

  @override
  String get emptyHomeGalaxyDescription =>
      'Every lecture you add lights a new star.\nKeep learning, and this galaxy will grow into one that\'s entirely your own.';

  @override
  String get emptyHomeStepMakeProfileTitle => 'Make Profile';

  @override
  String get emptyHomeStepMakeProfileDoneSubtitle => 'Your profile is set';

  @override
  String get emptyHomeStepMakeProfilePendingSubtitle =>
      'Tell leFture a bit about yourself';

  @override
  String get emptyHomeStepCreateCourseTitle => 'Create Course';

  @override
  String get emptyHomeStepCreateCourseDisabledSubtitle =>
      'Complete your profile first';

  @override
  String get emptyHomeStepCreateCourseDoneSubtitle => 'Course created';

  @override
  String get emptyHomeStepCreateCoursePendingSubtitle =>
      'Add your first course';

  @override
  String get emptyHomeStepRecordLectureTitle => 'Record Lecture';

  @override
  String get emptyHomeStepRecordLectureDisabledSubtitle =>
      'Create a course first';

  @override
  String get emptyHomeStepRecordLectureDoneSubtitle => 'Lecture recorded';

  @override
  String get emptyHomeStepRecordLecturePendingSubtitle =>
      'Record your first lecture';

  @override
  String get funFactsUntitledLecture => 'Untitled Lecture';

  @override
  String get funFactsUnknownLecture => 'Unknown Lecture';

  @override
  String funFactsUpdateReactionFailed(String error) {
    return 'Failed to update reaction: $error';
  }

  @override
  String get funFactsDefaultCardTitle => 'We are made of star-stuff';

  @override
  String get funFactsDefaultCardBody =>
      'You are made of star-stuff ✨ The carbon, oxygen, and iron in your body were forged in exploding stars billions of years ago. The history of the cosmos lives inside you.';

  @override
  String get funFactsDefaultCardFooter => 'Cosmic Origin · Carl Sagan';

  @override
  String get makeProfileBioEmptyError =>
      'Tell us a little about yourself first';

  @override
  String get makeProfileSheetTitle => 'Make Your Profile';

  @override
  String get makeProfileSheetSubtitle =>
      'This helps leFture personalize your fun facts and study material.';

  @override
  String get makeProfileChangeAvatarComingSoon => 'Change Avatar (Coming Soon)';

  @override
  String get makeProfileUsernameHint => 'e.g. Shogo';

  @override
  String get makeProfileAboutYouLabel => 'About You *';

  @override
  String get makeProfileAboutYouHint =>
      'Who are you, what do you study, how do you like to learn?';

  @override
  String get makeProfileInterestsLabel => 'Interests';

  @override
  String get makeProfileInterestsHint => 'e.g. astronomy, guitar, history';

  @override
  String get makeProfileFutureDreamsLabel => 'Future Dreams';

  @override
  String get makeProfileFutureDreamsHint => 'What are you working toward?';

  @override
  String get makeProfileSaveButton => 'Save Profile';

  @override
  String get courseIconCategorySchool => 'School';

  @override
  String get courseIconCategoryHumanityLang => 'Humanity & Lang';

  @override
  String get courseIconCategorySocietyLaw => 'Society & Law';

  @override
  String get courseIconCategoryScienceSpace => 'Science & Space';

  @override
  String get courseIconCategoryTechBuild => 'Tech & Build';

  @override
  String get courseIconCategoryAgriMarine => 'Agri & Marine';

  @override
  String get courseIconCategoryMedical => 'Medical';

  @override
  String get courseIconCategorySportsHealth => 'Sports & Health';

  @override
  String get courseIconCategoryArtTravel => 'Art & Travel';

  @override
  String contactFailedToPickFile(String error) {
    return 'Failed to pick file: $error';
  }

  @override
  String get contactAuthError => 'Authentication error. Please sign in again.';

  @override
  String get contactConnecting => 'Connecting to support service...';

  @override
  String get contactSlowService =>
      'The support service is taking longer than usual to start. Please try again in a moment, or email us directly at support@lefture.com.';

  @override
  String get contactSending => 'Sending inquiry...';

  @override
  String get contactPreparingUpload => 'Preparing file upload...';

  @override
  String get contactUploadingAttachment => 'Uploading attachment...';

  @override
  String get contactSubmittingTicket => 'Submitting support ticket...';

  @override
  String get contactTimeoutError =>
      'Connection timed out. Please check your network and try again, or email us at support@lefture.com.';

  @override
  String contactSubmissionError(String error) {
    return 'Submission failed: $error. You can also email us at support@lefture.com.';
  }

  @override
  String get contactTitleSent => 'Sent';

  @override
  String get contactTitle => 'Contact Us';

  @override
  String get contactHelpTitle => 'How can we help you?';

  @override
  String get contactHelpSubtitle =>
      'Please choose a category and specify your question or bug report below. We will reply to your email shortly.';

  @override
  String get contactCategoryLabel => 'Category';

  @override
  String get contactCategoryBug => 'Bug Report';

  @override
  String get contactCategoryFeedback => 'Request / Feedback';

  @override
  String get contactCategoryAccount => 'Account / Login';

  @override
  String get contactCategoryOther => 'Other';

  @override
  String get contactMessageDetailsLabel => 'Message Details';

  @override
  String get contactMessageRequired => 'Please enter your message details';

  @override
  String get contactAttachmentLabel => 'Attachment (Optional)';

  @override
  String get contactUploadButton => 'Upload Screenshot or File';

  @override
  String get contactSubmitButton => 'Send Inquiry';

  @override
  String get contactSuccessTitle => 'Inquiry Sent';

  @override
  String get contactSuccessDescription =>
      'Your inquiry has been successfully sent. A confirmation email has been sent to your inbox. We will review your message and reply via email.';

  @override
  String get contactTicketCodeLabel => 'Ticket Code';

  @override
  String get contactBackToSettingsButton => 'Back to Settings';

  @override
  String get appErrorDialogGuidance =>
      'Please wait a moment and try again. If the issue persists, please take a screenshot of this screen and contact us via Contact Us.';

  @override
  String get appErrorDialogTechnicalDetails => 'Technical Details:';

  @override
  String get appErrorDialogContactSupport => 'Contact Support';

  @override
  String get appErrorDialogClose => 'Close';

  @override
  String get appErrorBoxGuidance =>
      'Please wait a moment and try again. If the issue persists, please take a screenshot and contact support.';

  @override
  String get offlineBannerMessage => 'You\'re offline';

  @override
  String get recordingMiniPlayerRecording => 'Recording...';

  @override
  String get recordingMiniPlayerPaused => 'Recording Paused';

  @override
  String get aiChatSheetTitle => 'Ask AI';

  @override
  String get aiChatSheetInputHint => 'Ask about this lecture...';

  @override
  String get aiChatSheetPreviewFallback =>
      'This is a UI preview — real AI answers aren\'t wired up yet.';

  @override
  String get courseDeleteDialogTitle => 'Delete Course?';

  @override
  String courseDeleteDialogMessage(String title) {
    return 'Are you sure you want to delete \"$title\"? All lectures inside this course, and everything generated from them, will be deleted too.';
  }

  @override
  String get announcementDeleteDialogTitle => 'Delete Announcement?';

  @override
  String announcementDeleteDialogMessage(String title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get spaceshipAnnouncementGotIt => 'Got It';

  @override
  String get authOrDivider => 'or';

  @override
  String get commonEditButton => 'Edit';

  @override
  String get commonDeleteButton => 'Delete';

  @override
  String get legalDocumentLoadErrorTitle => 'Couldn\'t load this document';

  @override
  String get legalDocumentLoadErrorSubtitle =>
      'Check your connection and try again.';

  @override
  String get commonRetryButton => 'Retry';

  @override
  String legalDocumentLastUpdated(String date) {
    return 'Last updated $date';
  }

  @override
  String get broadSelectionSheetTitle => 'Select Transcript Section';

  @override
  String get broadSelectionSheetDescription =>
      'Multiple sections are included in your selection. Select which section you would like to view:';

  @override
  String get introBackButton => 'Back';

  @override
  String get introLanguageButton => 'Language';

  @override
  String get introNextButton => 'Next';

  @override
  String get introHeroEyebrow => 'Welcome to leFture';

  @override
  String get introHeroTitleLine1 => 'Record your lectures,';

  @override
  String get introHeroTitleLine2 => 'for your futures.';

  @override
  String get introHeroSubtitle => 'Dull lectures are now your entertainment.';

  @override
  String get introHeroStageLabel => 'recording → your universe';

  @override
  String get introMagicEyebrow => 'Three kinds of magic waiting for you';

  @override
  String get introMagicHeadline =>
      'Just hit record.\nWe’ll build your playground.';

  @override
  String get introMagicCard1Tag => 'Review Cards';

  @override
  String get introMagicCard1Title => 'Right after class, review made easy';

  @override
  String get introMagicCard1Desc =>
      'The moment you stop recording, key points are already distilled into cards.';

  @override
  String get introMagicCard2Tag => 'Deep Notes';

  @override
  String get introMagicCard2Title => 'Detailed notes, complete understanding';

  @override
  String get introMagicCard2Desc =>
      'Missed something? No worries — thorough notes have you covered.';

  @override
  String get introMagicCard3Tag => 'Fun Facts';

  @override
  String get introMagicCard3Title =>
      'Fun facts that hit your curiosity dead-on';

  @override
  String get introMagicCard3Desc =>
      'Delivered to spark exactly the kind of ‘huh, neat!’ you love.';

  @override
  String get introCtaLead =>
      'Learning excitement\nlike you\'ve never felt before.';

  @override
  String get introCtaSub =>
      'Start today.\nCreating an account is free and takes 30 seconds.';

  @override
  String get introCtaButton => 'Start recording your future, free';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get onboardingBackButton => 'Back';

  @override
  String get onboardingSkipButton => 'Skip';

  @override
  String get onboardingNextButton => 'Next';

  @override
  String get onboardingContinueButton => 'Continue';

  @override
  String get onboardingGetStartedButton => 'Get started';

  @override
  String get onboardingTutorialEyebrow => 'Welcome';

  @override
  String get onboardingTutorialTitle => 'Tutorial slides — coming soon';

  @override
  String get onboardingTutorialSubtitle =>
      'We\'re still designing this part — for now, let\'s get you set up.';

  @override
  String get onboardingPermissionsEyebrow => 'Setup';

  @override
  String get onboardingPermissionsTitle => 'Two quick permissions';

  @override
  String get onboardingPermissionsSubtitle =>
      'leFture needs these to record and to let you know when your notes are ready.';

  @override
  String get onboardingPermissionsMicTitle => 'Microphone';

  @override
  String get onboardingPermissionsMicSubtitle =>
      'So leFture can hear your lecture and transcribe it live.';

  @override
  String get onboardingPermissionsNotifTitle => 'Notifications';

  @override
  String get onboardingPermissionsNotifSubtitle =>
      'Know when notes and fun facts finish processing in the background.';

  @override
  String get onboardingPlanEyebrow => 'Almost done';

  @override
  String get onboardingPlanTitle => 'leFture is free right now';

  @override
  String get onboardingPlanBadge => 'Beta · free plan included';

  @override
  String get onboardingPlanSubtitle =>
      'Every feature is free while we\'re testing. Paid plans will live here later.';

  @override
  String get onboardingPlanActiveTitle => 'You\'re already on a plan';

  @override
  String get onboardingPlanClaimError =>
      'Couldn\'t activate your free plan. You can try again from your account page later.';

  @override
  String get onboardingDoneTitle => 'You\'re all set';

  @override
  String get onboardingDoneSubtitle =>
      'Let\'s create a course and record your first lecture!';
}
