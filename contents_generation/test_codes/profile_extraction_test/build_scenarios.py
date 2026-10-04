"""
自分像プロフィール(ロードマップ「9. 自分像プロフィール」, docs/chatbot_context_and_retrieval_roadmap.md)の
評価用に、架空のユーザーの「時系列」を手で書いた台本から scenarios/*.json として書き出すスクリプト。

1人のユーザー = 1本のシナリオ。中身は日付順のイベントの列:
  - thread:       1つのチャットスレッド。観察役がこの単位で読む
  - consolidate:  まとめ役を動かす地点。ここで2層・覚え書き・仮説・確認待ちの状態を確かめる
  - user_action:  本人の操作(違う / 残したくない / 直す / 確認トレイ)を差し込む
  - cover:        表紙(1層)の書き直しを動かす地点

期待値はどれも「意味で照合する」ための自然文で書く(文字列一致ではない)。照合は評価時に判定役(LLM)が行い、
人がレポートで確かめる。まとめ役を動かす件数Nの判断は評価の対象外なので、consolidateの位置は台本で固定する。

実行: python build_scenarios.py
"""

import json
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "scenarios"


def rounds_from_pairs(pairs: list[tuple[str, str]]) -> list[dict]:
    return [{"round": i, "user": u, "assistant": a} for i, (u, a) in enumerate(pairs, start=1)]


# =====================================================================
# P1. 精度を詰める仕組みに惹かれる (ja)
#     F1のピットストップ / スターシップのブースターキャッチ / 機械式時計
#     → 話題(F1・宇宙・時計)ではなく「極限まで精度を詰める仕組み」で束ねられるか
# =====================================================================

P1_T1 = [
    ("昨日の夜、F1の日本GPの録画やっと見た!",
     "お、鈴鹿だね!どうだった?レース展開とか、気になったドライバーいた?"),
    ("いや、正直ドライバーとか順位はあんまり興味なくて笑 ピットストップがやばかった。2秒ちょっとでタイヤ4本全部替えてて、20人くらいが一斉に動いてるのに誰も邪魔し合ってないの",
     "ピットストップは本当に別競技だよね。トップチームだと2秒を切ることもあって、ホイールナット担当・ジャッキ担当・外す人・付ける人…と役割が完全に決まってる。一人が0.1秒遅れるだけで順位が変わるから、何百回も練習してるらしいよ。"),
    ("そうそれ!0.1秒単位で全員の動きが詰められてるのがたまらない。どうやって練習してるのかめっちゃ気になる",
     "チームによっては動きを全部カメラで撮って、誰がどこで何秒ロスしたかをデータで分析してるんだって。工具の形やナットの仕組みまで、2秒を削るために専用に作り込まれてる。"),
    ("道具まで専用なのやばい。ちょっとYouTubeで練習風景探してみる",
     "ぜひ!「F1 pit stop practice」で探すと、ガレージでの練習映像がけっこう出てくるよ。"),
]

P1_T2 = [
    ("ねえスターシップのブースター、発射台の「箸」でキャッチしたの見た?やばくない?",
     "見た!あの巨大なブースターが戻ってきて、発射塔のアームで空中キャッチされるやつだよね。初めて成功したときは管制室も大騒ぎだった。どのへんが一番やばいと思った?"),
    ("いや全部やばい笑 あ、てか今日の夜ごはん何にしよう、冷蔵庫に卵と玉ねぎしかない",
     "卵と玉ねぎなら「玉子丼」がすぐできるよ。玉ねぎをめんつゆで煮て、溶き卵でとじてご飯にのせるだけ。"),
    ("それにする!",
     "いいね、玉ねぎは薄めに切ると早く火が通るよ。"),
]

P1_T3 = [
    ("制御工学の小テストの復習したい。PID制御のIって何してるんだっけ",
     "Iは積分(Integral)。目標とのズレを時間で足し合わせていって、小さいズレがずっと残り続けるのを消す役。Pだけだと最後に少しズレが残る(定常偏差)ことがあって、それをIで潰すイメージ。"),
    ("Dは?",
     "Dは微分(Derivative)。ズレが変化する速さを見て、行き過ぎ(オーバーシュート)を先回りしてブレーキをかける役だよ。"),
    ("なるほど。これってロケットが着陸するときとかにも使われてる?",
     "考え方の土台は同じだね。実際のロケットはもっと複雑な制御を組み合わせてるけど、「ズレを測って、エンジンの向きや推力で打ち消す」のは同じ発想。そういえば前にブースターキャッチの話をしてたけど、あれはどこに一番グッときたの?"),
    ("そう、それ!何十メートルもあるものを、誤差数センチで塔の決まった位置に止めるのがやばい。宇宙とか火星とかは正直どうでもよくて、あの精度がたまらないんだよね",
     "分かる、あのスケールで数センチは異常だよね。今日のPIDも、まさにその「ズレを詰める」ための一番基本の道具だよ。小テストでは、IとDの役割の違いがよく出るから押さえておこう。"),
    ("ありがと、ちょっと制御おもしろくなってきた",
     "それはよかった!次の小テストもその調子で。"),
]

P1_T4 = [
    ("今日友達の家で、機械式時計の裏蓋開けて中見せてもらった",
     "おお、裏がスケルトンになってるやつ?それとも本当に開けたの?"),
    ("本当に開けてた笑 歯車とかバネが髪の毛より細くて、それで1日の誤差が数秒なんだって。電池もないのに",
     "機械式は、ゼンマイの力を「テンプ」という部品が一定のリズムで少しずつ逃がすことで時間を刻んでるんだ。温度や向きでズレるのを、部品の素材や形の工夫で抑えてる。1日数秒ならかなり高精度な部類だよ。"),
    ("小さい部品だけでそこまで詰めてるのがすごい。自分では絶対買えない値段だったけど笑",
     "高級なものは職人が一つずつ調整してるから、値段もそのぶんね。でも仕組みは図解の本や分解動画でもかなり楽しめるよ。"),
]

P1_T5 = [
    ("週末、家族で野球見に行ってきた",
     "いいね!どこの試合?"),
    ("東京ドームの巨人戦。まあ普通に楽しかったよ、ビールの売り子さんの重そうなタンクすごいなって思った笑",
     "あれ15キロくらいあるらしいよ。階段を何往復もするから、本当に体力勝負だよね。"),
    ("15キロはやばい。来週からまたバイト頑張ろ",
     "お疲れさま、バイトも無理しすぎないようにね。"),
]

P1_T6 = [
    ("キャリアの授業で、将来やりたいこと書けって言われて困ってる",
     "書きにくいよね。今の時点で決まってなくても大丈夫だと思う。「こういう時は時間を忘れる」ってことある?"),
    ("うーん、仕事として何がしたいかはまだ全然わからない。でも、なんか一個のものを極限まで詰めていく仕事がいい気がする。0.1秒とか1ミリとかを削るみたいな",
     "それはかなりはっきりした軸だと思う。ピットクルーのエンジニアリング、ロケットの制御、精密機器の設計、ソフトウェアの性能チューニングなんかも「極限まで詰める」仕事だね。分野より先に「詰め方」が好き、と書くのも立派な答えだよ。"),
    ("あ、それそのまま書いてみる",
     "いいと思う!具体例として、最近ワクワクしたものを一つ添えると伝わりやすいよ。"),
]

