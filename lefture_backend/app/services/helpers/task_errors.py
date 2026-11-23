"""
DAGタスクの「やり直しても結果が変わらない」失敗を表す例外。

普通の例外はCloud Tasksに500を返して自動リトライさせる(通信断やLLMの一時的な
不調など、待てば直る失敗のため)。一方、音声に発話が無い・音声ファイルが無い
といった失敗は何度やっても同じ結果になるので、リトライは無駄な再実行と
ログの山を生むだけになる。この例外が投げられたら:

- processing_tasks.error_message には "CODE: message" だけを書く(トレースバック無し)。
  アプリ/Webアプリはこの先頭のCODEを見て専用の文言を出し、リトライボタンを隠す。
- /worker/* は200を返してCloud Tasksのリトライを止め、その場でジョブをFAILEDにする
  (main.py の _run_worker_task)。

CODEを増やすときは、Flutter(ProcessingTask.failureCode)とWebアプリ
(lib/pipelineSteps.ts の taskFailureCode)の既知コード一覧にも足すこと。
"""

# 音声はあるが、文字起こしの結果に発話が1文も無い(無音・極端に短い録音など)。
NO_SPEECH_DETECTED = "NO_SPEECH_DETECTED"

# 講義に音声ファイルが紐づいていない(アップロードが完了していない)。
# /start-analysis の409応答の error_code と同じ値。
AUDIO_NOT_UPLOADED = "AUDIO_NOT_UPLOADED"


class PermanentTaskError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(f"{code}: {message}")


def format_task_error(e: BaseException, tb: str) -> str:
    """processing_tasks.error_message に書く文字列。PermanentTaskErrorは "CODE: message" のみ。"""
    if isinstance(e, PermanentTaskError):
        return str(e)
    return f"{str(e)}\n{tb}"


def has_speech(assembled_transcript: list) -> bool:
    """組み立て済みトランスクリプトに、中身のある文が1つでもあるか。

    CORE_EXTRACTIONが入力として受け付ける条件(空でないtextを持つ文が1つ以上)と揃えている。
    """
    return any((item.get("text") or "").strip() for item in (assembled_transcript or []))
