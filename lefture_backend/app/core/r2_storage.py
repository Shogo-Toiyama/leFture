import os
import json
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from pathlib import Path
from typing import Any, Tuple

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
        # max_pool_connectionsはデフォルト10のままだと、asyncio.to_threadで
        # R2呼び出しを並列化した際にここがボトルネックになる。
        # main.py起動時に設定するThreadPoolExecutor(max_workers=64)と同程度以上を
        # 確保しておけば、スレッドプール側の並列度が実質的な上限になる。
        self.s3 = boto3.client(
            's3',
            endpoint_url=self.endpoint_url,
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key,
            config=Config(signature_version='s3v4', max_pool_connections=100),
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

    def download_binary(self, storage_path: str) -> bytes:
        """R2からバイナリデータ（音声など）を生バイトのまま取得する"""
        response = self.s3.get_object(Bucket=self.bucket_name, Key=storage_path)
        return response["Body"].read()

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

    def generate_presigned_put_url(
        self,
        uid: str,
        lecture_id: str,
        file_name: str,
        content_type: str = "application/octet-stream",
        expires_in: int = 3600,
    ) -> Tuple[str, str]:
        """
        クライアントがR2へ直接PUTできる署名付きURLを発行する。マスター音声のように
        Cloud Runのリクエストボディ上限(32MB)を超えうる大きなファイルを、
        Cloud Runを経由せずアップロードするために使う。
        署名処理はローカルで完結し、実際のネットワーク呼び出しは発生しない。
        """
        path = f"{uid}/{lecture_id}/{file_name}"
        url = self.s3.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self.bucket_name,
                "Key": path,
                "ContentType": content_type,
            },
            ExpiresIn=expires_in,
            HttpMethod="PUT",
        )
        return url, path

    def object_exists(self, storage_path: str) -> bool:
        """R2上に指定パスのオブジェクトが実在するか確認する。"""
        try:
            self.s3.head_object(Bucket=self.bucket_name, Key=storage_path)
            return True
        except ClientError:
            return False

# シングルトンとしてインスタンス化
storage_service = R2StorageService()