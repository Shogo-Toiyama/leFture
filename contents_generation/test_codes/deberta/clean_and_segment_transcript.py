import re
import json
import nltk

try:
    nltk.data.find('tokenizers/punkt')
except LookupError:
    nltk.download('punkt')
    nltk.download('punkt_tab') # 最近のNLTKバージョン用の念のための追加

def clean_and_segment_transcript(raw_text):
    """Whisper風の無骨なテキストに掃除し、NLTKで高度に1文ずつリスト化する"""
    # 1. テキストの掃除（前処理）
    text = re.sub(r'\[.*?\]', '', raw_text)
    text = re.sub(r'Prof:\s*', '', text)
    text = re.sub(r'Student:\s*', '', text)
    text = text.replace('—', ', ').replace('--', ', ')
    text = re.sub(r'\.{2,}', ',', text)
    text = text.replace('"', '').replace('“', '').replace('”', '')
    text = re.sub(r'\s+', ' ', text).strip()
    
    # 2. NLTKによる文分割（Sentence Tokenization）
    sentences = nltk.sent_tokenize(text)
    
    # 3. 前後の空白文字を消し、空の要素を弾く
    sentences = [s.strip() for s in sentences if s.strip()]
    
    return sentences

def export_for_browser(sentences, chunk_size=100, output_filename="browser_input.txt"):
    """
    ChatGPTにコピペしやすいように、指定した文の数（チャンク）ごとに分割して
    テキストファイルに書き出す関数。
    """
    with open(output_filename, 'w', encoding='utf-8') as f:
        total_chunks = (len(sentences) + chunk_size - 1) // chunk_size
        
        f.write("=== ChatGPTコピペ用データ ===\n")
        f.write(f"全 {len(sentences)} 文を {total_chunks} 個のチャンクに分割しました。\n")
        f.write("各チャンクを順番にChatGPTに貼り付けてください。\n\n")
        
        for i in range(0, len(sentences), chunk_size):
            chunk = sentences[i:i + chunk_size]
            chunk_number = (i // chunk_size) + 1
            
            f.write(f"--------------------------------------------------\n")
            f.write(f"📋 【チャンク {chunk_number} / {total_chunks}】\n")
            f.write(f"--------------------------------------------------\n")
            
            # JSONの配列形式に整形して書き出す
            f.write("```json\n")
            f.write(json.dumps(chunk, ensure_ascii=False, indent=2))
            f.write("\n```\n\n")
            
    print(f"✅ {output_filename} に出力が完了しました！")

# ==========================================
# テスト実行
# ==========================================
raw_transcript = """Prof: Right. This is it. The final reckoning. Or as the bursar calls it the last day of instruction before you all vanish into the library to weep over exchange rate volatility. I see the look on your faces. Is the air conditioning broken again or is that just the collective heat of five hundred brains trying to remember the difference between a dirty float and a crawling peg? And so on and so forth theoretically.
Prof: Today is the review for the final. I have the exam in this folder. Or is it the other folder? Right. Actually I think I left the key in my car. Which is fine. You do not need the key if you have the intuition. If you do not have the intuition by now well. There is always summer school. The university loves the extra revenue.
Prof: Let us look at the interest rate parity equation one last time. If the domestic rate is five percent and the foreign rate is three percent. Right. We write it as one plus zero point zero five over one plus zero point zero three. Wait. No that is not it. Wait. If the inflation is indexed. Plus. Minus.
Prof: Mhm. If I am in Zurich and I want to buy a sandwich in London. No. That is the purchasing power parity. Backwards. It is backwards. If the interest is higher in New York the dollar must. Face the board now. The denominator. If it is larger than the numerator. Right. No. Subtract the spread.
Prof: Right. Naturally. Moving on to the Black Scholes application for currency options.
Prof: The exam will have forty multiple choice questions and three long form problems. One of those problems involves a multi national corporation hedging a billion yen exposure. Do not forget the transaction costs. Students always forget the transaction costs as if the banks work for free. They do not. Trust me. I have seen the holiday homes of the managing directors in Lagos.
Student: Professor Okoro for the long form question on hedging do we need to calculate the delta neutral position using the continuous compounding formula or will the discrete version suffice for the points?
Prof: Great question.
Prof: The thing about the hedge fund industry in the early two thousands was that everyone thought they were a genius until the leverage caught up with them. I knew a guy at a firm in Greenwich who swore by his proprietary algorithm for Russian ruble futures. He bought a yacht and named it Alpha. Three months later the Russian government defaulted and he had to sell the yacht just to pay for the naming rights. The arrogance of the human mind when faced with a random walk is a fascinating study in psychology. Truly. He is a high school math teacher now. I think he is happier. Or at least he has less ulcers.
Prof: Does that clarify the rounding requirements for the decimal points? Good.
Prof: Right. I wanted to pull up the sample exam on the screen but it seems the projector has decided to enter a state of deep meditation. The light is blinking amber. Is that a warning or a suggestion? Right. The cursor is. Why is it moving in the opposite direction of my hand? It is like the mouse is haunted by the ghost of a failed economist. You know they spent three million dollars on this building and I still have to use a wooden stick to reach the emergency power switch. The inefficiency is a constant. It is the only variable in this room with a standard deviation of zero.
Prof: Forget the technology. It has failed us just like the Bretton Woods system. I will write the three main topics for the final on the board. One. Interest rate parity. Two. Capital asset pricing in global markets. Three. The death of hope. Right. That last one is a joke. Mostly.
Prof: If you can calculate the cross rate between the Swiss franc and the South African rand without getting a headache you will be fine. Mhm. Moves to the left see? Should be right. Is wrong on the slide. Right. If the carry trade unwinds the whole market goes to the floor and so on and so forth theoretically. Is the oxygen low in here? Just the panic? Right. Good luck. You will need it. Or better yet you will need to study. Thursday. In the big hall. Do not be late. The proctors have no souls.

"""

sentences = clean_and_segment_transcript(raw_transcript)
export_for_browser(sentences, chunk_size=139, output_filename="prompt_inputs.txt")