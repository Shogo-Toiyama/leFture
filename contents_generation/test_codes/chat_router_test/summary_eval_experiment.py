# contents_generation/test_codes/summary_eval_experiment.py
"""
Evaluation experiment for chat summarizer (GPT-6 Luna).
Tests:
1. Review agenda (multi-topic study list) -> needs_source: True
2. Simple style/facts -> needs_source: False
3. Noisy student turn with buried technical specs (Taro, boba tea, linear algebra) -> needs_source: False, but specs extracted cleanly into text.
"""

import asyncio
import json
import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parents[3]
load_dotenv(REPO_ROOT / 'lefture_backend' / '.env')
sys.path.insert(0, str(REPO_ROOT / 'lefture_backend'))

from app.services.chat_summary import (
    Turn,
    summarize_turns,
    extract_source_turns_to_fetch,
    EMPTY_HEADER,
    SUMMARY_MODEL,
)
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM


async def call_summary(turns: list[Turn], header: dict = None, prior_titles: list[str] = None):
    header = header or EMPTY_HEADER
    prior_titles = prior_titles or []
    billing = BillingEngine(task_type="CHAT_SUMMARY")
    llm = UnifiedLLM(billing)
    
    t0 = time.time()
    sections, new_header = await summarize_turns(
        llm=llm,
        prior_titles=prior_titles,
        header=header,
        turns=turns,
        language="ja",
        next_handle=1,
    )
    duration_sec = round(time.time() - t0, 2)
    source_turns_to_fetch = extract_source_turns_to_fetch(new_header)
    
    return {
        "duration_sec": duration_sec,
        "token_usage": getattr(billing, "last_usage", None),
        "sections": sections,
        "header": new_header,
        "source_turns_to_fetch": source_turns_to_fetch,
    }



