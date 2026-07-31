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

    def generate_presigned_get_url(self, storage_path: str, expires_in: int = 604800) -> str:
        """
        R2上の非公開オブジェクトを閲覧するための署名付きGET URLを発行する。
        expires_inのデフォルトは604800秒(7日)。AWS SigV4署名の仕様上、
        presigned URLの有効期限は最大7日までしか設定できない点に注意
        (7日を超える長期リンクが必要な場合は、都度発行し直す設計にする)。
        """
        return self.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket_name, "Key": storage_path},
            ExpiresIn=expires_in,
        )

    def delete_prefix(self, prefix: str) -> int:
        """
        指定prefix配下の全オブジェクトを削除する。削除件数を返す。
        delete_objectsは1回最大1000件までのため、list_objects_v2の
        ページング(IsTruncated/NextContinuationToken)にも対応する。
        """
        deleted = 0
        continuation_token = None
        while True:
            list_kwargs = {"Bucket": self.bucket_name, "Prefix": prefix}
            if continuation_token:
                list_kwargs["ContinuationToken"] = continuation_token
            response = self.s3.list_objects_v2(**list_kwargs)
            contents = response.get("Contents", [])
            if not contents:
                break

            keys = [{"Key": obj["Key"]} for obj in contents]
            self.s3.delete_objects(Bucket=self.bucket_name, Delete={"Objects": keys})
            deleted += len(keys)

            if not response.get("IsTruncated"):
                break
            continuation_token = response.get("NextContinuationToken")

        return deleted

    def object_exists(self, storage_path: str) -> bool:
        """R2上に指定パスのオブジェクトが実在するか確認する。"""
        try:
            self.s3.head_object(Bucket=self.bucket_name, Key=storage_path)
            return True
        except ClientError:
            return False

    def load_json_cache(self, storage_path: str) -> Any | None:
        """
        R2上のオブジェクトを読み込む。存在しない場合はNoneを返す（例外を飲む）。
        トピック単位キャッシュの読み込みに使う。
        """
        try:
            response = self.s3.get_object(Bucket=self.bucket_name, Key=storage_path)
            return json.loads(response["Body"].read().decode("utf-8"))
        except ClientError:
            return None

    def save_json_cache(self, storage_path: str, data: Any) -> str:
        """
        任意のR2パスにJSONを保存する（save_json_logと違いパスを自分で指定できる）。
        """
        json_data = json.dumps(data, indent=2, ensure_ascii=False)
        self.s3.put_object(
            Bucket=self.bucket_name,
            Key=storage_path,
            Body=json_data,
            ContentType="application/json"
        )
        return storage_path

    def generate_presigned_support_url(
        self,
        uid: str,
        file_name: str,
        content_type: str = "application/octet-stream",
        expires_in: int = 3600,
    ) -> Tuple[str, str]:
        """お問い合わせ添付ファイルを R2 へアップロードするための署名付きURLを発行"""
        import uuid
        unique_file_name = f"{uuid.uuid4()}_{file_name}"
        path = f"support_attachments/{uid}/{unique_file_name}"
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

# シングルトンとしてインスタンス化
storage_service = R2StorageService()