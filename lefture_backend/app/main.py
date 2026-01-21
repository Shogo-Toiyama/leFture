import os
from fastapi import FastAPI, BackgroundTasks, HTTPException, Request
from pydantic import BaseModel
from app.services.pipeline import run_lecture_pipeline

app = FastAPI()

# SupabaseからのWebhookペイロード構造に合わせる
class WebhookPayload(BaseModel):
    type: str
    table: str
    record: dict
    schema: str
    old_record: dict | None = None

@app.get("/")
def health_check():
    return {"status": "ok", "service": "leFture-backend"}

@app.post("/webhook/process-lecture")
async def trigger_processing(payload: WebhookPayload, background_tasks: BackgroundTasks):
    """
    Supabaseの processing_jobs テーブルへの INSERT をトリガーにする
    """
    print(f"📩 Webhook received: {payload.type} on {payload.table}")

    # INSERT時のみ反応する
    if payload.type != "INSERT":
        return {"message": "Ignored (not INSERT)"}

    record = payload.record
    job_id = record.get("id")
    
    if not job_id:
        raise HTTPException(status_code=400, detail="Missing job id")

    # バックグラウンドでパイプラインを実行
    background_tasks.add_task(run_lecture_pipeline, job_id)

    return {"message": "Job started", "job_id": job_id}