import math
from pathlib import Path
from groq import Groq
from app.services.helpers.helpers import print_log

class TranscriptionService:
    def __init__(self, collector=None):
        # APIキーは環境変数 GROQ_API_KEY から自動で読み込まれます
        self.client = Groq()
        self.model = "whisper-large-v3-turbo"
        # 旧コードとの互換性のため、使わなくても引数として受け取れるようにしておく
        self.collector = collector

    def run(self, audio_path: Path, chunk_index: int) -> dict:
        """
        WAVファイルを受け取り、Groqで文字起こしを行い、
        Flutter表示用のテキストと、後続処理用のJSON配列を返す。
        """
        print_log(f"   [Logic] Starting Groq transcription for chunk {chunk_index}")
        
        # 1. Groqに投げて verbose_json (詳細データ) で受け取る
        with open(audio_path, "rb") as f:
            res = self.client.audio.transcriptions.create(
                file=(audio_path.name, f.read()),
                model=self.model,
                response_format="verbose_json",
                language="ja"
            )

        full_text = res.text.strip()
        segments_data = []

        # 2. データの整形
        if hasattr(res, 'segments') and res.segments:
            for i, seg in enumerate(res.segments):
                seg_text = seg.get('text', '') if isinstance(seg, dict) else getattr(seg, 'text', '')
                
                # 🌟 丸めない！返ってきた生のfloat値をそのまま使う
                start = seg.get('start', 0.0) if isinstance(seg, dict) else getattr(seg, 'start', 0.0)
                end = seg.get('end', 0.0) if isinstance(seg, dict) else getattr(seg, 'end', 0.0)
                
                logprob = seg.get('avg_logprob', 0) if isinstance(seg, dict) else getattr(seg, 'avg_logprob', 0)

                # 対数確率(logprob) を 0.0〜1.0 の確率(confidence) に変換
                confidence = max(0.0, min(1.0, math.exp(logprob)))

                segments_data.append({
                    "sid": f"s{i+1:06d}",          # 🌟 シンプルに s000001 からスタート
                    "text": seg_text.strip(),
                    "confidence": round(confidence, 4), # confidenceは表示/計算用なので丸めてOK
                    "start": start,
                    "end": end,
                    "chunk_index": chunk_index     # 🌟 どのチャンクか記録しておく！
                })

        # 音声が短すぎてセグメントが分かれなかった場合の安全策
        if not segments_data and full_text:
            segments_data.append({
                "sid": "s000001",
                "text": full_text,
                "confidence": 0.99,
                "start": 0.0,
                "end": 0.0,
                "chunk_index": chunk_index
            })

        # 3. 結果を現場監督に返す
        return {
            "text": full_text,
            "segments": segments_data
        }