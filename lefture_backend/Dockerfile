# Python 3.14 (軽量版)。3.11は2027-10にサポート終了(contents_generation/test_codes/python314_upgrade)
FROM python:3.14-slim

# ffmpegなどのシステム依存関係をインストール
RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

# 作業ディレクトリ設定
WORKDIR /app

# print()を即座にCloud Runのログへ流すため、標準出力のバッファリングを無効化
ENV PYTHONUNBUFFERED=1

# 依存関係ファイルのコピーとインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN python -m nltk.downloader punkt punkt_tab

# コードをコピー
COPY . .

# Cloud Runはポート8080でリッスンすることを期待している
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]