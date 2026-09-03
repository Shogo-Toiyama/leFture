// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get signInWelcomeTitle => 'おかえりなさい';

  @override
  String get signInSubtitle => 'サインインして学習を続けましょう';

  @override
  String get emailLabel => 'メールアドレス';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get signInErrorEmailEmpty => 'メールアドレスを入力してください。';

  @override
  String get signInErrorPasswordEmpty => 'パスワードを入力してください。';

  @override
  String get forgotPasswordLink => 'パスワードをお忘れですか？';

  @override
  String get signInButton => 'サインイン';

  @override
  String get authDividerOr => 'または';

  @override
  String get continueWithGoogle => 'Googleで続ける';

  @override
  String get continueWithApple => 'Appleで続ける';

  @override
  String get continueWithEmail => 'メールアドレスで登録';

  @override
  String get signInNoAccountPrompt => 'アカウントをお持ちでない方は ';

  @override
  String get createAccountLink => 'アカウントを作成';

  @override
  String get signUpSuccessSnackbar => 'アカウントを作成しました！確認メールをご確認ください。';

  @override
  String get signUpErrorAgreeTerms => '利用規約に同意してください';

  @override
  String get signUpTitle => 'leFtureに参加する';

  @override
  String get signUpSubtitle => '今日から学習の旅を始めましょう';

  @override
  String get usernameLabel => 'ユーザー名';

  @override
  String get signUpErrorUsernameEmpty => 'ユーザー名を入力してください';

  @override
  String get signUpErrorUsernameTooShort => 'ユーザーネームは文字または数字を1文字以上含めてください';

  @override
  String get authErrorEmailRequired => 'メールアドレスを入力してください';

  @override
  String get authErrorEmailInvalid => '有効なメールアドレスを入力してください';

  @override
  String get confirmPasswordLabel => 'パスワード（確認）';

  @override
  String get signUpErrorPasswordEmpty => 'パスワードを入力してください';

  @override
  String get passwordErrorTooShort => 'パスワードは8文字以上で入力してください';

  @override
  String get confirmPasswordErrorEmpty => '確認用のパスワードを入力してください';

  @override
  String get passwordsMismatchError => 'パスワードが一致しません';

  @override
  String get signUpAgreementPrefix => '';

  @override
  String get termsAndConditionsLink => '利用規約';

  @override
  String get signUpAgreementMiddle => 'と';

  @override
  String get privacyPolicyLink => 'プライバシーポリシー';

  @override
  String get signUpAgreementSuffix => 'に同意します';

  @override
  String get signUpSubmitButton => 'アカウントを作成';

  @override
  String get signUpHasAccountPrompt => 'すでにアカウントをお持ちの方は ';

  @override
  String get signInLink => 'サインイン';

  @override
  String get forgotPasswordStatusWaking => 'メールサービスを起動しています…';

  @override
  String get forgotPasswordStatusSending => 'リセットリンクを送信しています…';

  @override
  String get forgotPasswordErrorSlowServer => 'メールサービスの起動に通常より時間がかかっています。';

  @override
  String get forgotPasswordSuccessTitle => 'メールをご確認ください';

  @override
  String get forgotPasswordTitle => 'パスワードをお忘れですか？';

  @override
  String forgotPasswordSuccessMessage(String email) {
    return '$email にパスワードリセット用のリンクを送信しました';
  }

  @override
  String get forgotPasswordSubtitle => 'ご安心ください。メールアドレスを入力すればリセットリンクをお送りします';

  @override
  String get forgotPasswordRetryButton => '届きませんか？もう一度送信';

  @override
  String get forgotPasswordHaveLinkButton => 'リセットリンクをお持ちの方はこちら';

  @override
  String get sendResetLinkButton => 'リセットリンクを送信';

  @override
  String get rememberedPasswordPrompt => 'パスワードを思い出しましたか？ ';

  @override
  String get resetPasswordLinkInvalidTitle => 'リンクが無効または期限切れです';

  @override
  String get requestNewLinkButton => '新しいリンクをリクエスト';

  @override
  String get resetPasswordSuccessTitle => 'パスワードを更新しました';

  @override
  String get resetPasswordSuccessMessage => 'パスワードの更新が完了しました。これで準備万端です！';

  @override
  String get goToDashboardButton => 'ダッシュボードへ';

  @override
  String get resetPasswordTitle => '新しいパスワードを設定';

  @override
  String get resetPasswordSubtitle => '以前使用したパスワードとは異なるものを設定してください';

  @override
  String get newPasswordLabel => '新しいパスワード';

  @override
  String get resetPasswordErrorEmpty => '新しいパスワードを入力してください';

  @override
  String get confirmNewPasswordLabel => '新しいパスワード（確認）';

  @override
  String get confirmNewPasswordErrorEmpty => '確認用の新しいパスワードを入力してください';

  @override
  String get resetPasswordButton => 'パスワードをリセット';

  @override
  String get passwordReqMinLength => '8文字以上';

  @override
  String get passwordReqUpperLower => '大文字と小文字を含む';

  @override
  String get passwordReqDigit => '数字を1つ以上含む';

  @override
  String get passwordReqSymbol => '記号を1つ以上含む';

  @override
  String get passwordStrengthWeak => '弱い';

  @override
  String get passwordStrengthFair => '普通';

  @override
  String get passwordStrengthGood => '良い';

  @override
  String get passwordStrengthStrong => '強い';

  @override
  String get recordingCourseLabel => 'コース';

  @override
  String get recordingNoCourseSelected => 'コースが選択されていません';

  @override
  String get recordingRealtimeOnBadge => 'リアルタイムON';

  @override
  String get recordingRealtimeOffBadge => 'リアルタイムOFF';

  @override
  String get recordingNoCourseWarning =>
      'コースが選択されていません。コースを設定しないとAI自動解析は開始されません。解析を始めるには、アップロードの前後どちらかでコースを選択してください。';

  @override
  String get recordingOrDivider => 'または';

  @override
  String get recordingFileAccessError => '選択したファイルにアクセスできません。別のファイルをお試しください。';

  @override
  String recordingFileSelectError(String error) {
    return 'ファイルの選択に失敗しました: $error';
  }

  @override
  String get recordingProcessingAudioFile => '音声ファイルを処理しています...';

  @override
  String get recordingFileSelected => 'ファイルを選択しました';

  @override
  String get recordingSelectAudioFile => '音声ファイルを選択';

  @override
  String get recordingDiscardDialogTitle => '録音を破棄しますか？';

  @override
  String get recordingDiscardDialogMessage => '現在の録音を削除します。この操作は取り消せません。';

  @override
  String get recordingCancelButton => 'キャンセル';

  @override
  String get recordingDiscardConfirmButton => '破棄';

  @override
  String get recordingConsentDialogTitle => '録音前に同意を得てください';

  @override
  String get recordingConsentDialogMessage => '録音を開始する前に、必ず周りの人の同意を得てください。';

  @override
  String get recordingConsentDialogCheckboxLabel => '次回以降表示しない';

  @override
  String get recordingConsentDialogConfirmButton => 'OK';

  @override
  String get recordingConsentInfoTooltip => '録音の同意に関する法律について';

  @override
  String get recordingConsentInfoDialogTitle => '録音同意に関する法律について';

  @override
  String get recordingConsentInfoDialogBody =>
      '録音の同意に関するルールは国や地域によって異なります。以下は一般的な情報であり、法的助言ではありません。実際に録音する場所の法律を必ずご自身で確認してください。\n\n■ アメリカ合衆国\n以下の12州は、その場にいる全員の同意が必要な「全員同意」州です。\nカリフォルニア、コネチカット、デラウェア、フロリダ、イリノイ、メリーランド、マサチューセッツ、モンタナ、ニューハンプシャー、オレゴン、ペンシルベニア、ワシントン\nそれ以外の州・DCは、会話の参加者の1人が同意していれば録音できる「一部同意」です。\n\n■ アメリカ以外の国\nドイツ、フランス、カナダ、オランダ、イタリアなど、多くの国でも参加者全員の同意、または録音者自身がその会話の当事者であることが求められます。\n\n講義であっても、教授や他の学生の同意なく録音すると、上記のような法律に抵触する可能性があります。必ず周囲の同意を得てから録音してください。';

  @override
  String get recordingConsentInfoDialogCloseButton => '閉じる';

  @override
  String get recordingDiscardButtonLabel => '録音を破棄';

  @override
  String get recordingSettingsSectionTitle => '設定';

  @override
  String get recordingTitleFieldLabel => '講義タイトル（任意）';

  @override
  String get recordingTitleFieldHint => '✨ 自動（AIがタイトルを生成します）';

  @override
  String get recordingAutoStartAnalysisTitle => '解析を自動開始';

  @override
  String get recordingAutoStartAnalysisSubtitle => 'アップロード完了後、自動的に解析処理を開始します。';

  @override
  String get recordingRealtimeTranscribeTitle => 'リアルタイム文字起こし';

  @override
  String get recordingRealtimeTranscribeSubtitle => '録音中の音声をリアルタイムで文字起こしします。';

  @override
  String get recordingCourseRequiredDialogTitle => '先にコースを選択してください';

  @override
  String get recordingCourseRequiredDialogMessage =>
      'この講義のコースを選択してください。コースが設定されていないと解析が開始されず、ノートが生成されません。';

  @override
  String get recordingCourseRequiredSelectButton => 'コースを選択';

  @override
  String get recordingRealtimeLockedDialogTitle => '録音中は変更できません';

  @override
  String get recordingRealtimeLockedDialogMessage =>
      'リアルタイム文字起こしのON/OFFは録音を開始する前にのみ変更できます。この設定を変えるには、録音を止めて新しく録音を開始してください。';

  @override
  String get recordingRealtimeCreditsDialogTitle => 'クレジットが不足しています';

  @override
  String get recordingRealtimeCreditsDialogMessage =>
      'リアルタイム文字起こしを利用するには、クレジット残高が必要です。';

  @override
  String get recordingRealtimeCreditsDialogConfirm => 'クレジットを確認';

  @override
  String get recordingSpeechModelDialogTitle => '音声モデルが必要です';

  @override
  String get recordingSpeechModelDialogMessage =>
      'リアルタイム文字起こしには、この言語のオンデバイス音声モデルが必要です。今すぐダウンロードしますか？';

  @override
  String get recordingSpeechModelDownloadConfirm => 'ダウンロード';

  @override
  String get recordingSpeechModelDownloadTooltip => '音声モデルをダウンロード';

  @override
  String get recordingSpeechModelPauseTooltip => 'ダウンロードを一時停止';

  @override
  String get recordingSpeechModelResumeTooltip => 'ダウンロードを再開';

  @override
  String get recordingSpeechModelRetryTooltip => 'ダウンロードを再試行';

  @override
  String get recordingSelectCourseBeforeUploadSnackbar =>
      'アップロードする前にコースを選択してください';

  @override
  String get recordingUploadingStatus => 'アップロード中...';

  @override
  String get recordingUploadButtonLabel => '録音をアップロード';

  @override
  String get recordingDoneOverlayTitle => '録音完了！';

  @override
  String get recordingRequestingPermissionStatus => 'マイクの許可をリクエストしています...';

  @override
  String get recordingGenericErrorFallback => 'エラー';

  @override
  String get recordingOpenSettingsButton => '設定を開く';

  @override
  String get recordingTryAgainButton => 'もう一度試す';

  @override
  String get recordingStatusPaused => '一時停止中';

  @override
  String get recordingStatusRecording => '録音中...';

  @override
  String get recordingStatusReady => '録音の準備ができました';

  @override
  String get recordingLanguageRowTitle => '録音言語';

  @override
  String get recordingLanguageRowSubtitle => '文字起こしや分析に使われる言語です。';

  @override
  String recordingAsrModelErrorPrefix(String message) {
    return '⚠️ $message';
  }

  @override
  String get recordingOnDeviceModelSubtitle => 'ライブ字幕にはオンデバイスの音声モデルが使われます。';

  @override
  String get recordingMomentFunLabel => '面白い瞬間';

  @override
  String get recordingMomentDifficultLabel => '難しい';

  @override
  String get recordingMomentRevisitLabel => '後で復習';

  @override
  String get recordingMomentNoteLabel => 'メモ';

  @override
  String get recordingLiveTranscriptHeader => 'ライブ文字起こし';

  @override
  String get recordingLiveListeningLabel => '聞き取り中';

  @override
  String get recordingLiveWaitingForSpeechLabel => '発話を待っています';

  @override
  String get recordingLivePausedLabel => '一時停止中';

  @override
  String get recordingLivePreparingLabel => '準備中...';

  @override
  String get recordingLiveTranscribingLabel => '認識中';

  @override
  String get recordingLiveDroppedNotice =>
      '端末の処理が追いつかず、ライブ表示の一部が欠けています。完全な文字起こしは録音後に届きます。';

  @override
  String get recordingLiveSkippedGapNotice =>
      'バッテリー節約のため、この区間は端末での文字起こしを停止しました。約1分で正式な文字起こしが表示されます。';

  @override
  String get recordingWaitingForAudio => '音声を待っています...';

  @override
  String get recordingRealtimeOffHint =>
      'ライブ字幕を使うには、（音声タブの「設定」から）リアルタイム文字起こしをオンにしてください。';

  @override
  String get recordingReactionFunLabel => '面白い';

  @override
  String get recordingReactionDifficultLabel => '難しい';

  @override
  String get recordingReactionRevisitLabel => '後で';

  @override
  String get recordingNoteInputHint => 'メモを書く...';

  @override
  String get recordingMomentsEmptyHint => '下のリアクションをタップするか、メモを追加すると、ここに表示されます。';

  @override
  String get coursePickerTitle => 'コースを選択';

  @override
  String get coursePickerCancelButton => 'キャンセル';

  @override
  String get coursePickerSearchHint => 'コースを検索...';

  @override
  String coursePickerErrorLoading(String error) {
    return 'エラー: $error';
  }

  @override
  String get coursePickerEmptyNoCourses => 'まだコースがありません';

  @override
  String get coursePickerEmptySearchResults => '該当するコースがありません';

  @override
  String get coursePickerConfirmButton => '確定';

  @override
  String get coursePickerContinueWithoutCourseButton => 'コースなしで続ける';

  @override
  String lectureViewerErrorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get lectureViewerLectureNotFound => '講義が見つかりません';

  @override
  String get lectureViewerUntitledLecture => '無題の講義';

  @override
  String get lectureViewerCourseCodeFallback => 'N/A';

  @override
  String get lectureViewerSummaryPlaceholder =>
      'この講義はまだ解析中です。準備ができ次第、ここに要約が表示されます。';

  @override
  String lectureViewerAnnouncementsChip(int count) {
    return 'お知らせ$count件';
  }

  @override
  String lectureViewerKeywordsChip(int count) {
    return 'キーワード$count件';
  }

  @override
  String lectureViewerTopicsChip(int count) {
    return 'トピック$count件';
  }

  @override
  String get lectureViewerReviewCardsTitle => '復習カード';

  @override
  String get lectureViewerDeepNotesTitle => '詳細ノート';

  @override
  String get lectureViewerFunFactHeader => 'ファンファクト';

  @override
  String get lectureViewerTranscriptButtonLabel => '文字起こし';

  @override
  String get lectureViewerFunFactLinkOpenFailedSnackbar => 'リンクを開けませんでした。';

  @override
  String lectureViewerReactionUpdateFailedSnackbar(String error) {
    return 'リアクションの更新に失敗しました: $error';
  }

  @override
  String get lectureViewerUntitledTerm => '無題の用語';

  @override
  String get lectureViewerAnnouncementsSheetTitle => 'お知らせ';

  @override
  String get lectureViewerKeywordsSheetTitle => 'キーワード';

  @override
  String get lectureViewerTopicsSheetTitle => 'トピック';

  @override
  String get lectureViewerTopicCardReviewCards => '復習カード';

  @override
  String get lectureViewerTopicCardDeepNotes => '詳細ノート';

  @override
  String get lectureViewerTopicEmptyState => '利用可能なトピックがまだありません';

  @override
  String get lectureViewerInfoSheetEmptyState => 'まだ何もありません';

  @override
  String get lectureViewerPartialFailureBanner => '一部のコンテンツを生成できませんでした';

  @override
  String get lectureViewerPipelineDetailsSheetTitle => '解析の進捗';

  @override
  String get pipelineStepsCancelledLabel => 'キャンセル済み';

  @override
  String get pipelineStepsRetryingAutomaticallyLabel => '自動的に再試行しています…';

  @override
  String get pipelineStepsInProgressLabel => '処理中';

  @override
  String pipelineStepsRetryConfirmMessageSimple(String step) {
    return '「$step」をやり直します。';
  }

  @override
  String pipelineStepsRetryConfirmMessageWithDownstream(
    String step,
    String downstreamSteps,
  ) {
    return '「$step」をやり直すと、それに依存する以下の処理もすべて再実行されます:\n$downstreamSteps';
  }

  @override
  String get pipelineStepsRetryDialogTitle => 'ここから再試行しますか？';

  @override
  String get pipelineStepsRetryConfirmButton => '再試行';

  @override
  String pipelineStepsRetryFailedSnackbar(String error) {
    return '再試行に失敗しました: $error';
  }

  @override
  String get pipelineStepsRetryTooltip => 'ここから再試行';

  @override
  String get pipelineStepsRetryingLabel => '再試行しています...';

  @override
  String get pipelineStepsRetryThisStepButton => 'このステップを再試行';

  @override
  String get notStartedNoActivePlanTitle => '有効なプランがありません';

  @override
  String get notStartedOutOfCreditsTitle => 'クレジット不足';

  @override
  String get notStartedNoAllocationMessage => '講義を解析するには、先にプランを選択する必要があります。';

  @override
  String get notStartedOutOfCreditsMessage =>
      '今期のクレジットを使い切りました。残高を確認するか、次回の更新をお待ちください。';

  @override
  String get notStartedCancelButton => 'キャンセル';

  @override
  String get notStartedViewCreditsButton => 'クレジットを見る';

  @override
  String get notStartedReadyTitle => '解析の準備ができました';

  @override
  String get notStartedReadySubtitle => '音声の準備ができています。AIで文字起こし・要約・ノートを生成しましょう。';

  @override
  String get notStartedAudioPreviewLoading => '音声を読み込み中...';

  @override
  String get notStartedAudioPreviewFailed => '音声のプレビューを読み込めませんでした。';

  @override
  String get notStartedNoCourseWarning =>
      'この講義にはまだコースが割り当てられていません。コースを設定するまで解析を開始できません。';

  @override
  String get notStartedChooseCourseButton => 'コースを選択';

  @override
  String get notStartedEditTooltip => 'タイトル・コースを編集';

  @override
  String get notStartedUploadingWarning => '音声をアップロード中です。完了すると自動的に解析が始まります。';

  @override
  String notStartedUploadRetryingWarning(String error) {
    return '音声をアップロード中です。通信が不安定なため、バックグラウンドで再試行しています: $error\n完了すると自動的に解析が始まります。';
  }

  @override
  String get notStartedUploadingLabel => '音声をアップロード中...';

  @override
  String get notStartedCancelUploadButton => 'キャンセル';

  @override
  String get notStartedUploadStoppedWarning =>
      'アップロードを停止しました。録音データは端末に残っています。いつでも再開できます。';

  @override
  String get notStartedResumeUploadButton => '再開';

  @override
  String get notStartedUploadStoppedLabel => 'アップロード停止中';

  @override
  String get notStartedStartingLabel => '開始しています...';

  @override
  String get notStartedStartAnalysisButton => '解析を開始';

  @override
  String notStartedErrorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String notStartedAutoStartFailedWarning(String error) {
    return 'アップロード後の自動解析開始を試みましたが失敗し、バックグラウンドで再試行中です: $error\n下のボタンから手動で開始することもできます。';
  }

  @override
  String get notStartedAnalysisStartingTitle => '解析を開始しています...';

  @override
  String get notStartedAnalysisStartingSubtitle => 'まもなく始まります。';

  @override
  String recoveryBannerTitle(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保存されていない録音が$countString件あります',
    );
    return '$_temp0';
  }

  @override
  String get recoveryBannerSubtitle => '音声は端末に残っています。タップして確認してください。';

  @override
  String recoveryListSheetTitle(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保存されていない録音($countString件)',
    );
    return '$_temp0';
  }

  @override
  String get recoverySafeTitle => '録音は無事に残っています';

  @override
  String get recoverySafeSubtitle =>
      '前回、この録音は最後まで保存されませんでした(アプリの終了またはクラッシュが原因と考えられます)。データは失われていません — 下で再生して内容を確認してから、どうするか選んでください。';

  @override
  String recoveryStartedAtLabel(String datetime) {
    return '開始: $datetime';
  }

  @override
  String recoveryDurationLabel(String duration) {
    return '長さ: $duration';
  }

  @override
  String get recoveryRealtimeOnLabel => 'リアルタイム文字起こし: オン';

  @override
  String get recoveryRealtimeOffLabel => 'リアルタイム文字起こし: オフ';

  @override
  String get recoveryViewDetails => '詳細を見る';

  @override
  String get recoveryHideDetails => '詳細を閉じる';

  @override
  String get recoveryDetailStartedAt => '開始日時';

  @override
  String get recoveryDetailDuration => '録音時間';

  @override
  String get recoveryDetailLanguage => '録音言語';

  @override
  String get recoveryDetailRealtime => 'リアルタイム文字起こし';

  @override
  String get recoveryStatusOn => 'オン';

  @override
  String get recoveryStatusOff => 'オフ';

  @override
  String recoveryEncodingLabel(int percent) {
    return '再生の準備中... $percent%';
  }

  @override
  String get recoveryEncodingFailedTitle => 'この録音を準備できませんでした';

  @override
  String get recoveryEncodingFailedRetryButton => '再試行';

  @override
  String get recoveryTranscriptSectionTitle => '文字起こし';

  @override
  String get recoveryMomentsSectionTitle => 'リアクション';

  @override
  String get recoveryStartAnalysisButton => '解析を開始';

  @override
  String get recoveryDeleteButton => '削除';

  @override
  String get recoveryUploadOnlyButton => 'アップロードのみ';

  @override
  String get recoveryEditTooltip => 'タイトル・コースを編集';

  @override
  String get recoveryDeleteConfirmTitle => 'この録音を削除しますか？';

  @override
  String get recoveryDeleteConfirmMessage =>
      'この操作は取り消せません。この音声は一度もアップロードされていないため、ここで削除すると完全に失われます。';

  @override
  String get recoveryDeleteConfirmButton => '削除';

  @override
  String get recoveryCancelButton => 'キャンセル';

  @override
  String get topicPreviewSaveTooltip => '保存';

  @override
  String get topicPreviewLikeTooltip => 'いいね';

  @override
  String get topicPreviewReadNoteButton => 'ノートを読む';

  @override
  String get processingViewStartOverDialogTitle => '最初からやり直しますか？';

  @override
  String get processingViewStartOverDialogMessage =>
      '解析全体を最初からやり直します。すでに完了している進捗は破棄されます。';

  @override
  String get processingViewStartOverConfirmButton => 'やり直す';

  @override
  String get processingViewFailedTitle => '解析に失敗しました';

  @override
  String get processingViewAnalyzingTitle => '講義を解析しています...';

  @override
  String processingViewStepsCompletedLabel(int completed, int total) {
    return '$completed / $total ステップ完了';
  }

  @override
  String get processingViewHoldToRestartHint => '上のアイコンを長押しすると最初からやり直せます。';

  @override
  String get processingViewStopButton => '停止';

  @override
  String get processingViewStoppingLabel => '停止しています...';

  @override
  String get processingViewStopDialogTitle => '解析を停止しますか？';

  @override
  String get processingViewStopDialogMessage =>
      '現在の解析を停止します。既に完了しているステップはそのまま残り、いつでも手動で再開できます。';

  @override
  String get processingViewStopConfirmButton => '停止';

  @override
  String processingViewStopFailedSnackbar(String error) {
    return '停止に失敗しました: $error';
  }

  @override
  String get processingViewStartingOverLabel => 'やり直しています...';

  @override
  String get processingViewStartOverFromScratchButton => '最初からやり直す';

  @override
  String get statusViewProcessingLabel => '処理しています...';

  @override
  String get statusViewFailedLabel => '失敗';

  @override
  String statusScaffoldErrorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get statusScaffoldSyncingTitle => '音声を同期しています...';

  @override
  String get statusScaffoldSyncingMessage => 'アップロードが完了するまでお待ちください。';

  @override
  String get statusScaffoldErrorTitle => '状態を取得できませんでした';

  @override
  String get statusScaffoldErrorMessage =>
      '分析が開始済みかどうか確認できませんでした。通信状態を確認して、もう一度お試しください。';

  @override
  String get statusScaffoldErrorRetryButton => '再試行';

  @override
  String get creditDetailTitle => 'クレジット';

  @override
  String get creditDetailRefreshTooltip => '更新';

  @override
  String get creditDetailLoadErrorMessage =>
      'クレジット情報を読み込めませんでした。接続を確認してもう一度お試しください。';

  @override
  String get creditDetailRetryButton => '再試行';

  @override
  String get creditDetailCurrentPlanTitle => '現在のプラン';

  @override
  String get creditDetailActiveBadge => '有効';

  @override
  String get creditDetailActivePlanFallback => '有効なプラン';

  @override
  String creditDetailCreditsPerMonth(int credits) {
    return '$creditsクレジット / 月';
  }

  @override
  String get creditDetailFullAccessSubtitle => '講義学習アシスタントの全機能をお楽しみください。';

  @override
  String get creditDetailMonthlyCreditsTitle => '月間クレジット';

  @override
  String creditDetailResetsOn(String date) {
    return '$dateにリセット';
  }

  @override
  String get creditDetailNoActivePlanTitle => '有効なプランがありません';

  @override
  String get creditDetailNoActivePlanSubtitle => '下のプランから選んで、講義資料の生成を始めましょう。';

  @override
  String get creditDetailPlansLoadError => 'プランを読み込めませんでした。下に引っ張って再読み込みしてください。';

  @override
  String creditDetailPlanActivatedSnackbar(String planName) {
    return '$planNameが有効になりました！';
  }

  @override
  String get creditDetailActivateErrorTitle => 'プランを有効にできませんでした';

  @override
  String get creditDetailOkButton => 'OK';

  @override
  String creditDetailPlanSubtitle(int credits, int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '/ $monthsヶ月',
    );
    return '$creditsクレジット $_temp0';
  }

  @override
  String get creditDetailPriceFree => '無料';

  @override
  String get creditDetailUsageHistoryTitle => '利用履歴';

  @override
  String get creditDetailHourlySummaryLabel => '1時間ごとの集計';

  @override
  String get creditDetailUsageHistoryLoadError => '利用履歴を読み込めませんでした。';

  @override
  String get creditDetailNoUsageActivity => '最近の利用履歴はありません。';

  @override
  String creditDetailViewMoreButton(int count) {
    return 'もっと見る（残り$count件）';
  }

  @override
  String creditDetailCreditsSuffix(String delta) {
    return '$delta クレジット';
  }

  @override
  String get activityRecordsTitleSaved => '保存済み';

  @override
  String get activityRecordsTitleLikes => 'いいね';

  @override
  String get activityRecordsTitleDislikes => '低評価';

  @override
  String get activityRecordsTitleAnnouncements => 'お知らせ';

  @override
  String get activityRecordsTitleTrash => 'ゴミ箱';

  @override
  String get activityRecordsEmptyTrashLabel => 'ゴミ箱を空にする';

  @override
  String get activityRecordsTrashRetentionBanner => 'ゴミ箱内のアイテムは30日後に完全に削除されます。';

  @override
  String get activityRecordsFilterAll => 'すべて';

  @override
  String get activityRecordsFilterReviewCards => '復習カード';

  @override
  String get activityRecordsFilterDeepNotes => '詳細ノート';

  @override
  String get activityRecordsFilterKeywords => 'キーワード';

  @override
  String get activityRecordsFilterFunFacts => 'ファンファクト';

  @override
  String get activityRecordsFilterActive => '未完了';

  @override
  String get activityRecordsFilterCompleted => '完了';

  @override
  String get activityRecordsFilterCourses => 'コース';

  @override
  String get activityRecordsFilterLectures => '講義';

  @override
  String activityRecordsItemsFoundCount(int count) {
    return '$count件見つかりました';
  }

  @override
  String get activityRecordsNoFilterMatch => 'このフィルターに一致するアイテムはありません。';

  @override
  String activityRecordsLoadFailed(String error) {
    return '記録の読み込みに失敗しました: $error';
  }

  @override
  String activityRecordsDeletedOnLabel(String date, String type) {
    return '$dateに削除 · $type';
  }

  @override
  String get activityRecordsRestoredSnackbar => 'アイテムを復元しました。';

  @override
  String activityRecordsDeleteItemDialogTitle(String title) {
    return '「$title」を削除しますか？';
  }

  @override
  String get activityRecordsDeleteItemDialogMessage =>
      'このアイテムはローカルデータベースとクラウドの両方から完全に削除されます。この操作は取り消せません。';

  @override
  String get activityRecordsCancelButton => 'キャンセル';

  @override
  String get activityRecordsDeleteButton => '削除';

  @override
  String get activityRecordsItemDeletedSnackbar => 'アイテムを完全に削除しました。';

  @override
  String get activityRecordsEmptyTrashDialogTitle => 'ゴミ箱を空にしますか？';

  @override
  String get activityRecordsEmptyTrashDialogMessage =>
      'ソフト削除されたすべての講義・コース・お知らせが、ローカルデータベースとクラウドの両方から完全に削除されます。この操作は取り消せません。';

  @override
  String get activityRecordsEmptyTrashSuccessSnackbar => 'ゴミ箱を空にしました。';

  @override
  String activityRecordsEmptyTrashPartialFailureSnackbar(
    int deletedCount,
    int failedCount,
  ) {
    return '$deletedCount件を削除しました。$failedCount件は失敗し、再試行のためゴミ箱に残ります。';
  }

  @override
  String get activityRecordsTypeLabelCourse => 'コース';

  @override
  String get activityRecordsTypeLabelLecture => '講義';

  @override
  String get activityRecordsTypeLabelAnnouncement => 'お知らせ';

  @override
  String get activityRecordsTypeLabelItem => 'アイテム';

  @override
  String get activityRecordsUndoUnsaved => '保存解除・タップで元に戻す';

  @override
  String get activityRecordsUndoUnreacted => 'リアクション解除・タップで元に戻す';

  @override
  String get activityRecordsContentTypeReviewCard => '復習カード';

  @override
  String get activityRecordsContentTypeDeepNote => '詳細ノート';

  @override
  String get activityRecordsContentTypeKeyword => 'キーワード';

  @override
  String get activityRecordsContentTypeFunFact => 'ファンファクト';

  @override
  String get activityRecordsContentTypeDefault => 'コンテンツ';

  @override
  String get myAccountTitle => 'マイアカウント';

  @override
  String get myAccountSectionProfile => 'プロフィール';

  @override
  String get myAccountSectionActivity => 'アクティビティ';

  @override
  String get myAccountSectionApplication => 'アプリケーション';

  @override
  String get myAccountSectionSettings => '設定';

  @override
  String get myAccountDefaultDisplayName => '探検者';

  @override
  String get myAccountSaveNameTooltip => '保存';

  @override
  String get myAccountCancelEditTooltip => 'キャンセル';

  @override
  String get myAccountEditNameTooltip => '名前を編集';

  @override
  String get myAccountAboutYouLabel => '自己紹介';

  @override
  String get myAccountAboutYouPlaceholder => 'まだ自己紹介が設定されていません。';

  @override
  String get myAccountInterestsLabel => '興味・関心';

  @override
  String get myAccountInterestsPlaceholder => 'まだ興味・関心が設定されていません。';

  @override
  String get myAccountFutureDreamsLabel => '将来の夢';

  @override
  String get myAccountFutureDreamsPlaceholder => 'まだ将来の夢が設定されていません。';

  @override
  String get myAccountCreditsUnavailable => 'クレジットを取得できません';

  @override
  String get myAccountLoadingCredits => 'クレジットを読み込んでいます…';

  @override
  String get myAccountTransmissionsTitle => 'トランスミッション';

  @override
  String get myAccountTransmissionsSubtitle => '最新情報とアップデート';

  @override
  String get myAccountIntroductionTitle => 'アプリ紹介';

  @override
  String get myAccountIntroductionSubtitle => '導入スライドを見返す';

  @override
  String get myAccountOnboardingTitle => 'オンボーディング';

  @override
  String get myAccountOnboardingSubtitle => '初期設定のやり直し';

  @override
  String get myAccountTutorialTitle => 'チュートリアル';

  @override
  String get myAccountTutorialSubtitle => '使い方ガイド';

  @override
  String get myAccountTutorialComingSoonSnackbar => 'チュートリアルは今後のアップデートで提供予定です。';

  @override
  String get myAccountNewBadge => 'NEW';

  @override
  String get myAccountNoTransmissionsSnackbar => '現在利用可能なトランスミッションはありません。';

  @override
  String get myAccountSavedSubtitle => '復習カード・詳細ノート・キーワード';

  @override
  String get myAccountLikesDislikesSubtitle => '復習カード・詳細ノート・ファンファクト';

  @override
  String get myAccountAnnouncementsSubtitle => '完了済みのものを含む';

  @override
  String get myAccountTrashSubtitle => '削除されたコース・講義';

  @override
  String get myAccountRecordingLanguageTitle => '録音言語';

  @override
  String get myAccountDisplayLanguageTitle => '表示言語';

  @override
  String get myAccountPermissionsTitle => '許可設定';

  @override
  String get myAccountPermissionsSubtitle => 'マイク・通知・バックグラウンド';

  @override
  String get permissionsSettingsPageTitle => '許可設定';

  @override
  String get myAccountPrivacyPolicyTitle => 'プライバシーポリシー';

  @override
  String get myAccountTermsOfServiceTitle => '利用規約';

  @override
  String get myAccountContactUsTitle => 'お問い合わせ';

  @override
  String get myAccountChangeEmailTitle => 'メールアドレスを変更';

  @override
  String get myAccountChangePasswordTitle => 'パスワードを変更';

  @override
  String get myAccountChangeLoginMethodTitle => 'ログイン方法を変更';

  @override
  String get myAccountChangeAccountTitle => 'アカウントを変更';

  @override
  String get myAccountSignOutTitle => 'サインアウト';

  @override
  String get myAccountDeleteAccountTitle => 'アカウントを削除';

  @override
  String get deleteAccountDialogTitle => 'アカウントを削除しますか？';

  @override
  String get deleteAccountDialogWarningMessage =>
      '本当にアカウントを削除してもよろしいですか？録音した講義、文字起こし、プロフィールデータはすべて完全に削除されます。この操作は取り消せません。';

  @override
  String get deleteAccountDialogWakingBackendStatus => 'バックエンドサービスを起動しています...';

  @override
  String get deleteAccountDialogDeletingStatus => 'アカウントを削除しています...';

  @override
  String get deleteAccountDialogSlowBackendError =>
      'バックエンドサービスの起動に通常より時間がかかっています。しばらくしてからもう一度お試しください。';

  @override
  String get deleteAccountDialogPasswordPrompt => '確認のためパスワードを入力してください:';

  @override
  String get deleteAccountDialogPasswordLabel => 'パスワード';

  @override
  String deleteAccountDialogEmailPrompt(String email) {
    return '確認のためメールアドレス（$email）を入力してください:';
  }

  @override
  String get deleteAccountDialogEmailLabel => 'メールアドレス';

  @override
  String deleteAccountDialogUsernamePrompt(String username) {
    return '確認のためユーザーネーム（$username）を入力してください:';
  }

  @override
  String get deleteAccountDialogUsernameLabel => 'ユーザーネーム';

  @override
  String get deleteAccountDialogCancelButton => 'キャンセル';

  @override
  String get deleteAccountDialogConfirmButton => 'アカウントを削除';

  @override
  String get plansTitle => 'プランと料金';

  @override
  String get plansHeadline => '学習をもっと加速させよう';

  @override
  String get plansSubheadline =>
      '学習ペースに合ったプランを選びましょう。アップグレード・ダウングレードはいつでも可能です。';

  @override
  String get plansBillingToggleMonthly => '月額';

  @override
  String get plansBillingToggleYearly => '年額';

  @override
  String get plansBillingToggleSaveBadge => '20%お得';

  @override
  String get plansStarterTitle => 'スターター';

  @override
  String get plansStarterSubtitle => '気軽に学びたい方向けの基本機能';

  @override
  String get plansStarterBillingPeriod => '永年無料';

  @override
  String get plansCurrentPlanBadge => '現在のプラン';

  @override
  String get plansStarterButtonCurrent => '現在有効なプラン';

  @override
  String get plansStarterButtonDowngrade => 'スタータープランにダウングレード';

  @override
  String get plansStarterFeature1 => '月間100クレジット';

  @override
  String get plansStarterFeature2 => '標準AI講義文字起こし';

  @override
  String get plansStarterFeature3 => 'コアトピックマップ生成';

  @override
  String get plansStarterFeature4 => '基本的なAI Q&Aチャット';

  @override
  String get plansStarterAlreadyOnSnackbar => 'すでにスタータープランをご利用中です。';

  @override
  String get plansProTitle => 'Orbit Pro';

  @override
  String get plansProSubtitle => '最高速度、無制限のインサイト';

  @override
  String get plansProBillingPeriodAnnual => '月額換算（年払い）';

  @override
  String get plansBillingPeriodMonthly => '月額';

  @override
  String get plansMostPopularBadge => '🔥 一番人気';

  @override
  String get plansProButton => 'Proにアップグレード';

  @override
  String get plansProFeature1 => '月間1,200クレジット（12倍）';

  @override
  String get plansProFeature2 => 'リアルタイムオンデバイス＆Whisper ASR';

  @override
  String get plansProFeature3 => '無制限の詳細ノート・復習カード';

  @override
  String get plansProFeature4 => 'AIモデルの優先処理速度';

  @override
  String get plansProFeature5 => '文字起こしのエクスポート（PDF・Markdown）';

  @override
  String get plansProFeature6 => 'ギャラクシーナレッジグラフ フル機能';

  @override
  String get plansMaxTitle => 'Orbit Max';

  @override
  String get plansMaxSubtitle => 'ヘビーユーザー・研究者向け';

  @override
  String get plansBestValueBadge => '⚡ ベストバリュー';

  @override
  String get plansMaxButton => 'Orbit Maxを入手';

  @override
  String get plansMaxFeature1 => '月間3,500クレジット';

  @override
  String get plansMaxFeature2 => 'Proの全機能を含む';

  @override
  String get plansMaxFeature3 => '高度なギャラクシーナレッジグラフ';

  @override
  String get plansMaxFeature4 => 'カスタムAIモデルコンテキスト＆ファインチューニング';

  @override
  String get plansMaxFeature5 => '24時間365日の優先サポート';

  @override
  String get plansMaxFeature6 => '新機能への早期アクセス';

  @override
  String get plansFooterNote => 'いつでもキャンセル可能。安全に暗号化されています。';

  @override
  String plansSelectDialogTitle(String planName) {
    return '$planNameを選択';
  }

  @override
  String plansSelectDialogMessage(String planName) {
    return '$planNameの購入機能は次回アップデートで近日公開予定です！';
  }

  @override
  String get plansSelectDialogConfirmButton => '了解';

  @override
  String get changePasswordResetSentTitle => 'リセットリンクを送信しました';

  @override
  String changePasswordResetSentMessage(String email) {
    return '登録されたメールアドレス（$email）にパスワードリセット用のリンクを送信しました。受信トレイを確認し、リンクから新しいパスワードを設定してください。';
  }

  @override
  String get changePasswordCloseButton => '閉じる';

  @override
  String get changePasswordTitle => 'パスワードを変更';

  @override
  String get changePasswordSubtitle =>
      '本人確認のため現在のパスワードを入力すると、メールにリセットリンクを送信します。';

  @override
  String get changePasswordSlowServerError =>
      'メールサービスの起動に通常より時間がかかっています。しばらくしてからもう一度お試しください。';

  @override
  String get changePasswordCurrentPasswordLabel => '現在のパスワード';

  @override
  String get changePasswordCurrentPasswordRequiredError => '現在のパスワードを入力してください';

  @override
  String get changeEmailDifferentRequiredError => '新しいメールアドレスは現在のものと異なる必要があります';

  @override
  String get changeEmailSendingVerificationStatus => '確認メールを送信しています...';

  @override
  String get changeEmailVerificationSentTitle => '確認メールを送信しました';

  @override
  String get changeEmailVerificationSentMessage =>
      '現在のメールアドレスと新しいメールアドレスの両方に確認リンクを送信しました。両方のメールから変更を確認してください。';

  @override
  String get changeEmailTitle => 'メールアドレスを変更';

  @override
  String changeEmailCurrentEmailLabel(String email) {
    return '現在のメールアドレスは$emailです';
  }

  @override
  String get changeEmailNewLabel => '新しいメールアドレス';

  @override
  String get changeEmailRequiredError => '新しいメールアドレスを入力してください';

  @override
  String get changeEmailInvalidError => '有効なメールアドレスを入力してください';

  @override
  String get changeEmailConfirmButton => '変更を確定';

  @override
  String get userProfileDetailTitle => 'プロフィール';

  @override
  String get userProfileDetailEditTooltip => 'プロフィールを編集';

  @override
  String changeAuthProviderCurrentLabel(String provider) {
    return '現在: $provider';
  }

  @override
  String get changeAuthProviderUnknownProvider => '不明';

  @override
  String get changeAuthProviderFooterNote =>
      '※ ログイン方法を変更すると認証設定が更新されます。いつでも元に戻せます。';

  @override
  String changeAccountCurrentLabel(String value) {
    return '現在: $value';
  }

  @override
  String changeAccountButtonLabel(String provider) {
    return '別の$providerアカウントを選択';
  }

  @override
  String get courseSheetSaveButton => '保存';

  @override
  String get courseNoAnnouncementsLabel => 'アナウンスはまだありません';

  @override
  String get coursePageTitle => 'コース';

  @override
  String get coursePageBackToCoursesLabel => 'コース一覧';

  @override
  String get coursePageNewCourseButton => '新規コース';

  @override
  String coursePageLoadError(String error) {
    return 'エラー: $error';
  }

  @override
  String get coursePageEmptyTitle => 'コースがまだありません';

  @override
  String get coursePageEmptySubtitle => '最初のコースを作成して始めましょう';

  @override
  String get coursePageNoYearLabel => '年度未設定';

  @override
  String get coursePageNoTermLabel => '学期未設定';

  @override
  String get coursePageTopicMapTitle => 'トピックマップ';

  @override
  String get coursePageTopicMapRecreatingLabel => '再作成中…';

  @override
  String get coursePageTopicMapRecreateLabel => 'トピックマップを再作成';

  @override
  String get coursePageTopicMapOpenLabel => 'トピックマップを開く';

  @override
  String get coursePageTopicMapNotGeneratedLabel => 'まだ生成されていません';

  @override
  String get coursePageLecturesTitle => '講義';

  @override
  String get coursePageNoLecturesYet => '記録された講義はまだありません';

  @override
  String get coursePageNewLectureButton => '新規講義';

  @override
  String get coursePageRecreateTopicMapDialogTitle => 'トピックマップを再作成しますか？';

  @override
  String get coursePageRecreateTopicMapDialogMessage =>
      'トピックマップを再作成しますか？最近の講義の変更を反映して修復します。数分かかる場合があります。';

  @override
  String get coursePageRecreateConfirmButton => '再作成';

  @override
  String get coursePageRecreateErrorTitle => 'トピックマップを再作成できませんでした';

  @override
  String get coursePageOkButton => 'OK';

  @override
  String get coursePageOfflineSnackbar => 'オフラインです。キャッシュされたデータを表示しています。';

  @override
  String get courseCreateSheetEditTitle => 'コースを編集';

  @override
  String get courseCreateSheetNewTitle => 'コースを作成';

  @override
  String get courseCreateSheetDesignPreviewLabel => 'デザインプレビュー';

  @override
  String get courseCreateSheetPreviewTitlePlaceholder => '新しいコース名';

  @override
  String get courseCreateSheetPreviewSubtitle => '見た目の設定';

  @override
  String get courseCreateSheetColorLabel => 'コースカラー';

  @override
  String get courseCreateSheetIconLabel => 'コースアイコン';

  @override
  String get courseCreateSheetYearLabel => '年度';

  @override
  String get courseCreateSheetYearHint => '例: 2026';

  @override
  String get courseCreateSheetTermLabel => '学期';

  @override
  String get courseCreateSheetTermHint => '例: 秋学期';

  @override
  String get courseCreateSheetTitleLabel => 'コース名 *';

  @override
  String get courseCreateSheetTitleHint => '例: コンピュータサイエンス入門';

  @override
  String get courseCreateSheetMoreInfoLabel => '詳細情報';

  @override
  String get courseCreateSheetCodeLabel => 'コースコード';

  @override
  String get courseCreateSheetCodeHint => '例: CS101';

  @override
  String get courseCreateSheetProfessorLabel => '教授';

  @override
  String get courseCreateSheetProfessorHint => '例: 山田先生';

  @override
  String get courseCreateSheetSchoolLabel => '学校';

  @override
  String get courseCreateSheetSchoolHint => '例: ○○大学';

  @override
  String get courseCreateSheetSubjectLabel => '科目';

  @override
  String get courseCreateSheetSubjectHint => '例: コンピュータサイエンス';

  @override
  String get courseCreateSheetSummaryLabel => '概要';

  @override
  String get courseCreateSheetSummaryHint => 'このコースはどんな内容ですか？';

  @override
  String get courseCreateSheetTitleRequiredError => 'コース名を入力してください';

  @override
  String get courseCreateSheetCustomColorDialogTitle => 'カスタムカラー';

  @override
  String get courseCreateSheetHueLabel => '色相';

  @override
  String get courseCreateSheetLightnessLabel => '明度';

  @override
  String get courseCreateSheetHexLabel => '16進数カラーコード';

  @override
  String get courseCreateSheetCancelButton => 'キャンセル';

  @override
  String get courseCreateSheetOkButton => 'OK';

  @override
  String get lectureEditSheetChangeCourseDialogTitle => 'コースを変更しますか？';

  @override
  String get lectureEditSheetChangeCourseDialogMessage =>
      'この講義のコースを変更すると、トピックマップの構造が変わり、同期に影響する可能性があります。続行してもよろしいですか？';

  @override
  String get lectureEditSheetProceedButton => '続行';

  @override
  String get lectureEditSheetTitle => '講義を編集';

  @override
  String get lectureEditSheetCourseLabel => 'コース';

  @override
  String get lectureEditSheetNoCourseLabel => 'コース未設定';

  @override
  String get lectureTileUnassignedCourse => 'コース未選択';

  @override
  String get lectureEditSheetUnknownCourseFallback => '不明なコース';

  @override
  String get lectureEditSheetDateTimeLabel => '講義日時';

  @override
  String get lectureEditSheetTitleFieldLabel => 'タイトル';

  @override
  String lectureEditSheetTitleFieldDefaultSuffix(String title) {
    return '$title（デフォルト）';
  }

  @override
  String get announcementEditSheetTitleRequiredError => 'タイトルを入力してください。';

  @override
  String get announcementEditSheetTitle => 'アナウンスを編集';

  @override
  String get announcementEditSheetTypeLabel => '種類';

  @override
  String get announcementEditSheetTitleFieldLabel => 'タイトル';

  @override
  String get announcementEditSheetTitleFieldHint => 'アナウンスのタイトル';

  @override
  String get announcementEditSheetDescriptionFieldLabel => '説明';

  @override
  String get announcementEditSheetDescriptionFieldHint => '追加の詳細（任意）';

  @override
  String get announcementEditSheetTypeTodo => 'やること';

  @override
  String get announcementEditSheetTypeEvent => 'イベント';

  @override
  String get announcementEditSheetTypeHint => 'ヒント';

  @override
  String get announcementEditSheetTypeInfo => '情報';

  @override
  String get courseDetailsSheetCreatedLabel => '作成日';

  @override
  String courseAnnouncementsSheetLoadError(String error) {
    return 'エラー: $error';
  }

  @override
  String get audioPlayerBarTopicIndexTitle => 'トピック目次';

  @override
  String audioPlayerBarTopicLabel(int index) {
    return 'トピック$index';
  }

  @override
  String get audioPlayerBarDownloadingMessage => '音声をストレージからダウンロード中…';

  @override
  String audioPlayerBarLoadErrorMessage(String error) {
    return '音声の読み込みに失敗しました: $error';
  }

  @override
  String get audioPlayerBarPreparingMessage => '音声プレイヤーを準備中…';

  @override
  String get audioPlayerBarPreviousTopicTooltip => '前のトピック / トピックを最初から再生';

  @override
  String get audioPlayerBarRewindTooltip => '10秒戻る';

  @override
  String get audioPlayerBarForwardTooltip => '10秒進む';

  @override
  String get audioPlayerBarNextTopicTooltip => '次のトピック';

  @override
  String get audioPlayerBarTopicIndexMenuTooltip => 'トピック目次メニュー';

  @override
  String announcementTranscriptModalErrorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get announcementTranscriptModalLectureNotFound => '講義が見つかりません';

  @override
  String get announcementTranscriptModalAutoScrollOnTooltip =>
      '自動スクロールモード（5秒後に再開）';

  @override
  String get announcementTranscriptModalAutoScrollOffTooltip =>
      '自動スクロール無効（OFF）';

  @override
  String get announcementTranscriptModalOfflineMessage =>
      'オフラインです。オンラインに戻ると文字起こしが読み込まれます。';

  @override
  String announcementTranscriptModalUnavailableError(String error) {
    return '文字起こしを利用できません: $error';
  }

  @override
  String get announcementTranscriptModalGeneratingMessage => '文字起こしを生成中…';

  @override
  String announcementTranscriptModalTopicLabel(int index) {
    return 'トピック$index';
  }

  @override
  String get announcementTranscriptModalLectureFallbackTitle => '講義';

  @override
  String get announcementTranscriptModalOfflineErrorShort => 'オフラインです';

  @override
  String transcriptPageLectureLoadError(String error) {
    return '講義の読み込みに失敗しました: $error';
  }

  @override
  String get transcriptPageLectureNotFound => '講義が見つかりません';

  @override
  String get transcriptPageTitle => '文字起こし';

  @override
  String get transcriptPageAutoScrollOnTooltip => '自動スクロールモード（5秒後に再開）';

  @override
  String get transcriptPageAutoScrollOffTooltip => '自動スクロール無効（OFF）';

  @override
  String get transcriptPageOfflineMessage => 'オフラインです。オンラインに戻ると文字起こしが読み込まれます。';

  @override
  String transcriptPageUnavailableError(String error) {
    return '文字起こしを利用できません: $error';
  }

  @override
  String get transcriptPageGeneratingMessage => '文字起こしがありません。';

  @override
  String transcriptPageTopicLabel(int index) {
    return 'トピック$index';
  }

  @override
  String get transcriptPageOfflineErrorShort => 'オフラインです';

  @override
  String get cardSelectionToolbarHighlightLabel => 'ハイライト';

  @override
  String get cardSelectionToolbarNoteLabel => 'ノート';

  @override
  String get cardSelectionToolbarCopyLabel => 'コピー';

  @override
  String get cardSelectionToolbarSourceLabel => '出典';

  @override
  String get cardSelectionToolbarLikeLabel => 'いいね';

  @override
  String get cardSelectionToolbarDislikeLabel => '低評価';

  @override
  String get cardSelectionToolbarSaveLabel => '保存';

  @override
  String get noteToolbarHintText => 'ノートを追加...';

  @override
  String get cardSelectionToolbarSourceNotFoundMessage =>
      '選択範囲に対応する出典が見つかりませんでした。';

  @override
  String get cardSelectionToolbarCopiedToClipboardMessage => 'クリップボードにコピーしました';

  @override
  String get reviewCardsViewerNoCardsYet => '復習カードはまだありません';

  @override
  String get reviewCardsViewerViewListTooltip => '一覧を表示';

  @override
  String reviewCardsViewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get reviewCardsViewerListSheetTitle => '復習カード一覧';

  @override
  String get reviewCardsViewerNavigationHint => '左右をタップ  •  スワイプでめくる';

  @override
  String get reviewCardTypeHook => 'つかみ';

  @override
  String get reviewCardTypeCoreWhy => '重要ポイント';

  @override
  String get reviewCardTypeGotcha => 'ひらめき';

  @override
  String get reviewCardTypeNextAction => '次のアクション';

  @override
  String get aiDisclaimerText => '※ AI生成コンテンツのため誤りが含まれる場合があります';

  @override
  String get changeAvatarSheetTitle => 'アバターを変更';

  @override
  String get changeAvatarSelectFromLibrary => 'ライブラリから選択';

  @override
  String get changeAvatarTabIcons => 'アイコン';

  @override
  String get changeAvatarTabBackgrounds => '背景';

  @override
  String get changeAvatarInitialsLabel => 'イニシャル';

  @override
  String get changeAvatarBgStyleVivid => 'ビビッド';

  @override
  String get changeAvatarBgStylePastel => 'パステル';

  @override
  String get changeAvatarBgStyleDark => 'ダーク';

  @override
  String get changeAvatarSave => '保存';

  @override
  String get changeAvatarRestoreSocialAccount => 'ソーシャルアカウントの画像に戻す';

  @override
  String get changeAvatarSavedSuccess => 'アバターを変更しました';

  @override
  String get changeAvatarUploading => '画像をアップロード中...';

  @override
  String get reviewCardsDashboardGeneratingMessage => '復習カードを生成中…';

  @override
  String get reviewCardsDashboardTitle => '復習カード';

  @override
  String get deepNotesListTitle => '詳細ノート';

  @override
  String get deepNotesDetailNoNotesAvailable => '利用可能なノートがありません';

  @override
  String get deepNotesDetailViewListTooltip => '一覧を表示';

  @override
  String deepNotesDetailPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get deepNotesDetailListSheetTitle => '詳細ノート一覧';

  @override
  String get deepNotesDetailPullPrevHint => '引くかタップで前のノートへ';

  @override
  String get deepNotesDetailPullNextHint => '引くかタップで次のノートへ';

  @override
  String get deepNotesDetailContentGeneratingPlaceholder =>
      'このトピックの詳細ノートはまだ生成中です…';

  @override
  String get deepNotesListGeneratingMessage => '詳細ノートを生成中…';

  @override
  String lectureNotePageTopicLabel(int index) {
    return 'トピック$index';
  }

  @override
  String get homeOfflineSnackBarMessage => 'オフライン状態です。キャッシュされたデータを表示しています。';

  @override
  String get initialSyncErrorTitle => 'アカウントの初期設定を完了できませんでした';

  @override
  String get initialSyncErrorMessage =>
      'データを取得するためサーバーに接続できませんでした。インターネット接続をご確認のうえ、もう一度お試しください。';

  @override
  String get initialSyncErrorRetryButton => '再試行';

  @override
  String get initialSyncErrorRetrying => '再試行中…';

  @override
  String get homeRecordLectureButton => '講義を録音する';

  @override
  String get homeAnnouncementsSheetTitle => 'お知らせ一覧';

  @override
  String get homeAnnouncementsEmptyMessage => '現在お知らせはありません';

  @override
  String homeAnnouncementsSheetLoadError(String error) {
    return 'エラー: $error';
  }

  @override
  String get homeEmptyAnnouncementMessage1 => '宇宙の探求を続けましょう！';

  @override
  String get homeEmptyAnnouncementMessage2 => 'すべての星は星くずから始まりました。その調子！';

  @override
  String get homeEmptyAnnouncementMessage3 => '銀河は静かです。次の講義で輝かせましょう。';

  @override
  String get homeEmptyAnnouncementMessage4 => '便りがないのは良い便り。新しい学びの時間ですか？';

  @override
  String get homeEmptyAnnouncementMessage5 => '宇宙は気長です。焦らずいきましょう。';

  @override
  String get homeCoursesSectionTitle => 'コース';

  @override
  String get homeRecentLecturesSectionTitle => '最近の講義';

  @override
  String get funFactsUntitledLecture => '無題の講義';

  @override
  String get funFactsUnknownLecture => '不明な講義';

  @override
  String funFactsUpdateReactionFailed(String error) {
    return 'リアクションの更新に失敗しました: $error';
  }

  @override
  String get funFactsDefaultCardTitle => '私たちは星の物質でできている';

  @override
  String get funFactsDefaultCardBody =>
      'あなたは星の物質からできています✨ あなたの体にある炭素、酸素、鉄は何十億年も前の超新星爆発で生成されました。宇宙の歴史があなたの中に生きているのです。';

  @override
  String get funFactsDefaultCardFooter => '宇宙の起源 · カール・セーガン';

  @override
  String get makeProfileBioEmptyError => 'まずあなた自身について少し教えてください';

  @override
  String get makeProfileSheetTitle => 'プロフィール作成';

  @override
  String get makeProfileSheetSubtitle => 'Fun Factsや学習素材をあなたに合わせてパーソナライズします。';

  @override
  String get makeProfileChangeAvatarComingSoon => 'アバター変更（準備中）';

  @override
  String get makeProfileUsernameHint => '例: Shogo';

  @override
  String get makeProfileAboutYouLabel => 'あなたについて *';

  @override
  String get makeProfileAboutYouHint => '専攻や学習スタイルなど、自由に書いてください';

  @override
  String get makeProfileInterestsLabel => '興味・関心';

  @override
  String get makeProfileInterestsHint => '例: 天文学、ギター、歴史';

  @override
  String get makeProfileFutureDreamsLabel => '将来の夢・目標';

  @override
  String get makeProfileFutureDreamsHint => 'どんな目標に向かって勉強していますか？';

  @override
  String get makeProfileSaveButton => 'プロフィールを保存';

  @override
  String get courseIconCategorySchool => '学校・学習';

  @override
  String get courseIconCategoryHumanityLang => '人文・語学';

  @override
  String get courseIconCategorySocietyLaw => '社会・法律';

  @override
  String get courseIconCategoryScienceSpace => '理学・宇宙';

  @override
  String get courseIconCategoryTechBuild => 'IT・工学・建築';

  @override
  String get courseIconCategoryAgriMarine => '農学・水産';

  @override
  String get courseIconCategoryMedical => '医学・医療';

  @override
  String get courseIconCategorySportsHealth => 'スポーツ・健康';

  @override
  String get courseIconCategoryArtTravel => '芸術・観光';

  @override
  String contactFailedToPickFile(String error) {
    return 'ファイルの選択に失敗しました: $error';
  }

  @override
  String get contactAuthError => '認証エラーが発生しました。再度サインインしてください。';

  @override
  String get contactConnecting => 'サポートサービスに接続中...';

  @override
  String get contactSlowService =>
      'サポートサービスの起動に時間がかかっています。しばらく時間をおいて再度お試しいただくか、support@lefture.com まで直接メールでお問い合わせください。';

  @override
  String get contactSending => 'お問い合わせを送信中...';

  @override
  String get contactPreparingUpload => 'ファイルのアップロードを準備中...';

  @override
  String get contactUploadingAttachment => '添付ファイルをアップロード中...';

  @override
  String get contactSubmittingTicket => 'チケットを送信中...';

  @override
  String get contactTimeoutError =>
      '接続がタイムアウトしました。ネットワーク接続を確認して再度お試しいただくか、support@lefture.com までメールでお問い合わせください。';

  @override
  String contactSubmissionError(String error) {
    return '送信に失敗しました: $error。support@lefture.com までメールでお問い合わせいただくことも可能です。';
  }

  @override
  String get contactTitleSent => '送信完了';

  @override
  String get contactTitle => 'お問い合わせ';

  @override
  String get contactHelpTitle => 'どのようなご要件ですか？';

  @override
  String get contactHelpSubtitle => 'カテゴリを選択し、質問や不具合の詳細をご記入ください。メールにて返信いたします。';

  @override
  String get contactCategoryLabel => 'カテゴリ';

  @override
  String get contactCategoryBug => '不具合・バグ報告';

  @override
  String get contactCategoryFeedback => 'ご要望・フィードバック';

  @override
  String get contactCategoryAccount => 'アカウント・ログイン';

  @override
  String get contactCategoryOther => 'その他';

  @override
  String get contactMessageDetailsLabel => 'お問い合わせ内容';

  @override
  String get contactMessageRequired => 'お問い合わせ内容を入力してください';

  @override
  String get contactAttachmentLabel => '添付ファイル（任意）';

  @override
  String get contactUploadButton => 'ファイルをアップロード';

  @override
  String get contactSubmitButton => 'お問い合わせを送信';

  @override
  String get contactSuccessTitle => '送信が完了しました';

  @override
  String get contactSuccessDescription =>
      'お問い合わせの送信が完了しました。ご登録メールアドレスに確認メールをお送りしました。内容を確認の上、メールにてご返信いたします。';

  @override
  String get contactTicketCodeLabel => 'チケットコード';

  @override
  String get contactBackToSettingsButton => '設定に戻る';

  @override
  String get appErrorDialogGuidance =>
      'しばらく時間をおいてから再度お試しください。問題が解決しない場合は、この画面のスクリーンショットを撮影の上、お問い合わせ画面よりご連絡ください。';

  @override
  String get appErrorDialogTechnicalDetails => '技術的な詳細:';

  @override
  String get appErrorDialogContactSupport => 'サポートにお問い合わせ';

  @override
  String get appErrorDialogClose => '閉じる';

  @override
  String get appErrorBoxGuidance =>
      'しばらく時間をおいてから再度お試しください。問題が解決しない場合は、スクリーンショットを撮影の上サポートにご連絡ください。';

  @override
  String get offlineBannerMessage => 'オフラインです';

  @override
  String get recordingMiniPlayerRecording => '録音中…';

  @override
  String get recordingMiniPlayerPaused => '一時停止中';

  @override
  String get aiChatSheetTitle => 'AIに質問';

  @override
  String get aiChatSheetInputHint => 'この講義について質問する…';

  @override
  String get aiChatSheetPreviewFallback => 'これはプレビューです。実際のAI回答機能は今後実装予定です。';

  @override
  String get courseDeleteDialogTitle => 'コースを削除しますか？';

  @override
  String courseDeleteDialogMessage(String title) {
    return '本当に「$title」を削除しますか？このコース内のすべての講義および生成データも削除されます。';
  }

  @override
  String get lectureDeleteDialogTitle => '講義を削除しますか？';

  @override
  String lectureDeleteDialogMessage(String title) {
    return '本当に「$title」を削除しますか？この操作により、講義とすべての生成コンテンツが削除されます。';
  }

  @override
  String get announcementDeleteDialogTitle => 'お知らせを削除しますか？';

  @override
  String announcementDeleteDialogMessage(String title) {
    return '本当に「$title」を削除しますか？';
  }

  @override
  String get spaceshipAnnouncementGotIt => '了解';

  @override
  String get authOrDivider => 'または';

  @override
  String get commonEditButton => '編集';

  @override
  String get commonDeleteButton => '削除';

  @override
  String get legalDocumentLoadErrorTitle => '文書を読み込めませんでした';

  @override
  String get legalDocumentLoadErrorSubtitle => 'ネットワーク接続を確認して、もう一度お試しください。';

  @override
  String get commonRetryButton => '再試行';

  @override
  String legalDocumentEffectiveDate(String date) {
    return '発効日: $date';
  }

  @override
  String get broadSelectionSheetTitle => '文字起こしセクションの選択';

  @override
  String get broadSelectionSheetDescription =>
      '選択範囲に複数のセクションが含まれています。表示したいセクションを選択してください:';

  @override
  String get introBackButton => '戻る';

  @override
  String get introLanguageButton => '言語';

  @override
  String get introNextButton => '次へ';

  @override
  String get introHeroEyebrow => 'ようこそ leFture へ';

  @override
  String get introHeroTitleLine1 => 'Record your lectures,';

  @override
  String get introHeroTitleLine2 => 'for your futures.';

  @override
  String get introHeroSubtitle => '退屈だった授業は、今日からあなただけのエンタメに。';

  @override
  String get introHeroStageLabel => '録音 → あなただけの宇宙へ';

  @override
  String get introMagicEyebrow => 'その未来が待つ、3つの魔法';

  @override
  String get introMagicHeadline => '録音ボタンを押すだけ。\nここが、あなたの新しい遊び場になる。';

  @override
  String get introMagicCard1Tag => 'Review Cards';

  @override
  String get introMagicCard1Title => '授業後すぐに、簡単復習';

  @override
  String get introMagicCard1Desc => '録り終えた瞬間、要点はもうカードに集約。';

  @override
  String get introMagicCard2Tag => 'Deep Notes';

  @override
  String get introMagicCard2Title => '詳細なノートで、完全理解';

  @override
  String get introMagicCard2Desc => '聞き逃しても大丈夫。深く、ていねいに。';

  @override
  String get introMagicCard3Tag => 'Fun Facts';

  @override
  String get introMagicCard3Title => '“おもしろ知識”が興味にダイレクトヒット';

  @override
  String get introMagicCard3Desc => 'あなたの「へぇ！」を狙い撃ちで届ける。';

  @override
  String get introCtaLead => '体験したことのない、\nワクワクする学びを。';

  @override
  String get introCtaSub => 'さあ、今日から始めよう。\n毎日の授業を心から楽しむために。';

  @override
  String get introCtaButton => 'leFtureをはじめる';

  @override
  String get dateToday => '今日';

  @override
  String get dateYesterday => '昨日';

  @override
  String get onboardingBackButton => '戻る';

  @override
  String get onboardingSkipButton => 'スキップ';

  @override
  String get onboardingNextButton => '次へ';

  @override
  String get onboardingContinueButton => '続ける';

  @override
  String get onboardingGetStartedButton => 'はじめる';

  @override
  String get onboardingIntroEyebrow => 'ようこそ';

  @override
  String get onboardingIntroTitle => 'さあ、あなただけの学びを始めましょう';

  @override
  String get onboardingIntroSubtitle =>
      'あと少しだけ準備をさせてください。この4つのステップで、あなた専用のleFtureが整います。';

  @override
  String get onboardingIntroHint => '約2分で完了します';

  @override
  String get onboardingIntroStep1Title => '言語設定';

  @override
  String get onboardingIntroStep1Desc => '表示言語と録音言語を選びます';

  @override
  String get onboardingIntroStep2Title => 'プロフィール';

  @override
  String get onboardingIntroStep2Desc => '専攻・興味・将来の夢を教えてください';

  @override
  String get onboardingIntroStep3Title => '権限許可';

  @override
  String get onboardingIntroStep3Desc => '録音とお知らせの権限を確認します';

  @override
  String get onboardingIntroStep4Title => 'ウェルカムボーナス';

  @override
  String get onboardingIntroStep4Desc => 'ウェルカムボーナスを受け取る';

  @override
  String get onboardingLanguageEyebrow => '言語';

  @override
  String get onboardingLanguageTitle => '言語を設定しましょう';

  @override
  String get onboardingLanguageSubtitle => 'アプリの表示言語と、録音する授業の言語を選んでください。';

  @override
  String get onboardingLanguageDisplayLabel => '表示言語';

  @override
  String get onboardingLanguageDisplayDesc => 'アプリの中身と生成コンテンツの表示言語';

  @override
  String get onboardingLanguageRecordingLabel => '録音言語';

  @override
  String get onboardingLanguageRecordingDesc => '録音する授業・講義の言語';

  @override
  String get onboardingLanguageFooterNote => '※ 後からアカウントページの「設定」よりいつでも変更できます。';

  @override
  String get onboardingPermissionsEyebrow => '初期設定';

  @override
  String get onboardingPermissionsTitle => 'いくつかの許可をお願いします';

  @override
  String get onboardingPermissionsSubtitle => 'バックグラウンドで録音を安全に維持するために必要です。';

  @override
  String get onboardingPermissionsMicTitle => 'マイク';

  @override
  String get onboardingPermissionsMicSubtitle =>
      '講義の音声を聞き取り、その場で文字起こしするために使います。';

  @override
  String get onboardingPermissionsNotifTitle => '通知';

  @override
  String get onboardingPermissionsNotifSubtitle =>
      'バックグラウンド録音を安定させるために使います（任意）。';

  @override
  String get onboardingPermissionsBackgroundTitle => 'バックグラウンドでも安定して動作させる';

  @override
  String get onboardingPermissionsBackgroundSubtitle =>
      '端末によっては、これを許可しないとバックグラウンドでの録音が停止してしまうことがあります。';

  @override
  String get onboardingPermissionsNotGrantedLabel => 'タップして許可';

  @override
  String get onboardingPermissionsOpenSettingsLabel => '設定を開く';

  @override
  String get onboardingPermissionsMicDialogTitle => 'マイクへのアクセスが必要です';

  @override
  String get onboardingPermissionsMicDialogMessage =>
      '録音・文字起こし・学習教材の生成には、マイクへのアクセスが必須です。次の画面で表示される許可のリクエストに回答してください。';

  @override
  String get onboardingPermissionsMicDialogContinue => '続ける';

  @override
  String get recordingMicSettingsDialogTitle => 'マイクへのアクセスがオフになっています';

  @override
  String get recordingMicSettingsDialogMessage =>
      'マイクへのアクセスがないと録音できません。設定アプリでマイクを許可すると録音を開始できます。';

  @override
  String get recordingMicSettingsDialogLater => 'あとで';

  @override
  String get recordingMicSettingsDialogOpenSettings => '設定を開く';

  @override
  String get onboardingPermissionsRequiredDialogTitle => 'バックグラウンド権限が必要です';

  @override
  String get onboardingPermissionsRequiredDialogMessage =>
      'アプリがバックグラウンドに移っても録音を続けるために必要です。続けるにはこれを許可してください。';

  @override
  String get onboardingPermissionsRequiredDialogButton => 'わかりました';

  @override
  String get onboardingPermissionsAllGranted => 'すべての権限が許可されています';

  @override
  String get onboardingPermissionsRequesting => '権限を要求中...';

  @override
  String get onboardingPermissionsAllowAll => 'すべての権限を許可';

  @override
  String get onboardingPlanEyebrow => 'もうすぐ完了';

  @override
  String get onboardingPlanTitle => 'leFtureを体験する';

  @override
  String get onboardingPlanBadge => 'ウェルカムボーナス：毎月1,500クレジット付与';

  @override
  String get onboardingPlanSubtitle =>
      'あなたのアカウントは「ウェルカムボーナス」プランでスタートします — 毎月1,500クレジットが無料で付与され、すべての機能をお使いいただけます。';

  @override
  String get onboardingPlanActiveTitle => 'すでにプランが有効です';

  @override
  String get onboardingPlanClaimError =>
      'プランを有効化できませんでした。後ほどアカウントページから再度お試しください。';

  @override
  String onboardingProfileStepCounter(int current, int total) {
    return 'プロフィール · $total問中$current問目';
  }

  @override
  String get onboardingProfileInterestsTitle => '何に興味がありますか？';

  @override
  String get onboardingProfileInterestsSubtitle => '豆知識や例えを、あなた好みに調整するために使います。';

  @override
  String get onboardingProfileDreamsTitle => '将来、何を目指していますか？';

  @override
  String get onboardingProfileDreamsSubtitle => '長期的な目標や、なりたい将来の姿など。';

  @override
  String get onboardingProfileBioTitle => '他にも、あなたらしさを教えてください';

  @override
  String get onboardingProfileBioSubtitle => '性格や価値観、今頑張っていることなど。';

  @override
  String get onboardingProfileBioRequiredNote => '必須項目です。あなた専用のコンテンツ作りに欠かせません。';

  @override
  String get onboardingDoneTitle => '準備完了です';

  @override
  String get onboardingDoneSubtitle => 'さっそくコースを作成して、最初の講義を録音しましょう！';

  @override
  String get pipelineTaskTranscribeMaster => '音声を文字起こし中';

  @override
  String get pipelineTaskCheckAndAssemble => '文字起こしデータを準備中';

  @override
  String get pipelineTaskCoreExtraction => '重要トピックを抽出中';

  @override
  String get pipelineTaskRoleClassification => '話者ロールを分類中';

  @override
  String get pipelineTaskAnnouncementGeneration => 'お知らせ・要連絡事項を抽出中';

  @override
  String get pipelineTaskTopicMapping => 'トピックマップを生成中';

  @override
  String get pipelineTaskReviewCardGeneration => '復習カードを生成中';

  @override
  String get pipelineTaskImagePromptGeneration => 'トピックアートをデザイン中';

  @override
  String get pipelineTaskImageRendering => 'トピックアートをレンダリング中';

  @override
  String get pipelineTaskFunFactBrainstorming => '関連トリビアの構想中';

  @override
  String get pipelineTaskFunFactSearch => '関連トリビアを検索中';

  @override
  String get pipelineTaskFunFactsGeneration => '関連トリビアを執筆中';

  @override
  String get pipelineTaskDetailContentsGeneration => '詳細ノート（Deep Notes）を執筆中';

  @override
  String get pipelineTaskFinalizeJob => '解析結果の最終処理中';

  @override
  String get homeTutorialCalloutMessage => 'このアプリについての講義を見てみよう!';

  @override
  String get lectureViewerTutorialReviewCardsCallout => '復習カードを見てみよう!';

  @override
  String get editKeywordDialogTitle => 'キーワードの編集';

  @override
  String get editKeywordTermLabel => '用語名';

  @override
  String get editKeywordTermHint => '用語名を入力';

  @override
  String get editKeywordDefinitionLabel => '説明 / 解釈';

  @override
  String get editKeywordDefinitionHint => 'キーワードの説明やメモを入力...';

  @override
  String get editKeywordSaveButton => '保存';

  @override
  String get editKeywordCancelButton => 'キャンセル';

  @override
  String get appGateMaintenanceTitle => 'ただいまメンテナンス中です';

  @override
  String get appGateMaintenanceDefaultMessage =>
      '現在サーバーのメンテナンスを行っています。しばらく経ってからもう一度お試しください。';

  @override
  String get appGateContinueButton => 'このまま使う';

  @override
  String get appGatePartialFeaturesUnavailableDisclaimer =>
      '一部機能は利用できない場合があります';

  @override
  String get appGateUpdateTitle => 'アップデートが必要です';

  @override
  String get appGateUpdateDefaultMessage =>
      'ご利用のバージョンは古いため、一部機能が正しく動作しない可能性があります。最新版へのアップデートをお願いします。';

  @override
  String get appGateUpdateButton => 'アップデートする';

  @override
  String get appGateUpdateLaterButton => '後で';

  @override
  String get appGateOpenStoreFailedSnackbar =>
      'App Storeを開けませんでした。App Storeアプリから直接アップデートしてください。';

  @override
  String get maintenanceBannerMessage => 'メンテナンス中：一部機能が利用できません';

  @override
  String get signOutBlockedByRecordingTitle => '録音中です';

  @override
  String get signOutBlockedByRecordingMessage => 'サインアウトする前に、録音を停止して保存してください。';

  @override
  String get signOutBlockedByRecordingConfirmButton => 'OK';

  @override
  String get signOutSyncingMessage => '未送信の変更を送信しています…';

  @override
  String get signOutPendingTitle => '未同期のデータが削除されます';

  @override
  String get signOutPendingIntro =>
      'サインアウトすると、このアカウントのデータはこの端末から削除されます。以下はまだサーバーに送信できていません:';

  @override
  String signOutPendingChangesLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未送信の変更 $count 件',
    );
    return '$_temp0';
  }

  @override
  String signOutPendingRecordingsLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '音声のアップロードが完了していない録音 $count 件。この音声はこの端末にしか存在せず、復元できません。',
    );
    return '$_temp0';
  }

  @override
  String get signOutOfflineTitle => 'オフラインのままサインアウトしますか？';

  @override
  String get signOutOfflineLine =>
      'オフラインのため、今は同期できません。また、再びサインインするにはネット接続が必要です。';

  @override
  String get signOutDiscardConfirmButton => '削除してサインアウト';

  @override
  String get signOutStayCancelButton => 'サインアウトしない';

  @override
  String get signInUserNotFoundMessage =>
      'アカウントが存在しません。新規登録画面からユーザーネームを設定して登録してください。';
}