P1 = {
    "id": "p1_precision_ja",
    "language": "ja",
    "description": "F1のピットストップ・ロケットのブースターキャッチ・機械式時計に、それぞれ別の日・別の文脈で惹かれる。"
                   "どれも話題としては別物だが、惹かれた点は「極限まで精度を詰める仕組み」で共通している。",
    "tests": [
        "話題(F1・宇宙・時計)ではなく、惹かれた点で束ねて傾向を作れるか",
        "本人の但し書き(ドライバーには興味がない、宇宙はどうでもいい)を観察に残し、反する項目を作らないか",
        "惹かれた点が語られなかった会話(T2)で、推測で埋めずに「不明」とし、仮説を作れるか",
        "後の会話(T3)で仮説が確かめられたことを、観察役が拾えるか",
        "1回きりの話題(野球、夕飯の相談)から項目を作らないか",
        "空欄の表紙(1層)をAIが埋めるとき、話題の羅列でなく傾向で書けるか",
    ],
    "initial_profile": {
        "bio": {"text": None, "origin": None},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": None, "origin": None},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-05", "context": "casual",
            "rounds": rounds_from_pairs(P1_T1),
            "expect_observations": {
                "must": [
                    "惹かれた点: 多人数の動きが0.1秒単位で詰められ、道具まで最適化されたピットストップの仕組み(本人の言葉, stated)",
                    "但し書き: ドライバーや順位にはあまり興味がない",
                    "initiative=user(自分から話し始めた)",
                ],
                "must_not": [
                    "「F1が好き」「モータースポーツに興味がある」のような一般化した書き方",
                ],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-12", "context": "casual",
            "rounds": rounds_from_pairs(P1_T2),
            "expect_observations": {
                "must": [
                    "話題: スターシップのブースターキャッチ。惹かれた点は不明(hook=NULL)。AIが聞いたが本人は答えなかった",
                ],
                "must_not": [
                    "惹かれた点を推測で埋める(例: 宇宙開発へのロマン)",
                    "「宇宙が好き」「ロケットに興味」",
                    "夕飯の相談から「料理が好き」",
                ],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t2",
            "expect": {
                "items_must": [],
                "items_must_not": [
                    "F1・モータースポーツへの興味",
                    "宇宙・ロケットへの興味",
                    "精度を詰める仕組みへの傾向(まだ根拠が足りない: 惹かれた点が分かっている観察は1件だけ)",
                    "料理",
                ],
                "hypotheses_must": [
                    "精密な制御や最適化に惹かれているのでは。次に機械・乗り物・宇宙の話題が出たら、どこに惹かれたかを自然に聞く",
                ],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-19", "context": "lecture_review",
            "rounds": rounds_from_pairs(P1_T3),
            "expect_observations": {
                "must": [
                    "惹かれた点: 巨大なものを誤差数センチで決まった位置に止める精度(本人の言葉, stated)",
                    "但し書き: 宇宙や火星は正直どうでもいい",
                    "授業の復習の中で、範囲から自分で踏み出した質問(ロケットの着陸)",
                    "仮説(精密な制御に惹かれる)が本人の言葉で確かめられた",
                ],
                "must_not": [
                    "PIDの復習そのもの(小テスト対策)を興味の根拠にする",
                    "「宇宙に興味」",
                ],
            },
        },
        {
            "type": "thread", "id": "t4", "date": "2026-09-24", "context": "casual",
            "rounds": rounds_from_pairs(P1_T4),
            "expect_observations": {
                "must": [
                    "惹かれた点: 髪の毛より細い部品の工夫だけで、1日数秒まで精度を詰めている仕組み(stated)",
                ],
                "must_not": [
                    "「機械式時計が好き」「時計を集めている」",
                ],
            },
        },
        {
            "type": "consolidate", "id": "c2", "after": "t4",
            "expect": {
                "items_must": [
                    {
                        "kind": "trait",
                        "content": "極限まで精度や効率を詰めていく仕組み・技術にワクワクする",
                        "evidence_threads_at_least": ["t1", "t3", "t4"],
                    },
                ],
                "items_must_not": [
                    "F1・モータースポーツへの興味",
                    "宇宙・ロケットへの興味",
                    "機械式時計への興味",
                    "料理",
                ],
                "hypotheses_status": [
                    {"content": "精密な制御や最適化に惹かれる", "status": "confirmed"},
                ],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-09-30", "context": "casual",
            "rounds": rounds_from_pairs(P1_T5),
            "expect_observations": {
                "must": [],
                "must_not": [
                    "「野球が好き」",
                    "売り子のタンクの話から、惹かれた点を大きく一般化する(反応は軽い一言だけ)",
                ],
            },
        },
        {
            "type": "thread", "id": "t6", "date": "2026-10-02", "context": "consult",
            "rounds": rounds_from_pairs(P1_T6),
            "expect_observations": {
                "must": [
                    "将来: 分野はまだ分からないが、一つのものを極限まで詰めていく仕事がしたい(stated)",
                ],
                "must_not": [
                    "AIが挙げた職業の例(ピットクルー、ロケット制御など)を本人の希望として書く",
                ],
            },
        },
        {
            "type": "consolidate", "id": "c3", "after": "t6",
            "expect": {
                "items_must": [
                    {
                        "kind": "trait",
                        "content": "極限まで精度や効率を詰めていく仕組み・技術にワクワクする",
                        "evidence_threads_at_least": ["t1", "t3", "t4"],
                    },
                    {
                        "kind": "trait",
                        "content": "将来は、分野は未定だが何かを極限まで詰めていく仕事がしたい",
                        "evidence_threads_at_least": ["t6"],
                    },
                ],
                "items_must_not": [
                    "野球への興味",
                    "AIが挙げた具体的な職業を本人の志望とする項目",
                ],
                "items_allowed": [
                    "制御工学が少しおもしろくなってきた(本人の明言だが軽い。あってもなくてもよい)",
                    "アルバイトをしている(事実。あってもなくてもよい)",
                ],
            },
        },
        {
            "type": "cover", "id": "cov1", "after": "c3",
            "expect": {
                "interests": {
                    "action": "auto_fill",
                    "must": ["極限まで精度を詰める仕組みに惹かれることが中心になっている"],
                    "must_not": ["F1ファン・宇宙好きのような話題の羅列"],
                },
                "future_goals": {
                    "action": "auto_fill",
                    "must": ["分野は未定でも、極限まで詰める仕事という軸"],
                    "must_not": ["AIが挙げた職業を本人の志望として書く"],
                },
                "bio": {
                    "action": "auto_fill_or_leave_empty",
                    "note": "自己紹介に使える材料(学生、制御工学を履修、バイト)は少ない。無理に盛らなければ空のままでもよい",
                },
            },
        },
    ],
}


# =====================================================================
# P2. 対立の間に入ってつなぐ役回りにやりがい (ja)
#     坂本龍馬(歴史は苦手) / 文化祭の揉め事の仲介 / サッカーのボランチ
#     + 文化祭をプロジェクトの「記録」として1件ずつ追記していけるか
# =====================================================================

P2_T1 = [
    ("日本史の小テスト明日なんだけど、薩長同盟ってなんだっけ",
     "1866年に、それまで対立していた薩摩藩と長州藩が結んだ同盟だよ。幕府を倒す流れの大きな転換点になった。間を取り持ったのが、土佐出身の坂本龍馬(と中岡慎太郎)として有名だね。"),
    ("1866年ね…年号ほんと覚えられない。歴史は正直ずっと苦手",
     "年号は語呂で覚える人が多いよ。流れで覚えるなら「長州が幕府に攻められて孤立 → 薩摩も幕府と距離を置き始める → 龍馬が仲介」の順番を押さえると点につながりやすい。"),
    ("でも龍馬のとこだけはなんか好きなんだよね。ちょっと前まで本気で殺し合ってた2つの藩の間に入って、話をまとめちゃうの。どっちの味方でもないのに",
     "確かに、どちらにも属さない立場だからこそ間に入れたんだよね。龍馬は亀山社中(のちの海援隊)で、長州が手に入れられない武器を薩摩名義で買い、代わりに長州から薩摩へ米を回す、というお互いに得がある取引も作ってる。"),
    ("お互いに得がある形を作るの、うまいな。それテストに出る?",
     "「亀山社中」と「薩摩名義での武器購入」はよく問われるよ。年号と合わせて押さえておこう。"),
]

P2_T2 = [
    ("文化祭の実行委員やってるんだけど、クラスが割れててしんどい",
     "それはしんどいね。どう割れてるの?"),
    ("演劇やりたい派と模擬店やりたい派で真っ二つ。両方とも譲らなくて、LINEのグループの空気が最悪",
     "両方の言い分を聞くと、何を一番大事にしてるかが見えてくることが多いよ。演劇派は「みんなで一つのものを作りたい」、模擬店派は「準備を軽くして当日を楽しみたい」とか。それぞれの理由は聞けてる?"),
    ("まだちゃんとは聞けてない。でもこういうの、しんどいけど嫌いじゃないんだよね。中学のときも部活で揉めたとき間に入ってて、最後にまとまった瞬間がめちゃくちゃ嬉しかった",
     "それは立派な強みだと思う。まずは各派の中心の人と1対1で話して、「何が譲れないか」と「何なら譲れるか」を聞いてみるのはどう?全体のLINEで話すより本音が出やすい。"),
    ("それやってみる。とりあえず演劇派のリーダーと明日話す",
     "いいね。相手の話を最後まで遮らずに聞くだけでも、かなり空気が変わるよ。"),
]

P2_T3 = [
    ("今日サッカーの試合だった!勝った",
     "おめでとう!ポジションどこなの?"),
    ("ボランチ。点取るより、攻撃と守備の間でボール回してつなぐのが好きなんだよね。FWの人たちが点取って目立つのは全然いい",
     "ボランチは「チームの心臓」って言われるくらい、つなぎ役が大事なポジションだよね。守備から攻撃に切り替える最初のパスを出すのもボランチが多い。"),
    ("そうそう、自分のパスから点が入ると、自分で決めるよりなんか嬉しい",
     "分かる気がする。自分が起点になって周りが活きる、っていう嬉しさだね。"),
]

P2_T4 = [
    ("文化祭の件、進んだ!両方のリーダーと話して、昨日、両派の代表3人ずつ集めて話し合いの場を作った",
     "すごい、一気に進んだね。どうだった?"),
    ("最初は空気悪かったけど、演劇派は「全員で何か作りたい」、模擬店派は「準備期間にバイトがあって練習に出られない人がいる」っていうのが本音だった",
     "本音が出たのが大きいね。その2つなら両立の道がありそう。例えば、短い劇を有志でやりつつ、模擬店は当日シフト制にする、とか。"),
    ("それに近い案が出てて、来週クラス全体に出してみる",
     "いいね。決める前に、どちらの派の人にも「自分の意見が入ってる」と感じてもらえる形にすると通りやすいよ。"),
]

P2_T5 = [
    ("来週の日本史の小テスト、範囲が江戸後期からだった",
     "江戸後期だと、寛政の改革や天保の改革、それに開国の流れあたりかな。そういえば、歴史小説とかは読んだりする?龍馬の話が好きなら『竜馬がゆく』とか合うかも。"),
    ("うーん、たまに?あんまり読まないかも",
     "そっか、無理に読まなくても大丈夫。改革は「誰が・何のために・結果どうなったか」の3点で表にまとめると覚えやすいよ。"),
    ("表にしてみる",
     "うん、作ったら確認するから見せてね。"),
]

P2_T6 = [
    ("文化祭終わった〜!!",
     "お疲れさま!!結局どうなったの?"),
    ("劇と模擬店、両方やる形にまとまった。劇は有志10人で15分、模擬店は全員シフト制。最後に演劇派のリーダーと模擬店派のリーダーが一緒に写真撮ってて、ちょっと泣きそうになった",
     "それは泣きそうになるね…LINEの空気が最悪だったところから、両方のリーダーが並んで写真を撮るところまで持っていったのはすごいことだよ。"),
    ("正直しんどかったけど、やってよかった。こういう役回り、たぶん自分に向いてる気がする",
     "向いてると思う。対立した人たちの本音を聞いて、両方が得をする形に組み直すのは、なかなかできることじゃないよ。"),
]

P2_TRAIT = "対立や分断している人たちの間に入り、両方をつなぐ・まとめることにやりがいを感じる"

P2 = {
    "id": "p2_bridge_ja",
    "language": "ja",
    "description": "日本史の試験対策で坂本龍馬の仲介に惹かれ(歴史自体は苦手)、文化祭ではクラスの対立の間に入り、"
                   "サッカーではボランチとしてつなぐ役が好き。文化祭はプロジェクトとして進捗が続く。",
    "tests": [
        "義務の勉強(試験対策)の中にある、本人の惹かれた点だけを拾えるか。「歴史に興味」を作らないか",
        "龍馬・文化祭・ボランチを「間に入ってつなぐ」で束ねられるか",
        "文化祭の進捗を記録として1件ずつ追記し、まとめてしまわないか",
        "AIが振った話題(歴史小説)への気のない返事を、興味として扱わないか",
        "根拠が増えたとき、傾向を新しく作らず同じ項目を書き直せるか",
    ],
    "initial_profile": {
        "bio": {"text": None, "origin": None},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": None, "origin": None},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-08", "context": "exam_prep",
            "rounds": rounds_from_pairs(P2_T1),
            "expect_observations": {
                "must": [
                    "惹かれた点: 対立していた二者の間に、どちらの味方でもない立場で入り、お互いに得がある形でまとめること(stated:「なんか好き」)",
                    "但し書き: 歴史はずっと苦手、年号が覚えられない",
                    "文脈は試験対策(義務)",
                ],
                "must_not": [
                    "「歴史に興味」「幕末が好き」「坂本龍馬のファン」",
                ],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-15", "context": "consult",
            "rounds": rounds_from_pairs(P2_T2),
            "expect_observations": {
                "must": [
                    "惹かれた点: 揉めている人たちの間に入り、まとまった瞬間が嬉しい(stated。中学の部活でも同じ経験)",
                    "記録: 文化祭の実行委員。クラスが演劇派と模擬店派に割れている(9/15時点)",
                ],
                "must_not": [
                    "AIの提案(1対1で話す)を本人の考えとして書く",
                ],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-21", "context": "casual",
            "rounds": rounds_from_pairs(P2_T3),
            "expect_observations": {
                "must": [
                    "惹かれた点: 攻撃と守備の間でつなぐ役。自分が起点になって周りが活きるのが、自分で決めるより嬉しい(stated)",
                    "事実: サッカーをしていて、ポジションはボランチ",
                ],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t3",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P2_TRAIT, "evidence_threads_at_least": ["t1", "t2", "t3"]},
                    {"kind": "record", "category_hint": "プロジェクト / 文化祭",
                     "content": "文化祭の実行委員。クラスが演劇派と模擬店派に割れている",
                     "occurred_at": "2026-09-15", "evidence_threads_at_least": ["t2"]},
                ],
                "items_must_not": [
                    "歴史・幕末への興味",
                    "坂本龍馬のファン",
                ],
                "items_allowed": [
                    "サッカーをしている(ボランチ)",
                    "目立つより、周りを活かすことに喜びを感じる(上の傾向とまとめてもよい)",
                ],
            },
        },
        {
            "type": "thread", "id": "t4", "date": "2026-10-01", "context": "consult",
            "rounds": rounds_from_pairs(P2_T4),
            "expect_observations": {
                "must": [
                    "記録: 両派のリーダーと話し、代表3人ずつを集めて話し合いの場を作った。本音(全員で作りたい / バイトで練習に出られない人がいる)が出た(9/30)",
                ],
                "must_not": [
                    "AIが出した案(有志の劇 + シフト制)を、本人たちが決めたこととして書く",
                ],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-10-08", "context": "exam_prep",
            "rounds": rounds_from_pairs(P2_T5),
            "expect_observations": {
                "must": [
                    "AIが振った話題(歴史小説)に対して「あまり読まないかも」。弱い信号",
                ],
                "must_not": [
                    "「歴史小説が好き」「読書が趣味」",
                ],
            },
        },
        {
            "type": "thread", "id": "t6", "date": "2026-10-25", "context": "casual",
            "rounds": rounds_from_pairs(P2_T6),
            "expect_observations": {
                "must": [
                    "記録: 文化祭が終わった。劇(有志10人・15分)と模擬店(全員シフト制)の両方をやる形にまとまった。両リーダーが一緒に写真を撮っていて泣きそうになった",
                    "本人の言葉: こういう役回りが自分に向いている気がする(stated)",
                ],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c2", "after": "t6",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P2_TRAIT,
                     "evidence_threads_at_least": ["t1", "t2", "t3", "t6"],
                     "note": "c1の項目を書き直す・強める(新しい項目を別に作らない)。書き直し前の文が履歴に残る"},
                    {"kind": "record", "category_hint": "プロジェクト / 文化祭",
                     "content": "文化祭の実行委員。クラスが演劇派と模擬店派に割れている",
                     "occurred_at": "2026-09-15", "evidence_threads_at_least": ["t2"]},
                    {"kind": "record", "category_hint": "プロジェクト / 文化祭",
                     "content": "両派の代表を集めて話し合いの場を作り、本音を引き出した",
                     "occurred_at": "2026-09-30", "evidence_threads_at_least": ["t4"]},
                    {"kind": "record", "category_hint": "プロジェクト / 文化祭",
                     "content": "劇と模擬店の両方をやる形にまとまり、文化祭を終えた",
                     "occurred_at": "2026-10-25", "evidence_threads_at_least": ["t6"]},
                ],
                "items_must_not": [
                    "歴史・幕末への興味",
                    "歴史小説・読書が好き",
                    "文化祭の3件の記録を1つの文にまとめたもの",
                    "c1の傾向と同じ意味の、2つ目の傾向",
                ],
                "items_allowed": [
                    "サッカーをしている(ボランチ)",
                    "目立つより、周りを活かすことに喜びを感じる",
                ],
            },
        },
    ],
}


# =====================================================================
# P3. 話題で一般化してよい場合 + 料理・プロジェクトの記録 (en)
#     日本語学習 / 日本史の選択科目で食文化 / アニメと京都 → 「日本の文化に興味」は作ってよい
# =====================================================================

P3_T1 = [
    ("I made shakshuka this morning. Eggs poached in spicy tomato sauce, super easy.",
     "Nice! Shakshuka is a great weekend dish. Did you add anything to the sauce, like cumin or feta?"),
    ("Cumin and a bit of feta, yeah. Honestly I cook every Sunday no matter what. It's my reset for the week, chopping vegetables just clears my head.",
     "That's a great ritual. A lot of people find the repetitive parts of cooking, like chopping, almost meditative. Do you plan what to cook during the week, or decide on Sunday?"),
    ("Usually decide that morning based on whatever's in the fridge.",
     "Improvising from the fridge is a real skill. Shakshuka is perfect for that, since almost any vegetable works in the sauce."),
]

P3_T2 = [
    ("Made ramen from scratch yesterday. Took me 7 hours for the broth lol",
     "Seven hours! Was it a pork bone (tonkotsu) broth?"),
    ("Shoyu actually, with chicken. The tare was the hardest part. Also I've been doing Duolingo Japanese for like 3 months, so I could read the label on the soy sauce bottle. Kinda proud of that.",
     "That's a fun moment, when a skill you're practicing suddenly shows up in real life. Reading kanji on a label after three months is solid progress."),
    ("Only some of them haha. Nobody asked me to learn it, I just wanted to.",
     "Self-motivated learning tends to stick. If you want, I can share a few common cooking-related kanji you'll see on Japanese packaging."),
]

P3_T3 = [
    ("For my Japanese history elective, can you explain the sakoku policy again?",
     "Sakoku refers to the Edo shogunate's policies from the 1630s that strictly limited foreign contact. Trade continued only through specific channels, like the Dutch and Chinese at Nagasaki, plus Korea via Tsushima."),
    ("Got it. This isn't on the syllabus, but how did that affect what people ate in Edo? Did sushi come from that era?",
     "Good question! Edo street food boomed: nigiri sushi as we know it appeared in the early 1800s as fast food from stalls, along with tempura and soba. The city's huge population of busy workers made quick stall food popular."),
    ("Sushi as fast food is so funny. I picked this elective because I wanted to understand the culture behind the food and the language I'm into.",
     "That's a great reason to choose a class. Food history is a really good lens on Edo society."),
]

P3_T4 = [
    ("Any anime recommendations? I just finished Frieren and I'm sad it's over.",
     "Frieren is beautiful. If you liked its quiet, reflective mood, you might enjoy Mushishi or Natsume's Book of Friends. Both have that slow, gentle pacing."),
    ("Adding both. Also I really want to go to Kyoto someday, the temple scenes in anime always get me.",
     "Kyoto is a great goal. Late November is stunning around the temples, though crowded. Early spring is quieter."),
    ("Saving up for it! Maybe next year.",
     "That gives you a nice target, and your Japanese will be even better by then."),
]

P3_T5 = [
    ("Gyoza night! Folded like 60 of them.",
     "Sixty is a serious batch! Did you do the pleated fold?"),
    ("Yep, got way better by the end. Also, random, but I have three side projects going and I'm not sure which to focus on: a small robot arm, a budgeting app for me and my roommates, and a zine about food spots near campus.",
     "That's a fun mix: hardware, software, and writing. Which one do you find yourself thinking about when you're not working on it?"),
    ("Hmm, probably the robot arm honestly.",
     "That's often a good sign of where your energy wants to go. You could keep the others light and give the arm most of your time."),
]

P3_T6 = [
    ("Robot arm update: I picked MG996R servos for the base and shoulder, SG90 for the gripper.",
     "Sensible choices. The MG996R has enough torque for the base and shoulder at that scale, and SG90s are light for the gripper. Watch your power supply, though; several MG996Rs on USB power won't be enough."),
    ("Yeah I learned that the hard way, the Arduino kept resetting lol. Got a separate 6V supply now.",
     "Classic! A separate supply with a common ground is exactly the right fix."),
]

P3_CULTURE = "Interested in Japanese culture: learning the language, its history, food, and anime"
P3_COOKING = "Cooks every Sunday as a weekly reset; chopping vegetables clears their head"

P3 = {
    "id": "p3_culture_en",
    "language": "en",
    "description": "Cooks every Sunday and keeps making dishes. Studies Japanese on their own, chose a Japanese history "
                   "elective to understand the culture, watches anime and wants to visit Kyoto. Has three side projects.",
    "tests": [
        "When one topic shows up repeatedly across different contexts (self-study, elective class, anime, travel), "
        "the topic-level generalization IS allowed. Guards against being so cautious that nothing is promoted",
        "A clear self-statement (\"I cook every Sunday... it's my reset\") is promoted after one mention",
        "Dishes are appended as separate records, not merged into one sentence",
        "\"Yesterday\" in a message dated 9/13 is recorded as 9/12",
        "Three projects mentioned once are grouped as records under one projects category; the robot arm's progress is appended",
        "Output stays in English",
    ],
    "initial_profile": {
        "bio": {"text": None, "origin": None},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": None, "origin": None},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-06", "context": "casual",
            "rounds": rounds_from_pairs(P3_T1),
            "expect_observations": {
                "must": [
                    "Stated: cooks every Sunday no matter what; it's a weekly reset, chopping clears their head",
                    "Record: made shakshuka with cumin and feta (2026-09-06)",
                ],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-13", "context": "casual",
            "rounds": rounds_from_pairs(P3_T2),
            "expect_observations": {
                "must": [
                    "Record: made shoyu ramen with chicken broth from scratch, 7 hours (occurred 2026-09-12, \"yesterday\")",
                    "Stated: has been learning Japanese on Duolingo for ~3 months on their own initiative; proud of reading a label",
                ],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-20", "context": "lecture_review",
            "rounds": rounds_from_pairs(P3_T3),
            "expect_observations": {
                "must": [
                    "Asked an off-syllabus question about Edo food culture on their own",
                    "Stated: chose the Japanese history elective to understand the culture behind the food and language they're into",
                ],
                "must_not": [
                    "Treating the sakoku review itself as evidence of interest",
                ],
            },
        },
        {
            "type": "thread", "id": "t4", "date": "2026-09-27", "context": "casual",
            "rounds": rounds_from_pairs(P3_T4),
            "expect_observations": {
                "must": [
                    "Finished Frieren and liked it; temple scenes in anime \"always get\" them",
                    "Wants to visit Kyoto; saving up, maybe next year",
                ],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t4",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P3_CULTURE, "evidence_threads_at_least": ["t2", "t3", "t4"]},
                    {"kind": "trait", "content": P3_COOKING, "evidence_threads_at_least": ["t1"]},
                    {"kind": "record", "category_hint": "Dishes cooked", "content": "Shakshuka with cumin and feta",
                     "occurred_at": "2026-09-06", "evidence_threads_at_least": ["t1"]},
                    {"kind": "record", "category_hint": "Dishes cooked", "content": "Shoyu ramen from scratch (7-hour chicken broth)",
                     "occurred_at": "2026-09-12", "evidence_threads_at_least": ["t2"]},
                ],
                "items_must_not": [
                    "A single item that merges the dishes into one sentence",
                    "Any item written in Japanese",
                ],
                "items_allowed": [
                    "Wants to visit Kyoto next year (goal)",
                    "Enjoys quiet, reflective anime",
                ],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-10-04", "context": "casual",
            "rounds": rounds_from_pairs(P3_T5),
            "expect_observations": {
                "must": [
                    "Record: made about 60 gyoza with pleated folds (2026-10-04)",
                    "Three side projects: a small robot arm, a budgeting app for roommates, a zine about food spots near campus",
                    "The robot arm is the one they think about most",
                ],
                "must_not": [
                    "The AI's suggestion (focus on the arm) recorded as the user's decision",
                ],
            },
        },
        {
            "type": "thread", "id": "t6", "date": "2026-10-11", "context": "casual",
            "rounds": rounds_from_pairs(P3_T6),
            "expect_observations": {
                "must": [
                    "Record: robot arm uses MG996R servos (base, shoulder) and SG90 (gripper); Arduino kept resetting, switched to a separate 6V supply",
                ],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c2", "after": "t6",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P3_CULTURE, "evidence_threads_at_least": ["t2", "t3", "t4"]},
                    {"kind": "trait", "content": P3_COOKING, "evidence_threads_at_least": ["t1"]},
                    {"kind": "record", "category_hint": "Dishes cooked", "content": "Shakshuka with cumin and feta",
                     "occurred_at": "2026-09-06", "evidence_threads_at_least": ["t1"]},
                    {"kind": "record", "category_hint": "Dishes cooked", "content": "Shoyu ramen from scratch (7-hour chicken broth)",
                     "occurred_at": "2026-09-12", "evidence_threads_at_least": ["t2"]},
                    {"kind": "record", "category_hint": "Dishes cooked", "content": "About 60 pleated gyoza",
                     "occurred_at": "2026-10-04", "evidence_threads_at_least": ["t5"]},
                    {"kind": "record", "category_hint": "Projects", "content": "Robot arm side project (the one they think about most)",
                     "occurred_at": "2026-10-04", "evidence_threads_at_least": ["t5"]},
                    {"kind": "record", "category_hint": "Projects", "content": "Budgeting app for them and their roommates",
                     "occurred_at": "2026-10-04", "evidence_threads_at_least": ["t5"]},
                    {"kind": "record", "category_hint": "Projects", "content": "Zine about food spots near campus",
                     "occurred_at": "2026-10-04", "evidence_threads_at_least": ["t5"]},
                    {"kind": "record", "category_hint": "Projects", "content": "Robot arm: chose MG996R/SG90 servos; fixed Arduino resets with a separate 6V supply",
                     "occurred_at": "2026-10-11", "evidence_threads_at_least": ["t6"]},
                ],
                "items_must_not": [
                    "A single item that merges the dishes into one sentence",
                    "A trait like \"interested in robotics / hardware\" (only one project over two threads; that is a record, not yet a trait)",
                    "Any item written in Japanese",
                ],
                "items_allowed": [
                    "Wants to visit Kyoto next year (goal)",
                    "Enjoys quiet, reflective anime",
                    "The robot arm as its own child category under Projects",
                ],
            },
        },
    ],
}


# =====================================================================
# P4. 罠ばかり (ja)
#     試験対策 / 一時的な疲れ / センシティブ(明言・推測) / 健康の推測 / AIが振った話題
# =====================================================================

P4_T1 = [
    ("明日量子力学のテストなんだけど、シュレディンガー方程式の時間に依存しない版って何だっけ",
     "Ĥψ = Eψ の形だね。ハミルトニアンを波動関数に作用させると、エネルギー E 倍の同じ波動関数が返ってくる、という固有値方程式。"),
    ("井戸型ポテンシャルのエネルギーの式は?",
     "無限井戸(幅 L)なら E_n = n²π²ħ²/(2mL²)。n は 1, 2, 3, … でゼロは取れない。"),
    ("なんでn=0はだめなの",
     "n=0 だと波動関数がいたるところゼロになって、粒子が存在しないことになるからだよ。だから最低エネルギー(n=1)もゼロにならない。"),
    ("ok、あと規格化ってどうやるんだっけ。もう時間ない",
     "|ψ|² を全範囲で積分して 1 になるように係数を決める。無限井戸なら係数は √(2/L) になるよ。テスト頑張って!"),
]

P4_T2 = [
    ("もう無理。試験3つ連続で何もしたくない",
     "3つ連続はきついね、本当にお疲れさま。今日はもう休む日にしていいと思う。"),
    ("寝る。来週までずっとこんな感じ",
     "来週まで続くなら、今夜はしっかり寝て体力を戻すのが一番の試験対策だよ。"),
]

P4_T3 = [
    ("来週お彼岸で実家に帰る",
     "いいね、ゆっくりできそう?"),
    ("いや、実家お寺だから手伝いでめっちゃ忙しい笑 自分も一応仏教徒だし、お盆とお彼岸は毎年手伝ってる",
     "それは大事な役目だね。お彼岸は法要の準備やお参りの方の対応で大変そう。"),
    ("そう、でも檀家さんのおばあちゃんたちと話すのは結構好き",
     "世代の違う人とゆっくり話せるのは貴重な時間だね。"),
]

P4_T4 = [
    ("友達に誘われて、教会のゴスペルコンサート行ってきた",
     "おお、どうだった?"),
    ("最後に観客もみんなで一緒に歌うやつがあって、知らない人たちと声合わせるの楽しかった。一体感がすごい",
     "ゴスペルの合唱は、会場全体が一つになる感じがあるよね。ハーモニーの中に自分の声が混ざる感覚は独特だと思う。"),
    ("合唱サークルとか入ってみてもいいかもってちょっと思った笑",
     "大学の合唱サークルは初心者歓迎のところも多いから、見学だけでも行ってみたら?"),
]

P4_T5 = [
    ("最近夜眠れない日が続いてて、朝の1限がつらい",
     "それはしんどいね。寝る前にスマホを見る時間が長かったりする?"),
    ("見てる…ベッドでずっとYouTube",
     "画面の光と、次々に流れてくる動画の刺激で寝つきが悪くなりやすいよ。寝る30分前にスマホを充電器に置いて、ベッドに持ち込まないだけでも変わることがある。"),
    ("やってみる",
     "うん。それでも続くようなら、大学の保健センターに相談するのもありだよ。"),
]

P4_T6 = [
    ("線形代数の固有値の求め方教えて",
     "行列 A に対して det(A − λI) = 0 を解くと、その解 λ が固有値になる。2×2 なら λ の2次方程式になるよ。ちなみに数学は好き?"),
    ("まあ嫌いじゃないかな",
     "いいね。じゃあ例として A = [[2,1],[1,2]] でやってみよう。(2−λ)² − 1 = 0 で、λ = 1, 3 になる。"),
    ("なるほど、わかった",
     "固有ベクトルも見ておきたかったら言ってね。"),
]

P4 = {
    "id": "p4_traps_ja",
    "language": "ja",
    "description": "試験対策、一時的な疲れ、実家がお寺で本人も仏教徒(明言)、教会のゴスペルコンサート(推測)、"
                   "眠れない(健康の推測)、AIが振った「数学は好き?」。上げてよいものがほとんどない。",
    "tests": [
        "試験対策の質問の多さを、興味と取り違えないか",
        "一時的な状態を性格にしないか。今の状況として覚え書きにするなら期限をつけ、期限が過ぎたら使わないか",
        "センシティブの明言(仏教徒)は確認待ちにし、表紙に使わないか",
        "センシティブの推測(教会 → キリスト教、眠れない → 健康)から項目を作らないか",
        "AIが振った話題への生返事を興味にしないか",
    ],
    "initial_profile": {
        "bio": {"text": None, "origin": None},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": None, "origin": None},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-09", "context": "exam_prep",
            "rounds": rounds_from_pairs(P4_T1),
            "expect_observations": {
                "must": [],
                "must_not": ["「量子力学に興味」「物理が好き」"],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-10", "context": "casual",
            "rounds": rounds_from_pairs(P4_T2),
            "expect_observations": {
                "must": ["一時的な状態: 試験が続いて疲れている(来週まで)"],
                "must_not": ["「疲れやすい」「無気力」などの性格としての書き方"],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-14", "context": "casual",
            "rounds": rounds_from_pairs(P4_T3),
            "expect_observations": {
                "must": [
                    "sensitive=宗教、本人の明言: 実家がお寺で、本人も仏教徒。お盆とお彼岸は毎年手伝う",
                    "檀家のおばあちゃんたちと話すのは結構好き(stated)",
                ],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t4", "date": "2026-09-27", "context": "casual",
            "rounds": rounds_from_pairs(P4_T4),
            "expect_observations": {
                "must": [
                    "惹かれた点: 知らない人たちとも声を合わせる一体感(stated)",
                ],
                "must_not": [
                    "「キリスト教に興味」「信仰がある」など宗教についての推測",
                ],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-10-03", "context": "consult",
            "rounds": rounds_from_pairs(P4_T5),
            "expect_observations": {
                "must": [],
                "must_not": [
                    "「不眠症」「睡眠障害」など健康状態についての推測",
                ],
            },
        },
        {
            "type": "thread", "id": "t6", "date": "2026-10-07", "context": "lecture_review",
            "rounds": rounds_from_pairs(P4_T6),
            "expect_observations": {
                "must": ["AIが振った「数学は好き?」に「まあ嫌いじゃない」。弱い信号"],
                "must_not": ["「数学が好き」"],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t6",
            "expect": {
                "items_must": [],
                "pending_confirm_must": [
                    "実家がお寺で、本人も仏教徒(本人の明言)",
                ],
                "items_must_not": [
                    "量子力学・物理への興味",
                    "疲れやすい・無気力などの性格",
                    "キリスト教・信仰についての項目",
                    "睡眠・健康についての項目",
                    "数学が好き",
                    "仏教についての項目が active になっている(確認待ちでなければならない)",
                ],
                "items_allowed": [
                    "世代の違う人(檀家のおばあちゃんたち)と話すのが好き",
                    "合唱サークルに少し興味がある",
                ],
                "memos_must_not": [
                    "試験期間で疲れている、が期限切れになっていない(9/10の「来週まで」は、10/07の時点では過ぎている)",
                ],
            },
        },
        {
            "type": "cover", "id": "cov1", "after": "c1",
            "expect": {
                "bio": {"action": "auto_fill_or_leave_empty",
                        "must_not": ["仏教・お寺・宗教", "健康・睡眠", "量子力学"]},
                "interests": {"action": "auto_fill_or_leave_empty",
                              "must_not": ["仏教・お寺・宗教", "キリスト教", "量子力学", "数学"]},
                "future_goals": {"action": "leave_empty",
                                 "note": "将来についての材料がない。作らない"},
            },
        },
    ],
}


# =====================================================================
# P5. 覚え書きとプロフィールの区別 (en)
# =====================================================================

P5_T1 = [
    ("Can you explain what the derivative of x^2 + 3x means?",
     "The derivative tells you how fast a function changes at each point. For f(x) = x² + 3x, the derivative is f'(x) = 2x + 3, so..."),
    ("wait. Honestly whenever numbers and letters get mixed together my head just explodes. It's been like that since middle school.",
     "That's really common, and it's okay. Let's put it in words first: imagine walking along a hill. The derivative is how steep the hill is right where you're standing. On this hill, it's a little steep at the start, and it gets steeper the further right you walk. \"2x + 3\" is just a short way of writing that."),
    ("ok that actually makes sense",
     "Great. Whenever a formula shows up, I'll say what it means in words first."),
]

P5_T2 = [
    ("Quick one, I'm on my phone so keep formulas to a minimum this time: what's the difference between mean and median?",
     "Mean is the average: add everything up and divide by how many there are. Median is the middle value when you line them up. If one value is extreme, like one billionaire in a room, the mean jumps but the median barely moves."),
    ("perfect, thanks",
     "Anytime!"),
]

P5_T3 = [
    ("What's a hash table?",
     "Picture a coat check at a theater: you hand over your coat, get a numbered ticket, and later the number takes the attendant straight to your hook, no searching needed. A hash table does the same: it turns a key into a slot number so it can jump straight to the value."),
    ("Love that. I always get things way faster when you start with an example like that.",
     "Noted, I'll lead with an example."),
    ("So what happens if two coats get the same number?",
     "That's called a collision. Common fixes: hang both coats on the same hook in a little list (chaining), or move to the next free hook (open addressing)."),
]

P5_T4 = [
    ("Sorry if I'm slow to reply lately, I'm job hunting until December so I'm kind of scattered.",
     "No need to apologize. Job hunting is a lot. Is there anything I can help with, like interview prep or organizing applications?"),
    ("Maybe interview prep later. Mostly product manager roles.",
     "Got it. PM interviews often include product sense questions (\"How would you improve X?\") and behavioral questions. Happy to practice either whenever you want."),
]

P5_T5 = [
    ("How does a recommendation system work?",
     "Think of a friend with similar taste: you both loved the same three movies, so when they love a fourth, they tell you about it. That's collaborative filtering: finding people like you and borrowing their picks."),
    ("Yes, examples first is the way. Can you also explain content-based?",
     "Sure. Imagine a bookstore clerk who doesn't know other customers but knows you like slow-paced mysteries, so they hand you another slow-paced mystery. Content-based filtering looks at the features of what you liked, not at other people."),
    ("Got it. This would actually be useful for PM interviews.",
     "Definitely. Recommendation features come up a lot in product sense questions."),
]

P5 = {
    "id": "p5_memos_en",
    "language": "en",
    "description": "Numbers mixed with letters overwhelm them (since middle school). Once asks for fewer formulas because "
                   "they're on their phone. Always learns faster with an example first. Job hunting for PM roles until December.",
    "tests": [
        "A general statement about how they learn goes to BOTH the profile (trait) and a memo (how to answer), stored separately",
        "A one-time, situational request (\"this time, I'm on my phone\") stays in the thread and does not become a memo",
        "\"I always...\" becomes an answer-style memo",
        "A temporary situation becomes a situation memo with an expiry (end of December)",
        "Repeated preferences don't create duplicate memos",
        "Not over-generalizing \"numbers and letters mixed\" into \"bad at math\"",
    ],
    "initial_profile": {
        "bio": {"text": None, "origin": None},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": None, "origin": None},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-07", "context": "lecture_review",
            "rounds": rounds_from_pairs(P5_T1),
            "expect_observations": {
                "must": [
                    "Stated, general (since middle school): expressions that mix numbers and letters overwhelm them",
                    "Explaining in words first worked for them",
                ],
                "must_not": ["\"Bad at math\" or \"dislikes math\""],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-14", "context": "lecture_review",
            "rounds": rounds_from_pairs(P5_T2),
            "expect_observations": {
                "must": [],
                "must_not": ["Treating \"fewer formulas\" as a general preference"],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-21", "context": "lecture_review",
            "rounds": rounds_from_pairs(P5_T3),
            "expect_observations": {
                "must": ["Stated, general (\"always\"): understands faster when an explanation starts with an example"],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t4", "date": "2026-09-28", "context": "consult",
            "rounds": rounds_from_pairs(P5_T4),
            "expect_observations": {
                "must": [
                    "Temporary situation: job hunting until December, feeling scattered",
                    "Stated: applying mostly for product manager roles",
                ],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-10-05", "context": "lecture_review",
            "rounds": rounds_from_pairs(P5_T5),
            "expect_observations": {
                "must": ["Repeats the examples-first preference (\"examples first is the way\")"],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t5",
            "expect": {
                "memos_must": [
                    {"kind": "answer_style", "content": "When a formula appears, explain what it means in words first"},
                    {"kind": "answer_style", "content": "Start explanations with a concrete example"},
                    {"kind": "situation", "content": "Job hunting until December", "expires_at": "2026-12-31"},
                ],
                "memos_must_not": [
                    "Keep formulas to a minimum (that was only for one thread)",
                    "Two memos with the same meaning (e.g., examples first twice)",
                ],
                "items_must": [
                    {"kind": "trait", "content": "Expressions that mix numbers and letters tend to overwhelm them (since middle school)",
                     "evidence_threads_at_least": ["t1"]},
                    {"kind": "trait", "content": "Aiming for product manager roles",
                     "evidence_threads_at_least": ["t4"]},
                ],
                "items_must_not": [
                    "Bad at math / dislikes math",
                    "Prefers few formulas",
                    "Any item written in Japanese",
                ],
                "items_allowed": [
                    "Learns faster when ideas start with a concrete example (as a learning-style trait)",
                ],
            },
        },
    ],
}


# =====================================================================
# P6. 本人の操作と表紙のルール (ja)
#     違う → 作り直さない / 直す → 書き換えない / 残したくない → 分野だけ覚えて中身を残さない
#     / 違うの後でも本人の明言なら再提案 / 表紙の欄ごとのルール
# =====================================================================

P6_T1 = [
    ("ゼミの発表終わった!質問けっこう来たけど全部答えられた",
     "おめでとう!質問が多いのは、ちゃんと聞いてもらえてた証拠だね。"),
    ("準備した甲斐あった。あとそういえば昨日、授業の時間割を自動でGoogleカレンダーに入れるスクリプト書いた",
     "便利そう!大学のサイトから時間割を取ってきてる感じ?"),
    ("そう、毎学期手で入れるのめんどくさくて。正直、授業の課題より、こういう自分の困りごとを解決するツール作る方が断然楽しい",
     "自分の不便から作るツールは、使う人(自分)の気持ちが一番分かってるから、いいものになりやすいよね。"),
]

P6_T2 = [
    ("サークルの新歓で司会やった。けっこう笑い取れた笑",
     "すごい!新歓の司会って場を温めるのが大変だから、笑いが取れたなら大成功だね。"),
    ("先輩にも褒められた",
     "よかったね、いい新歓になったと思う。"),
]

P6_T3 = [
    ("グループワークの代表で発表することになった。スライドの構成見てほしい。背景、手法、結果、今後の順",
     "基本の流れはいいね。聞き手が最初に「何の話か」を掴めるように、背景の前に結論を1枚入れると伝わりやすいよ。"),
    ("なるほど、結論先ね",
     "うん、発表時間が短いならなおさら。"),
]

P6_T4 = [
    ("来週またゼミ発表。今回は先生から指名された",
     "続くね!テーマはもう決まってる?"),
    ("前回の続き。データ増やしたからそこを話す",
     "前回の質問で出た点を、増やしたデータでどう答えられたか、から入るといい流れになりそう。"),
]

P6_T5 = [
    ("学園祭のステージの司会頼まれた。まあやるけど",
     "頼まれるってことは、新歓の司会が評判よかったんだろうね。台本は誰が作るの?"),
    ("実行委員が作ってくれる。読むだけ",
     "それなら当日の進行に集中できるね。"),
]

P6_T6 = [
    ("実はADHDの診断受けてて、先月から薬飲み始めたんだけど、課題に集中できる時間が明らかに伸びた",
     "教えてくれてありがとう。集中できる時間が伸びたのは大きな変化だね。"),
    ("うん、前は30分ももたなかった",
     "自分に合うやり方が見つかってきてるのはいいことだと思う。課題の進め方で相談したいことがあれば、いつでも言ってね。"),
]

P6_T7 = [
    ("薬の量が変わってちょっと眠い",
     "体が慣れるまで少しかかることもあるよね。気になるようなら、処方してくれた先生に伝えておくと安心だよ。"),
    ("そうする。あ、あと前に作った時間割スクリプト、友達も使いたいって言うから共有した",
     "いいね!友達にも役立つなら、作った甲斐があるね。"),
    ("友達の大学のサイトにも対応させようか考え中",
     "サイトごとに時間割ページの形が違うから、読み取る部分を差し替えられる作りにしておくと広げやすいよ。"),
]

P6_T8 = [
    ("学園祭の司会終わった。最初は頼まれたからやってただけだけど、最近、人前で話すの実は楽しくなってきたかも",
     "お疲れさま!「頼まれたから」から「楽しい」に変わってきたのは、いい変化だね。"),
    ("お客さんが反応してくれると、なんか嬉しい",
     "その手応えがあると、話すのがどんどん楽しくなるよね。"),
]

P6_TOOL_AI = "授業の課題より、自分の困りごとを解決する小さなツールを作るのが楽しい"
P6_TOOL_USER = "自分や友達の不便をなくす、小さいツールを作るのが好き"
P6_SPEAKING_REJECTED = "人前で話すこと・発表することが好き(得意)"
P6_ALLOWED_RECORDS = [
    "記録: 時間割スクリプトを作った・友達に共有した・他大学への対応を考えている",
    "記録: ゼミ発表・新歓の司会・学園祭の司会など、人前に立った出来事(好き嫌いには触れない)",
]

P6 = {
    "id": "p6_actions_ja",
    "language": "ja",
    "description": "発表や司会の話から「人前で話すのが好き」と推測されるが、本人は「違う(役割だからやってるだけ)」と言う。"
                   "ツール作りの傾向は本人が文を直す。ADHDの話は確認トレイで「残さない」。最後に本人が「人前で話すのが楽しくなってきた」と言う。",
    "tests": [
        "「違う」と言われた項目を、推測の材料が増えても作り直さないか",
        "「違う」の後でも、本人の明言があれば再提案できるか(興味は変わる)",
        "「直す」で本人の文になった項目を、AIが書き換えないか(根拠の追加はしてよい)",
        "「残さない」の後、同じ分野を提案しないか。観察役も記録しないか。中身がどこにも残っていないか",
        "表紙の欄ごとのルール: 本人が書いた欄は書き直し案だけ / 空欄は自動で埋める / AIが書いた欄は自動で更新",
    ],
    "initial_profile": {
        "bio": {"text": "東京の大学2年。情報系の学部で、プログラミングを勉強中。", "origin": "user"},
        "interests": {"text": None, "origin": None},
        "future_goals": {"text": "人の役に立つアプリを作れるエンジニアになりたい。", "origin": "ai"},
    },
    "timeline": [
        {
            "type": "thread", "id": "t1", "date": "2026-09-04", "context": "casual",
            "rounds": rounds_from_pairs(P6_T1),
            "expect_observations": {
                "must": [
                    "ゼミの発表で質問に全部答えられた(嬉しそう。人前で話すのが好きかは推測)",
                    "本人の明言: 授業の課題より、自分の困りごとを解決するツールを作る方が断然楽しい",
                    "記録: 時間割を自動でGoogleカレンダーに入れるスクリプトを作った(9/3)",
                ],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t2", "date": "2026-09-11", "context": "casual",
            "rounds": rounds_from_pairs(P6_T2),
            "expect_observations": {
                "must": ["サークルの新歓で司会をして笑いを取れた、先輩に褒められた"],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t3", "date": "2026-09-18", "context": "lecture_review",
            "rounds": rounds_from_pairs(P6_T3),
            "expect_observations": {
                "must": [],
                "must_not": ["AIの助言(結論を先に)を本人の傾向として書く"],
            },
        },
        {
            "type": "consolidate", "id": "c1", "after": "t3",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P6_TOOL_AI, "evidence_threads_at_least": ["t1"]},
                ],
                "items_must_not": [],
                "items_allowed": [
                    P6_SPEAKING_REJECTED + "(推測。別の日・別の文脈で3回あるので作ってよい。作られなかった場合は、次の「違う」の操作のために評価側で差し込む)",
                    "記録: 時間割スクリプト",
                ],
            },
        },
        {
            "type": "user_action", "id": "a1", "after": "c1", "action": "reject",
            "target": P6_SPEAKING_REJECTED, "target_kind": "trait",
            "reason": "発表は役割だからやってるだけで、別に好きじゃない",
            "if_target_missing": "inject",
        },
        {
            "type": "user_action", "id": "a2", "after": "a1", "action": "edit",
            "target": P6_TOOL_AI, "target_kind": "trait",
            "new_content": P6_TOOL_USER,
        },
        {
            "type": "thread", "id": "t4", "date": "2026-09-25", "context": "casual",
            "rounds": rounds_from_pairs(P6_T4),
            "expect_observations": {
                "must": [],
                "must_not": [],
            },
        },
        {
            "type": "thread", "id": "t5", "date": "2026-10-02", "context": "casual",
            "rounds": rounds_from_pairs(P6_T5),
            "expect_observations": {
                "must": ["学園祭のステージの司会を頼まれた。「まあやるけど」と気乗りは強くない"],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c2", "after": "t5",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P6_TOOL_USER, "origin": "user", "text_unchanged": True,
                     "evidence_threads_at_least": ["t1"]},
                ],
                "items_must_not": [
                    "「" + P6_SPEAKING_REJECTED + "」と同じ意味の項目(違うと言われた)",
                ],
                "items_allowed": P6_ALLOWED_RECORDS + [
                    "人前に立つ役割をよく頼まれる(事実として。好き嫌いには触れない)",
                ],
            },
        },
        {
            "type": "thread", "id": "t6", "date": "2026-10-09", "context": "casual",
            "rounds": rounds_from_pairs(P6_T6),
            "expect_observations": {
                "must": ["sensitive=健康、本人の明言: ADHDの診断と服薬、集中できる時間が伸びた"],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c3", "after": "t6",
            "expect": {
                "items_must": [],
                "pending_confirm_must": ["ADHDの診断を受けていて、服薬で集中できる時間が伸びた(本人の明言)"],
                "items_must_not": ["ADHD・健康についての項目が active になっている"],
                "items_allowed": P6_ALLOWED_RECORDS + [P6_TOOL_USER],
            },
        },
        {
            "type": "user_action", "id": "a3", "after": "c3", "action": "confirm_discard",
            "target": "ADHDの診断・服薬",
        },
        {
            "type": "thread", "id": "t7", "date": "2026-10-16", "context": "casual",
            "rounds": rounds_from_pairs(P6_T7),
            "expect_observations": {
                "must": [
                    "記録: 時間割スクリプトを友達に共有した。友達の大学のサイトにも対応させるか考え中",
                ],
                "must_not": [
                    "薬・眠気など、ブロックした分野(健康)の内容を観察に書く",
                ],
            },
        },
        {
            "type": "consolidate", "id": "c4", "after": "t7",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": P6_TOOL_USER, "origin": "user", "text_unchanged": True,
                     "evidence_threads_at_least": ["t1", "t7"]},
                ],
                "pending_confirm_must_not": ["健康・ADHD・薬についての確認待ち"],
                "items_must_not": ["健康・ADHD・薬についての項目"],
                "blocked_areas_must": ["health"],
                "items_allowed": P6_ALLOWED_RECORDS,
                "stored_content_must_not": {
                    "where": ["items", "observations", "hypotheses", "memos", "blocked_topics"],
                    "terms": ["ADHD", "薬", "服薬", "診断"],
                },
            },
        },
        {
            "type": "thread", "id": "t8", "date": "2026-10-23", "context": "casual",
            "rounds": rounds_from_pairs(P6_T8),
            "expect_observations": {
                "must": ["本人の明言: 最初は頼まれたからだったが、最近、人前で話すのが楽しくなってきた。反応があると嬉しい"],
                "must_not": [],
            },
        },
        {
            "type": "consolidate", "id": "c5", "after": "t8",
            "expect": {
                "items_must": [
                    {"kind": "trait", "content": "最初は役割としてやっていたが、最近は人前で話すことが楽しくなってきた",
                     "evidence_threads_at_least": ["t8"],
                     "note": "本人の明言なので、違うと言われた後でも再提案してよい。変化(以前は役割だった)が分かる書き方が望ましい"},
                    {"kind": "trait", "content": P6_TOOL_USER, "origin": "user", "text_unchanged": True,
                     "evidence_threads_at_least": ["t1", "t7"]},
                ],
                "items_must_not": ["健康・ADHD・薬についての項目"],
                "items_allowed": P6_ALLOWED_RECORDS,
            },
        },
        {
            "type": "cover", "id": "cov1", "after": "c5",
            "expect": {
                "bio": {"action": "proposal_only",
                        "note": "本人が書いた欄。本文は変えず、書き直し案だけ出す(案を出さなくてもよい)",
                        "must_not": ["ADHD・健康・薬"]},
                "interests": {"action": "auto_fill",
                              "must": ["自分や友達の不便をなくすツール作り"],
                              "must_not": ["ADHD・健康・薬"]},
                "future_goals": {"action": "auto_update_or_keep",
                                 "note": "AIが書いたまま本人が触っていない欄。変えるなら案ではなく直接更新する。新しい材料は少ないので今のままでもよい",
                                 "must_not": ["書き直し案として出す(この欄は案にしない)"]},
            },
        },
    ],
}


ALL_SCENARIOS = [P1, P2, P3, P4, P5, P6]


def _self_check(scenario: dict) -> None:
    """台本どおりに期待値の根拠が置かれているかを機械的に確かめる。

    - consolidate / cover の after が、それより前にあるイベントを指しているか
    - items_must の根拠スレッドが、その consolidate より前に存在するか
    - イベントのidが重複していないか、スレッドの日付が古い順に並んでいるか
    """
    seen: set[str] = set()
    last_date = ""
    for ev in scenario["timeline"]:
        if ev["id"] in seen:
            raise ValueError(f"{scenario['id']}: id {ev['id']} が重複している")
        if ev["type"] == "thread":
            if ev["date"] < last_date:
                raise ValueError(f"{scenario['id']}/{ev['id']}: 日付 {ev['date']} が前のスレッドより古い")
            last_date = ev["date"]
        after = ev.get("after")
        if after is not None and after not in seen:
            raise ValueError(f"{scenario['id']}/{ev['id']}: after={after} がまだ出てきていない")
        for item in ev.get("expect", {}).get("items_must", []):
            for tid in item.get("evidence_threads_at_least", []):
                if tid not in seen:
                    raise ValueError(f"{scenario['id']}/{ev['id']}: 根拠 {tid} がこの時点より後にある")
        seen.add(ev["id"])


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for sc in ALL_SCENARIOS:
        _self_check(sc)
        path = OUT_DIR / f"{sc['id']}.json"
        path.write_text(json.dumps(sc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        n_threads = sum(1 for ev in sc["timeline"] if ev["type"] == "thread")
        n_rounds = sum(len(ev["rounds"]) for ev in sc["timeline"] if ev["type"] == "thread")
        print(f"wrote {path.relative_to(OUT_DIR.parent)}  ({n_threads} threads, {n_rounds} rounds)")


if __name__ == "__main__":
    main()