def make_test_case_1() -> list[Turn]:
    """Test Case 1: Explicit 7-topic review agenda established in Turn 1."""
    return [
        Turn(
            number=1,
            user_message_id="u1",
            assistant_message_id="a1",
            user_content="明日ネットワークの期末テストがあるので、授業の全範囲を復習したいです。\n具体的には以下の7つのテーマを1つずつ順番に対策していきたいです：\n1. OSI参照モデルと各層のカプセル化\n2. エンドツーエンド原理（End-to-End argument）\n3. 回線交換とパケット交換の違い\n4. データリンク層のフレーミングと誤り検出（CRC）\n5. スライディングウィンドウとフロー制御\n6. IPアドレッシングとサブネットマスク計算\n7. ルーティングアルゴリズム（距離ベクトルとリンク状態）\nまずは1番のOSI参照モデルから解説をお願いできますか？",
            assistant_content="テスト前の全範囲総復習ですね！素晴らしい計画です。挙げてもらった7つのテーマは、講義の骨格そのものなので、1つずつ確実に自分の言葉で説明できるようにしていきましょう。\n\nまずは「1. OSI参照モデルと各層のカプセル化」から始めます。\n\n### なぜ層（レイヤー）に分けるのか？\nネットワーク通信は非常に複雑です。もし単一のプログラムですべて（電気信号の送信からWebページのレンダリングまで）を制御しようとすると、一部のハードウェアが変わっただけで全体を書き直す必要があります。そこで、各層が「下位層の具体的な実装を知らなくても、提供されるサービスだけを利用できる」ように抽象化したのが階層モデルです。\n\n### データのカプセル化（Encapsulation）の流れ\n上位層から下位層へデータが渡される際、各層が自身の制御情報（ヘッダー）をデータの前後に付与していきます：\n- **アプリケーション層**: 生のメッセージ（HTTPリクエストなど）\n- **トランスポート層 (TCP/UDP)**: ポート番号やシーケンス番号を含むヘッダーを付与し、セグメントを生成\n- **ネットワーク層 (IP)**: 送信元・宛先IPアドレスを含むIPヘッダーを付与し、パケット（データグラム）を生成\n- **データリンク層 (イーサネット)**: MACアドレスや誤り検出用FCS/CRCを含むヘッダー/トレーラを付与し、フレームを生成\n- **物理層**: ビット列を電気信号や光信号、電波に変換して媒体へ送信\n\n受信側では、これと逆の順序で各層のヘッダーを取り外しながらデータを復元していきます（非カプセル化）。\n\nまずはこの「各層がヘッダーを足していく流れ」と「なぜ層を分けるのかの理由」について、疑問点はありますか？問題なければ2番のエンドツーエンド原理に進みます！",
            assistant_created_at="2026-10-24T10:00:00Z",
            reply_language="ja",
        ),
        Turn(
            number=2,
            user_message_id="u2",
            assistant_message_id="a2",
            user_content="カプセル化の流れはバッチリ理解できました！トランスポート層でポート番号、ネットワーク層でIP、データリンク層でMACアドレスが付くんですね。次は2番のエンドツーエンド原理をお願いします。",
            assistant_content="カプセル化の各アドレスの対応関係まで完璧に整理できていますね！では予定通り、2番の「エンドツーエンド原理（End-to-End Principle）」に進みましょう。\n\n### エンドツーエンド原理の核心\nこの原理は、1981年にSaltzer、Reed、Clarkによって提唱された「通信ネットワークにおける機能配置の設計思想」です。\n一言で言えば：\n**「通信を行う両端のアプリケーション（エンド）でしか完全に実現・保証できない機能は、ネットワーク内部（ルーターやスイッチなど）ではなく、エンドホストに実装すべきである」**\nという考え方です。\n\n### 典型例：ファイルの信頼性保証\n例えば、ホストAからホストBへファイルを転送する場合を考えます：\n1. ネットワーク内の各ルーター間のリンクでどんなに誤り訂正やパケット再送を行って「通信路の信頼性」を高めても、ルーター内部のメモリ破損、ルーター自体のクラッシュ、あるいはホストAのディスク読み取りエラーまでは防げません。\n2. 結局、ファイルが正しく届いたかを100%保証するには、受信側のホストBがファイル全体のハッシュ値やチェックサムを計算し、送信側のホストAと照合する「エンド間のチェック」が不可欠です。\n3. であれば、ネットワーク内部に重厚で複雑な信頼性保証機構を組み込むのはコストと遅延の無駄（オーバーヘッド）になり、ネットワーク全体の柔軟性や高速性を損なってしまいます。\n\nそのため、インターネットの基盤（IP層）は「ベストエフォート（届く保証はしない）」というシンプルな設計にし、信頼性が必要なアプリだけがトランスポート層（TCP）でエンド間の再送制御を行うという設計になりました。\n\nこの考え方は試験でも非常によく出題されます。「なぜネットワーク内部に頼ってはいけないのか」という観点は腑に落ちましたか？",
            assistant_created_at="2026-10-24T10:05:00Z",
            reply_language="ja",
        )
    ]


