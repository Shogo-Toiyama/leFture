走らせる前に、これ絶対実行してね！
- python3 -m venv .venv
- source .venv/bin/activate
- pip install -r requirements.txt

- python3 -m contents_generation.main

新しいパッケージをインストールしたら
- pip freeze > requirements.txt

---

ローカルサーバー再起動: cd lefture_backend && python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8080
端末再接続時: adb reverse tcp:8080 tcp:8080 を毎回実行 → flutter run --dart-define=BACKEND_URL=http://localhost:8080
ADCアカウント: gcloud config set account shogo.toiyama@gmail.com でleftureプロジェクトに切り替え済み