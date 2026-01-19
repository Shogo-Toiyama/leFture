# Python 3.11 (軽量版)
FROM python:3.11-slim

# ffmpegなどのシステム依存関係をインストール
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ設定
WORKDIR /app

# 依存関係ファイルのコピーとインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# コードをコピー
COPY . .

# Cloud Runはポート8080でリッスンすることを期待している
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]