def make_test_case_2() -> list[Turn]:
    """Test Case 2: Simple style preferences and single facts."""
    return [
        Turn(
            number=1,
            user_message_id="u1",
            assistant_message_id="a1",
            user_content="英語のネットワークの授業を受けてるんだけど、専門用語が多くてついていけないです。説明してもらうときは、専門用語に必ず英語表記も併記してもらえますか？",
            assistant_content="もちろんです！英語の講義だと、概念自体だけでなく英語の専門用語と日本語の対応を押さえておくことがテストでも実務でもすごく大切ですよね。以降の解説では、すべての重要な専門用語に必ず [英語表記] を添えて回答しますね。\n\nまずはどのトピックや概念から見ていきましょうか？気になっている講義の箇所があれば教えてください！",
            assistant_created_at="2026-10-24T10:00:00Z",
            reply_language="ja",
        ),
        Turn(
            number=2,
            user_message_id="u2",
            assistant_message_id="a2",
            user_content="TCPの3-way handshakeの仕組みを教えてほしいです。何を交換して何を確認してるんですか？",
            assistant_content="TCPの接続確立手順である「3ウェイ・ハンドシェイク [Three-Way Handshake]」ですね！\n\nクライアント [Client] とサーバー [Server] の間で、通信を始める前にお互いの準備ができているか、そしてデータの順番を管理する初期シーケンス番号 [ISN: Initial Sequence Number] を同期するために行われます。\n\n### 3つのステップ\n1. **SYN (Synchronize)**: クライアント → サーバー\n   - クライアントが「接続したいです」という合図（SYNフラグ=1）と、自分が使う初期シーケンス番号（例: `seq=x`）を送ります。\n2. **SYN-ACK (Synchronize-Acknowledgment)**: サーバー → クライアント\n   - サーバーが「了解しました、あなたの番号を確認しました（`ack=x+1`）」と伝え、同時に「こちらの初期シーケンス番号はこれです（SYNフラグ=1, `seq=y`）」と返します。\n3. **ACK (Acknowledgment)**: クライアント → サーバー\n   - クライアントが「サーバー側の番号を確認しました（`ack=y+1`）」と最後の確認を送ります。このパケットからデータを含めて送ることも可能です。\n\nこれによって、双方向 [Bidirectional] でパケットが届くこと、そしてお互いの初期番号が合意できたことが確認されます！",
            assistant_created_at="2026-10-24T10:05:00Z",
            reply_language="ja",
        )
    ]


