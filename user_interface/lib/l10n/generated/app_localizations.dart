import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// Large headline on the sign-in screen, greeting a returning user. Warm and casual, not formal.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get signInWelcomeTitle;

  /// Subtitle under the sign-in headline. 'learning journey' refers to the user's ongoing lecture study progress in the app, keep the encouraging tone.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue your learning journey'**
  String get signInSubtitle;

  /// Floating label text inside the email text field. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// Floating label text inside the password text field. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Inline validation error shown when the user taps Sign In with an empty email field. Polite request, not scolding.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address.'**
  String get signInErrorEmailEmpty;

  /// Inline validation error shown when the user taps Sign In with an empty password field. Polite request, not scolding.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password.'**
  String get signInErrorPasswordEmpty;

  /// Small tappable link above the Sign In button that leads to password reset. Standard app UI phrase, keep it short.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordLink;

  /// Primary call-to-action button label that submits the sign-in form. Keep as a short imperative/label, not a full sentence.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInButton;

  /// Single word shown between two horizontal lines, separating email/password sign-in from social sign-in buttons below. Must stay very short (1 word) to fit the divider.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authDividerOr;

  /// Button label to sign in via Google OAuth. 'Google' is the brand name and must NOT be translated or transliterated.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// Button label to sign in via Apple OAuth. 'Apple' is the brand name and must NOT be translated or transliterated.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// Button label on the sign-up screen that expands an accordion with email/password fields, shown alongside 'Continue with Google'/'Continue with Apple' as an equal third option.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get continueWithEmail;

  /// Leading half of a sentence immediately followed by the 'Create Account' link button on the same line, e.g. "Don't have an account? [Create Account]". Keep it able to flow into a following link naturally; trailing space in English is intentional for layout, translations don't need to preserve the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get signInNoAccountPrompt;

  /// Tappable link, continues the sentence started by signInNoAccountPrompt, navigates to the sign-up screen. Short label, matches tone of a button/link rather than a full sentence.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccountLink;

  /// Snackbar toast shown right after successful sign-up, telling the user to check their inbox for a verification email. Celebratory but brief.
  ///
  /// In en, this message translates to:
  /// **'Account created! Please check your email to verify.'**
  String get signUpSuccessSnackbar;

  /// Inline error shown when the user taps Create Account without checking the terms-agreement checkbox.
  ///
  /// In en, this message translates to:
  /// **'Please agree to the Terms and Conditions'**
  String get signUpErrorAgreeTerms;

  /// Large headline on the sign-up screen. 'leFture' is the app's brand name (stylized, lowercase 'le' + capital 'F') and must NOT be translated or transliterated — keep it verbatim in every language.
  ///
  /// In en, this message translates to:
  /// **'Join leFture'**
  String get signUpTitle;

  /// Subtitle under the sign-up headline. Encouraging, casual tone, same 'learning journey' concept as the sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Start your learning journey today'**
  String get signUpSubtitle;

  /// Floating label text inside the username text field on sign-up. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get usernameLabel;

  /// Inline validation error when the username field is left empty on sign-up.
  ///
  /// In en, this message translates to:
  /// **'Please enter a username'**
  String get signUpErrorUsernameEmpty;

  /// Inline validation error when the username is shorter than the 3-character minimum.
  ///
  /// In en, this message translates to:
  /// **'Username must be at least 3 characters'**
  String get signUpErrorUsernameTooShort;

  /// Shared inline validation error for an empty email field, used across sign-up and forgot-password forms (not the sign-in form, which has its own slightly different wording).
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get authErrorEmailRequired;

  /// Shared inline validation error when the email field fails format validation, used across sign-up and forgot-password forms.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get authErrorEmailInvalid;

  /// Floating label text inside the 'confirm password' field on sign-up. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPasswordLabel;

  /// Inline validation error when the password field is left empty on sign-up.
  ///
  /// In en, this message translates to:
  /// **'Please enter a password'**
  String get signUpErrorPasswordEmpty;

  /// Shared inline validation error when a password is shorter than the 8-character minimum, used on both sign-up and reset-password forms.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordErrorTooShort;

  /// Inline validation error when the 'confirm password' field is left empty on sign-up.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get confirmPasswordErrorEmpty;

  /// Shared inline validation error when password and confirm-password fields differ, used on both sign-up and reset-password forms.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsMismatchError;

  /// First fragment of a sentence rendered as: [signUpAgreementPrefix][termsAndConditionsLink (tappable)][signUpAgreementMiddle][privacyPolicyLink (tappable)][signUpAgreementSuffix]. The two link fragments are always rendered in this fixed order (Terms then Privacy) and are individually tappable, so they cannot be merged into the surrounding text. If your language's grammar needs the verb/particle at the end instead of the start, move that wording into signUpAgreementSuffix and leave this prefix empty or minimal — do not try to reorder the two links themselves.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get signUpAgreementPrefix;

  /// Tappable link text (first of two) inside the sign-up agreement sentence; opens the Terms and Conditions document. See signUpAgreementPrefix for how the surrounding sentence is assembled.
  ///
  /// In en, this message translates to:
  /// **'Terms and Conditions'**
  String get termsAndConditionsLink;

  /// Fragment between the two tappable links in the sign-up agreement sentence (see signUpAgreementPrefix). Just the conjunction/connector, e.g. ' and ' or the equivalent particle.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get signUpAgreementMiddle;

  /// Tappable link text (second of two) inside the sign-up agreement sentence; opens the Privacy Policy document. See signUpAgreementPrefix for how the surrounding sentence is assembled.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyLink;

  /// Final fragment of the sign-up agreement sentence, after both links (see signUpAgreementPrefix). Empty in English because the sentence already ends after the two links; languages that put the verb ('...に同意します' etc.) at the end should put it here instead of in the prefix.
  ///
  /// In en, this message translates to:
  /// **''**
  String get signUpAgreementSuffix;

  /// Primary call-to-action button that submits the sign-up form and creates the account. Note this is a different UI element from createAccountLink (which is a small nav link elsewhere) even though the English text happens to match — translate based on this being a prominent submit button.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get signUpSubmitButton;

  /// Leading half of a sentence immediately followed by the 'Sign In' link on the sign-up screen, e.g. "Already have an account? [Sign In]". Same pattern as signInNoAccountPrompt but inverted direction.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get signUpHasAccountPrompt;

  /// Small tappable link (not a form-submit button) that navigates back to the sign-in screen, used from sign-up and forgot-password screens. Short label.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signInLink;

  /// Transient status line shown under a loading spinner while the backend cold-starts before sending a password reset email. Informal, reassuring tone.
  ///
  /// In en, this message translates to:
  /// **'Waking up email service...'**
  String get forgotPasswordStatusWaking;

  /// Transient status line shown under a loading spinner while the password reset email is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending reset link...'**
  String get forgotPasswordStatusSending;

  /// Error message shown if the backend fails to warm up in time before sending the password reset email.
  ///
  /// In en, this message translates to:
  /// **'The email service is taking longer than usual to start.'**
  String get forgotPasswordErrorSlowServer;

  /// Headline shown after a password reset email was successfully sent.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get forgotPasswordSuccessTitle;

  /// Headline on the forgot-password screen before the user submits their email. Casual, matches the tone of a question.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPasswordTitle;

  /// Confirmation message shown after sending the reset email, with the user's own email address interpolated at the end.
  ///
  /// In en, this message translates to:
  /// **'We\'ve sent a password reset link to {email}'**
  String forgotPasswordSuccessMessage(String email);

  /// Subtitle on the forgot-password screen before submission, reassuring and casual tone ('No worries').
  ///
  /// In en, this message translates to:
  /// **'No worries, enter your email and we\'ll send you a reset link'**
  String get forgotPasswordSubtitle;

  /// Outlined button shown after the reset email is sent, lets the user go back and resend to a different email. Casual, conversational phrasing.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t get it? Try again'**
  String get forgotPasswordRetryButton;

  /// Button shown after the reset email is sent, for users who already clicked the emailed link elsewhere and want to jump to the reset-password form directly.
  ///
  /// In en, this message translates to:
  /// **'I have a reset link'**
  String get forgotPasswordHaveLinkButton;

  /// Primary call-to-action button that submits the forgot-password form and triggers the reset email.
  ///
  /// In en, this message translates to:
  /// **'Send Reset Link'**
  String get sendResetLinkButton;

  /// Leading half of a sentence immediately followed by the 'Sign In' link on the forgot-password screen, e.g. "Remembered your password? [Sign In]".
  ///
  /// In en, this message translates to:
  /// **'Remembered your password? '**
  String get rememberedPasswordPrompt;

  /// Error-state headline shown when the user opens a password-reset email link that is no longer valid.
  ///
  /// In en, this message translates to:
  /// **'Link invalid or expired'**
  String get resetPasswordLinkInvalidTitle;

  /// Button on the invalid/expired reset-link error screen that sends the user back to request a fresh reset email.
  ///
  /// In en, this message translates to:
  /// **'Request a New Link'**
  String get requestNewLinkButton;

  /// Success-state headline shown after the user successfully sets a new password.
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get resetPasswordSuccessTitle;

  /// Success-state body message shown after the user successfully sets a new password. Warm, celebratory closing tone ('You're all set!').
  ///
  /// In en, this message translates to:
  /// **'Your password has been updated successfully. You\'re all set!'**
  String get resetPasswordSuccessMessage;

  /// Button on the password-reset success screen that takes the user into the app's main/home screen.
  ///
  /// In en, this message translates to:
  /// **'Go to Dashboard'**
  String get goToDashboardButton;

  /// Headline on the reset-password form (reached via emailed link).
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get resetPasswordTitle;

  /// Subtitle/instruction on the reset-password form.
  ///
  /// In en, this message translates to:
  /// **'Your new password must be different from previously used passwords'**
  String get resetPasswordSubtitle;

  /// Floating label text inside the new-password field on the reset-password form. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// Inline validation error when the new-password field is left empty on the reset-password form.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new password'**
  String get resetPasswordErrorEmpty;

  /// Floating label text inside the 'confirm new password' field on the reset-password form. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPasswordLabel;

  /// Inline validation error when the 'confirm new password' field is left empty on the reset-password form.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your new password'**
  String get confirmNewPasswordErrorEmpty;

  /// Primary call-to-action button that submits the reset-password form.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPasswordButton;

  /// Short checklist-item / helper-text label describing a password requirement (minimum length). Used both as a field helper text and as a live checklist item next to a checkmark icon — keep it short enough to fit inline next to an icon.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordReqMinLength;

  /// Short checklist-item label describing a password requirement (needs both uppercase and lowercase letters). Displayed next to a checkmark icon in a live password-strength checklist.
  ///
  /// In en, this message translates to:
  /// **'Upper & lowercase letters'**
  String get passwordReqUpperLower;

  /// Short checklist-item label describing a password requirement (needs at least one digit). Displayed next to a checkmark icon in a live password-strength checklist.
  ///
  /// In en, this message translates to:
  /// **'At least one number'**
  String get passwordReqDigit;

  /// Short checklist-item label describing a password requirement (needs at least one symbol/special character). Displayed next to a checkmark icon in a live password-strength checklist.
  ///
  /// In en, this message translates to:
  /// **'At least one symbol'**
  String get passwordReqSymbol;

  /// Single-word password strength rating, shown next to a segmented strength bar as the user types a password. Keep to 1 short word.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passwordStrengthWeak;

  /// Single-word password strength rating (better than Weak, worse than Good), shown next to a segmented strength bar. Keep to 1 short word.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get passwordStrengthFair;

  /// Single-word password strength rating (better than Fair, worse than Strong), shown next to a segmented strength bar. Keep to 1 short word.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get passwordStrengthGood;

  /// Single-word password strength rating, the highest tier, shown next to a segmented strength bar. Keep to 1 short word.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passwordStrengthStrong;

  /// Small label above the selected course name on the Recording page's course-selector tile. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get recordingCourseLabel;

  /// Placeholder text shown on the Recording page's course-selector tile when the user hasn't picked a course yet.
  ///
  /// In en, this message translates to:
  /// **'No course selected'**
  String get recordingNoCourseSelected;

  /// Short badge text inside a pill on the Recording page indicating the Realtime Transcribe toggle is currently on. Must stay short to fit inline in the pill.
  ///
  /// In en, this message translates to:
  /// **'Realtime ON'**
  String get recordingRealtimeOnBadge;

  /// Companion badge to recordingRealtimeOnBadge, shown when Realtime Transcribe is off. Must stay short to fit inline in the pill.
  ///
  /// In en, this message translates to:
  /// **'Realtime OFF'**
  String get recordingRealtimeOffBadge;

  /// Warning banner shown while actively recording/paused with no course assigned, explaining AI analysis needs a course to run. Informative, mildly cautionary tone, not alarming.
  ///
  /// In en, this message translates to:
  /// **'No course selected. Automated AI analysis will not start unless a course is assigned. Please select a course before or after uploading to start analysis.'**
  String get recordingNoCourseWarning;

  /// Short divider word between two horizontal lines on the Recording page, separating the record button area from the 'select an existing audio file' option below it. Must stay very short (1 word) to fit the divider. English uses uppercase for visual style; other languages should just use their natural word for 'or'.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get recordingOrDivider;

  /// Snackbar error shown when the file picker returns a file with no usable local path.
  ///
  /// In en, this message translates to:
  /// **'Unable to access the selected file. Please try another file.'**
  String get recordingFileAccessError;

  /// Snackbar error shown when the native file picker throws an exception while picking an audio file. {error} is the raw exception's toString() (technical, not pre-localized), appended plainly after the colon.
  ///
  /// In en, this message translates to:
  /// **'Failed to select file: {error}'**
  String recordingFileSelectError(String error);

  /// Shown next to a spinner while a picked local audio file is being validated, before the 'file selected' state appears.
  ///
  /// In en, this message translates to:
  /// **'Processing audio file...'**
  String get recordingProcessingAudioFile;

  /// Label shown once the user has successfully picked a local audio file, replacing the 'Select audio file' prompt.
  ///
  /// In en, this message translates to:
  /// **'File selected'**
  String get recordingFileSelected;

  /// Tappable prompt inviting the user to pick an existing audio file from their device instead of recording live audio.
  ///
  /// In en, this message translates to:
  /// **'Select audio file'**
  String get recordingSelectAudioFile;

  /// Title of the confirmation dialog shown when the user taps the Discard button while a recording is active, paused, or errored.
  ///
  /// In en, this message translates to:
  /// **'Discard Recording?'**
  String get recordingDiscardDialogTitle;

  /// Body text of the discard-recording confirmation dialog, warning the action is permanent and irreversible.
  ///
  /// In en, this message translates to:
  /// **'This will delete the current recording. This action cannot be undone.'**
  String get recordingDiscardDialogMessage;

  /// Generic Cancel button label, reused across the Recording page's confirmation dialogs (the discard-recording dialog and the speech-model-download-required dialog).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get recordingCancelButton;

  /// Destructive confirm button label inside the discard-recording dialog, permanently deletes the in-progress recording.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get recordingDiscardConfirmButton;

  /// Text button (with a trash icon) below the recording controls that opens the discard-recording confirmation dialog. Different from recordingDiscardConfirmButton, which is the dialog's own confirm action.
  ///
  /// In en, this message translates to:
  /// **'Discard Recording'**
  String get recordingDiscardButtonLabel;

  /// Header label for the collapsible 'More Settings' accordion section on the Recording page, which reveals the title field, auto-start toggle, realtime-transcribe toggle, and language row.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get recordingSettingsSectionTitle;

  /// Floating label for the optional lecture-title text field inside the Recording page's More Settings section.
  ///
  /// In en, this message translates to:
  /// **'Lecture title (Optional)'**
  String get recordingTitleFieldLabel;

  /// Hint text shown inside the empty lecture-title field, explaining that the AI will auto-generate a title if the field is left blank. Keep the ✨ emoji.
  ///
  /// In en, this message translates to:
  /// **'✨ Auto (AI will generate title)'**
  String get recordingTitleFieldHint;

  /// Title of a toggle row in the Recording page's More Settings section, controlling whether AI analysis starts automatically after upload.
  ///
  /// In en, this message translates to:
  /// **'Auto-start analysis'**
  String get recordingAutoStartAnalysisTitle;

  /// Subtitle/description text under the 'Auto-start analysis' toggle row, explaining what the toggle does.
  ///
  /// In en, this message translates to:
  /// **'Automatically start processing tasks after upload completes.'**
  String get recordingAutoStartAnalysisSubtitle;

  /// Title of a toggle row in the Recording page's More Settings section, enabling on-device live captions while recording.
  ///
  /// In en, this message translates to:
  /// **'Realtime transcribe'**
  String get recordingRealtimeTranscribeTitle;

  /// Subtitle/description text under the 'Realtime transcribe' toggle row, explaining what the toggle does.
  ///
  /// In en, this message translates to:
  /// **'Transcribe audio stream in realtime as you record.'**
  String get recordingRealtimeTranscribeSubtitle;

  /// Title of the dialog shown when the user turns on Realtime transcribe but the on-device speech model for the current recording language hasn't been downloaded yet.
  ///
  /// In en, this message translates to:
  /// **'Speech model required'**
  String get recordingSpeechModelDialogTitle;

  /// Body text of the speech-model-required dialog, asking the user to confirm downloading the on-device model for their selected recording language.
  ///
  /// In en, this message translates to:
  /// **'Realtime transcription needs this language\'s on-device speech model. Download it now?'**
  String get recordingSpeechModelDialogMessage;

  /// Confirm button label on the speech-model-required dialog; starts downloading the on-device speech model.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get recordingSpeechModelDownloadConfirm;

  /// Snackbar shown when the user tries to upload a picked local audio file without first selecting a course.
  ///
  /// In en, this message translates to:
  /// **'Please select a course before uploading'**
  String get recordingSelectCourseBeforeUploadSnackbar;

  /// Shared status text meaning an upload is currently in progress. Shown both inside the disabled Upload button and in the status area above the record button during the 'uploading' phase.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get recordingUploadingStatus;

  /// Primary call-to-action button label that submits/uploads the finished recording (or a selected local audio file).
  ///
  /// In en, this message translates to:
  /// **'Upload Recording'**
  String get recordingUploadButtonLabel;

  /// Headline shown in a full-screen success overlay right after the recording/upload flow completes. Celebratory, brief, exclamation intended.
  ///
  /// In en, this message translates to:
  /// **'Recording Done!'**
  String get recordingDoneOverlayTitle;

  /// Status text shown while the app is waiting on the OS's microphone-permission prompt, before recording can start.
  ///
  /// In en, this message translates to:
  /// **'Requesting microphone permission...'**
  String get recordingRequestingPermissionStatus;

  /// Fallback single-word status text used only if a recording error occurred but no specific error message was available to show instead.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get recordingGenericErrorFallback;

  /// Button shown in the recording error state that deep-links out to the OS app-settings screen (e.g. so the user can grant microphone permission).
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get recordingOpenSettingsButton;

  /// Button shown in the recording error state that resets the recording flow so the user can retry from scratch.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get recordingTryAgainButton;

  /// Short status pill/badge label shown while a recording is paused. Reused in two places on the Recording page (a larger status pill and a small inline badge).
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recordingStatusPaused;

  /// Short status pill/badge label shown while actively recording audio. Reused in two places on the Recording page (a larger status pill and a small inline badge).
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get recordingStatusRecording;

  /// Status text shown before the user has started recording (idle phase).
  ///
  /// In en, this message translates to:
  /// **'Ready to record'**
  String get recordingStatusReady;

  /// Title of the settings row that lets the user pick which language is used for on-device live transcription while recording.
  ///
  /// In en, this message translates to:
  /// **'Recording language'**
  String get recordingLanguageRowTitle;

  /// Subtitle of the 'Recording language' settings row when the on-device speech model failed to prepare. {message} is an already-localized, human-readable error string produced elsewhere in the app; this key only supplies the warning-emoji prefix and placement. Keep the ⚠️ emoji.
  ///
  /// In en, this message translates to:
  /// **'⚠️ {message}'**
  String recordingAsrModelErrorPrefix(String message);

  /// Subtitle of the 'Recording language' settings row in the normal (non-error) case, explaining what the on-device model is used for.
  ///
  /// In en, this message translates to:
  /// **'On-device speech model used for live captions.'**
  String get recordingOnDeviceModelSubtitle;

  /// Label shown on a moment/reaction timeline entry when its type is 'fun' (the student marked this point in the lecture as fun/interesting), next to a star icon.
  ///
  /// In en, this message translates to:
  /// **'Fun moment'**
  String get recordingMomentFunLabel;

  /// Label for a moment/reaction timeline entry of type 'difficult' (the student marked this point as hard to understand).
  ///
  /// In en, this message translates to:
  /// **'Difficult'**
  String get recordingMomentDifficultLabel;

  /// Label for a moment/reaction timeline entry of type 'revisit', meaning the student wants to come back and review this point later.
  ///
  /// In en, this message translates to:
  /// **'Revisit later'**
  String get recordingMomentRevisitLabel;

  /// Label for a moment/reaction timeline entry of type 'note' (a free-text note the student typed during the lecture).
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get recordingMomentNoteLabel;

  /// Small header above the scrolling live-transcript panel on the Recording page's Live tab. Shown in English as all-caps for visual style with letter-spacing; languages without case distinction (e.g. Japanese) can just use the natural phrase.
  ///
  /// In en, this message translates to:
  /// **'LIVE TRANSCRIPT'**
  String get recordingLiveTranscriptHeader;

  /// Placeholder text shown in the live transcript panel before any speech has been transcribed yet.
  ///
  /// In en, this message translates to:
  /// **'Waiting for audio...'**
  String get recordingWaitingForAudio;

  /// Hint box shown on the Live tab when Realtime Transcribe is off, telling the user where to go to enable it (references the 'More Settings' section and 'Voice' tab by name — keep those consistent with how they're labeled elsewhere in the app).
  ///
  /// In en, this message translates to:
  /// **'Turn on Realtime Transcribe (More Settings, Voice tab) to see live captions and ask AI here.'**
  String get recordingRealtimeOffHint;

  /// Short caption under an icon on one of three reaction buttons (Fun / Difficult / Revisit) on the Recording page's Live tab. Must stay very short to fit under the icon.
  ///
  /// In en, this message translates to:
  /// **'Fun'**
  String get recordingReactionFunLabel;

  /// Short caption under the icon on the 'Difficult' reaction button on the Live tab. Must stay very short to fit under the icon.
  ///
  /// In en, this message translates to:
  /// **'Difficult'**
  String get recordingReactionDifficultLabel;

  /// Short caption under the icon on the 'Revisit' reaction button on the Live tab. Must stay very short to fit under the icon (shorter than the timeline's fuller 'Revisit later' wording).
  ///
  /// In en, this message translates to:
  /// **'Revisit'**
  String get recordingReactionRevisitLabel;

  /// Hint text inside the free-text note input field on the Live tab, inviting the student to type a quick note during the lecture. Casual tone.
  ///
  /// In en, this message translates to:
  /// **'Jot a quick note...'**
  String get recordingNoteInputHint;

  /// Empty-state hint shown in the moments timeline before the user has added any reactions or notes yet. Casual, instructive tone.
  ///
  /// In en, this message translates to:
  /// **'Tap a reaction or add a note below — it\'ll show up here.'**
  String get recordingMomentsEmptyHint;

  /// Header title of the bottom sheet used to pick a course to assign to the current recording.
  ///
  /// In en, this message translates to:
  /// **'Select Course'**
  String get coursePickerTitle;

  /// Cancel link in the course-picker bottom sheet's header; dismisses the sheet without changing the recording's selected course.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get coursePickerCancelButton;

  /// Hint text inside the search field at the top of the course-picker bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Search courses...'**
  String get coursePickerSearchHint;

  /// Error text shown in the course-picker sheet if the course list fails to load. {error} is the raw exception's toString() (technical, not pre-localized).
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String coursePickerErrorLoading(String error);

  /// Empty-state text in the course-picker sheet shown when the user hasn't created any courses at all.
  ///
  /// In en, this message translates to:
  /// **'No courses yet'**
  String get coursePickerEmptyNoCourses;

  /// Empty-state text in the course-picker sheet shown when the search query matches no courses (but the user does have courses).
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get coursePickerEmptySearchResults;

  /// Primary bottom button label in the course-picker sheet when a course is currently selected; confirms that selection and closes the sheet.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get coursePickerConfirmButton;

  /// Primary bottom button label in the course-picker sheet when no course is selected; lets the user proceed/close the sheet without assigning one.
  ///
  /// In en, this message translates to:
  /// **'Continue without Course'**
  String get coursePickerContinueWithoutCourseButton;

  /// Generic inline error fallback shown when an async provider (the lecture itself, or the course's lecture list) fails to load on the Lecture Viewer page. {error} is the raw exception's toString(), not pre-localized. Reused across a few async-loading fallbacks on this page.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String lectureViewerErrorPrefix(String error);

  /// Fallback body text shown if a lecture ID resolves to no record (e.g. a deleted lecture) on the Lecture Viewer page.
  ///
  /// In en, this message translates to:
  /// **'Lecture not found'**
  String get lectureViewerLectureNotFound;

  /// Fallback lecture title used when neither the user-set title nor the AI-generated title is available yet.
  ///
  /// In en, this message translates to:
  /// **'Untitled Lecture'**
  String get lectureViewerUntitledLecture;

  /// Fallback shown next to the lecture date when the lecture has no assigned course (so there's no course code to show). Very short; use your language's common 'not applicable' abbreviation if one exists, otherwise a short dash is fine.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get lectureViewerCourseCodeFallback;

  /// Placeholder body text shown instead of an AI-generated summary while analysis hasn't produced one yet.
  ///
  /// In en, this message translates to:
  /// **'This lecture is still being analyzed. The summary will appear here once it\'s ready.'**
  String get lectureViewerSummaryPlaceholder;

  /// Label inside a small tappable pill/chip near the top of the Lecture Viewer page, showing how many announcements exist for this lecture. Tapping it opens a bottom sheet listing them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} announcement} other{{count} announcements}}'**
  String lectureViewerAnnouncementsChip(int count);

  /// Label inside a small tappable pill/chip near the top of the Lecture Viewer page, showing how many keywords exist for this lecture. Tapping it opens a bottom sheet listing them.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} keyword} other{{count} keywords}}'**
  String lectureViewerKeywordsChip(int count);

  /// Label inside a small pill/chip near the top of the Lecture Viewer page, showing how many topics were extracted from this lecture. Currently not tappable (informational only).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} topic} other{{count} topics}}'**
  String lectureViewerTopicsChip(int count);

  /// Title text inside one of two large square navigation cards on the Lecture Viewer page; taps into the Review Cards study mode for this lecture. Short label.
  ///
  /// In en, this message translates to:
  /// **'Review Cards'**
  String get lectureViewerReviewCardsTitle;

  /// Title text inside the second large square navigation card on the Lecture Viewer page; taps into the Deep Notes reading view for this lecture. Short label.
  ///
  /// In en, this message translates to:
  /// **'Deep Notes'**
  String get lectureViewerDeepNotesTitle;

  /// Small all-caps section header above a single featured fun-fact card on the Lecture Viewer page. Shown uppercase in English for visual style with letter-spacing; languages without case distinction can just use the natural phrase.
  ///
  /// In en, this message translates to:
  /// **'FUN FACT'**
  String get lectureViewerFunFactHeader;

  /// Label on a full-width button/row at the bottom of the Lecture Viewer page that navigates to the full lecture transcript. Short label.
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get lectureViewerTranscriptButtonLabel;

  /// Snackbar shown if saving a like/dislike reaction on a fun-fact card fails. {error} is the raw exception's toString().
  ///
  /// In en, this message translates to:
  /// **'Failed to update reaction: {error}'**
  String lectureViewerReactionUpdateFailedSnackbar(String error);

  /// Fallback title shown for a keyword/term card when the keyword text itself is empty.
  ///
  /// In en, this message translates to:
  /// **'Untitled term'**
  String get lectureViewerUntitledTerm;

  /// Header title of the bottom sheet opened by tapping the announcements chip, listing all announcements for this lecture.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get lectureViewerAnnouncementsSheetTitle;

  /// Header title of the bottom sheet opened by tapping the keywords chip, listing all keyword/term cards for this lecture.
  ///
  /// In en, this message translates to:
  /// **'Keywords'**
  String get lectureViewerKeywordsSheetTitle;

  /// Empty-state text shown inside the announcements/keywords bottom sheet when that list has no items.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get lectureViewerInfoSheetEmptyState;

  /// Subtitle shown under a pipeline step's name on the lecture processing screen when that step (task) was cancelled and will not run. Short status word.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get pipelineStepsCancelledLabel;

  /// Subtitle shown under a pipeline step that failed but the backend is expected to auto-retry it soon (the job as a whole isn't marked failed yet). Keep the ellipsis, conveys an ongoing background process.
  ///
  /// In en, this message translates to:
  /// **'Retrying automatically…'**
  String get pipelineStepsRetryingAutomaticallyLabel;

  /// Subtitle shown under the pipeline step that is currently running, next to a small spinner icon.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get pipelineStepsInProgressLabel;

  /// Confirmation dialog body when the user retries a single completed pipeline step that nothing else depends on. {step} is the human-readable step name (already localized elsewhere, e.g. "Transcription"), shown inside quotes.
  ///
  /// In en, this message translates to:
  /// **'This will redo \"{step}\".'**
  String pipelineStepsRetryConfirmMessageSimple(String step);

  /// Confirmation dialog body when retrying a completed pipeline step that later steps depend on; warns those downstream steps will also be redone. {step} is the step being retried; {downstreamSteps} is a comma-separated list of already human-readable downstream step names. Keep the line break before the list.
  ///
  /// In en, this message translates to:
  /// **'This will redo \"{step}\" and re-run everything that depends on it:\n{downstreamSteps}.'**
  String pipelineStepsRetryConfirmMessageWithDownstream(
    String step,
    String downstreamSteps,
  );

  /// Title of the confirmation dialog shown before retrying a completed pipeline step.
  ///
  /// In en, this message translates to:
  /// **'Retry from here?'**
  String get pipelineStepsRetryDialogTitle;

  /// Confirm button label on the 'Retry from here?' dialog. Short label/verb, not a full sentence.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get pipelineStepsRetryConfirmButton;

  /// Snackbar shown if requesting a pipeline step retry throws an error. {error} is the raw exception's toString().
  ///
  /// In en, this message translates to:
  /// **'Retry failed: {error}'**
  String pipelineStepsRetryFailedSnackbar(String error);

  /// Tooltip on the small retry icon button next to a completed pipeline step, shown on long-press/hover.
  ///
  /// In en, this message translates to:
  /// **'Retry from here'**
  String get pipelineStepsRetryTooltip;

  /// Label on the 'Retry this step' button while a stuck/failed step's retry request is in flight.
  ///
  /// In en, this message translates to:
  /// **'Retrying...'**
  String get pipelineStepsRetryingLabel;

  /// Button label on a failed/stuck pipeline step card that lets the user manually retry just that step.
  ///
  /// In en, this message translates to:
  /// **'Retry this step'**
  String get pipelineStepsRetryThisStepButton;

  /// Dialog title shown when the user tries to start lecture analysis but has no active subscription/credit plan selected at all.
  ///
  /// In en, this message translates to:
  /// **'No Active Plan'**
  String get notStartedNoActivePlanTitle;

  /// Dialog title shown when the user tries to start lecture analysis but has used up all their available credits for the current period.
  ///
  /// In en, this message translates to:
  /// **'Out of Credits'**
  String get notStartedOutOfCreditsTitle;

  /// Body text of the dialog shown for the 'no active plan' case, explaining the user must pick a plan before analysis will run.
  ///
  /// In en, this message translates to:
  /// **'You need to select a plan before you can analyze lectures.'**
  String get notStartedNoAllocationMessage;

  /// Body text of the dialog shown for the 'out of credits' case, explaining the user's options (check balance or wait for renewal).
  ///
  /// In en, this message translates to:
  /// **'You\'ve used up your credits for this period. Check your balance or wait for your next renewal.'**
  String get notStartedOutOfCreditsMessage;

  /// Cancel button on the insufficient-credits dialog shown from the 'Ready to Analyze' screen; dismisses without navigating anywhere.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get notStartedCancelButton;

  /// Confirm button on the insufficient-credits dialog; navigates the user to the credit/plan detail screen.
  ///
  /// In en, this message translates to:
  /// **'View Credits'**
  String get notStartedViewCreditsButton;

  /// Headline shown on the Lecture Viewer's 'not started' state, once audio has finished uploading but AI analysis hasn't been triggered yet.
  ///
  /// In en, this message translates to:
  /// **'Ready to Analyze'**
  String get notStartedReadyTitle;

  /// Subtitle under the 'Ready to Analyze' headline, briefly explaining what starting analysis will produce.
  ///
  /// In en, this message translates to:
  /// **'The audio is ready. Generate transcript, summary, and notes with AI.'**
  String get notStartedReadySubtitle;

  /// Warning banner shown on the 'Ready to Analyze' screen when the lecture has no course assigned yet, explaining analysis is blocked until one is chosen.
  ///
  /// In en, this message translates to:
  /// **'This lecture isn\'t assigned to a course yet. Analysis can\'t start until it is.'**
  String get notStartedNoCourseWarning;

  /// Button inside the no-course warning banner that opens the lecture-edit sheet so the user can assign a course.
  ///
  /// In en, this message translates to:
  /// **'Choose Course'**
  String get notStartedChooseCourseButton;

  /// Label on the 'Start Analysis' button while the start-analysis request is in flight (shown with a spinner).
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get notStartedStartingLabel;

  /// Primary call-to-action button that kicks off AI analysis of the lecture's audio (transcript, summary, notes, etc).
  ///
  /// In en, this message translates to:
  /// **'Start Analysis'**
  String get notStartedStartAnalysisButton;

  /// Inline error text shown below the Start Analysis button if starting analysis fails for a reason other than insufficient credits (that case gets its own dialog instead). {error} is the raw error object's toString().
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String notStartedErrorPrefix(String error);

  /// Tooltip on a bookmark icon button in the footer of a topic preview card (currently a placeholder/no-op action). Short label.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get topicPreviewSaveTooltip;

  /// Tooltip on a heart/favorite icon button in the footer of a topic preview card (currently a placeholder/no-op action). Short label.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get topicPreviewLikeTooltip;

  /// Button label in the footer of a topic preview card that opens the full deep-note content for this topic segment.
  ///
  /// In en, this message translates to:
  /// **'Read Note'**
  String get topicPreviewReadNoteButton;

  /// Title of the confirmation dialog shown when the user long-presses the progress icon to restart the whole analysis pipeline from scratch.
  ///
  /// In en, this message translates to:
  /// **'Start Over?'**
  String get processingViewStartOverDialogTitle;

  /// Body text of the start-over confirmation dialog, warning that all completed progress will be lost.
  ///
  /// In en, this message translates to:
  /// **'This restarts the whole analysis from scratch. Progress that\'s already completed will be discarded.'**
  String get processingViewStartOverDialogMessage;

  /// Destructive confirm button label on the start-over confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Start Over'**
  String get processingViewStartOverConfirmButton;

  /// Headline shown on the processing screen when the lecture's analysis job has failed.
  ///
  /// In en, this message translates to:
  /// **'Analysis Failed'**
  String get processingViewFailedTitle;

  /// Headline shown on the processing screen while the lecture's analysis job is actively running.
  ///
  /// In en, this message translates to:
  /// **'Analyzing Lecture...'**
  String get processingViewAnalyzingTitle;

  /// Progress readout under the headline on the processing screen, showing how many of the pipeline's steps have finished. {completed} and {total} are plain integers.
  ///
  /// In en, this message translates to:
  /// **'{completed} / {total} steps completed'**
  String processingViewStepsCompletedLabel(int completed, int total);

  /// Small hint text shown only while analysis is actively running (not failed), telling the user how to trigger a full restart via long-press.
  ///
  /// In en, this message translates to:
  /// **'Hold the icon above to start over from scratch.'**
  String get processingViewHoldToRestartHint;

  /// Label on the 'Start over from scratch' button while the restart request is in flight (shown with a spinner), only in the failed-job state.
  ///
  /// In en, this message translates to:
  /// **'Starting over...'**
  String get processingViewStartingOverLabel;

  /// Button shown only when the analysis job has failed; lets the user manually trigger a full restart (a text alternative to the long-press gesture used in the non-failed state).
  ///
  /// In en, this message translates to:
  /// **'Start over from scratch'**
  String get processingViewStartOverFromScratchButton;

  /// Label shown on the shared StatusView widget's action button while its isLoading flag is true, replacing whatever specific buttonLabel the caller passed in (e.g. 'Retry', 'Continue'). Must stay generic enough to fit any caller's button.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get statusViewProcessingLabel;

  /// Fallback error text shown if the lecture's UI-state stream itself fails to load (rare/unexpected). {error} is the raw exception's toString().
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String statusScaffoldErrorPrefix(String error);

  /// Headline shown while the recorded lecture audio is still uploading/syncing to the server, before any processing can begin.
  ///
  /// In en, this message translates to:
  /// **'Syncing Audio...'**
  String get statusScaffoldSyncingTitle;

  /// Subtitle under the syncing headline, asking the user to wait for the upload to finish.
  ///
  /// In en, this message translates to:
  /// **'Please wait for the upload to complete.'**
  String get statusScaffoldSyncingMessage;

  /// AppBar title on the Credit Detail page, reached by tapping the credit card on My Account. Also reused as the 'Credits' label inside that credit card widget itself. Short label.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get creditDetailTitle;

  /// Tooltip on the AppBar refresh icon button of the Credit Detail page; manually re-fetches credit summary and usage history.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get creditDetailRefreshTooltip;

  /// Body text shown under a wifi-off icon when the credit summary fails to load on the Credit Detail page.
  ///
  /// In en, this message translates to:
  /// **'Could not load credit info. Check your connection and try again.'**
  String get creditDetailLoadErrorMessage;

  /// Short retry button/label, reused in two places on the Credit Detail page: below the credit-summary load error, and next to the usage-history load error.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get creditDetailRetryButton;

  /// Section header on the card showing the user's currently active subscription plan, on the Credit Detail page.
  ///
  /// In en, this message translates to:
  /// **'Current Plan'**
  String get creditDetailCurrentPlanTitle;

  /// Small all-caps pill badge next to the Current Plan header, indicating the plan is active. Keep it very short.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get creditDetailActiveBadge;

  /// Fallback plan name shown on the Current Plan card if the specific plan's display name isn't available yet.
  ///
  /// In en, this message translates to:
  /// **'Active Plan'**
  String get creditDetailActivePlanFallback;

  /// Subtitle on the Current Plan card showing the plan's monthly credit allowance, e.g. '1200 credits / month'.
  ///
  /// In en, this message translates to:
  /// **'{credits} credits / month'**
  String creditDetailCreditsPerMonth(int credits);

  /// Fallback subtitle on the Current Plan card shown when no specific credit count is available for the active plan.
  ///
  /// In en, this message translates to:
  /// **'Enjoy full access to your lecture companion features.'**
  String get creditDetailFullAccessSubtitle;

  /// Section header on the card showing the user's current credit balance vs monthly allocation, on the Credit Detail page.
  ///
  /// In en, this message translates to:
  /// **'Monthly Credits'**
  String get creditDetailMonthlyCreditsTitle;

  /// Small caption under the credit balance bar showing when the monthly allowance next resets. {date} is a locale-formatted date string (e.g. 'Jan 5, 2026') produced by intl's DateFormat.yMMMd, already localized.
  ///
  /// In en, this message translates to:
  /// **'Resets on {date}'**
  String creditDetailResetsOn(String date);

  /// Headline on the plan-picker card shown to users who haven't claimed any plan yet, on the Credit Detail page.
  ///
  /// In en, this message translates to:
  /// **'No active plan'**
  String get creditDetailNoActivePlanTitle;

  /// Subtitle under the 'No active plan' headline, prompting the user to pick one of the plan tiles below.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan below to start generating lecture materials.'**
  String get creditDetailNoActivePlanSubtitle;

  /// Error text shown in the plan-picker section if the list of claimable plans fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load plans. Pull to refresh and try again.'**
  String get creditDetailPlansLoadError;

  /// Snackbar shown right after the user successfully claims/activates a plan from the plan-picker. Celebratory, brief.
  ///
  /// In en, this message translates to:
  /// **'{planName} activated!'**
  String creditDetailPlanActivatedSnackbar(String planName);

  /// Title of the error dialog shown if claiming/activating a plan fails.
  ///
  /// In en, this message translates to:
  /// **'Could not activate plan'**
  String get creditDetailActivateErrorTitle;

  /// Dismiss button on the 'Could not activate plan' error dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get creditDetailOkButton;

  /// Subtitle on a claimable-plan tile in the plan-picker, combining the credit amount with its billing interval, e.g. '100 credits / month' or '300 credits / 3 months'.
  ///
  /// In en, this message translates to:
  /// **'{credits} credits {months, plural, one{/ month} other{/ {months} months}}'**
  String creditDetailPlanSubtitle(int credits, int months);

  /// Price label on a claimable-plan tile when the plan has no cost (price is null or zero).
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get creditDetailPriceFree;

  /// Section header for the credit usage history list on the Credit Detail page.
  ///
  /// In en, this message translates to:
  /// **'Usage History'**
  String get creditDetailUsageHistoryTitle;

  /// Small caption next to the Usage History header, clarifying that entries are grouped hourly.
  ///
  /// In en, this message translates to:
  /// **'Hourly summary'**
  String get creditDetailHourlySummaryLabel;

  /// Inline error text shown if the credit usage history fails to load, next to a Retry button.
  ///
  /// In en, this message translates to:
  /// **'Could not load usage history.'**
  String get creditDetailUsageHistoryLoadError;

  /// Empty-state text shown in the Usage History section when there are no usage entries yet.
  ///
  /// In en, this message translates to:
  /// **'No recent usage activity recorded.'**
  String get creditDetailNoUsageActivity;

  /// Button below the first 10 usage history entries that expands the list to show the rest. {count} is how many additional entries remain hidden.
  ///
  /// In en, this message translates to:
  /// **'View More ({count} more)'**
  String creditDetailViewMoreButton(int count);

  /// Trailing amount on a usage-history row, showing the signed credit delta for that entry (e.g. '+50 credits' or '-3 credits'). {delta} is already formatted with its sign.
  ///
  /// In en, this message translates to:
  /// **'{delta} credits'**
  String creditDetailCreditsSuffix(String delta);

  /// AppBar title of the Activity Records page when showing saved items (review cards, deep notes, keywords). Also reused as the 'Saved' tile title on the My Account page's Activity section, which links here.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get activityRecordsTitleSaved;

  /// AppBar title of the Activity Records page when showing liked items. Also reused as the 'Likes' tile title on the My Account page's Activity section.
  ///
  /// In en, this message translates to:
  /// **'Likes'**
  String get activityRecordsTitleLikes;

  /// AppBar title of the Activity Records page when showing disliked items. Also reused as the 'Dislikes' tile title on the My Account page's Activity section.
  ///
  /// In en, this message translates to:
  /// **'Dislikes'**
  String get activityRecordsTitleDislikes;

  /// AppBar title of the Activity Records page when showing announcements. Also reused as the 'Announcements' tile title on the My Account page's Activity section, and as the 'Announcements' filter chip label on the Trash view of this same page.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get activityRecordsTitleAnnouncements;

  /// AppBar title of the Activity Records page when showing soft-deleted items. Also reused as the 'Trash' tile title on the My Account page's Activity section.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get activityRecordsTitleTrash;

  /// Reused in two places on the Trash view of the Activity Records page: as the tooltip on the AppBar's delete-sweep icon, and as the destructive confirm button label inside the resulting 'Empty Trash?' confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get activityRecordsEmptyTrashLabel;

  /// Informational banner at the top of the Trash view, explaining the auto-purge retention policy.
  ///
  /// In en, this message translates to:
  /// **'Items in Trash will be permanently deleted after 30 days.'**
  String get activityRecordsTrashRetentionBanner;

  /// Filter chip label meaning no sub-filter is applied; used across all variants (Saved/Likes/Dislikes/Announcements/Trash) of the Activity Records page's filter row. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get activityRecordsFilterAll;

  /// Filter chip label restricting the list to review-card items, shown on the Saved/Likes/Dislikes variants of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Review Cards'**
  String get activityRecordsFilterReviewCards;

  /// Filter chip label restricting the list to deep-note items, shown on the Saved/Likes/Dislikes variants of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Deep Notes'**
  String get activityRecordsFilterDeepNotes;

  /// Filter chip label restricting the list to keyword/term items, shown only on the Saved variant of the Activity Records page (keywords can be saved but not liked/disliked).
  ///
  /// In en, this message translates to:
  /// **'Keywords'**
  String get activityRecordsFilterKeywords;

  /// Filter chip label restricting the list to fun-fact items, shown on the Likes/Dislikes variants of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Fun Facts'**
  String get activityRecordsFilterFunFacts;

  /// Filter chip label restricting the announcements list to not-yet-completed announcements, on the Announcements variant of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activityRecordsFilterActive;

  /// Filter chip label restricting the announcements list to completed announcements, on the Announcements variant of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get activityRecordsFilterCompleted;

  /// Filter chip label restricting the list to deleted courses, on the Trash variant of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get activityRecordsFilterCourses;

  /// Filter chip label restricting the list to deleted lectures, on the Trash variant of the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'Lectures'**
  String get activityRecordsFilterLectures;

  /// Small counter text above the filter chips on the Activity Records page, showing how many items match the current filter.
  ///
  /// In en, this message translates to:
  /// **'{count} items found'**
  String activityRecordsItemsFoundCount(int count);

  /// Empty-state text shown when the current filter selection matches zero records on the Activity Records page.
  ///
  /// In en, this message translates to:
  /// **'No items match this filter.'**
  String get activityRecordsNoFilterMatch;

  /// Error text shown if the activity records list fails to load. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Failed to load records: {error}'**
  String activityRecordsLoadFailed(String error);

  /// Caption on a trash-list row showing when the item was deleted and what kind of item it is. {date} is already formatted (e.g. 'Jan 5, 2026'); {type} is one of the already-localized type labels (Course/Lecture/Announcement/Item).
  ///
  /// In en, this message translates to:
  /// **'Deleted on {date} · {type}'**
  String activityRecordsDeletedOnLabel(String date, String type);

  /// Snackbar shown after successfully restoring a single item out of the Trash.
  ///
  /// In en, this message translates to:
  /// **'Item restored successfully.'**
  String get activityRecordsRestoredSnackbar;

  /// Title of the confirmation dialog shown when permanently deleting a single trashed item. {title} is that item's own title/name (user content, not pre-localized).
  ///
  /// In en, this message translates to:
  /// **'Delete {title}?'**
  String activityRecordsDeleteItemDialogTitle(String title);

  /// Body text of the permanent-delete confirmation dialog for a single trashed item, warning it's irreversible.
  ///
  /// In en, this message translates to:
  /// **'This item will be permanently deleted from both the local database and the cloud. This action cannot be undone.'**
  String get activityRecordsDeleteItemDialogMessage;

  /// Cancel button label, reused across the Activity Records page's two Trash confirmation dialogs (single-item delete and empty-trash).
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get activityRecordsCancelButton;

  /// Destructive confirm button label inside the single-item permanent-delete dialog on the Trash view.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get activityRecordsDeleteButton;

  /// Snackbar shown after successfully permanently deleting a single trashed item.
  ///
  /// In en, this message translates to:
  /// **'Item permanently deleted.'**
  String get activityRecordsItemDeletedSnackbar;

  /// Title of the confirmation dialog shown when the user taps the AppBar's empty-trash icon.
  ///
  /// In en, this message translates to:
  /// **'Empty Trash?'**
  String get activityRecordsEmptyTrashDialogTitle;

  /// Body text of the empty-trash confirmation dialog, warning that clearing the whole trash is irreversible.
  ///
  /// In en, this message translates to:
  /// **'All soft-deleted lectures, courses, and announcements will be permanently deleted from both the local database and the cloud. This action cannot be undone.'**
  String get activityRecordsEmptyTrashDialogMessage;

  /// Snackbar shown after successfully emptying the entire trash with no failures.
  ///
  /// In en, this message translates to:
  /// **'Trash emptied successfully.'**
  String get activityRecordsEmptyTrashSuccessSnackbar;

  /// Snackbar shown after emptying the trash when some items failed to delete (e.g. network issue) and remain for a later retry.
  ///
  /// In en, this message translates to:
  /// **'{deletedCount} item(s) deleted, {failedCount} failed and remain in trash for retry.'**
  String activityRecordsEmptyTrashPartialFailureSnackbar(
    int deletedCount,
    int failedCount,
  );

  /// Short type label shown next to a deleted-course row's date on the Trash view, and used as the Trash filter chip label restricting to courses.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get activityRecordsTypeLabelCourse;

  /// Short type label shown next to a deleted-lecture row's date on the Trash view, and used as the Trash filter chip label restricting to lectures.
  ///
  /// In en, this message translates to:
  /// **'Lecture'**
  String get activityRecordsTypeLabelLecture;

  /// Short type label shown next to a deleted-announcement row's date on the Trash view, and used as the Trash filter chip label restricting to announcements (singular, distinct from the plural activityRecordsTitleAnnouncements used elsewhere).
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get activityRecordsTypeLabelAnnouncement;

  /// Generic fallback type label shown next to a trashed row's date when the item's specific type isn't one of Course/Lecture/Announcement.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get activityRecordsTypeLabelItem;

  /// Small italic caption shown on a content card in the Saved list right after the user unsaves it, before the list refreshes; tapping the card's action icon again undoes the unsave. Keep the bullet separator.
  ///
  /// In en, this message translates to:
  /// **'Unsaved • Tap to undo'**
  String get activityRecordsUndoUnsaved;

  /// Small italic caption shown on a content card in the Likes/Dislikes list right after the user removes their reaction, before the list refreshes; tapping again undoes it. Keep the bullet separator.
  ///
  /// In en, this message translates to:
  /// **'Unreacted • Tap to undo'**
  String get activityRecordsUndoUnreacted;

  /// All-caps badge label on a content card in the Saved/Likes/Dislikes lists identifying it as a review card.
  ///
  /// In en, this message translates to:
  /// **'Review Card'**
  String get activityRecordsContentTypeReviewCard;

  /// All-caps badge label on a content card in the Saved/Likes/Dislikes lists identifying it as a deep note.
  ///
  /// In en, this message translates to:
  /// **'Deep Note'**
  String get activityRecordsContentTypeDeepNote;

  /// All-caps badge label on a content card in the Saved list identifying it as a saved keyword/term.
  ///
  /// In en, this message translates to:
  /// **'Keyword'**
  String get activityRecordsContentTypeKeyword;

  /// All-caps badge label on a content card in the Likes/Dislikes lists identifying it as a fun fact.
  ///
  /// In en, this message translates to:
  /// **'Fun Fact'**
  String get activityRecordsContentTypeFunFact;

  /// Generic fallback all-caps badge label on a content card when its specific type doesn't match a known category.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get activityRecordsContentTypeDefault;

  /// AppBar title of the My Account page (the main profile/settings hub).
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get myAccountTitle;

  /// All-caps section header on the My Account page, above the About You/Interests/Future Dreams preview tiles.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get myAccountSectionProfile;

  /// All-caps section header on the My Account page, above the Saved/Likes/Dislikes/Announcements/Trash tiles.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get myAccountSectionActivity;

  /// All-caps section header on the My Account page, above the Transmissions tile.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get myAccountSectionApplication;

  /// All-caps section header on the My Account page, above the language, legal, account, and sign-out settings groups.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get myAccountSectionSettings;

  /// Playful fallback display name shown in the My Account header when the user hasn't set a username yet.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get myAccountDefaultDisplayName;

  /// Tooltip on the checkmark icon button that confirms an in-progress display-name edit on the My Account page header.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get myAccountSaveNameTooltip;

  /// Tooltip on the close/X icon button that discards an in-progress display-name edit on the My Account page header.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get myAccountCancelEditTooltip;

  /// Tooltip on the pencil icon button next to the display name on the My Account page header, which starts inline editing.
  ///
  /// In en, this message translates to:
  /// **'Edit Name'**
  String get myAccountEditNameTooltip;

  /// All-caps small label above the user's bio text, reused on both the My Account page's profile preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'ABOUT YOU'**
  String get myAccountAboutYouLabel;

  /// Placeholder text shown in place of the bio when the user hasn't written one yet, reused on both the My Account preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'No description set yet.'**
  String get myAccountAboutYouPlaceholder;

  /// All-caps small label above the user's interests text, reused on both the My Account page's profile preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'INTERESTS'**
  String get myAccountInterestsLabel;

  /// Placeholder text shown in place of the interests field when unset, reused on both the My Account preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'No interests set yet.'**
  String get myAccountInterestsPlaceholder;

  /// All-caps small label above the user's future-goals text, reused on both the My Account page's profile preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'FUTURE DREAMS'**
  String get myAccountFutureDreamsLabel;

  /// Placeholder text shown in place of the future-goals field when unset, reused on both the My Account preview tile and the full Profile detail page.
  ///
  /// In en, this message translates to:
  /// **'No future dream set yet.'**
  String get myAccountFutureDreamsPlaceholder;

  /// Text shown in place of the credit balance on the My Account page's credit card if fetching the summary fails.
  ///
  /// In en, this message translates to:
  /// **'Credits unavailable'**
  String get myAccountCreditsUnavailable;

  /// Text shown in place of the credit balance on the My Account page's credit card while the summary is still loading. Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Loading credits…'**
  String get myAccountLoadingCredits;

  /// Tile title in the Application section of the My Account page; opens the app announcements/what's-new modal.
  ///
  /// In en, this message translates to:
  /// **'Transmissions'**
  String get myAccountTransmissionsTitle;

  /// Subtitle under the Transmissions tile on the My Account page, briefly describing what it contains.
  ///
  /// In en, this message translates to:
  /// **'What\'s new & updates'**
  String get myAccountTransmissionsSubtitle;

  /// Tiny all-caps badge on the Transmissions tile shown when there are unread announcements. Must stay very short (fits a small pill).
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get myAccountNewBadge;

  /// Snackbar shown if the user taps the Transmissions tile but there are currently no announcements to show.
  ///
  /// In en, this message translates to:
  /// **'No transmissions available at this time.'**
  String get myAccountNoTransmissionsSnackbar;

  /// Subtitle under the 'Saved' tile in the Activity section of the My Account page, listing which content types can be saved. Keep the middle-dot separators.
  ///
  /// In en, this message translates to:
  /// **'Review Cards · Deep Notes · Keywords'**
  String get myAccountSavedSubtitle;

  /// Subtitle under both the 'Likes' and 'Dislikes' tiles in the Activity section of the My Account page, listing which content types can be reacted to. Keep the middle-dot separators.
  ///
  /// In en, this message translates to:
  /// **'Review Cards · Deep Notes · Fun Facts'**
  String get myAccountLikesDislikesSubtitle;

  /// Subtitle under the 'Announcements' tile in the Activity section of the My Account page, clarifying the list includes already-completed announcements too.
  ///
  /// In en, this message translates to:
  /// **'Including completed ones'**
  String get myAccountAnnouncementsSubtitle;

  /// Subtitle under the 'Trash' tile in the Activity section of the My Account page.
  ///
  /// In en, this message translates to:
  /// **'Deleted courses & lectures'**
  String get myAccountTrashSubtitle;

  /// Settings tile title on the My Account page that opens the language-selection sheet for the on-device recording/transcription language.
  ///
  /// In en, this message translates to:
  /// **'Recording Language'**
  String get myAccountRecordingLanguageTitle;

  /// Settings tile title on the My Account page that opens the language-selection sheet for the app's UI display language.
  ///
  /// In en, this message translates to:
  /// **'Display Language'**
  String get myAccountDisplayLanguageTitle;

  /// Settings tile title on the My Account page that navigates to the Privacy Policy document.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get myAccountPrivacyPolicyTitle;

  /// Settings tile title on the My Account page that navigates to the Terms of Service document.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get myAccountTermsOfServiceTitle;

  /// Settings tile title on the My Account page that navigates to the contact/support screen.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get myAccountContactUsTitle;

  /// Settings tile title on the My Account page (shown only for email/password accounts) that opens the Change Email bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get myAccountChangeEmailTitle;

  /// Settings tile title on the My Account page (shown only for email/password accounts) that opens the Change Password bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get myAccountChangePasswordTitle;

  /// Settings tile title on the My Account page that opens the sheet for switching to a different OAuth login provider. Also reused as that sheet's own header title.
  ///
  /// In en, this message translates to:
  /// **'Change Login Method'**
  String get myAccountChangeLoginMethodTitle;

  /// Settings tile title on the My Account page (shown only for OAuth-only accounts) that opens the Change Account bottom sheet. Also reused as that sheet's own header title.
  ///
  /// In en, this message translates to:
  /// **'Change Account'**
  String get myAccountChangeAccountTitle;

  /// Destructive-styled settings tile title on the My Account page that signs the user out.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get myAccountSignOutTitle;

  /// Destructive-styled settings tile title on the My Account page that opens the account-deletion confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get myAccountDeleteAccountTitle;

  /// Title of the account-deletion confirmation dialog, next to a warning icon.
  ///
  /// In en, this message translates to:
  /// **'Delete Account?'**
  String get deleteAccountDialogTitle;

  /// Body warning text at the top of the account-deletion confirmation dialog, before the password/email confirmation field.
  ///
  /// In en, this message translates to:
  /// **'Are you absolutely sure you want to delete your account? All your recorded lectures, transcripts, and personal profile data will be permanently deleted. This action cannot be undone.'**
  String get deleteAccountDialogWarningMessage;

  /// Transient status line shown while the backend cold-starts before the delete-account request is sent.
  ///
  /// In en, this message translates to:
  /// **'Waking up backend service...'**
  String get deleteAccountDialogWakingBackendStatus;

  /// Transient status line shown while the delete-account request is in flight.
  ///
  /// In en, this message translates to:
  /// **'Deleting account...'**
  String get deleteAccountDialogDeletingStatus;

  /// Error message shown if the backend fails to warm up in time before the delete-account request can be sent.
  ///
  /// In en, this message translates to:
  /// **'The backend service is taking longer than usual to start. Please try again in a moment.'**
  String get deleteAccountDialogSlowBackendError;

  /// Instruction label above the password field in the delete-account dialog, shown only for email/password accounts.
  ///
  /// In en, this message translates to:
  /// **'Enter your password to confirm:'**
  String get deleteAccountDialogPasswordPrompt;

  /// Floating label text inside the password confirmation field of the delete-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get deleteAccountDialogPasswordLabel;

  /// Instruction label above the email field in the delete-account dialog, shown only for OAuth-only accounts (no password to verify). {email} is the user's own current email address.
  ///
  /// In en, this message translates to:
  /// **'Type your email to confirm ({email}):'**
  String deleteAccountDialogEmailPrompt(String email);

  /// Floating label text inside the email confirmation field of the delete-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get deleteAccountDialogEmailLabel;

  /// Cancel button on the delete-account confirmation dialog; dismisses without deleting anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get deleteAccountDialogCancelButton;

  /// Destructive confirm button inside the delete-account dialog that actually submits the deletion request.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountDialogConfirmButton;

  /// AppBar title of the Plans page, a pricing/upgrade screen reached from the account area.
  ///
  /// In en, this message translates to:
  /// **'Plans & Pricing'**
  String get plansTitle;

  /// Large marketing headline at the top of the Plans page. Energetic, casual tone, matches the 'learning journey' phrasing used elsewhere in onboarding/auth screens.
  ///
  /// In en, this message translates to:
  /// **'Supercharge your learning journey'**
  String get plansHeadline;

  /// Subtitle under the Plans page headline, reassuring the user plan changes are flexible.
  ///
  /// In en, this message translates to:
  /// **'Choose the plan that fits your study pace. Upgrade or downgrade anytime.'**
  String get plansSubheadline;

  /// Left segment label of the monthly/yearly billing toggle switch at the top of the Plans page.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get plansBillingToggleMonthly;

  /// Right segment label of the monthly/yearly billing toggle switch at the top of the Plans page.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get plansBillingToggleYearly;

  /// Tiny all-caps badge next to the Yearly toggle segment, advertising the annual-billing discount. Must stay short to fit inline in the pill; keep the percentage.
  ///
  /// In en, this message translates to:
  /// **'SAVE 20%'**
  String get plansBillingToggleSaveBadge;

  /// Name of the free pricing tier's card on the Plans page.
  ///
  /// In en, this message translates to:
  /// **'Starter'**
  String get plansStarterTitle;

  /// One-line tagline under the Starter plan's name on its pricing card.
  ///
  /// In en, this message translates to:
  /// **'Essential tools for casual learners'**
  String get plansStarterSubtitle;

  /// Small text next to the '$0' price on the Starter plan card, emphasizing it never expires/never charges.
  ///
  /// In en, this message translates to:
  /// **'forever free'**
  String get plansStarterBillingPeriod;

  /// All-caps badge shown on a pricing card that matches the user's currently active plan (only ever the Starter card today, since paid tiers aren't purchasable yet).
  ///
  /// In en, this message translates to:
  /// **'CURRENT PLAN'**
  String get plansCurrentPlanBadge;

  /// Disabled button label on the Starter card when it is the user's current plan, replacing the normal call-to-action.
  ///
  /// In en, this message translates to:
  /// **'Current Active Plan'**
  String get plansStarterButtonCurrent;

  /// Button label on the Starter card when the user is currently on a different (paid) plan, offering to downgrade.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to Starter'**
  String get plansStarterButtonDowngrade;

  /// First bullet-point feature listed on the Starter pricing card, with a checkmark icon.
  ///
  /// In en, this message translates to:
  /// **'100 Monthly Credits'**
  String get plansStarterFeature1;

  /// Second bullet-point feature listed on the Starter pricing card, with a checkmark icon.
  ///
  /// In en, this message translates to:
  /// **'Standard AI Lecture Transcripts'**
  String get plansStarterFeature2;

  /// Third bullet-point feature listed on the Starter pricing card, with a checkmark icon.
  ///
  /// In en, this message translates to:
  /// **'Core Topic Map Generation'**
  String get plansStarterFeature3;

  /// Fourth bullet-point feature listed on the Starter pricing card, with a checkmark icon.
  ///
  /// In en, this message translates to:
  /// **'Basic AI Q&A Chat'**
  String get plansStarterFeature4;

  /// Snackbar shown if the user taps the Starter card's button while already on the free tier (a placeholder no-op today, since downgrade isn't wired up yet).
  ///
  /// In en, this message translates to:
  /// **'You are already on the Starter plan.'**
  String get plansStarterAlreadyOnSnackbar;

  /// Name of the mid-tier paid pricing plan's card on the Plans page. 'Orbit' matches the app's space theme; keep as a proper-noun-style plan name, do not translate the word 'Pro' loosely if your language commonly keeps 'Pro' as a loanword for product tiers.
  ///
  /// In en, this message translates to:
  /// **'Orbit Pro'**
  String get plansProTitle;

  /// One-line tagline under the Orbit Pro plan's name on its pricing card.
  ///
  /// In en, this message translates to:
  /// **'Maximum speed, unlimited insights'**
  String get plansProSubtitle;

  /// Small text next to the price on the Orbit Pro/Orbit Max cards when the annual-billing toggle is selected, clarifying the monthly-equivalent price is billed as one yearly charge.
  ///
  /// In en, this message translates to:
  /// **'per month, billed yearly'**
  String get plansProBillingPeriodAnnual;

  /// Small text next to the price on the Orbit Pro/Orbit Max cards when the monthly-billing toggle is selected.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get plansBillingPeriodMonthly;

  /// All-caps badge on the Orbit Pro pricing card highlighting it as the most popular choice. Keep the 🔥 emoji.
  ///
  /// In en, this message translates to:
  /// **'🔥 MOST POPULAR'**
  String get plansMostPopularBadge;

  /// Call-to-action button label on the Orbit Pro pricing card; opens the (placeholder) plan-selection dialog.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get plansProButton;

  /// First bullet-point feature on the Orbit Pro pricing card. Keep the '12x boost' emphasis on the multiplier over the free tier.
  ///
  /// In en, this message translates to:
  /// **'1,200 Monthly Credits (12x boost)'**
  String get plansProFeature1;

  /// Second bullet-point feature on the Orbit Pro pricing card. 'ASR' (automatic speech recognition) and 'Whisper' (a specific speech-recognition model name) should stay as technical terms/brand-like names, not be translated.
  ///
  /// In en, this message translates to:
  /// **'Realtime On-Device & Whisper ASR'**
  String get plansProFeature2;

  /// Third bullet-point feature on the Orbit Pro pricing card. 'Deep Notes' and 'Review Cards' are the app's own named study-material features, keep consistent with their labels elsewhere in the app.
  ///
  /// In en, this message translates to:
  /// **'Unlimited Deep Notes & Review Cards'**
  String get plansProFeature3;

  /// Fourth bullet-point feature on the Orbit Pro pricing card.
  ///
  /// In en, this message translates to:
  /// **'High-Priority AI Model Speed'**
  String get plansProFeature4;

  /// Fifth bullet-point feature on the Orbit Pro pricing card. 'PDF' and 'Markdown' are file-format names, keep untranslated.
  ///
  /// In en, this message translates to:
  /// **'Export Transcripts (PDF & Markdown)'**
  String get plansProFeature5;

  /// Sixth bullet-point feature on the Orbit Pro pricing card. 'Galaxy Knowledge Graph' is a named in-app feature, matching the app's space theme.
  ///
  /// In en, this message translates to:
  /// **'Full Galaxy Knowledge Graph'**
  String get plansProFeature6;

  /// Name of the top-tier paid pricing plan's card on the Plans page. Keep as a proper-noun-style plan name, matching plansProTitle's naming convention.
  ///
  /// In en, this message translates to:
  /// **'Orbit Max'**
  String get plansMaxTitle;

  /// One-line tagline under the Orbit Max plan's name on its pricing card.
  ///
  /// In en, this message translates to:
  /// **'For heavy researchers & power users'**
  String get plansMaxSubtitle;

  /// All-caps badge on the Orbit Max pricing card highlighting it as the best value tier. Keep the ⚡ emoji.
  ///
  /// In en, this message translates to:
  /// **'⚡ BEST VALUE'**
  String get plansBestValueBadge;

  /// Call-to-action button label on the Orbit Max pricing card; opens the (placeholder) plan-selection dialog.
  ///
  /// In en, this message translates to:
  /// **'Get Orbit Max'**
  String get plansMaxButton;

  /// First bullet-point feature on the Orbit Max pricing card.
  ///
  /// In en, this message translates to:
  /// **'3,500 Monthly Credits'**
  String get plansMaxFeature1;

  /// Second bullet-point feature on the Orbit Max pricing card, noting it's a superset of the Orbit Pro tier.
  ///
  /// In en, this message translates to:
  /// **'All Pro Features Included'**
  String get plansMaxFeature2;

  /// Third bullet-point feature on the Orbit Max pricing card, an upgraded version of plansProFeature6.
  ///
  /// In en, this message translates to:
  /// **'Advanced Galaxy Knowledge Graph'**
  String get plansMaxFeature3;

  /// Fourth bullet-point feature on the Orbit Max pricing card. 'Fine-tuning' is a machine-learning term, keep its conventional translation if your language has an established one.
  ///
  /// In en, this message translates to:
  /// **'Custom AI Model Context & Fine-tuning'**
  String get plansMaxFeature4;

  /// Fifth bullet-point feature on the Orbit Max pricing card. Keep '24/7' as-is (commonly understood numeral shorthand).
  ///
  /// In en, this message translates to:
  /// **'Dedicated 24/7 Priority Support'**
  String get plansMaxFeature5;

  /// Sixth bullet-point feature on the Orbit Max pricing card.
  ///
  /// In en, this message translates to:
  /// **'Early Access to New Experimental Features'**
  String get plansMaxFeature6;

  /// Small reassurance note at the bottom of the Plans page, next to a shield icon.
  ///
  /// In en, this message translates to:
  /// **'Cancel anytime. Encrypted & secure.'**
  String get plansFooterNote;

  /// Title of the placeholder dialog shown when tapping a paid plan's call-to-action button (purchasing isn't implemented yet). {planName} is the already-localized plan name (e.g. plansProTitle's value).
  ///
  /// In en, this message translates to:
  /// **'Select {planName}'**
  String plansSelectDialogTitle(String planName);

  /// Body text of the placeholder plan-selection dialog, telling the user purchasing isn't available yet. Upbeat, apologetic-but-excited tone. {planName} is the already-localized plan name.
  ///
  /// In en, this message translates to:
  /// **'{planName} purchasing flow is coming soon in the next update!'**
  String plansSelectDialogMessage(String planName);

  /// Dismiss button on the placeholder plan-selection dialog. Casual acknowledgement phrase, not a formal 'OK'.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get plansSelectDialogConfirmButton;

  /// Success-state headline in the Change Password bottom sheet, shown after the reset email was sent.
  ///
  /// In en, this message translates to:
  /// **'Reset Link Sent'**
  String get changePasswordResetSentTitle;

  /// Success-state body message in the Change Password bottom sheet. {email} is the user's own account email address.
  ///
  /// In en, this message translates to:
  /// **'We have sent a password reset link to your email address ({email}). Please check your inbox and click the link to set your new password.'**
  String changePasswordResetSentMessage(String email);

  /// Button that dismisses the bottom sheet after a successful action; reused in both the Change Password sheet's success state and the Change Email sheet's success state.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get changePasswordCloseButton;

  /// Headline at the top of the Change Password bottom sheet, before submission. Also matches the settings tile label that opens this sheet (myAccountChangePasswordTitle).
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// Instruction text under the Change Password sheet's headline, explaining the current-password-verification flow.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password to verify your identity and send a reset link to your email.'**
  String get changePasswordSubtitle;

  /// Error message shown in the Change Password sheet if the backend email service fails to warm up in time. Also reused verbatim in the Change Email sheet for the same cold-start scenario.
  ///
  /// In en, this message translates to:
  /// **'The email service is taking longer than usual to start. Please try again in a moment.'**
  String get changePasswordSlowServerError;

  /// Floating label text inside the current-password field on the Change Password sheet.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get changePasswordCurrentPasswordLabel;

  /// Form validation error shown if the user submits the Change Password sheet with an empty current-password field.
  ///
  /// In en, this message translates to:
  /// **'Please enter your current password'**
  String get changePasswordCurrentPasswordRequiredError;

  /// Validation error shown in the Change Email sheet if the entered new email is identical to the account's current email.
  ///
  /// In en, this message translates to:
  /// **'New email must be different from current email'**
  String get changeEmailDifferentRequiredError;

  /// Transient status line shown under a loading spinner while the Change Email sheet's verification email is being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending verification email...'**
  String get changeEmailSendingVerificationStatus;

  /// Success-state headline in the Change Email bottom sheet, shown after the verification email was sent.
  ///
  /// In en, this message translates to:
  /// **'Verification Email Sent'**
  String get changeEmailVerificationSentTitle;

  /// Success-state body message in the Change Email bottom sheet, explaining both inboxes need to confirm the change.
  ///
  /// In en, this message translates to:
  /// **'A verification link has been sent to both your current email and new email. Please verify the change from both boxes to complete the update.'**
  String get changeEmailVerificationSentMessage;

  /// Headline at the top of the Change Email bottom sheet, before submission. Also matches the settings tile label that opens this sheet (myAccountChangeEmailTitle).
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmailTitle;

  /// Instruction text under the Change Email sheet's headline, showing the account's current email for reference. {email} is the user's own current email address.
  ///
  /// In en, this message translates to:
  /// **'Your current email address is {email}'**
  String changeEmailCurrentEmailLabel(String email);

  /// Floating label text inside the new-email field on the Change Email sheet.
  ///
  /// In en, this message translates to:
  /// **'New Email Address'**
  String get changeEmailNewLabel;

  /// Form validation error shown if the user submits the Change Email sheet with an empty new-email field.
  ///
  /// In en, this message translates to:
  /// **'Please enter a new email'**
  String get changeEmailRequiredError;

  /// Form validation error shown if the new-email field fails basic format validation on the Change Email sheet.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get changeEmailInvalidError;

  /// Primary submit button label on the Change Email sheet's form.
  ///
  /// In en, this message translates to:
  /// **'Confirm Change'**
  String get changeEmailConfirmButton;

  /// AppBar title of the full Profile detail page (About You/Interests/Future Dreams), reached by tapping a preview tile on My Account.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get userProfileDetailTitle;

  /// Tooltip on the AppBar edit-pencil icon of the Profile detail page; opens the profile-editing bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get userProfileDetailEditTooltip;

  /// Small caption under the Change Login Method sheet's title, showing which OAuth provider is currently linked. {provider} is already upper-cased (e.g. 'GOOGLE') or the changeAuthProviderUnknownProvider fallback text; not further translated.
  ///
  /// In en, this message translates to:
  /// **'Current: {provider}'**
  String changeAuthProviderCurrentLabel(String provider);

  /// Fallback value shown in changeAuthProviderCurrentLabel if the current auth provider can't be determined. Short word.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get changeAuthProviderUnknownProvider;

  /// Small reassurance note at the bottom of the Change Login Method sheet. Keep the ※ reference-mark symbol as a visual note-marker.
  ///
  /// In en, this message translates to:
  /// **'※ Changing your login method will update your authentication settings. You can switch back anytime.'**
  String get changeAuthProviderFooterNote;

  /// Small caption under the Change Account sheet's title, showing the currently linked account's email (or the provider name if the email isn't available). {value} is either an email address or an already-resolved provider display name (e.g. 'Google'), neither of which is further translated.
  ///
  /// In en, this message translates to:
  /// **'Current: {value}'**
  String changeAccountCurrentLabel(String value);

  /// Primary button label on the Change Account sheet, prompting the user to pick another account with the same OAuth provider. {provider} is the provider's display name ('Google' or 'Apple'), a brand name kept untranslated.
  ///
  /// In en, this message translates to:
  /// **'Choose a different {provider} account'**
  String changeAccountButtonLabel(String provider);

  /// Save button in the top-right of a bottom sheet header, shared verbatim across the Course/Lecture/Announcement edit-or-create sheets (course_create_sheet.dart, lecture_edit_sheet.dart, announcement_edit_sheet.dart). Shows a small spinner in its place while the submit request is in flight. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get courseSheetSaveButton;

  /// Shared fallback/empty-state text meaning a course has no announcements. Used both as the placeholder text inside the Course page's announcement-preview card (when the course has none) and as the empty-state message in the Course Announcements bottom sheet (when the active-announcements list for that course is empty).
  ///
  /// In en, this message translates to:
  /// **'No announcements yet'**
  String get courseNoAnnouncementsLabel;

  /// AppBar title on the top-level Course list page (shown when no specific course is selected, displaying all courses grouped by year/term).
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get coursePageTitle;

  /// Label reused on two buttons that both open the course-creation sheet on the Course list page: the floating action button, and the call-to-action button shown in the empty-courses state. Short label, fits next to a '+' icon.
  ///
  /// In en, this message translates to:
  /// **'New Course'**
  String get coursePageNewCourseButton;

  /// Inline error text shown on the Course list page if the course list fails to load. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String coursePageLoadError(String error);

  /// Headline shown on the Course list page's empty state when the user has no courses at all yet.
  ///
  /// In en, this message translates to:
  /// **'No courses yet'**
  String get coursePageEmptyTitle;

  /// Subtitle under the empty-state headline on the Course list page, encouraging the user to tap the New Course button below it.
  ///
  /// In en, this message translates to:
  /// **'Create your first course to get started'**
  String get coursePageEmptySubtitle;

  /// Section heading shown on the Course list page grouping courses that have no Year attribute set, sorted to the bottom of the year list. Short label, matches the style of an actual year value like '2026' since it's displayed in the same heading slot.
  ///
  /// In en, this message translates to:
  /// **'No Year'**
  String get coursePageNoYearLabel;

  /// Sub-heading shown on the Course list page (nested under a year section) grouping courses that have no Term attribute set. Short label, matches the style of an actual term value like 'Fall' since it's displayed in the same heading slot.
  ///
  /// In en, this message translates to:
  /// **'No Term'**
  String get coursePageNoTermLabel;

  /// Section header above the Topic Map preview card on the Course detail page (the per-course lecture list view).
  ///
  /// In en, this message translates to:
  /// **'Topic Map'**
  String get coursePageTopicMapTitle;

  /// Label shown over the Topic Map preview card while a stale topic map is being recreated in the background (with a small spinner above it). Keep the ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Recreating…'**
  String get coursePageTopicMapRecreatingLabel;

  /// Call-to-action label overlaid on the Topic Map preview card when the map is stale (out of date due to recent lecture changes) and needs the user to tap it to regenerate.
  ///
  /// In en, this message translates to:
  /// **'Recreate Topic Map'**
  String get coursePageTopicMapRecreateLabel;

  /// Small hint label in the bottom-left corner of the Topic Map preview card when a valid, up-to-date map exists and can be opened by tapping the card.
  ///
  /// In en, this message translates to:
  /// **'Open Topic Map'**
  String get coursePageTopicMapOpenLabel;

  /// Small hint label in the bottom-left corner of the Topic Map preview card when no topic map has been generated for this course yet (e.g. zero lectures analyzed so far).
  ///
  /// In en, this message translates to:
  /// **'Not generated yet'**
  String get coursePageTopicMapNotGeneratedLabel;

  /// Section header above the lecture list on the Course detail page.
  ///
  /// In en, this message translates to:
  /// **'Lectures'**
  String get coursePageLecturesTitle;

  /// Empty-state text shown in the Lectures section of the Course detail page when this course has no recorded lectures yet.
  ///
  /// In en, this message translates to:
  /// **'No lectures recorded yet'**
  String get coursePageNoLecturesYet;

  /// Floating action button label on the Course detail page that starts a new recording pre-assigned to this course. Short label, fits next to a '+' icon.
  ///
  /// In en, this message translates to:
  /// **'New Lecture'**
  String get coursePageNewLectureButton;

  /// Title of the confirmation dialog shown when the user taps a stale Topic Map preview card, before regenerating it.
  ///
  /// In en, this message translates to:
  /// **'Recreate Topic Map?'**
  String get coursePageRecreateTopicMapDialogTitle;

  /// Body text of the recreate-topic-map confirmation dialog, explaining why it's needed (recent lecture changes) and setting time expectations.
  ///
  /// In en, this message translates to:
  /// **'Do you want to recreate the topic map? This repairs it after recent lecture changes and may take a few minutes.'**
  String get coursePageRecreateTopicMapDialogMessage;

  /// Confirm button label on the recreate-topic-map confirmation dialog. Short verb, not a full sentence.
  ///
  /// In en, this message translates to:
  /// **'Recreate'**
  String get coursePageRecreateConfirmButton;

  /// Title of the error dialog shown if recreating the topic map fails. The dialog's body shows the raw error message underneath (already stripped of a leading 'Exception: ' prefix elsewhere in code, not pre-localized).
  ///
  /// In en, this message translates to:
  /// **'Could not recreate topic map'**
  String get coursePageRecreateErrorTitle;

  /// Dismiss button on the 'Could not recreate topic map' error dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get coursePageOkButton;

  /// Snackbar shown on the Course list/detail pages when the user pulls to refresh while offline; the page still shows whatever was last cached locally.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing cached data.'**
  String get coursePageOfflineSnackbar;

  /// Header title of the Course Create/Edit bottom sheet when editing an existing course (an existingCourse was passed in).
  ///
  /// In en, this message translates to:
  /// **'Edit Course'**
  String get courseCreateSheetEditTitle;

  /// Header title of the Course Create/Edit bottom sheet when creating a brand-new course (no existingCourse passed in). Distinct from coursePageNewCourseButton, which is a button label elsewhere, even though the English text happens to match.
  ///
  /// In en, this message translates to:
  /// **'New Course'**
  String get courseCreateSheetNewTitle;

  /// Small all-caps-style section label above the live preview card showing the course's chosen icon/color combination on the Course Create/Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Design Preview'**
  String get courseCreateSheetDesignPreviewLabel;

  /// Placeholder title text shown inside the live design-preview card when the user hasn't typed a course title yet.
  ///
  /// In en, this message translates to:
  /// **'New Course Title'**
  String get courseCreateSheetPreviewTitlePlaceholder;

  /// Fixed caption under the title inside the live design-preview card on the Course Create/Edit sheet, describing that this card previews the course's icon/color styling.
  ///
  /// In en, this message translates to:
  /// **'Visual Representation'**
  String get courseCreateSheetPreviewSubtitle;

  /// Small section label above the horizontal row of selectable color swatches on the Course Create/Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Course Color'**
  String get courseCreateSheetColorLabel;

  /// Small section label above the icon-category chips and icon grid on the Course Create/Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Course Icon'**
  String get courseCreateSheetIconLabel;

  /// Floating label text inside the Year autocomplete text field on the Course Create/Edit sheet. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get courseCreateSheetYearLabel;

  /// Hint/example text inside the empty Year field on the Course Create/Edit sheet. Keep the 'e.g.' example format; adapt the sample year value if useful, otherwise keep as-is.
  ///
  /// In en, this message translates to:
  /// **'e.g. 2026'**
  String get courseCreateSheetYearHint;

  /// Floating label text inside the Term autocomplete text field on the Course Create/Edit sheet. Also reused as the row label for the combined Term/Year row on the Course Details bottom sheet (course_details_sheet.dart), since both refer to the same course attribute. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Term'**
  String get courseCreateSheetTermLabel;

  /// Hint/example text inside the empty Term field on the Course Create/Edit sheet. Keep the 'e.g.' example format; adapt the sample term value if useful (e.g. a season name common in your locale's academic calendar), otherwise keep as-is.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fall'**
  String get courseCreateSheetTermHint;

  /// Floating label text inside the required Course Title field on the Course Create/Edit sheet. Keep the trailing ' *' asterisk marker indicating the field is required.
  ///
  /// In en, this message translates to:
  /// **'Course Title *'**
  String get courseCreateSheetTitleLabel;

  /// Hint/example text inside the empty Course Title field. Keep the 'e.g.' example format; the sample course name can be adapted to something natural in your locale.
  ///
  /// In en, this message translates to:
  /// **'e.g. Introduction to Computer Science'**
  String get courseCreateSheetTitleHint;

  /// Tappable label next to an expand/collapse chevron on the Course Create/Edit sheet, revealing optional fields (course code, professor, school, subject, summary) when tapped.
  ///
  /// In en, this message translates to:
  /// **'More Info'**
  String get courseCreateSheetMoreInfoLabel;

  /// Floating label text inside the optional Course Code field on the Course Create/Edit sheet (e.g. 'CS101'). Also reused as the row label for the course code on the Course Details bottom sheet (course_details_sheet.dart). Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Course Code'**
  String get courseCreateSheetCodeLabel;

  /// Hint/example text inside the empty Course Code field. Keep the 'e.g.' example format; the sample code (letters+digits) can stay as a generic example or use a locally natural equivalent.
  ///
  /// In en, this message translates to:
  /// **'e.g. CS101'**
  String get courseCreateSheetCodeHint;

  /// Floating label text inside the optional Professor autocomplete field on the Course Create/Edit sheet. Also reused as the row label for the professor's name on the Course Details bottom sheet (course_details_sheet.dart). Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Professor'**
  String get courseCreateSheetProfessorLabel;

  /// Hint/example text inside the empty Professor field. Keep the 'e.g.' example format; the sample name/title can be adapted to a natural example for your locale.
  ///
  /// In en, this message translates to:
  /// **'e.g. Dr. Smith'**
  String get courseCreateSheetProfessorHint;

  /// Floating label text inside the optional School autocomplete field on the Course Create/Edit sheet. Also reused as the row label for the school name on the Course Details bottom sheet (course_details_sheet.dart). Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get courseCreateSheetSchoolLabel;

  /// Hint/example text inside the empty School field. Keep the 'e.g.' example format; the sample school name can be adapted to something recognizable in your locale.
  ///
  /// In en, this message translates to:
  /// **'e.g. UCLA'**
  String get courseCreateSheetSchoolHint;

  /// Floating label text inside the optional Subject autocomplete field on the Course Create/Edit sheet. Also reused as the row label for the subject on the Course Details bottom sheet (course_details_sheet.dart). Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get courseCreateSheetSubjectLabel;

  /// Hint/example text inside the empty Subject field. Keep the 'e.g.' example format.
  ///
  /// In en, this message translates to:
  /// **'e.g. Computer Science'**
  String get courseCreateSheetSubjectHint;

  /// Floating label text inside the optional multi-line Summary field on the Course Create/Edit sheet. Also reused as the section header above the summary paragraph on the Course Details bottom sheet (course_details_sheet.dart), when a summary is set. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get courseCreateSheetSummaryLabel;

  /// Hint text inside the empty multi-line Summary field, phrased as a friendly question inviting a short description.
  ///
  /// In en, this message translates to:
  /// **'What is this course about?'**
  String get courseCreateSheetSummaryHint;

  /// Inline form-validation error shown below the form if the user taps Save with an empty Course Title field. Should read as a plain, direct validation message rather than a full apologetic sentence.
  ///
  /// In en, this message translates to:
  /// **'Course title is required'**
  String get courseCreateSheetTitleRequiredError;

  /// Title of the dialog that opens when the user taps the rainbow-gradient swatch at the end of the color row, letting them pick a fully custom course color via hue/lightness sliders or a hex code.
  ///
  /// In en, this message translates to:
  /// **'Custom Color'**
  String get courseCreateSheetCustomColorDialogTitle;

  /// Small label above the horizontal rainbow-gradient slider in the Custom Color dialog, letting the user pick the color's hue. Color-theory term; keep the conventional translation used in design/photo-editing tools in your language.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get courseCreateSheetHueLabel;

  /// Small label above the dark-to-light gradient slider in the Custom Color dialog, letting the user pick the color's lightness. Color-theory term; keep the conventional translation used in design/photo-editing tools in your language.
  ///
  /// In en, this message translates to:
  /// **'Lightness'**
  String get courseCreateSheetLightnessLabel;

  /// Floating label text inside the hex-code text field in the Custom Color dialog, where the user can type a color as text (e.g. '#FFB300') instead of using the sliders.
  ///
  /// In en, this message translates to:
  /// **'Hex Color Code'**
  String get courseCreateSheetHexLabel;

  /// Cancel button in the Custom Color dialog's action row; closes the dialog without changing the course's selected color.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get courseCreateSheetCancelButton;

  /// Confirm button in the Custom Color dialog's action row; applies the currently previewed custom color as the course's color and closes the dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get courseCreateSheetOkButton;

  /// Title of the confirmation dialog shown when the user changes a lecture's assigned course on the Lecture Edit sheet, before saving.
  ///
  /// In en, this message translates to:
  /// **'Change Course?'**
  String get lectureEditSheetChangeCourseDialogTitle;

  /// Body text of the change-course confirmation dialog, warning about downstream effects on Topic Map structures and sync before the user confirms reassigning a lecture to a different course.
  ///
  /// In en, this message translates to:
  /// **'Changing the course of this lecture will modify Topic Map structures and might affect synchronization. Are you sure you want to proceed?'**
  String get lectureEditSheetChangeCourseDialogMessage;

  /// Confirm button label on the change-course confirmation dialog. Short verb, not a full sentence.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get lectureEditSheetProceedButton;

  /// Header title of the Lecture Edit bottom sheet, used to change a lecture's assigned course, date/time, and title.
  ///
  /// In en, this message translates to:
  /// **'Edit Lecture'**
  String get lectureEditSheetTitle;

  /// Small section label above the tappable course-selector row on the Lecture Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get lectureEditSheetCourseLabel;

  /// Placeholder text shown inside the course-selector row on the Lecture Edit sheet when the lecture currently has no course assigned.
  ///
  /// In en, this message translates to:
  /// **'No Course (Unassigned)'**
  String get lectureEditSheetNoCourseLabel;

  /// Fallback course title used in the rare case where the lecture's assigned course ID doesn't match any course currently loaded in memory (e.g. a sync race). Should practically never be visible to users.
  ///
  /// In en, this message translates to:
  /// **'Unknown Course'**
  String get lectureEditSheetUnknownCourseFallback;

  /// Small section label above the tappable date/time row on the Lecture Edit sheet, which opens the native date then time pickers.
  ///
  /// In en, this message translates to:
  /// **'Lecture Date & Time'**
  String get lectureEditSheetDateTimeLabel;

  /// Floating label text inside the optional lecture-title field on the Lecture Edit sheet. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get lectureEditSheetTitleFieldLabel;

  /// Hint text inside the empty lecture-title field when the lecture already has an AI-generated title, showing that title as the default that will be used if the user leaves the field blank. {title} is the AI-generated title (user/AI content, not pre-localized); keep the '(Default)' qualifier after it, translated naturally.
  ///
  /// In en, this message translates to:
  /// **'{title} (Default)'**
  String lectureEditSheetTitleFieldDefaultSuffix(String title);

  /// Inline form-validation error shown if the user taps Save on the Announcement Edit sheet with an empty title field.
  ///
  /// In en, this message translates to:
  /// **'Title cannot be empty.'**
  String get announcementEditSheetTitleRequiredError;

  /// Header title of the Announcement Edit bottom sheet, used to change an announcement's type, title, and description.
  ///
  /// In en, this message translates to:
  /// **'Edit Announcement'**
  String get announcementEditSheetTitle;

  /// Small section label above the row of type-selector chips (Todo/Event/Hint/Info) on the Announcement Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get announcementEditSheetTypeLabel;

  /// Floating label text inside the announcement title field on the Announcement Edit sheet. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get announcementEditSheetTitleFieldLabel;

  /// Hint text inside the empty announcement title field on the Announcement Edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Announcement title'**
  String get announcementEditSheetTitleFieldHint;

  /// Floating label text inside the optional multi-line announcement description field on the Announcement Edit sheet. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get announcementEditSheetDescriptionFieldLabel;

  /// Hint text inside the empty announcement description field, clarifying the field is optional.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get announcementEditSheetDescriptionFieldHint;

  /// Label on the 'Todo' type-selector chip on the Announcement Edit sheet, one of four announcement categories the user picks from (Todo/Event/Hint/Info). Must stay short to fit inline in a chip next to an icon.
  ///
  /// In en, this message translates to:
  /// **'Todo'**
  String get announcementEditSheetTypeTodo;

  /// Label on the 'Event' type-selector chip on the Announcement Edit sheet, one of four announcement categories (Todo/Event/Hint/Info). Must stay short to fit inline in a chip next to an icon.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get announcementEditSheetTypeEvent;

  /// Label on the 'Hint' type-selector chip on the Announcement Edit sheet, one of four announcement categories (Todo/Event/Hint/Info) — this 'Hint' refers to a study/exam tip announcement type, unrelated to text-field hint text. Must stay short to fit inline in a chip next to an icon.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get announcementEditSheetTypeHint;

  /// Label on the 'Info' type-selector chip on the Announcement Edit sheet, one of four announcement categories (Todo/Event/Hint/Info). Must stay short to fit inline in a chip next to an icon.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get announcementEditSheetTypeInfo;

  /// Row label on the Course Details bottom sheet, next to the course's creation date. Short label, not a sentence.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get courseDetailsSheetCreatedLabel;

  /// Inline error text shown in the Course Announcements bottom sheet if the announcements list fails to load. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String courseAnnouncementsSheetLoadError(String error);

  /// Header title inside the slide-up topic index menu of the shared AudioPlayerBar (used from the Transcript page and the Announcement Transcript modal). Sits next to a list icon and a close button. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Topic Index'**
  String get audioPlayerBarTopicIndexTitle;

  /// Small pill/badge label identifying a topic by its 1-based index number, shown both in the AudioPlayerBar's topic index list rows and in its embedded current-topic header bar above the playback controls. Must stay very short — it's rendered inline next to a color swatch and the topic's title.
  ///
  /// In en, this message translates to:
  /// **'Topic {index}'**
  String audioPlayerBarTopicLabel(int index);

  /// Status text shown next to a small spinner inside the AudioPlayerBar while the lecture's audio file is still being downloaded from remote storage, before playback controls become available.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio from storage…'**
  String get audioPlayerBarDownloadingMessage;

  /// Error text shown inside the AudioPlayerBar in place of playback controls when the audio file failed to download/load. {error} may be a raw exception string or a short pre-localized phrase (e.g. an offline message) passed in by the caller.
  ///
  /// In en, this message translates to:
  /// **'Failed to load audio: {error}'**
  String audioPlayerBarLoadErrorMessage(String error);

  /// Status text shown inside the AudioPlayerBar after the audio file has downloaded but before the underlying audio player has finished initializing playback.
  ///
  /// In en, this message translates to:
  /// **'Preparing audio player…'**
  String get audioPlayerBarPreparingMessage;

  /// Tooltip on the 'skip previous' icon button in the AudioPlayerBar's control row. Pressing it either restarts the current topic (if recently started) or jumps to the previous topic. Describes both behaviors briefly.
  ///
  /// In en, this message translates to:
  /// **'Previous Topic / Restart Topic'**
  String get audioPlayerBarPreviousTopicTooltip;

  /// Tooltip on the 'rewind 10 seconds' icon button in the AudioPlayerBar's control row. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Rewind 10s'**
  String get audioPlayerBarRewindTooltip;

  /// Tooltip on the 'forward 10 seconds' icon button in the AudioPlayerBar's control row. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Forward 10s'**
  String get audioPlayerBarForwardTooltip;

  /// Tooltip on the 'skip next' icon button in the AudioPlayerBar's control row, which jumps playback to the start of the next topic. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Next Topic'**
  String get audioPlayerBarNextTopicTooltip;

  /// Tooltip on the list/menu icon button at the right end of the AudioPlayerBar's control row, which opens the slide-up topic index menu. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Topic Index Menu'**
  String get audioPlayerBarTopicIndexMenuTooltip;

  /// Fallback error text shown filling the whole Announcement Transcript modal sheet if the underlying lecture fails to load. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String announcementTranscriptModalErrorPrefix(String error);

  /// Fallback message filling the whole Announcement Transcript modal sheet when the lecture referenced by the announcement can no longer be found.
  ///
  /// In en, this message translates to:
  /// **'Lecture not found'**
  String get announcementTranscriptModalLectureNotFound;

  /// Tooltip on the sync/auto-scroll toggle icon button in the Announcement Transcript modal's header, shown while auto-scroll is currently ON. Explains that manual scrolling pauses it and it auto-resumes after 5 seconds of inactivity. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll Mode (5s Resume)'**
  String get announcementTranscriptModalAutoScrollOnTooltip;

  /// Tooltip on the sync/auto-scroll toggle icon button in the Announcement Transcript modal's header, shown while auto-scroll is currently OFF. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll Disabled (OFF)'**
  String get announcementTranscriptModalAutoScrollOffTooltip;

  /// Message shown in place of the transcript list in the Announcement Transcript modal when the transcript failed to load specifically because the device has no network connection (ArtifactOfflineException).
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Transcript will load once you\'re back online.'**
  String get announcementTranscriptModalOfflineMessage;

  /// Message shown in place of the transcript list in the Announcement Transcript modal when the transcript failed to load for a reason other than being offline. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Transcript unavailable: {error}'**
  String announcementTranscriptModalUnavailableError(String error);

  /// Message shown in place of the transcript list in the Announcement Transcript modal when the transcript request succeeded but returned no sentences yet, meaning generation is still in progress.
  ///
  /// In en, this message translates to:
  /// **'Transcript is being generated…'**
  String get announcementTranscriptModalGeneratingMessage;

  /// Small badge label identifying a topic by its 1-based index number, shown on the standalone topic-header tile inside the Announcement Transcript modal's scrolling transcript list. Must stay very short — rendered inline next to a color bar and the topic's title.
  ///
  /// In en, this message translates to:
  /// **'Topic {index}'**
  String announcementTranscriptModalTopicLabel(int index);

  /// Fallback title shown at the top of the Announcement Transcript modal when the lecture has neither a user-given title nor an AI-generated title.
  ///
  /// In en, this message translates to:
  /// **'Lecture'**
  String get announcementTranscriptModalLectureFallbackTitle;

  /// Short offline-error phrase passed as the {error} value into the AudioPlayerBar's own 'Failed to load audio: {error}' message, shown when the audio file couldn't download because the device has no network connection. Must stay short since it's embedded inside another sentence.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get announcementTranscriptModalOfflineErrorShort;

  /// Fallback error text shown filling the whole Transcript page when the lecture itself fails to load. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Error loading lecture: {error}'**
  String transcriptPageLectureLoadError(String error);

  /// Fallback message filling the whole Transcript page when the lecture referenced by the route can no longer be found.
  ///
  /// In en, this message translates to:
  /// **'Lecture not found'**
  String get transcriptPageLectureNotFound;

  /// AppBar title of the full-screen Transcript page (the standalone page reached from the lecture viewer, distinct from the Announcement Transcript modal bottom sheet).
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get transcriptPageTitle;

  /// Tooltip on the sync/auto-scroll toggle icon button in the Transcript page's AppBar, shown while auto-scroll is currently ON. Explains that manual scrolling pauses it and it auto-resumes after 5 seconds of inactivity. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll Mode (5s Resume)'**
  String get transcriptPageAutoScrollOnTooltip;

  /// Tooltip on the sync/auto-scroll toggle icon button in the Transcript page's AppBar, shown while auto-scroll is currently OFF. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll Disabled (OFF)'**
  String get transcriptPageAutoScrollOffTooltip;

  /// Message shown in place of the transcript list on the Transcript page when the transcript failed to load specifically because the device has no network connection (ArtifactOfflineException).
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Transcript will load once you\'re back online.'**
  String get transcriptPageOfflineMessage;

  /// Message shown in place of the transcript list on the Transcript page when the transcript failed to load for a reason other than being offline. {error} is the raw exception's toString(), not pre-localized.
  ///
  /// In en, this message translates to:
  /// **'Transcript unavailable: {error}'**
  String transcriptPageUnavailableError(String error);

  /// Message shown in place of the transcript list on the Transcript page when the transcript request succeeded but returned no sentences yet, meaning generation is still in progress.
  ///
  /// In en, this message translates to:
  /// **'Transcript is being generated…'**
  String get transcriptPageGeneratingMessage;

  /// Small badge label identifying a topic by its 1-based index number, shown on the standalone topic-header tile inside the Transcript page's scrolling transcript list. Must stay very short — rendered inline next to a color bar and the topic's title.
  ///
  /// In en, this message translates to:
  /// **'Topic {index}'**
  String transcriptPageTopicLabel(int index);

  /// Short offline-error phrase passed as the {error} value into the AudioPlayerBar's own 'Failed to load audio: {error}' message, shown when the audio file couldn't download because the device has no network connection. Must stay short since it's embedded inside another sentence.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get transcriptPageOfflineErrorShort;

  /// Icon+label button in the text-selection state of the CardSelectionToolbar (shown above Review Cards / Deep Notes content once the user selects text). Opens the highlight color/mode sub-toolbar. Must stay short — a single word under a small icon in a horizontally scrolling toolbar.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get cardSelectionToolbarHighlightLabel;

  /// Icon+label button in the text-selection state of the CardSelectionToolbar (shown above Review Cards / Deep Notes content once the user selects text). Opens the note-taking sub-toolbar to attach a note to the selection. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get cardSelectionToolbarNoteLabel;

  /// Icon+label button in the text-selection state of the CardSelectionToolbar, currently a UI-only placeholder action for copying the selected text. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get cardSelectionToolbarCopyLabel;

  /// Icon+label button in the text-selection state of the CardSelectionToolbar, currently a UI-only placeholder action for viewing the transcript source of the selected text. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get cardSelectionToolbarSourceLabel;

  /// Icon+label button in the default (no selection) state of the CardSelectionToolbar shown above Review Cards / Deep Notes content, used to mark the card as liked. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get cardSelectionToolbarLikeLabel;

  /// Icon+label button in the default (no selection) state of the CardSelectionToolbar shown above Review Cards / Deep Notes content, used to mark the card as disliked. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Dislike'**
  String get cardSelectionToolbarDislikeLabel;

  /// Icon+label button in the default (no selection) state of the CardSelectionToolbar shown above Review Cards / Deep Notes content, used to bookmark/save the card. Must stay short.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get cardSelectionToolbarSaveLabel;

  /// Placeholder hint text inside the empty text field of the NoteSubToolbar (the small draggable card used to attach a note to a highlighted text selection), shown only while the field is in editable mode.
  ///
  /// In en, this message translates to:
  /// **'Add a note...'**
  String get noteToolbarHintText;

  /// SnackBar message shown on the Review Cards viewer and Deep Notes detail pages when the user taps the CardSelectionToolbar's 'Source' button but no matching transcript citation could be located for the currently selected text. Shared verbatim between both pages since the Source lookup logic and message are identical.
  ///
  /// In en, this message translates to:
  /// **'No source found for the selection.'**
  String get cardSelectionToolbarSourceNotFoundMessage;

  /// Brief SnackBar confirmation (shown for ~2 seconds) on the Review Cards viewer and Deep Notes detail pages after the user taps the CardSelectionToolbar's 'Copy' button and the selected text is copied. Shared verbatim between both pages since the Copy logic and message are identical.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get cardSelectionToolbarCopiedToClipboardMessage;

  /// Body text shown on the Review Cards viewer (full-screen flashcard page) when a lecture has no topics/groups to build cards from at all (distinct from an individual card still being generated).
  ///
  /// In en, this message translates to:
  /// **'No review cards yet'**
  String get reviewCardsViewerNoCardsYet;

  /// Tooltip for the grid-view icon button in the Review Cards viewer's header row, which opens a bottom sheet listing all cards grouped by topic so the user can jump directly to one.
  ///
  /// In en, this message translates to:
  /// **'View List'**
  String get reviewCardsViewerViewListTooltip;

  /// Compact 'current position / total count' counter shown in the Review Cards viewer header, e.g. '3 / 12'. Purely numeric with a slash separator, no words to localize, but placeholders let the number formatting/direction adapt per locale.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String reviewCardsViewerPageCounter(int current, int total);

  /// Title at the top of the bottom sheet opened from the Review Cards viewer's grid-view button, listing every topic's cover and content cards for quick navigation.
  ///
  /// In en, this message translates to:
  /// **'Review Cards List'**
  String get reviewCardsViewerListSheetTitle;

  /// Small hint text below the flashcard area on the Review Cards viewer, explaining the two navigation gestures: tapping the left/right edge of a card moves one card at a time, swiping moves between whole topics. Keep concise; the '•' separates the two clauses and can be kept or replaced with a locale-appropriate separator.
  ///
  /// In en, this message translates to:
  /// **'Tap left / right  •  Swipe to change topic'**
  String get reviewCardsViewerNavigationHint;

  /// Empty-state message on the Review Cards dashboard (topic overview grid for a lecture) shown while no review card topics/groups exist yet because generation hasn't produced any. Ellipsis conveys an in-progress background process.
  ///
  /// In en, this message translates to:
  /// **'Review cards are being generated…'**
  String get reviewCardsDashboardGeneratingMessage;

  /// Header title on the Review Cards dashboard page.
  ///
  /// In en, this message translates to:
  /// **'Review Cards'**
  String get reviewCardsDashboardTitle;

  /// Header title on the Deep Notes list and detail pages.
  ///
  /// In en, this message translates to:
  /// **'Deep Notes'**
  String get deepNotesListTitle;

  /// Fallback body text on the Deep Notes detail page (single-note reader/editor) shown when the topic list has finished resolving but is still empty, i.e. genuinely no notes exist (as opposed to the 'still being generated' placeholder shown per-note while content streams in).
  ///
  /// In en, this message translates to:
  /// **'No notes available'**
  String get deepNotesDetailNoNotesAvailable;

  /// Tooltip for the grid-view icon button in the Deep Notes detail page's header row, which opens a bottom sheet listing all topics/notes for the lecture so the user can jump directly to one.
  ///
  /// In en, this message translates to:
  /// **'View List'**
  String get deepNotesDetailViewListTooltip;

  /// Compact 'current position / total count' counter shown in the Deep Notes detail page header, e.g. '2 / 6'. Purely numeric with a slash separator, no words to localize, but placeholders let the number formatting/direction adapt per locale.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String deepNotesDetailPageCounter(int current, int total);

  /// Title at the top of the bottom sheet opened from the Deep Notes detail page's grid-view button, listing every topic's note for quick navigation, each with its index badge, title and summary.
  ///
  /// In en, this message translates to:
  /// **'Deep Notes List'**
  String get deepNotesDetailListSheetTitle;

  /// Tiny hint label above the up-arrow at the very top of a Deep Note's scrollable content, shown only when there is a previous topic. Explains that overscrolling upward (or tapping the arrow) navigates to the previous note. Keep short — sits directly above/below a small icon.
  ///
  /// In en, this message translates to:
  /// **'Pull or tap to previous note'**
  String get deepNotesDetailPullPrevHint;

  /// Tiny hint label below the down-arrow at the very bottom of a Deep Note's scrollable content, shown only when there is a next topic. Explains that overscrolling downward (or tapping the arrow) navigates to the next note. Keep short — sits directly above/below a small icon. Should read as a natural counterpart to deepNotesDetailPullPrevHint.
  ///
  /// In en, this message translates to:
  /// **'Pull or tap to next note'**
  String get deepNotesDetailPullNextHint;

  /// Placeholder markdown body shown in place of a Deep Note's main content while that specific topic's note hasn't finished generating yet (the topic/summary already exist, but the detailed note body is still empty). Ellipsis conveys an in-progress background process.
  ///
  /// In en, this message translates to:
  /// **'Deep notes for this topic are still being generated…'**
  String get deepNotesDetailContentGeneratingPlaceholder;

  /// Empty-state message on the Deep Notes list page (topic overview list for a lecture) shown while no topics exist yet because generation hasn't produced any. Ellipsis conveys an in-progress background process.
  ///
  /// In en, this message translates to:
  /// **'Deep notes are being generated…'**
  String get deepNotesListGeneratingMessage;

  /// Small label line above the lecture title in the LectureNotePage app bar, showing the 1-based index of the topic/segment being viewed, e.g. 'Topic 3'. Same pattern as transcriptPageTopicLabel/announcementTranscriptModalTopicLabel elsewhere in the app.
  ///
  /// In en, this message translates to:
  /// **'Topic {index}'**
  String lectureNotePageTopicLabel(int index);

  /// SnackBar message shown when pulling to refresh on the home page while offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing cached data.'**
  String get homeOfflineSnackBarMessage;

  /// Floating call-to-action button at the bottom of the home screen to start recording a lecture.
  ///
  /// In en, this message translates to:
  /// **'Record Lecture'**
  String get homeRecordLectureButton;

  /// Title at the top of the All Announcements bottom sheet on the home page.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get homeAnnouncementsSheetTitle;

  /// Empty state message shown in the All Announcements sheet when there are no active announcements.
  ///
  /// In en, this message translates to:
  /// **'No announcements — you\'re all caught up!'**
  String get homeAnnouncementsEmptyMessage;

  /// Error state shown in the All Announcements sheet when the announcements list fails to load. Same 'Error: {error}' pattern used elsewhere in the app (e.g. coursePickerErrorLoading).
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String homeAnnouncementsSheetLoadError(String error);

  /// Random empty state message for the home announcement bar.
  ///
  /// In en, this message translates to:
  /// **'Keep exploring the universe!'**
  String get homeEmptyAnnouncementMessage1;

  /// Random empty state message for the home announcement bar.
  ///
  /// In en, this message translates to:
  /// **'Every star started as stardust. Keep going.'**
  String get homeEmptyAnnouncementMessage2;

  /// Random empty state message for the home announcement bar.
  ///
  /// In en, this message translates to:
  /// **'Your galaxy is quiet for now — the next lecture will light it up.'**
  String get homeEmptyAnnouncementMessage3;

  /// Random empty state message for the home announcement bar.
  ///
  /// In en, this message translates to:
  /// **'No news is good news. Time to learn something new?'**
  String get homeEmptyAnnouncementMessage4;

  /// Random empty state message for the home announcement bar.
  ///
  /// In en, this message translates to:
  /// **'The universe is patient. So can you be.'**
  String get homeEmptyAnnouncementMessage5;

  /// Section header title for Courses on the home page.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get homeCoursesSectionTitle;

  /// Section header subtitle for Recent Lectures on the home page.
  ///
  /// In en, this message translates to:
  /// **'RECENT LECTURES'**
  String get homeRecentLecturesSectionTitle;

  /// Fallback name used in the welcome greeting on the empty home onboarding screen if the user has no username set.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get emptyHomeDefaultName;

  /// Headline greeting on the empty home onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Welcome to leFture, {name}.'**
  String emptyHomeWelcomeGreeting(String name);

  /// Subheadline under the welcome greeting on the empty home screen.
  ///
  /// In en, this message translates to:
  /// **'Start building your future.'**
  String get emptyHomeStartBuilding;

  /// Explanatory text under the galaxy graphic on the empty home onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Every lecture you add lights a new star.\nKeep learning, and this galaxy will grow into one that\'s entirely your own.'**
  String get emptyHomeGalaxyDescription;

  /// Step 1 title in the onboarding checklist on the empty home screen.
  ///
  /// In en, this message translates to:
  /// **'Make Profile'**
  String get emptyHomeStepMakeProfileTitle;

  /// Step 1 subtitle when completed.
  ///
  /// In en, this message translates to:
  /// **'Your profile is set'**
  String get emptyHomeStepMakeProfileDoneSubtitle;

  /// Step 1 subtitle when pending.
  ///
  /// In en, this message translates to:
  /// **'Tell leFture a bit about yourself'**
  String get emptyHomeStepMakeProfilePendingSubtitle;

  /// Step 2 title in the onboarding checklist on the empty home screen.
  ///
  /// In en, this message translates to:
  /// **'Create Course'**
  String get emptyHomeStepCreateCourseTitle;

  /// Step 2 subtitle when disabled.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile first'**
  String get emptyHomeStepCreateCourseDisabledSubtitle;

  /// Step 2 subtitle when completed.
  ///
  /// In en, this message translates to:
  /// **'Course created'**
  String get emptyHomeStepCreateCourseDoneSubtitle;

  /// Step 2 subtitle when pending.
  ///
  /// In en, this message translates to:
  /// **'Add your first course'**
  String get emptyHomeStepCreateCoursePendingSubtitle;

  /// Step 3 title in the onboarding checklist on the empty home screen.
  ///
  /// In en, this message translates to:
  /// **'Record Lecture'**
  String get emptyHomeStepRecordLectureTitle;

  /// Step 3 subtitle when disabled.
  ///
  /// In en, this message translates to:
  /// **'Create a course first'**
  String get emptyHomeStepRecordLectureDisabledSubtitle;

  /// Step 3 subtitle when completed.
  ///
  /// In en, this message translates to:
  /// **'Lecture recorded'**
  String get emptyHomeStepRecordLectureDoneSubtitle;

  /// Step 3 subtitle when pending.
  ///
  /// In en, this message translates to:
  /// **'Record your first lecture'**
  String get emptyHomeStepRecordLecturePendingSubtitle;

  /// Fallback title for a lecture in Fun Facts card when title is empty.
  ///
  /// In en, this message translates to:
  /// **'Untitled Lecture'**
  String get funFactsUntitledLecture;

  /// Fallback title for a lecture in Fun Facts card when lecture object is not found.
  ///
  /// In en, this message translates to:
  /// **'Unknown Lecture'**
  String get funFactsUnknownLecture;

  /// SnackBar error message when updating a Fun Fact reaction fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to update reaction: {error}'**
  String funFactsUpdateReactionFailed(String error);

  /// Title for default Carl Sagan fun fact card shown when no fun facts exist yet.
  ///
  /// In en, this message translates to:
  /// **'We are made of star-stuff'**
  String get funFactsDefaultCardTitle;

  /// Body for default Carl Sagan fun fact card shown when no fun facts exist yet.
  ///
  /// In en, this message translates to:
  /// **'You are made of star-stuff ✨ The carbon, oxygen, and iron in your body were forged in exploding stars billions of years ago. The history of the cosmos lives inside you.'**
  String get funFactsDefaultCardBody;

  /// Footer metadata for default Carl Sagan fun fact card.
  ///
  /// In en, this message translates to:
  /// **'Cosmic Origin · Carl Sagan'**
  String get funFactsDefaultCardFooter;

  /// Validation error when user tries to submit profile with empty bio.
  ///
  /// In en, this message translates to:
  /// **'Tell us a little about yourself first'**
  String get makeProfileBioEmptyError;

  /// Title at top of Make Profile bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Make Your Profile'**
  String get makeProfileSheetTitle;

  /// Subtitle text at top of Make Profile bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'This helps leFture personalize your fun facts and study material.'**
  String get makeProfileSheetSubtitle;

  /// Disabled label below avatar preview in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Change Avatar (Coming Soon)'**
  String get makeProfileChangeAvatarComingSoon;

  /// Hint text for username field in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'e.g. Shogo'**
  String get makeProfileUsernameHint;

  /// Field label for Bio in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'About You *'**
  String get makeProfileAboutYouLabel;

  /// Hint text for Bio field in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Who are you, what do you study, how do you like to learn?'**
  String get makeProfileAboutYouHint;

  /// Field label for Interests in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get makeProfileInterestsLabel;

  /// Hint text for Interests field in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'e.g. astronomy, guitar, history'**
  String get makeProfileInterestsHint;

  /// Field label for Future Dreams in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Future Dreams'**
  String get makeProfileFutureDreamsLabel;

  /// Hint text for Future Dreams field in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'What are you working toward?'**
  String get makeProfileFutureDreamsHint;

  /// Submit button label in Make Profile sheet.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get makeProfileSaveButton;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get courseIconCategorySchool;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Humanity & Lang'**
  String get courseIconCategoryHumanityLang;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Society & Law'**
  String get courseIconCategorySocietyLaw;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Science & Space'**
  String get courseIconCategoryScienceSpace;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Tech & Build'**
  String get courseIconCategoryTechBuild;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Agri & Marine'**
  String get courseIconCategoryAgriMarine;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Medical'**
  String get courseIconCategoryMedical;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Sports & Health'**
  String get courseIconCategorySportsHealth;

  /// Course icon category title.
  ///
  /// In en, this message translates to:
  /// **'Art & Travel'**
  String get courseIconCategoryArtTravel;

  /// Error message when file picker fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick file: {error}'**
  String contactFailedToPickFile(String error);

  /// Auth error in contact page.
  ///
  /// In en, this message translates to:
  /// **'Authentication error. Please sign in again.'**
  String get contactAuthError;

  /// Status message while warming up backend in contact page.
  ///
  /// In en, this message translates to:
  /// **'Connecting to support service...'**
  String get contactConnecting;

  /// Backend timeout message in contact page.
  ///
  /// In en, this message translates to:
  /// **'The support service is taking longer than usual to start. Please try again in a moment, or email us directly at support@lefture.com.'**
  String get contactSlowService;

  /// Status message while sending inquiry.
  ///
  /// In en, this message translates to:
  /// **'Sending inquiry...'**
  String get contactSending;

  /// Status message while preparing file upload.
  ///
  /// In en, this message translates to:
  /// **'Preparing file upload...'**
  String get contactPreparingUpload;

  /// Status message while uploading attachment.
  ///
  /// In en, this message translates to:
  /// **'Uploading attachment...'**
  String get contactUploadingAttachment;

  /// Status message while submitting ticket.
  ///
  /// In en, this message translates to:
  /// **'Submitting support ticket...'**
  String get contactSubmittingTicket;

  /// Timeout error message in contact page.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Please check your network and try again, or email us at support@lefture.com.'**
  String get contactTimeoutError;

  /// General submission error message in contact page.
  ///
  /// In en, this message translates to:
  /// **'Submission failed: {error}. You can also email us at support@lefture.com.'**
  String contactSubmissionError(String error);

  /// App bar title when inquiry is sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get contactTitleSent;

  /// App bar title for contact page.
  ///
  /// In en, this message translates to:
  /// **'Contact Us'**
  String get contactTitle;

  /// Heading on contact page form.
  ///
  /// In en, this message translates to:
  /// **'How can we help you?'**
  String get contactHelpTitle;

  /// Subtitle instructions on contact page form.
  ///
  /// In en, this message translates to:
  /// **'Please choose a category and specify your question or bug report below. We will reply to your email shortly.'**
  String get contactHelpSubtitle;

  /// Dropdown label for category in contact page.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get contactCategoryLabel;

  /// Category option for Bug Report.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get contactCategoryBug;

  /// Category option for Request / Feedback.
  ///
  /// In en, this message translates to:
  /// **'Request / Feedback'**
  String get contactCategoryFeedback;

  /// Category option for Account / Login.
  ///
  /// In en, this message translates to:
  /// **'Account / Login'**
  String get contactCategoryAccount;

  /// Category option for Other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get contactCategoryOther;

  /// Text area label for message details.
  ///
  /// In en, this message translates to:
  /// **'Message Details'**
  String get contactMessageDetailsLabel;

  /// Validation error when message details is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your message details'**
  String get contactMessageRequired;

  /// Label for attachment section.
  ///
  /// In en, this message translates to:
  /// **'Attachment (Optional)'**
  String get contactAttachmentLabel;

  /// Button text to upload attachment.
  ///
  /// In en, this message translates to:
  /// **'Upload Screenshot or File'**
  String get contactUploadButton;

  /// Submit button label on contact page.
  ///
  /// In en, this message translates to:
  /// **'Send Inquiry'**
  String get contactSubmitButton;

  /// Success screen headline.
  ///
  /// In en, this message translates to:
  /// **'Inquiry Sent'**
  String get contactSuccessTitle;

  /// Success screen body description.
  ///
  /// In en, this message translates to:
  /// **'Your inquiry has been successfully sent. A confirmation email has been sent to your inbox. We will review your message and reply via email.'**
  String get contactSuccessDescription;

  /// Label for ticket code on success screen.
  ///
  /// In en, this message translates to:
  /// **'Ticket Code'**
  String get contactTicketCodeLabel;

  /// Button to return after inquiry sent.
  ///
  /// In en, this message translates to:
  /// **'Back to Settings'**
  String get contactBackToSettingsButton;

  /// User guidance paragraph in error dialog.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment and try again. If the issue persists, please take a screenshot of this screen and contact us via Contact Us.'**
  String get appErrorDialogGuidance;

  /// Technical details header in error dialog and error box.
  ///
  /// In en, this message translates to:
  /// **'Technical Details:'**
  String get appErrorDialogTechnicalDetails;

  /// Button text to navigate to contact page from error dialog.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get appErrorDialogContactSupport;

  /// Button text to close error dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get appErrorDialogClose;

  /// User guidance paragraph in inline error box.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment and try again. If the issue persists, please take a screenshot and contact support.'**
  String get appErrorBoxGuidance;

  /// Message displayed in the top banner when device is offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get offlineBannerMessage;

  /// Status text in recording mini player when actively recording.
  ///
  /// In en, this message translates to:
  /// **'Recording...'**
  String get recordingMiniPlayerRecording;

  /// Status text in recording mini player when recording is paused.
  ///
  /// In en, this message translates to:
  /// **'Recording Paused'**
  String get recordingMiniPlayerPaused;

  /// Title in AI chat sheet header.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get aiChatSheetTitle;

  /// TextField hint text in AI chat sheet.
  ///
  /// In en, this message translates to:
  /// **'Ask about this lecture...'**
  String get aiChatSheetInputHint;

  /// Fallback bot response text in dummy AI chat preview.
  ///
  /// In en, this message translates to:
  /// **'This is a UI preview — real AI answers aren\'t wired up yet.'**
  String get aiChatSheetPreviewFallback;

  /// Dialog title when asking to delete a course.
  ///
  /// In en, this message translates to:
  /// **'Delete Course?'**
  String get courseDeleteDialogTitle;

  /// Confirmation message when asking to delete a course.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"? All lectures inside this course, and everything generated from them, will be deleted too.'**
  String courseDeleteDialogMessage(String title);

  /// Dialog title when asking to delete an announcement.
  ///
  /// In en, this message translates to:
  /// **'Delete Announcement?'**
  String get announcementDeleteDialogTitle;

  /// Confirmation message when asking to delete an announcement.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?'**
  String announcementDeleteDialogMessage(String title);

  /// Default action button text in spaceship announcement modal.
  ///
  /// In en, this message translates to:
  /// **'Got It'**
  String get spaceshipAnnouncementGotIt;

  /// Divider text separating password auth and social sign in.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get authOrDivider;

  /// Generic Edit button label.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEditButton;

  /// Generic Delete button label.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDeleteButton;

  /// Title text on error screen when legal document fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this document'**
  String get legalDocumentLoadErrorTitle;

  /// Subtitle text on error screen when legal document fails to load.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get legalDocumentLoadErrorSubtitle;

  /// Generic Retry button label.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetryButton;

  /// Last updated date label shown at top of legal documents.
  ///
  /// In en, this message translates to:
  /// **'Last updated {date}'**
  String legalDocumentLastUpdated(String date);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
