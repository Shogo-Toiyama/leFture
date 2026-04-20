import os
import json
import boto3
from botocore.config import Config
from pathlib import Path
from typing import Any

class R2StorageService:
    def __init__(self):
        # 環境変数からR2の接続情報を取得
        self.bucket_name = os.getenv("R2_BUCKET_NAME")
        self.endpoint_url = os.getenv("R2_ENDPOINT_URL")
        self.access_key = os.getenv("R2_ACCESS_KEY_ID")
        self.secret_key = os.getenv("R2_SECRET_ACCESS_KEY")
        required = {
            "R2_BUCKET_NAME": self.bucket_name,
            "R2_ENDPOINT_URL": self.endpoint_url,
            "R2_ACCESS_KEY_ID": self.access_key,
            "R2_SECRET_ACCESS_KEY": self.secret_key,
        }
        missing = [k for k, v in required.items() if not v]
        if missing:
            raise RuntimeError(f"Missing R2 environment variables: {', '.join(missing)}")
        
        # S3互換クライアントの初期化
        self.s3 = boto3.client(
            's3',
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            config=Config(signature_version='s3v4'),
            region_name='auto' # R2はregion_name='auto'でOK
        )

    def upload_file(self, local_path: Path, storage_path: str, content_type: str = "application/octet-stream"):
        """ファイルをR2にアップロード"""
        self.s3.upload_file(
            str(local_path), 
            self.bucket_name, 
            storage_path,
            ExtraArgs={'ContentType': content_type}
        )
        return storage_path

    def download_file(self, storage_path: str, local_path: Path):
        """ファイルをR2からダウンロード"""
        self.s3.download_file(self.bucket_name, storage_path, str(local_path))

    def save_json_log(self, uid: str, lecture_id: str, task_type: str, data: Any):
        """
        中間処理のJSONデータをログとして保存する。
        パス例: {uid}/{lecture_id}/pipeline_logs/{task_type}.json
        """
        storage_path = f"{uid}/{lecture_id}/pipeline_logs/{task_type}.json"
        json_data = json.dumps(data, indent=2, ensure_ascii=False)
        
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=storage_path,
            Body=json_data,
            ContentType="application/json"
        )
        print(f"📁 Log saved to R2: {storage_path}")
        return storage_path
    
    def save_binary(self, uid: str, lecture_id: str, file_name: str, data: bytes, content_type: str = "application/octet-stream") -> str:
        """バイナリデータ（画像など）をR2に保存し、パスを返す"""
        path = f"{uid}/{lecture_id}/{file_name}"
        # AWS S3 / Boto3 の場合
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=path,
            Body=data,
            ContentType=content_type
        )
        return path

# シングルトンとしてインスタンス化
storage_service = R2StorageService()