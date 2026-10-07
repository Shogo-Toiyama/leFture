# file_attachment_test

チャットのファイル添付(PDF・docx・画像)の取り出しとビジョンの書き起こしを、実物の資料で確かめる(2026-10-05〜)。
設計: docs/chatbot_context_and_retrieval_roadmap.md 10章。

- `materials/` に実物の資料を置く(授業のスライドPDF・スキャンしたPDF・手書きノートや板書の写真・docxなど)。
  中身は個人の資料なので git には入れない(.gitignore)。
- `results/` に結果を書き出す(同じく git には入れない)。