def make_test_case_3() -> list[Turn]:
    """Test Case 3: Noisy student turn (Turn 4) with buried specs + boba/Taro/linear algebra noise.
    Turns 1-8 form a continuous development flow. AI responses are long and realistic.
    """
    return [
        Turn(
            number=1,
            user_message_id="u1",
            assistant_message_id="a1",
            user_content="ネットワークのプログラミング課題で、UDPソケットを使って信頼性のあるデータ転送（簡易TCPみたいなプロトコル）をPythonで自作することになったんだけど、正直どこから手をつければいいのか分からなくて…何から始めるのがいいと思う？",
            assistant_content="UDP上での信頼性通信プロトコル（Reliable Data Transfer）の実装課題ですね！これはコンピュータネットワークのプログラミング演習では定番かつ一番学びが大きい課題です。\n\nUDPはご存知の通り「コネクションレス」「パケット損失・順序の逆転・重複を検知・回復しない」プロトコルなので、TCPがOSの中で行っていることをすべて自分のコード（アプリケーション層）でエミュレートする必要があります。\n\n### 最初の一歩としてのロードマップ\nいきなり複雑な再送やウィンドウ制御を書こうとするとデバッグが地獄になるので、以下のステップで進めるのが鉄則です：\n\n1. **Step 1: 生のUDP通信の確認**\n   - まずは標準ライブラリの `socket` を使って、送信側から受信側へ文字列を送り、受信側がエコーバックするだけの最小構成を作ります。\n2. **Step 2: パケットフォーマット（ヘッダー構造）の定義**\n   - データ本体の前に「シーケンス番号」「ACK番号」「フラグ」などをどう付与するかを決め、`struct` モジュールでパック・アンパックできるようにします。\n3. **Step 3: 停止待ち（Stop-and-Wait）プロトコル**\n   - 1パケット送ったらACKが返ってくるまで待ち、返ってきたら次のパケットを送るという最小の信頼性制御を作ります。\n4. **Step 4: タイムアウトと再送**\n   - `socket.settimeout()` を使って、一定時間ACKが来なければ同じパケットを再送する処理を入れます。\n\nまずはStep 1のシンプルなUDP送受信スクリプトは書けそうでしょうか？それともコードの雛形から一緒に見ていきましょうか？",
            assistant_created_at="2026-10-24T10:00:00Z",
            reply_language="ja",
        ),
        Turn(
            number=2,
            user_message_id="u2",
            assistant_message_id="a2",
            user_content="なるほど、段階を踏んでいくんだね。ステップ1のシンプルなUDPの送受信はなんとか書けた！socket(AF_INET, SOCK_DGRAM)作ってbindして、sendtoとrecvfromでやり取りするやつだよね。次はステップ2のヘッダー構造なんだけど、Pythonでパケットにヘッダーをつけるってどうやるの？文字列でカンマ区切りとかじゃダメなのかな？",
            assistant_content="Step 1クリア、幸先いいスタートですね！\n\nカンマ区切りの文字列（例: `\"1,0,data\"`）でも一応通信はできますが、ネットワークの課題としては一般的に**バイナリ形式の固定ヘッダー**を作ることが求められます。文字列だと数字の桁数によってヘッダー長が変わってしまったり、パースに無駄なCPU処理がかかったりするためです。\n\n### `struct` モジュールによるバイナリパック\nPythonでは標準ライブラリの `struct` モジュールを使うと、C言語の構造体のようにバイト列を直接組み立てることができます。\n\n例えば：\n- シーケンス番号: 32ビット整数（4バイト）\n- ACK番号: 32ビット整数（4バイト）\n- フラグ（ACKフラグやFINフラグなど）: 16ビット整数（2バイト）\n\nこのように定義すると、合計10バイトの固定長ヘッダーになります。\n```python\nimport struct\n\n# ネットワークバイトオーダー（ビッグエンディアン '!'）で、4バイト符号なし整数(I)×2、2バイト整数(H)×1\nheader_format = '!IIH'\nheader = struct.pack(header_format, seq_num, ack_num, flags)\npacket = header + payload_bytes\n```\n\n受信側では、届いたパケットの先頭10バイトだけを切り取って `struct.unpack('!IIH', packet[:10])` とすれば、瞬時に各フィールドの値を取り出せます。残りの `packet[10:]` がそのままデータ本体（ペイロード）になります。\n\n課題の仕様書などで、ヘッダーに含めるべきフィールドの指定などはありますか？",
            assistant_created_at="2026-10-24T10:06:00Z",
            reply_language="ja",
        ),
        Turn(
            number=3,
            user_message_id="u3",
            assistant_message_id="a3",
            user_content="structモジュールってそうやって使うのか！C言語みたいでかっこいい。ヘッダーのバイト数を固定にしておけば、スライスで先頭何バイトか切り取るだけでいいから受信側がめっちゃ楽になるね。課題の仕様書を確認してみる！",
            assistant_content="そうなんです！まさに低レイヤーのネットワーク通信の醍醐味ですよね。\n\n固定長ヘッダーにしておけば、受信側は「最初のNバイトをunpackしてヘッダーを読み、残りをデータとして扱う」という処理が数行で書けます。\n仕様書には、ポート番号の指定やパケットの最大サイズ、シーケンス番号の初期値や増え方（バイト単位かパケット単位か）、再送ルールなどが詳しく書いてあるはずです。\n\n確認できたら、気になったところや指定されている条件を教えてください！それに合わせてヘッダーのフォーマットやロジックを一緒に組み立てましょう🔥",
            assistant_created_at="2026-10-24T10:12:00Z",
            reply_language="ja",
        ),
        Turn(
            number=4,
            user_message_id="u4",
            assistant_message_id="a4",
            user_content="仕様書見てきたんだけどさ、友達の太郎に線形代数の課題がめっちゃ難しくてやばいって言われて焦って、あいつ手伝ってくれって頼んでも全然手伝ってくれないし、マジでイライラしてリフレッシュにタピオカ飲みに行っちゃったんだけど、普通に並んでて結構時間食ったから、その時間勉強しとけばよかったわ…あいつテスト前いつもこうなんだよな。\nで、仕様書なんだけど、サーバー側のポートはなんか5000から5010の間で動かすように指定されてて、パケットのサイズもなんか1500のイーサネット？に入り切るように1472バイトが上限って言われたんだよね。シーケンス番号は0スタートで、上限いったら最初に戻る（モジュロ？ってやつ？）仕様にしないといけないらしくて。あ、そういえば今は必要ないかもだけど、このプロジェクト後半で使うらしくて、ACKが3回連続で重複して届いたらタイムアウト待たずにすぐ再送する機能も後で追加するって書いてあった！",
            assistant_content="太郎くんとのやり取りとタピオカ並び、お疲れ様でした…！友達の態度にモヤモヤするのめっちゃ分かりますが、甘いものでリフレッシュできたと思ってここから集中して取り返していきましょう💪\n\n仕様書から重要な要件をしっかり読み取ってきてくれましたね！仕様として非常に明確なポイントが4つあります：\n\n1. **サーバーのポート範囲**: 5000〜5010番ポートを使用すること。\n2. **最大パケットサイズ（ペイロード上限）**: 1472バイト。\n   - これは一般的なイーサネットのMTU（1500バイト）から、IPヘッダー（20バイト）とUDPヘッダー（8バイト）を引いた `1500 - 28 = 1472バイト` にぴったり収めるための標準的な設計値です。フラグメンテーションを防ぐためですね。\n3. **シーケンス番号の管理**: 0から開始し、上限に達したら剰余演算（Modulo wraparound、32ビットなら `seq % (2**32)`）で0に戻る巡回仕様。\n4. **将来の実装要件（後半パート）**: 3回連続の重複ACK（Triple Duplicate ACKs）を受け取った場合の高速再送（Fast Retransmit）。\n\n後半で使う高速再送（TCP Tahoe/Renoの仕組みですね！）も頭の片隅に置きつつ、まずは基本の1472バイト上限のパケット作成と、ポート5000番台での送受信から固めていきましょう。\n\nまずは送信用パケットを組み立てる関数を作ってみますか？",
            assistant_created_at="2026-10-24T10:20:00Z",
            reply_language="ja",
        ),
        Turn(
            number=5,
            user_message_id="u5",
            assistant_message_id="a5",
            user_content="ありがとう、ちょっと落ち着いたわ笑。タピオカ代は無駄にしたけどコード書く！じゃあまずはその1472バイトのペイロードとヘッダーをまとめる送信用関数を作りたいんだけど、struct.packのフォーマット文字列ってどう書けばいいかな？シーケンス番号32bit符号なし整数、ACK番号32bit、フラグ16bitの10バイトヘッダーにしたい。",
            assistant_content="切り替え素晴らしいです！その意気でいきましょう🔥\n\nシーケンス番号32bit（4バイト）、ACK番号32bit（4バイト）、フラグ16bit（2バイト）の合計10バイトヘッダーですね。この場合、フォーマット文字列は `'!IIH'` になります！\n\n### フォーマットの内訳\n- `!`: ネットワークバイトオーダー（ビッグエンディアン）。異なるアーキテクチャ間でもバイト順を統一するために必須です。\n- `I`: 4バイト符号なし整数（unsigned int, 0〜4,294,967,295）。シーケンス番号用。\n- `I`: 4バイト符号なし整数。ACK番号用。\n- `H`: 2バイト符号なし整数（unsigned short, 0〜65,535）。フラグ用。\n\n### 送信用パケット作成関数の例\n```python\nimport struct\n\nHEADER_FORMAT = '!IIH'\nHEADER_SIZE = struct.calcsize(HEADER_FORMAT)  # 10バイト\nMAX_PAYLOAD_SIZE = 1472\n\ndef create_packet(seq_num: int, ack_num: int, flags: int, data: bytes) -> bytes:\n    if len(data) > MAX_PAYLOAD_SIZE:\n        raise ValueError(f\"Payload too large: {len(data)} > {MAX_PAYLOAD_SIZE}\")\n    # 32bit符号なしのラップアラウンド処理\n    seq_32 = seq_num % (2**32)\n    ack_32 = ack_num % (2**32)\n    header = struct.pack(HEADER_FORMAT, seq_32, ack_32, flags)\n    return header + data\n```\n\nこれで、ペイロードが1472バイトを超えていないかのチェックと、シーケンス番号が上限を超えた場合のモジュロ処理（`% (2**32)`）も安全に組み込めます。これを組み込んでみてください！",
            assistant_created_at="2026-10-24T10:28:00Z",
            reply_language="ja",
        ),
        Turn(
            number=6,
            user_message_id="u6",
            assistant_message_id="a6",
            user_content="送信用関数できた！で、仕様書にあったポート5000番でサーバーを動かして、5001番のクライアントからパケットを送るテストをやってみたんだけど、受信側でパケットを受け取った後にACKをどうやって送り返せばいい？送信元のIPとポートを取得してそのままsendtoすればいいのかな？",
            assistant_content="パケット作成とローカルでの送受信テスト、順調に進んでますね！5000番と5010番の範囲内にちゃんと収まっていて完璧です。\n\nまさにその通りです！UDPでは `recvfrom` を呼び出すと、受信データと一緒に「送信元のIPアドレスとポート番号のタプル」が返ってきます。\n\n### 受信側でのACK返信コード例\n```python\n# サーバー側（例: ポート5000でバインド中）\ndata, client_addr = server_socket.recvfrom(2048)  # 1472 + ヘッダー10バイトを受け取れる十分なバッファ\n\n# 先頭10バイトをヘッダーとして解読\nseq_num, ack_num, flags = struct.unpack('!IIH', data[:10])\npayload = data[10:]\nprint(f\"Received seq={seq_num}, payload len={len(payload)} from {client_addr}\")\n\n# ACKパケットの作成（受信したseq_numに対するACKとして、ACK番号にseq_num+1や確認応答を入れる）\n# ACKフラグとして例えばビット0を立てる（0x01）\nack_flags = 0x01\nack_packet = create_packet(seq_num=0, ack_num=seq_num, flags=ack_flags, data=b'')\n\n# 送信元（client_addr）に向けてそのまま送り返す\nserver_socket.sendto(ack_packet, client_addr)\n```\n\n`client_addr` には `('127.0.0.1', 5001)` のようなタプルが入っているので、そのまま `server_socket.sendto(ack_packet, client_addr)` に渡すだけで相手にACKが届きます！",
            assistant_created_at="2026-10-24T10:35:00Z",
            reply_language="ja",
        ),
        Turn(
            number=7,
            user_message_id="u7",
            assistant_message_id="a7",
            user_content="ACKの返送も動いた！でもこれだとパケットが途中で消えたときに止まっちゃうよね。タイムアウトを設定して再送するのって、sock.settimeout()でやるのが普通？",
            assistant_content="ACKの送受信まで動きましたか！素晴らしいです👏\n\n仰る通り、UDPのままだとパケットロスやACKロスが起きた瞬間にお互い待ちぼうけになってフリーズしてしまいます。そこでタイムアウトと再送の出番です。\n\nPythonのソケットプログラミングでは、`sock.settimeout(秒数)` を設定して `socket.timeout` 例外をキャッチするのが最も一般的かつ確実な方法です！\n\n### クライアント側のタイムアウト再送ループの例\n```python\nimport socket\n\nclient_socket.settimeout(1.0)  # 1秒でタイムアウト\n\nmax_retries = 5\nretries = 0\nacked = False\n\nwhile not acked and retries < max_retries:\n    try:\n        # パケット送信\n        client_socket.sendto(packet, server_addr)\n        # ACK待ち\n        ack_data, _ = client_socket.recvfrom(1024)\n        _, ack_num, ack_flags = struct.unpack('!IIH', ack_data[:10])\n        \n        if ack_flags & 0x01 and ack_num == expected_ack:\n            acked = True\n            print(\"ACK received successfully!\")\n    except socket.timeout:\n        retries += 1\n        print(f\"Timeout! Retrying ({retries}/{max_retries})...\")\n\nif not acked:\n    print(\"Connection failed: exceeded maximum retries.\")\n```\n\nこのように書けば、1秒経ってもACKが届かない場合に `socket.timeout` が発生し、ループが回って再送が行われます。これでStop-and-Waitプロトコルの基本が完成します！",
            assistant_created_at="2026-10-24T10:42:00Z",
            reply_language="ja",
        ),
        Turn(
            number=8,
            user_message_id="u8",
            assistant_message_id="a8",
            user_content="タイムアウト再送もなんとかできたっぽい。あとはさっき言ってた、後半で必要になるっていう3回連続重複ACKの判定なんだけど、これって今の段階からカウンタ変数だけでも作っておいた方がいいかな？それとも一旦今の基本機能のテストを先にやるべき？",
            assistant_content="ここまで実装できたの本当にすごいです！立派なStop-and-Wait信頼性通信が完成しましたね🎉\n\nご質問の「3回連続重複ACK（Fast Retransmit）のカウンタを今作るべきか」についてですが：\n\n**結論としては、絶対に「一旦今の基本機能の動作確認とテスト」を先にやり切ることを強くおすすめします！**\n\n### 理由\n1. **Stop-and-Wait環境では重複ACKは起きない**:\n   - 重複ACKが発生するのは、ウィンドウ制御（Go-Back-NやSelective Repeat）で未確認パケットをパイプラインで複数同時に飛ばしているときに、途中のパケットだけが抜けた場合です。\n   - 1パケットずつ送って待つ現在のStop-and-Waitの段階では、重複ACKが発生する状況自体が基本的にありません。\n2. **まずはパケットロス試験で基本の堅牢性を固める**:\n   - ランダムにパケットを破棄するプロキシや受信側のテストコードを書いて、「タイムアウト再送が正しく行われ、データが壊れずに最後まで届くか」を検証する方が、課題の採点でも配点が大きいです。\n\n後半パートに入ってウィンドウ制御（パイプライン送信）を追加するタイミングで、重複ACKのカウンタ（`dup_ack_count`）と即時再送ロジックを実装するのが一番手戻りが少なく綺麗な設計になります！",
            assistant_created_at="2026-10-24T10:50:00Z",
            reply_language="ja",
        )
    ]


