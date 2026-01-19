from fastapi import FastAPI, BackgroundTasks, HTTPException
from pydantic import BaseModel
from app.services.pipeline import process_lecture_job
import os

app = FastAPI()

# SupabaseのWebhookから送られてくるペイロードの定義
# (実際のSupabaseの設定に合わせて調整してください)
class WebhookPayload(BaseModel):
    type: str
    table: str
    record: dict  # ここに新しいRowのデータが入る
    schema: str

@app.get("/")
def health_check():
    return {"status": "ok", "service": "leFture-backend"}

@app.post("/webhook/process-lecture")
async def trigger_processing(payload: WebhookPayload, background_tasks: BackgroundTasks):
    """
    Supabaseからの通知を受け取り、バックグラウンド処理を開始して、
    即座に200 OKを返す。
    """
    # セキュリティチェック (簡易版: 環境変数のシークレットと照合など推奨)
    # if request.headers.get("X-Supabase-Secret") != os.environ["MY_SECRET"]:
    #     raise HTTPException(status_code=401)

    record = payload.record
    lecture_id = record.get("id")
    file_path = record.get("file_path") # DBのカラム名に合わせる

    if not lecture_id or not file_path:
        raise HTTPException(status_code=400, detail="Missing id or file_path")

    # 重たい処理はバックグラウンドタスクに投げる！
    # これにより、Supabase側にはすぐにレスポンスが返り、タイムアウトしない。
    background_tasks.add_task(process_lecture_job, lecture_id, file_path)

    return {"message": "Job received and started", "lecture_id": lecture_id}