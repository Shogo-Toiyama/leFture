"""
email_content.py
----------------
leFture メール文言多言語化データ定義。

【設計方針】
- メール本文・件名・各ボタン・注釈などのテキストを言語別に完全分離して管理する。
- 日本語 (EmailContentJA) と 英語 (EmailContentEN) を定義。
- ヘルパー関数 get_email_content(lang) で言語コードに応じたコンテンツオブジェクトを返す。
"""

from typing import Type


class EmailContentEN:
    """英語用メール文言定義"""

    # --- Common ---
    SUPPORT_APP_NAME = "leFture Support"
    SUPPORT_DESK_APP_NAME = "leFture Support Desk"
    FOOTER_IGNORE_NOTE = "If you did not request this email, you can safely ignore it."
    FOOTER_COPYRIGHT = "&copy; {year} leFture. All rights reserved."

    # --- Signup Email ---
    SIGNUP_SUBJECT = "leFture - Verify Email Address"
    SIGNUP_HEADING = "Welcome to leFture!"
    SIGNUP_BODY = "Thank you for signing up for leFture. Please click the button below to verify your email address."
    SIGNUP_BUTTON = "Verify Email Address"
    SIGNUP_EXPIRE_NOTE = "This link is valid for <strong>24 hours</strong>."
    SIGNUP_FALLBACK_NOTE = "If the button doesn't work, copy and paste the link below into your browser:"

    # --- Password Reset Email ---
    PASSWORD_RESET_SUBJECT = "leFture - Reset Your Password"
    PASSWORD_RESET_HEADING = "Reset Your Password"
    PASSWORD_RESET_BODY = "A request has been made to reset your password. Please click the button below to set a new password."
    PASSWORD_RESET_BUTTON = "Reset Password"
    PASSWORD_RESET_EXPIRE_NOTE = "This link is valid for <strong>1 hour</strong>. If you did not request a password reset, you can safely ignore this email."

    # --- Email Change Confirmation ---
    EMAIL_CHANGE_SUBJECT = "leFture - Confirm Email Address Change"
    EMAIL_CHANGE_HEADING = "Confirm Email Change"
    EMAIL_CHANGE_BODY = "A change of email address has been requested for your leFture account. Please click the button below to confirm this change."
    EMAIL_CHANGE_NEW_EMAIL_LABEL = "New Email Address"
    EMAIL_CHANGE_BUTTON = "Confirm Email Change"
    EMAIL_CHANGE_EXPIRE_NOTE = "This link is valid for <strong>24 hours</strong>. If you did not make this request, please ignore this email."

    # --- Support User Acknowledgment ---
    SUPPORT_ACK_SUBJECT = "leFture Support - Inquiry Received [{ticket_code}]"
    SUPPORT_ACK_HEADING = "Inquiry Received"
    SUPPORT_ACK_BODY = "Thank you for contacting leFture Support. We have received your report and our team is currently reviewing your message."
    SUPPORT_ACK_TICKET_CODE_LABEL = "Ticket Code"
    SUPPORT_ACK_CATEGORY_LABEL = "Category"
    SUPPORT_ACK_MESSAGE_LABEL = "Message Details"
    SUPPORT_ACK_FOOTER_NOTE = "Our support team will get back to you as soon as possible via this email address. Please keep your ticket code for reference."

    # --- Support Admin Notification ---
    SUPPORT_ADMIN_SUBJECT = "[leFture Support] New Inquiry: {ticket_code}"
    SUPPORT_ADMIN_HEADING = "[Action Required] New Support Inquiry"
    SUPPORT_ADMIN_BODY = "A new support ticket has been submitted by a user:"
    SUPPORT_ADMIN_FOOTER_NOTE = "Replying directly to this email will respond to the user's email address (<strong>{user_email}</strong>)."

    # --- Trial Ending Reminder ---
    # 送信タイミング(トライアル終了の7日前)は複数州の自動更新法(カリフォルニア州
    # ARL等)が要求する通知期間(トライアル終了の3〜21日前)に収まるよう選んでいる。
    # 金額・頻度・解約方法の明示も同法が求める開示事項に対応する。
    TRIAL_ENDING_SUBJECT = "Your leFture {plan_name} trial ends on {end_date}"
    TRIAL_ENDING_HEADING = "Your Free Trial Is Ending Soon"
    TRIAL_ENDING_BODY = (
        "Your free trial of the <strong>{plan_name}</strong> plan ends on "
        "<strong>{end_date}</strong>. After that, your subscription will "
        "automatically continue and your payment method will be charged "
        "unless you cancel before then."
    )
    TRIAL_ENDING_INFO_PLAN_LABEL = "Plan"
    TRIAL_ENDING_INFO_PRICE_LABEL = "Price after trial"
    TRIAL_ENDING_INFO_DATE_LABEL = "First charge date"
    TRIAL_ENDING_BUTTON = "Manage or Cancel Subscription"
    TRIAL_ENDING_FOOTER_NOTE = (
        "You can cancel anytime before the trial ends from the Plans page in "
        "your account, at no charge. If you take no action, your subscription "
        "continues automatically."
    )