async def run_all_tests():
    print("=" * 60)
    print("Starting Summarizer Evaluation with GPT-6 Luna...")
    print("=" * 60)
    
    # Run Test 1
    print("\n--- Running Test Case 1 (Explicit Review Agenda) ---")
    t1_turns = make_test_case_1()
    res1 = await call_summary(t1_turns)
    print(f"Latency: {res1['duration_sec']}s")
    print(f"Sections ({len(res1['sections'])}):")
    for s in res1['sections']:
        print(f"  [S{s['handle']}] {s['title']} (turns {s['turns']})")
    print("Header:")
    print(json.dumps(res1['header'], ensure_ascii=False, indent=2))
    print(f"Source turns to fetch: {res1['source_turns_to_fetch']}")
    
    # Run Test 2
    print("\n--- Running Test Case 2 (Simple Style / Single Facts) ---")
    t2_turns = make_test_case_2()
    res2 = await call_summary(t2_turns)
    print(f"Latency: {res2['duration_sec']}s")
    print(f"Sections ({len(res2['sections'])}):")
    for s in res2['sections']:
        print(f"  [S{s['handle']}] {s['title']} (turns {s['turns']})")
    print("Header:")
    print(json.dumps(res2['header'], ensure_ascii=False, indent=2))
    print(f"Source turns to fetch: {res2['source_turns_to_fetch']}")
    
    # Run Test 3
    print("\n--- Running Test Case 3 (Noisy Turn 4 with Buried Technical Specs) ---")
    t3_turns = make_test_case_3()
    res3 = await call_summary(t3_turns)
    print(f"Latency: {res3['duration_sec']}s")
    print(f"Sections ({len(res3['sections'])}):")
    for s in res3['sections']:
        print(f"  [S{s['handle']}] {s['title']} (turns {s['turns']})")
    print("Header:")
    print(json.dumps(res3['header'], ensure_ascii=False, indent=2))
    print(f"Source turns to fetch: {res3['source_turns_to_fetch']}")

    # Save all results to JSON
    output_path = "contents_generation/test_codes/summary_eval_results.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({
            "test_case_1": res1,
            "test_case_2": res2,
            "test_case_3": res3,
        }, f, ensure_ascii=False, indent=2)
    print(f"\nAll results saved to {output_path}")


if __name__ == "__main__":
    asyncio.run(run_all_tests())
