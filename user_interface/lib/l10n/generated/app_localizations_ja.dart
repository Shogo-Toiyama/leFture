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
  String get signUpErrorUsernameTooShort => 'ユーザー名は3文字以上で入力してください';

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
  String get recordingSpeechModelDialogTitle => '音声モデルが必要です';

  @override
  String get recordingSpeechModelDialogMessage =>
      'リアルタイム文字起こしには、この言語のオンデバイス音声モデルが必要です。今すぐダウンロードしますか？';

  @override
  String get recordingSpeechModelDownloadConfirm => 'ダウンロード';

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
  String recordingAsrModelErrorPrefix(String message) {
    return '⚠️ $message';
  }

  @override
  String get recordingOnDeviceModelSubtitle => 'ライブ字幕にはオンデバイスの音声モデルが使われます。';

  @override
  String get recordingMomentFunLabel => '楽しい瞬間';

  @override
  String get recordingMomentDifficultLabel => '難しい';

  @override
  String get recordingMomentRevisitLabel => '後で復習';

  @override
  String get recordingMomentNoteLabel => 'メモ';

  @override
  String get recordingLiveTranscriptHeader => 'ライブ文字起こし';

  @override
  String get recordingWaitingForAudio => '音声を待っています...';

  @override
  String get recordingRealtimeOffHint =>
      'ライブ字幕やAIとの会話を使うには、（Voiceタブの「More Settings」から）リアルタイム文字起こしをオンにしてください。';

  @override
  String get recordingReactionFunLabel => '楽しい';

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
  String get lectureViewerFunFactHeader => '雑学';

  @override
  String get lectureViewerTranscriptButtonLabel => '文字起こし';

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
  String get lectureViewerInfoSheetEmptyState => 'まだ何もありません';

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
  String get notStartedNoCourseWarning =>
      'この講義にはまだコースが割り当てられていません。コースを設定するまで解析を開始できません。';

  @override
  String get notStartedChooseCourseButton => 'コースを選択';

  @override
  String get notStartedStartingLabel => '開始しています...';

  @override
  String get notStartedStartAnalysisButton => '解析を開始';

  @override
  String notStartedErrorPrefix(String error) {
    return 'エラー: $error';
  }

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
  String get processingViewStartingOverLabel => 'やり直しています...';

  @override
  String get processingViewStartOverFromScratchButton => '最初からやり直す';

  @override
  String get statusViewProcessingLabel => '処理しています...';

  @override
  String statusScaffoldErrorPrefix(String error) {
    return 'エラー: $error';
  }

  @override
  String get statusScaffoldSyncingTitle => '音声を同期しています...';

  @override
  String get statusScaffoldSyncingMessage => 'アップロードが完了するまでお待ちください。';

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
  String get activityRecordsFilterFunFacts => '雑学';

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
  String get activityRecordsContentTypeFunFact => '雑学';

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
  String get myAccountNewBadge => 'NEW';

  @override
  String get myAccountNoTransmissionsSnackbar => '現在利用可能なトランスミッションはありません。';

  @override
  String get myAccountSavedSubtitle => '復習カード・詳細ノート・キーワード';

  @override
  String get myAccountLikesDislikesSubtitle => '復習カード・詳細ノート・雑学';

  @override
  String get myAccountAnnouncementsSubtitle => '完了済みのものを含む';

  @override
  String get myAccountTrashSubtitle => '削除されたコース・講義';

  @override
  String get myAccountRecordingLanguageTitle => '録音言語';

  @override
  String get myAccountDisplayLanguageTitle => '表示言語';

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
  String get courseCreateSheetNewTitle => '新規コース';

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
  String get transcriptPageGeneratingMessage => '文字起こしを生成中…';

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
  String get reviewCardsViewerNavigationHint => '左右をタップ  •  スワイプでトピック切替';

  @override
  String get reviewCardsDashboardGeneratingMessage => '復習カードを生成中…';

  @override
  String get reviewCardsDashboardTitle => '復習カード';

  @override
  String get deepNotesListTitle => 'ディープノート';

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
  String get emptyHomeDefaultName => 'チャレンジャー';

  @override
  String emptyHomeWelcomeGreeting(String name) {
    return 'leFtureへようこそ、$nameさん';
  }

  @override
  String get emptyHomeStartBuilding => 'あなたの未来を創り始めましょう。';

  @override
  String get emptyHomeGalaxyDescription =>
      '講義を追加するたびに、新しい星が灯ります。\n学びを重ねることで、あなただけの銀河が広がっていきます。';

  @override
  String get emptyHomeStepMakeProfileTitle => 'プロフィール作成';

  @override
  String get emptyHomeStepMakeProfileDoneSubtitle => 'プロフィール設定完了';

  @override
  String get emptyHomeStepMakeProfilePendingSubtitle => 'あなたについて教えてください';

  @override
  String get emptyHomeStepCreateCourseTitle => 'コースを作成';

  @override
  String get emptyHomeStepCreateCourseDisabledSubtitle => '最初にプロフィールを設定してください';

  @override
  String get emptyHomeStepCreateCourseDoneSubtitle => 'コース作成済み';

  @override
  String get emptyHomeStepCreateCoursePendingSubtitle => '最初のコースを追加しましょう';

  @override
  String get emptyHomeStepRecordLectureTitle => '講義を録音';

  @override
  String get emptyHomeStepRecordLectureDisabledSubtitle => '最初にコースを作成してください';

  @override
  String get emptyHomeStepRecordLectureDoneSubtitle => '講義録音済み';

  @override
  String get emptyHomeStepRecordLecturePendingSubtitle => '最初の講義を録音しましょう';

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
  String legalDocumentLastUpdated(String date) {
    return '最終更新日: $date';
  }
}