class EmailContentJA:
    """日本語用メール文言定義"""

    # --- Common ---
    SUPPORT_APP_NAME = "leFture サポート"
    SUPPORT_DESK_APP_NAME = "leFture サポートデスク"
    FOOTER_IGNORE_NOTE = "本メールにお心当たりがない場合は、破棄していただけますようお願いいたします。"
    FOOTER_COPYRIGHT = "&copy; {year} leFture. All rights reserved."

    # --- Signup Email ---
    SIGNUP_SUBJECT = "【leFture】メールアドレスの確認"
    SIGNUP_HEADING = "leFtureへようこそ！"
    SIGNUP_BODY = "leFtureにご登録いただきありがとうございます。以下のボタンをクリックしてメールアドレスの確認を完了してください。"
    SIGNUP_BUTTON = "メールアドレスを確認する"
    SIGNUP_EXPIRE_NOTE = "このリンクの有効期限は <strong>24時間</strong> です。"
    SIGNUP_FALLBACK_NOTE = "ボタンが機能しない場合は、以下のリンクをコピーしてブラウザのアドレスバーに貼り付けてください："

    # --- Password Reset Email ---
    PASSWORD_RESET_SUBJECT = "【leFture】パスワード再設定のご案内"
    PASSWORD_RESET_HEADING = "パスワードの再設定"
    PASSWORD_RESET_BODY = "パスワード再設定のリクエストを受け付けました。以下のボタンをクリックして新しいパスワードを設定してください。"
    PASSWORD_RESET_BUTTON = "パスワードを再設定する"
    PASSWORD_RESET_EXPIRE_NOTE = "このリンクの有効期限は <strong>1時間</strong> です。パスワード再設定のリクエストをしていない場合は、このメールを破棄してください。"

    # --- Email Change Confirmation ---
    EMAIL_CHANGE_SUBJECT = "【leFture】メールアドレス変更の確認"
    EMAIL_CHANGE_HEADING = "メールアドレス変更の確認"
    EMAIL_CHANGE_BODY = "leFtureアカウントのメールアドレス変更リクエストを受け付けました。以下のボタンをクリックして変更を確定してください。"
    EMAIL_CHANGE_NEW_EMAIL_LABEL = "新しいメールアドレス"
    EMAIL_CHANGE_BUTTON = "メールアドレス変更を確定する"
    EMAIL_CHANGE_EXPIRE_NOTE = "このリンクの有効期限は <strong>24時間</strong> です。変更リクエストをしていない場合は、このメールを破棄してください。"

    # --- Support User Acknowledgment ---
    SUPPORT_ACK_SUBJECT = "【leFture サポート】お問い合わせを受領いたしました [{ticket_code}]"
    SUPPORT_ACK_HEADING = "お問い合わせを受領いたしました"
    SUPPORT_ACK_BODY = "leFture サポートにお問い合わせいただきありがとうございます。ご送信いただいた内容を正常に受け付けました。担当チームにて順次確認・対応を行っております。"
    SUPPORT_ACK_TICKET_CODE_LABEL = "チケットコード"
    SUPPORT_ACK_CATEGORY_LABEL = "カテゴリ"
    SUPPORT_ACK_MESSAGE_LABEL = "お問い合わせ内容"
    SUPPORT_ACK_FOOTER_NOTE = "サポートチームより、本メールアドレス宛に折り返しご連絡いたします。お問い合わせの際はチケットコードをお控えください。"

    # --- Support Admin Notification ---
    SUPPORT_ADMIN_SUBJECT = "【leFture サポート】新規お問い合わせ: {ticket_code}"
    SUPPORT_ADMIN_HEADING = "[要対応] 新規サポートお問い合わせ"
    SUPPORT_ADMIN_BODY = "ユーザーより新しいサポート問い合わせが送信されました："
    SUPPORT_ADMIN_FOOTER_NOTE = "このメールに直接返信すると、ユーザーのメールアドレス（<strong>{user_email}</strong>）へ返信されます。"

    # --- Trial Ending Reminder ---
    # 送信タイミング(トライアル終了の7日前)は米国複数州の自動更新法(カリフォルニア州
    # ARL等、トライアル終了の3〜21日前に通知を義務付け)に収まるよう選んでいる。
    # 日本の特商法には同種の「終了前通知」の明文義務は無いが、同じ体験に揃える。
    TRIAL_ENDING_SUBJECT = "【leFture】{plan_name}プランの無料トライアルは{end_date}に終了します"
    TRIAL_ENDING_HEADING = "無料トライアルはまもなく終了します"
    TRIAL_ENDING_BODY = (
        "ご利用中の<strong>{plan_name}</strong>プランの無料トライアルは"
        "<strong>{end_date}</strong>に終了します。それ以降は自動的に有料プランへ"
        "移行し、登録済みのお支払い方法に課金されます。継続を希望されない場合は、"
        "それまでに解約手続きをお願いいたします。"
    )
    TRIAL_ENDING_INFO_PLAN_LABEL = "プラン"
    TRIAL_ENDING_INFO_PRICE_LABEL = "トライアル終了後の料金"
    TRIAL_ENDING_INFO_DATE_LABEL = "初回課金日"
    TRIAL_ENDING_BUTTON = "プランを管理・解約する"
    TRIAL_ENDING_FOOTER_NOTE = (
        "トライアル終了前であれば、アカウントのPlansページからいつでも無料で"
        "解約いただけます。特に操作がない場合、そのまま自動的にご契約が継続します。"
    )


def get_email_content(lang: str) -> Type[EmailContentEN]:
    """
    言語コード (例: 'ja', 'en') に対応するメール文言クラスを返す。
    指定が無い場合や未対応の言語は EmailContentEN にフォールバックする。
    """
    if lang and lang.lower().startswith("ja"):
        return EmailContentJA
    return EmailContentEN
