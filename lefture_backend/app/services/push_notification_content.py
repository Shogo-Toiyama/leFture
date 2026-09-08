"""
push_notification_content.py
-----------------------------
leFture プッシュ通知文言多言語化データ定義。email_content.py と同じ設計方針:
- 通知の件名・本文を言語別に完全分離して管理する。
- 日本語 (PushContentJA) と 英語 (PushContentEN) を定義。
- ヘルパー関数 get_push_content(lang) で言語コードに応じたコンテンツオブジェクトを返す。
"""

from typing import Type


class PushContentEN:
    """英語用プッシュ通知文言定義"""

    UNTITLED_LECTURE = "Lecture"

    JOB_COMPLETED_TITLE = "Analysis complete"
    JOB_COMPLETED_BODY = 'Analysis of "{lecture_title}" is complete.'


class PushContentJA:
    """日本語用プッシュ通知文言定義"""

    UNTITLED_LECTURE = "講義"

    JOB_COMPLETED_TITLE = "分析が完了しました"
    JOB_COMPLETED_BODY = "「{lecture_title}」の分析が完了しました。"


def get_push_content(lang: str) -> Type[PushContentEN]:
    """
    言語コード (例: 'ja', 'en') に対応するプッシュ通知文言クラスを返す。
    指定が無い場合や未対応の言語は PushContentEN にフォールバックする。
    """
    if lang and lang.lower().startswith("ja"):
        return PushContentJA
    return PushContentEN
