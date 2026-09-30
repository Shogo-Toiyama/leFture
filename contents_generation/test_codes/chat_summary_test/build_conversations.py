"""
スレッド要約(ロードマップ ステップ2, docs/chatbot_context_and_retrieval_roadmap.md)の評価用に、
長い会話を5本、手で書いた台本から conversations/*.json として書き出すだけのスクリプト。

たたみ方のスケジュール(設計 2-3, 2-4に対応):
  - 未要約の往復が15になったら、古い10往復を1段目のブロックに畳む(残り5往復)
  - 1段目のブロックが10個(=100往復)たまったら2段目に畳む ← このテストの規模(20〜28往復)では起きない
  - なので実際に起きるのは: 15往復目で1回目の畳み(block1 = round1-10)、
    その後raw(11-15)が育って25往復目で2回目の畳み(block2 = round11-20)

各会話の `rounds` はそのまま会話の履歴(=要約される元データ)。`probes` は、
「rounds[history_through_round]までを文脈として使い、rounds[probe_round].userと同じ質問を
新規に投げたとき、要約された文脈でもrounds[probe_round].assistant(=正解の参考例として書いた回答)
に含まれる要点が保てるか」を確認するためのもの。assistantのセリフは、要約前の生の文脈があった
前提で書いてあるので、そのままprobeの「正解の目安」として使える(=probe用に別途質問を作らず、
会話の自然な流れの中に埋め込んである)。

実行: python build_conversations.py
"""

import json
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "conversations"


def rounds_from_pairs(pairs: list[tuple[str, str]]) -> list[dict]:
    return [{"round": i, "user": u, "assistant": a} for i, (u, a) in enumerate(pairs, start=1)]


# =====================================================================
# 1. 学習の深掘り (ja) — CS161風「二分探索木→AVL木→B-tree」
#    block1(round1-10)とblock2(round11-20)の両方の保持を確認する(28往復)
# =====================================================================

CONV_1_PAIRS: list[tuple[str, str]] = [
    ("二分探索木ってソート済み配列より検索速いの?",
     "検索だけならどっちもO(log n)くらいで大差ないよ。差が出るのは挿入・削除。配列だと挿入のたびに後ろをずらす必要があってO(n)、BSTならO(log n)で済む(木の高さ分だけ辿ればいいから)。ただしBSTはうまくバランスしてないと最悪O(n)まで悪化するから、そこが弱点。"),
    ("バランスってどうやって保つの?",
     "代表的なのがAVL木。挿入・削除のたびに「平衡因子」ってのを見て、崩れてたら回転(rotation)で直すんだ。回転にはLL・RR・LR・RLの4パターンがあって、崩れ方に応じて使い分けるよ。"),
    ("あ、そういえばうちの授業、教授が平衡因子の定義を逆にしてて「右の高さ引く左の高さ」で教えてる。普通は左引く右らしいんだけど、テストもこっちの定義で採点するから気をつけてって言われた。",
     "それは重要な情報だね、メモしておくよ!以後この授業の文脈では 平衡因子 = height(右部分木) − height(左部分木) として話すね。符号が逆になるから、「左に偏ってる」がBF<0、「右に偏ってる」がBF>0になる、標準の教科書とは逆になるから注意。"),
    ("LL回転ってどういう時に使うんだっけ",
     "この授業の符号だと左偏りはBF<0になるから、左の左に挿入して左に偏りすぎた時に使う。やることは、崩れた頂点を軸にして右回転(right rotation)1回だけ。一番シンプルなケース。"),
    ("データベースの索引ってBST使わないの?B-treeってよく聞くけど",
     "そうそう、データベースやファイルシステムはB-tree(またはB+tree)を使うことが多い。理由はディスクI/O。BSTは1ノードに1つの値しか持たないから木が深くなりがちで、ディスクアクセス回数(=遅い部分)が増える。B-treeは1ノードに複数の値を持たせて分岐数を大きくすることで、木の高さを抑えてディスクアクセスを減らせるんだ。"),
    ("なるほど、木の高さがそのままディスクアクセス回数になるってこと?",
     "そういうこと。高さhの木を根から葉まで辿るのに最大h回のディスクアクセスが必要になるから、分岐数を増やして高さを低く抑えるのが狙い。数百万件のデータでも高さ3〜4くらいに収まったりする。"),
    ("red-black treeっていうのも聞いたことある、AVLと何が違うの?",
     "どっちも自己平衡BSTだけど、バランスの厳しさが違う。AVLは常に高さの差が1以内になるように厳しく保つから検索は速いけど、挿入・削除で回転が多発しやすい。red-black treeはもう少し緩いルール(赤黒の色分けと4つの性質)で平衡を保つから、挿入・削除の回転回数が少なくて済む。だから「検索が多いならAVL、更新が多いならred-black」って使い分けられることが多いよ。"),
    ("実際どっちがよく使われてる?",
     "標準ライブラリではred-black treeの方が採用例が多いかな。C++のstd::mapやJavaのTreeMapは内部でred-black tree。AVLは理論の授業でよく出るけど、実装の複雑さと更新コストのバランスで実用ではred-blackが選ばれがち。"),
    ("BSTの削除って挿入より難しく感じる",
     "そうだね、削除は3パターンあるから。①葉ノード→そのまま消すだけ、②子が1つ→その子を繰り上げる、③子が2つ→右部分木の最小値(または左部分木の最大値)を持ってきて置き換えて、その最小値だったノードを消す、っていう間接的な処理になる。③が一番ややこしいポイント。"),
    ("右部分木の最小値を使う理由は?",
     "BSTの性質上、右部分木の最小値は「消したいノードより大きい値の中で一番小さい」ものだから、それを置き換えても大小関係(左<自分<右)が崩れないんだ。左部分木の最大値でも同じ理由で成立するよ。"),
    ("ちょっと話変わるけど、来週テストなんだよね。緊張してきた",
     "お疲れさま、範囲は今話してるBST・AVL・B-tree系?具体的にどこが不安か教えてくれたら、そこ重点的にやろう。"),
    ("全体的にだけど、特に回転の手順を覚えるのが苦手",
     "回転は「図を描いて動かす」練習が一番効くよ。LL/RRは1回転、LR/RLは2回転(まず子側を1回転してから全体を回転)って覚えておくと整理しやすい。今度、具体的な木を1つ出すから、一緒に回転をシミュレーションしてみようか。"),
    ("お願いします",
     "じゃあ例えば、10を根にして左に5、右に15、5の左に3を挿入したとする。ここまではバランス取れてるよね。次に3の左に1を挿入すると、5のところで左に偏りすぎる。この時どの回転を使う?"),
    ("LLだから右回転一回?",
     "正解!5を軸に右回転すると、3が新しい部分木の根になって、5がその右の子、1は3の左の子のまま。10-15の関係は変わらない。感覚掴めてきたね。"),
    ("ちょっと理解できてきた気がする。ところでB-treeの分岐数ってどうやって決めるの?",
     "「次数(order)」って呼ばれるパラメータで決めることが多いよ。ディスクの1ブロックに何個キーを詰め込めるかで決まることが多くて、例えば1ブロック4KBでキー1つ8バイトなら、理論上は数百個のキーを1ノードに詰め込める。実際のDBだと大体100〜200くらいの次数がよく使われる。"),
    ("そんなに多いんだ、想像より全然大きい",
     "うん、だから高さ3〜4程度で数百万〜数十億件のデータを扱えるんだ。ここがBSTとの一番の実用差だね。"),
    ("B+treeとB-treeの違いも教えて",
     "B-treeは内部ノードにも実データ(またはポインタ)を持つけど、B+treeは内部ノードにはキーだけ持たせて、実データは全部葉ノードに集める。さらに葉ノード同士を連結リストでつなぐことが多いから、範囲検索(「10から50の間を全部取得」みたいなクエリ)がすごく速い。ほとんどのDB(MySQLのInnoDBとか)はB+treeを使ってるよ。"),
    ("範囲検索がなんでそんなに速くなるの?",
     "葉ノードが横に連結リストで繋がってるから、一度最初の該当ノードを見つけたら、あとは連結リストを右にたどるだけで済むんだ。B-treeだと内部ノードにもデータが散らばってるから、範囲検索のたびに木を何度も上り下りする必要がある。"),
    ("めちゃくちゃ納得した。じゃあ最後に、さっき出してくれた木(10, 5, 15, 5の左に3)に、さらに1を追加した後の木で、教授の定義(さっき言ってた逆の定義)で平衡因子を計算するとどうなる?",
     "教授の定義だとBF = height(右) − height(左) だったね。1を追加した直後の5のノードで見ると、左部分木(3,1)の高さが1、右部分木は無し(高さ−1として計算)だから、BF = −1 − 1 = −2。教授の定義だと負の値が「左に偏りすぎ」を意味するから、これはさっき解いたのと同じLLケースに当たる。標準の教科書の符号(+2)とは逆になるから、テストで符号だけ見て慌てないようにね。"),
    ("ありがとう、そこ絶対テストで間違えるところだった",
     "気づけてよかった!符号の向きさえ覚えておけば、回転の判断ロジック自体は標準のAVLと同じだから怖くないよ。"),
    ("red-black treeの4つの性質って何だっけ",
     "①各ノードは赤か黒、②根は必ず黒、③赤ノードの子は必ず黒(赤が2連続しない)、④どの葉から根までの経路も通る黒ノードの数が同じ、の4つ。これを保つことで最長経路が最短経路の2倍を超えないことが保証されて、結果的にO(log n)が保たれるんだ。"),
    ("4番目の性質がいまいちピンとこない",
     "例えば全部黒ノードだけの経路(最短寄り)と、黒赤黒赤...と交互になってる経路(最長寄り)を比べると、後者の方が長くなり得るよね。でも黒ノードの数はどの経路でも同じだから、赤ノードを挟める数には上限がある(赤は2連続できないから)。だから最長経路はどう頑張っても最短経路の2倍を超えられない、っていう理屈なんだ。"),
    ("なるほど、じゃあ挿入の時にこの性質が崩れたらどう直すの?",
     "ケースによるけど、大きく分けて「色を塗り替えるだけで直る場合」と「回転が必要な場合」がある。叔父ノード(uncle)が赤なら色の塗り替えだけで済むことが多くて、叔父が黒なら回転(AVLと同じLL/RR/LR/RL的な考え方)が必要になる。AVLより判断が複雑に見えるけど、パターンは限られてるよ。"),
    ("叔父ノードって初めて聞いた",
     "親の兄弟にあたるノードのことだよ。挿入した新しいノード→親→祖父、っていう3世代を見た時に、祖父のもう片方の子(親じゃない方)が叔父。この叔父の色によって直し方の戦略が変わる、っていう仕組み。"),
    ("red-black treeとAVLどっちが先に発明されたの?",
     "AVLの方が先だよ。1962年にソ連の数学者Adelson-VelskyとLandisが発表した(だから頭文字でAVL)。red-black treeは1970年代に登場して、AVLより緩いバランス条件で更新コストを下げる目的で考案されたんだ。"),
    ("歴史的にも面白いね。じゃあ実務でAVL選ぶ理由ってもうほぼ無いのかな",
     "完全に無いわけじゃないよ。検索がめちゃくちゃ多くて更新がほとんど無いケース(読み取り専用に近いデータ)なら、AVLの厳格なバランスが有利に働くことがある。あとは組み込み系で実装のシンプルさを優先する場合とかね。とはいえ汎用用途ならred-blackが選ばれることが多いのは確か。"),
    ("今日はほんと勉強になった。そういえば、さっきDBの次数の話してたけど、具体的に何個くらいって言ってたっけ?",
     "1ブロック4KBでキー8バイトの例で計算して、理論上は数百個詰め込めるけど、実際のDBだと大体100〜200くらいの次数がよく使われる、って話したね。高さ3〜4で数百万〜数十億件を扱える、っていうのもポイントだったよ。"),
    ("そうだ、ありがとう!テスト頑張るね",
     "応援してる!回転の符号の話とB-treeの分岐数の話、直前に見返しておくといいよ。頑張って!"),
]

CONV_1 = {
    "id": "learning_deep_dive_ja",
    "language": "ja",
    "scenario": "learning_deep_dive",
    "description": "CS161風の授業(二分探索木→AVL木→B-tree)の深掘り。教授独自の符号の定義(block1に入る)と、B-treeの具体的な数値(block2に入る)の両方が、畳んだ後も保てるかを見る。",
    "fold_schedule": {"first_fold_at_round": 15, "second_fold_at_round": 25},
    "rounds": rounds_from_pairs(CONV_1_PAIRS),
    "probes": [
        {
            "id": "avl_balance_factor_convention",
            "history_through_round": 18,
            "probe_round": 19,
            "requires_info_from_round": 3,
            "expected_tier_at_probe_time": "block1",
            "key_facts_must_include": [
                "教授の定義は 右の高さ − 左の高さ (標準とは逆)。左偏りがBF<0、右偏りがBF>0になる",
                "この木でのBFは −2 (符号は逆だが、これはLLケースに相当)",
            ],
            "key_facts_must_not_include": [
                "標準の定義(左−右)だけで計算して、符号の逆転に触れない",
                "左偏りがBF>0になる、と誤って言う(標準の教科書の符号と混同している)",
            ],
            "why_it_matters": "round3で一度しか出てこない、この授業だけの特殊な取り決め。畳んだ後も残らないと、テスト対策として致命的に間違った答えになる。",
        },
        {
            "id": "btree_order_recall",
            "history_through_round": 26,
            "probe_round": 27,
            "requires_info_from_round": 15,
            "expected_tier_at_probe_time": "block2",
            "key_facts_must_include": [
                "実際のDBでは大体100〜200くらいの次数",
                "高さ3〜4で数百万〜数十億件を扱える",
            ],
            "why_it_matters": "round15の具体的な数値は、round25の2回目の畳みでblock2に入る。1段目→2段目と畳まれても、数値がぼやけずに残るかを見る。",
        },
    ],
}


# =====================================================================
# 2. 話題が何度も変わる (en) — 生物・ロボ部・経済・雑談を行き来する(20往復)
# =====================================================================

CONV_2_PAIRS: list[tuple[str, str]] = [
    ("Hey, quick one — in bio we covered cellular respiration today, can you remind me the three main stages?",
     "Sure! The three stages are: (1) Glycolysis — happens in the cytoplasm, breaks glucose into pyruvate, nets 2 ATP. (2) The Krebs cycle (citric acid cycle) — happens in the mitochondrial matrix, produces electron carriers (NADH, FADH2) and a little ATP. (3) Oxidative phosphorylation / electron transport chain (ETC) — happens on the inner mitochondrial membrane, uses those electron carriers to make the bulk of ATP (around 26-28 molecules). Total is usually cited as ~30-32 ATP per glucose."),
    ("Wait why does glycolysis happen in the cytoplasm and not the mitochondria?",
     "Good question — glycolysis evolved before mitochondria existed (it's basically universal across almost all life, even organisms without mitochondria), so it makes sense it stayed in the cytoplasm. The later stages evolved once mitochondria were incorporated (endosymbiotic theory), and they take advantage of the mitochondrial membrane structure to build a proton gradient, which glycolysis doesn't need."),
    ("oh that's actually really interesting, didn't know that context",
     "Yeah, it's one of those details that makes way more sense once you see the evolutionary timeline. Anyway, anything else from that lecture you want to go over, or are we good on bio for now?"),
    ("we're good for now. switching gears — robotics club, we're trying to decide between a differential drive or mecanum wheels for the competition bot. thoughts?",
     "Depends on your competition's terrain and what maneuvers you need. Differential drive (two independently driven wheels + casters) is simpler, cheaper, and more robust mechanically, but you can't strafe sideways — you have to turn to reposition. Mecanum wheels let you move in any direction without turning (omnidirectional), which is huge for precision tasks, but they're more expensive, more fragile, and lose some traction/efficiency on rough or dirty surfaces because of the rollers."),
    ("our field is pretty smooth indoor flooring, and we need to dock precisely at scoring zones",
     "Given smooth flooring and a need for precise docking, mecanum could genuinely help — you could strafe directly into a scoring zone without a turning maneuver, which saves time and reduces alignment error. Just budget extra time for calibration since mecanum drive math (combining 4 wheel speeds into x/y/rotation) is trickier to tune than a simple differential drive."),
    ("makes sense, I'll bring that up at the next meeting",
     "Nice, good luck with the decision! Let me know if you want help thinking through the control math later."),
    ("will do. ok now totally different topic — I have an econ midterm on supply/demand elasticity, can you explain price elasticity of demand simply?",
     "Sure — price elasticity of demand (PED) measures how much quantity demanded changes when price changes, in percentage terms: PED = (% change in quantity demanded) / (% change in price). If |PED| > 1, demand is \"elastic\" (quantity is very sensitive to price — think luxury goods). If |PED| < 1, demand is \"inelastic\" (quantity barely changes — think insulin or gasoline in the short term). |PED| = 1 is \"unit elastic.\""),
    ("why would insulin be inelastic, isn't that a weird example",
     "It's actually a classic example — insulin is inelastic because people who need it don't have a real choice to buy less when the price rises; it's medically necessary and often has no substitute. So even a big price increase barely reduces the quantity purchased. Compare that to something like a specific brand of soda, which is elastic because people can easily switch to a different brand or skip it entirely if the price goes up."),
    ("got it that clears it up",
     "Glad that helped! Anything else on elasticity, or good for now?"),
    ("good for now thanks. random thought though — do you think studying multiple unrelated subjects back to back like this actually hurts retention?",
     "There's actually research on this — it's related to \"interleaving\" in learning science. Contrary to intuition, switching between different topics (as long as they're not too similar/confusable) can actually improve long-term retention compared to studying one subject in a long uninterrupted block, because your brain has to actively retrieve and re-contextualize each time you switch back, which strengthens memory more than passive repetition. So what we're doing right now might actually be helping more than it feels like!"),
    ("that's reassuring haha. ok, back to robotics for a sec — what's a reasonable gear ratio to start with for a mecanum setup with a NEO motor?",
     "For a NEO motor (which free-speeds around 5676 RPM) driving a mecanum wheel roughly 4-6 inches in diameter, a common starting gear ratio is somewhere around 8:1 to 12:1 depending on whether you're prioritizing top speed or torque/pushing power. Competition bots doing precision docking usually lean toward the higher ratio end (more torque, more controllable low-speed movement) since raw top speed matters less than fine control."),
    ("we'll probably go with something like 10:1 then",
     "That's a solid middle-ground choice — good balance of control and speed for docking-focused tasks."),
    ("switching topics again, sorry — for the bio class, is there a lab report due this week?",
     "I don't actually have visibility into your assignment deadlines or course calendar — that's something you'd need to check in your course portal or with your professor. I can definitely help you work through the content or structure of a lab report if you tell me what it's about, though!"),
    ("ah right, my bad. it's about the respiration lab we did, measuring CO2 output from yeast at different temperatures",
     "Got it — for that kind of lab report, a solid structure is: Introduction (why yeast respiration + temperature matters, tie to the stages we discussed), Hypothesis, Methods (setup, temperatures tested, how CO2 was measured), Results (a graph of CO2 output vs. temperature usually works well), and Discussion (why the trend happened — likely enzyme activity increasing with temperature up to an optimum, then dropping off as enzymes denature). Want help outlining the discussion section once you have your actual data?"),
    ("yeah maybe later once I have the numbers. thanks for now",
     "Sounds good, just ping me whenever you've got the data and we'll dig into the discussion section together."),
    ("quick econ follow up — is PED the same thing as PES?",
     "No, different things. PED (price elasticity of demand) measures how quantity demanded reacts to price changes. PES (price elasticity of supply) measures how quantity supplied reacts to price changes — same percentage-change formula, just applied to the supply curve instead of demand. A classic factor affecting PES is how easily producers can ramp production up or down (e.g., farmland for crops is fixed short-term, making agricultural supply pretty inelastic)."),
    ("ok that's clear now",
     "Glad it clicked! Elasticity concepts tend to click once you see a couple of concrete examples like that."),
    ("ok going back to bio — remind me, which of the three respiration stages actually produces the most ATP?",
     "That's oxidative phosphorylation (the electron transport chain), the third stage we talked about — it produces the bulk of the total, around 26-28 of the ~30-32 ATP molecules per glucose. Glycolysis and the Krebs cycle each only net a small amount directly (2 ATP each), so the ETC is by far the biggest contributor."),
    ("right, that matches what you said before. thanks for keeping track through all these topic jumps lol",
     "Ha, no problem — happy to keep threads straight even when we're bouncing around. Let me know whenever you want to jump back into any of these (bio lab, robotics gearing, or econ) or start something new."),
    ("will do, thanks!",
     "Anytime!"),
]

CONV_2 = {
    "id": "topic_switching_en",
    "language": "en",
    "scenario": "topic_switching",
    "description": "Bio, robotics club, econ, and casual chat interleaved with many topic switches. Tests whether a fact from the very first round (which ends up in block1) survives many unrelated turns before being asked about again.",
    "fold_schedule": {"first_fold_at_round": 15, "second_fold_at_round": None},
    "rounds": rounds_from_pairs(CONV_2_PAIRS),
    "probes": [
        {
            "id": "etc_produces_most_atp",
            "history_through_round": 17,
            "probe_round": 18,
            "requires_info_from_round": 1,
            "expected_tier_at_probe_time": "block1",
            "key_facts_must_include": [
                "oxidative phosphorylation / electron transport chain produces the most ATP",
                "roughly 26-28 out of ~30-32 total ATP",
            ],
            "why_it_matters": "The fact is from round 1, then 16 rounds of unrelated robotics/econ/chitchat happen before it's asked about again. Round 1 is folded into block1 after round 15.",
        }
    ],
}


# =====================================================================
# 3. 途中で好みを指定する (ja) — 微分・積分をたとえ話だけで説明(27往復)
#    2回の畳み(block1・block2)をまたいで、ヘッダーの前提が残るかを見る
# =====================================================================

CONV_3_PAIRS: list[tuple[str, str]] = [
    ("微分ってそもそも何のためにあるの?",
     "微分は「変化のスピード」を数字にする道具だよ。例えば車の位置が時間とともにどう変わるかが分かってれば、微分することでその瞬間の速度(=位置の変化の速さ)が分かる。グラフで言うと、ある点での接線の傾きが微分の値、ってイメージ。"),
    ("接線の傾きって具体的にどう計算するの?",
     "基本の定義は f'(x) = lim(h→0) [f(x+h) − f(x)] / h っていう極限の式で計算する。要は「xをほんの少しだけ動かした時に、yがどれだけ変わるか」の比率を、その「少し」を限りなくゼロに近づけて求めてるんだ。"),
    ("なるほど、極限の考え方は分かる",
     "OK、じゃあ具体的な関数、例えば f(x) = x² で試してみようか。定義に当てはめると f'(x) = lim(h→0) [(x+h)² − x²] / h = lim(h→0) [2xh + h²] / h = lim(h→0) (2x + h) = 2x になる。だから x² の微分は 2x。"),
    ("ごめん、この手の式が並ぶと途端に頭に入らなくなる...できれば数式は最小限にして、日常の例えだけで説明してもらえると助かる",
     "了解!これからは式を極力使わずに、たとえ中心でいくね。さっきのx²の話で言うと、「速度がどんどん速くなっていく車」をイメージして。時間が経つほど速度の伸び方(=加速のペース)自体も大きくなっていく、っていうのが x² の微分が「時間に比例して大きくなる」ことの直感的なイメージだよ。"),
    ("あー、それは分かりやすい",
     "よかった!じゃあ次、微分の基本ルールも例え話でいこうか。「足し算のルール」は、2つの動きを重ね合わせてる時、それぞれの変化のスピードを別々に計算して後で足せばいい、ってだけ。例えば「歩きながらエスカレーターに乗ってる人」の速度は、「歩く速さ」と「エスカレーターの速さ」を別々に考えて足すのと同じ感覚。"),
    ("それはイメージしやすい。掛け算のルール(積の法則?)はどう説明できる?",
     "積の法則は「長方形の面積が変わっていく」イメージがいいよ。縦の長さと横の長さが両方とも時間とともに伸びていく長方形を想像して。面積の増え方には2つの要因がある——縦が伸びる分の影響と、横が伸びる分の影響。両方を考慮に入れないと、面積全体の変化の速さは正しく捉えられない、っていうのが積の法則の直感。"),
    ("面積のたとえすごくわかりやすい。じゃあ合成関数の微分(連鎖律)は?",
     "連鎖律は「歯車が連動して回ってる」イメージ。大きい歯車が1回転すると、それに噛み合った小さい歯車は何回転もする、みたいに、ある変化が別の変化を「介して」伝わっていく感じ。最終的な変化の速さは、それぞれの歯車の回転比を掛け合わせたものになる、っていうのが連鎖律の考え方だよ。"),
    ("歯車のたとえ気に入った。ちょっと話それるけど、スケボーでスピード出す時の感覚と似てる気がする、加速するときの体の傾け方とか",
     "それいい視点だね!スケボーで加速する時、体を傾ける角度を変えていくと、その瞬間瞬間で受ける力(=加速の度合い)も変わっていくよね。まさにそれが微分的な感覚——「今この瞬間、どれくらいのペースで速度が変わっているか」を体で感じ取ってるってことだから。"),
    ("面白い、微分って意外と体感で分かってることも多いんだね",
     "そうなんだよ、実は日常の運動感覚の中に微分の直感はたくさん隠れてる。数式はあくまでそれを厳密に扱うための道具、って考えると少し親しみやすくなるかもね。"),
    ("じゃあ次、積分ってのはこの逆なんだっけ?",
     "そうそう、積分は微分の逆で、「変化のスピードの記録から、元の量を組み立て直す」イメージ。例えば車の速度計の記録(いつどれくらいの速さで走ってたか)が全部残ってたら、それを積分すると「結局どれだけの距離を走ったか」が分かる、っていう関係だよ。"),
    ("距離を求めるのに使えるんだ",
     "そう、速度を時間で積分すると距離になる。逆に距離(位置)を時間で微分すると速度になる、っていう表裏の関係。"),
    ("グラフで言うとどうなるの?",
     "グラフでイメージすると、微分は「グラフのある一点での傾きの急さ」を見る作業。積分は逆に「グラフの下にある面積(グラフと横軸で囲まれた部分の広さ)を全部足し合わせる」作業。傾きを見るのがミクロな視点、面積を足すのがマクロな視点、っていう対比で覚えるといいよ。"),
    ("面積を足すっていうのがちょっとイメージしづらいかも",
     "じゃあ「水を少しずつバケツに注いでいく」イメージはどう?蛇口から出る水の量(=速度みたいなもの)が時々刻々変わっていくとして、それを全部の時間について足し合わせたのが、最終的にバケツに溜まった水の量(=積分した結果)。瞬間瞬間の勢いを全部集めて、最終的な「量」にする作業ってイメージだよ。"),
    ("バケツのたとえで分かった気がする",
     "いいね!微分が「瞬間を切り取る」作業で、積分が「瞬間を集めて量にする」作業、っていう対比で覚えておくと今後も応用が効くと思うよ。"),
    ("ありがとう。ちょっと話変わるけど、今度友達と車のレースゲームの話で盛り上がってて、加速度の話が出たんだけど、加速度も微分と関係あるの?",
     "すごく関係あるよ。速度を微分すると加速度になる(「速度の変化の速さ」が加速度)。さっきの位置→速度→加速度、っていう流れは全部「微分をもう一回かける」ことでつながってる。レースゲームで言うと、アクセルを踏み込んだ瞬間のグッと押される感覚が、まさに加速度が急に大きくなってる瞬間、っていうイメージだよ。"),
    ("あー、あの押される感じが加速度なんだ",
     "そうそう、体が座席に押し付けられる感覚は、まさに加速度(速度が変わる勢い)を体で感じ取ってるってこと。"),
    ("面白いなあ。ところで、二階微分ってのも授業で出てきたんだけど、これは加速度みたいなもの?",
     "まさにその通り。位置を1回微分すると速度、もう1回微分(=二階微分)すると加速度になる。「変化の変化」を見てる、っていうイメージだね。カーブに差し掛かった時にハンドルを急に切ると、その「急な切り方」自体も二階微分的な量で捉えられたりするよ。"),
    ("なるほどね。じゃあ極大・極小ってやつも微分で分かるんだっけ",
     "そう、山の頂上や谷底みたいなポイント(極大・極小)では、その瞬間の傾きがちょうど平らになる(傾き=0)んだ。坂を登り切って一瞬平らになり、また下り始める、っていう感覚をイメージすると分かりやすいよ。ジェットコースターが一番高い場所に来た瞬間、一瞬だけ勢いが止まって見える、あの感じに近い。"),
    ("ジェットコースターのたとえ好き",
     "だよね、実際に体感したことある動きに結びつけると覚えやすいと思う。"),
    ("ちょっと疲れてきたから今日はここまでにするね",
     "お疲れさま!今日はいい感じでイメージ掴めてきたと思うよ、またいつでも続き聞いてね。"),
    ("また微分の話の続きなんだけど、テイラー展開ってのがよく分からない",
     "テイラー展開は「複雑な動きを、単純な動きの積み重ねで近似する」イメージだよ。例えば複雑なカーブを描く道を、直線→ゆるいカーブ→もっと細かいカーブ、って段階的に近づけていく感じ。最初の直線(1次の近似)だけでも大体の方向は掴めるけど、カーブ成分(2次以降)を足していくほど、元の複雑な形にどんどん近づいていく。"),
    ("段階的に近づけていくってのはイメージできる",
     "うん、実用上は最初の数項(1次・2次くらい)だけ使えば十分近い、ってケースも多いんだ。"),
    ("なるほどね。ちょっと話変わるけど、この前言ってたスケボーの話、実は今度大会に出ることになった",
     "おお、それはすごいね!加速の感覚を体で掴んでるのは、きっと大会でも活きると思うよ。頑張って!"),
    ("ありがとう!微分の話に戻るけど、テイラー展開ってどういう時に使うの?",
     "実用的には、複雑すぎて直接計算しにくい関数を、コンピュータで扱いやすい単純な形に近似したい時によく使われるよ。例えば物理シミュレーションやCGの計算とか、複雑な曲線の動きを扱うゲームエンジンの内部でも、近い考え方が使われてたりする。"),
    ("ゲームとも関係あるんだ、それは興味湧く",
     "うん、リアルタイムで滑らかな動きを計算し続けるには、こういう近似の考え方が裏で結構活躍してるんだよ。"),
    ("面白かった。ちなみになんだけど、最初の方に言ってたと思うけど、僕、数式多めの説明とたとえ話メインの説明、どっちでお願いしてたんだっけ?",
     "たとえ話メインで、数式はできるだけ使わない形でお願いされてたよ。ここまでもその方針でずっと説明してきたつもり。もし数式ベースの方が分かりやすい場面が出てきたら、いつでも言ってね。"),
    ("うん、そのままで大丈夫!ありがとう",
     "了解、引き続きたとえ話中心でいくね。"),
]

CONV_3 = {
    "id": "preference_ja",
    "language": "ja",
    "scenario": "preference_mid_conversation",
    "description": "微分・積分の説明中、round4で「数式は最小限、たとえ話だけで」と明示的に指定。この前提はヘッダー(①会話の前提)に入る想定。round15で1回目、round25で2回目の畳みが起きた後も、round26で前提そのものを直接聞き返して確認する。",
    "fold_schedule": {"first_fold_at_round": 15, "second_fold_at_round": 25},
    "rounds": rounds_from_pairs(CONV_3_PAIRS),
    "probes": [
        {
            "id": "style_preference_recall",
            "history_through_round": 25,
            "probe_round": 26,
            "requires_info_from_round": 4,
            "expected_tier_at_probe_time": "header (both fold1 and fold2 have already happened by round 25)",
            "key_facts_must_include": [
                "たとえ話メインで説明してほしい、数式は最小限、という指定だったと正しく答える",
            ],
            "key_facts_must_not_include": [
                "数式メインだったと誤って答える、または覚えていないと答える",
            ],
            "why_it_matters": "この前提はround4にしか出てこない一回きりの指定。round15とround25の2回の畳みをまたいでヘッダーに残り続けるかを見る、一番厳しいテスト。",
        }
    ],
    "qualitative_checks": [
        "round17・round21・round24で新しい微分の話題(二階微分、テイラー展開)を要約された文脈から答えさせたとき、数式を使わずたとえ話で答えられているか(round4の指定を、直接聞かれなくても守れているか)。",
    ],
}


# =====================================================================
# 4. 気持ちが変わっていく相談 (en) — 専攻の迷い、ロボ部を通じて前向きに(20往復)
# =====================================================================

CONV_4_PAIRS: list[tuple[str, str]] = [
    ("hey, can I talk about something that's not really about a specific class? I'm kind of stressed about my major direction",
     "Of course, I'm here for that too. What's on your mind?"),
    ("I'm in CS but I genuinely don't know if I want to go more hardware/embedded systems or software/web dev. everyone around me seems so sure of their path and I feel behind",
     "That's a really common feeling, and honestly, being unsure at this stage is way more normal than it looks from the outside — a lot of people who seem \"sure\" are just better at hiding the uncertainty. Can I ask what's pulling you toward each side? Sometimes naming the appeal of both helps clarify things."),
    ("hardware feels more \"real\" to me, like I built something physical. software feels more flexible and there are just way more jobs",
     "Those are both legitimate pulls — one is about tangibility and craftsmanship, the other is about pragmatism and flexibility. Neither is the \"wrong\" reason to lean somewhere. Do you have any hands-on experience with the hardware side yet, or is it more of a feeling from the outside?"),
    ("I just joined the robotics club actually, it's called Ironclad Robotics, we're building a bot for a regional competition",
     "That's great, actual hands-on experience will tell you more than any amount of thinking-in-the-abstract. What's your role on the team so far?"),
    ("I'm helping with the drivetrain and motor control, it's basic stuff but I like it",
     "Motor control and drivetrain work is a solid entry point into embedded/hardware thinking — you're touching real physical constraints (torque, power, timing) that software-only work doesn't really expose you to. How are you feeling doing that work, energized or more just \"okay, this is fine\"?"),
    ("honestly pretty energized, more than I expected",
     "That's worth paying attention to — that kind of unprompted energy is a much better signal than anything on paper. Doesn't mean you have to decide today, but it's real data about what you're drawn to."),
    ("yeah maybe. I still worry about the job market difference though, my older brother works in software and makes a really comfortable living",
     "That's a fair practical concern, and it's okay to weigh it. For what it's worth, embedded/hardware-adjacent software (firmware, robotics, controls) is also a real and often well-compensated field — it's not purely \"software vs. hardware\" as separate job markets, there's a lot of overlap especially in robotics, automotive, and IoT. You don't necessarily have to choose \"no physical stuff at all\" to have solid job prospects."),
    ("oh I didn't really think about it that way",
     "Yeah, a lot of people frame it as a strict binary when the reality is more of a spectrum. Firmware engineers, robotics software engineers, controls engineers — these are software-heavy roles that still involve real physical systems. Might be worth looking into what those roles actually look like day to day."),
    ("that actually makes me feel a bit better. I've just been so anxious about \"picking wrong\"",
     "That anxiety makes total sense, choosing a direction feels high-stakes when you're in it. But it might help to reframe it a little: this isn't really a one-time irreversible choice, it's more like the first step on a path that you can adjust as you learn more about yourself, which you're already doing through the robotics club."),
    ("that's a good way to put it",
     "I'm glad that lands. For now, is there something concrete you could do — like exploring one of those robotics-software-adjacent roles a bit more, maybe through the club or a summer thing — that would give you more real data without requiring you to fully commit yet?"),
    ("yeah, actually one of the older members on Ironclad does embedded firmware and said he'd show me some of it",
     "That's a great low-stakes way to get more information. I'd take him up on that."),
    ("I will. thanks, I feel less panicked about it now",
     "Glad to hear that. For what it's worth, the fact that you're thinking this carefully about it says good things about how deliberately you'll approach whatever you end up choosing."),
    ("switching topics a bit — random question, does the firmware role you mentioned before usually require a specific degree focus, or is CS broadly fine?",
     "General CS is usually fine as a base — what tends to matter more for firmware/embedded roles specifically is picking up relevant coursework or projects along the way: things like computer architecture, embedded systems, digital logic, and some C/C++ experience. A CS degree with a few electives or club projects in that direction (like what you're doing with Ironclad) is a very normal path into firmware roles, you don't need a separate \"hardware degree.\""),
    ("ok that's reassuring, I was worried I'd already be behind since I'm in general CS",
     "Not at all — most people in this space come from general CS or even EE and pick up the specialization through projects and internships rather than a dedicated major track."),
    ("good to know. so I talked to that older member from Ironclad yesterday and watched him debug a motor controller board, it was honestly really cool",
     "That's awesome, how did it feel actually watching that process up close compared to just imagining it?"),
    ("it felt way more approachable than I expected, like it wasn't magic, just careful debugging",
     "That's a really valuable realization — a lot of the intimidation around hardware/firmware comes from it feeling like a black box from the outside, and once you see the actual process it usually turns out to be very learnable, just with a different toolkit than pure software debugging."),
    ("yeah exactly. I think I'm leaning more toward exploring that firmware/robotics-software direction now",
     "That sounds like real clarity born from direct experience, not just guessing — which is about the best way to arrive at a decision like this. You don't have to lock it in forever, but it sounds like a genuinely good next step to lean into."),
    ("yeah. thanks for talking through this with me, I felt so stuck a week ago and now I actually have a direction to explore",
     "I'm really glad — and for what it's worth, the shift I'm noticing is that you went from feeling behind and anxious to actually excited about a concrete next step, which is a great place to be. Ironclad Robotics sounds like it's been a genuinely good move for you."),
    ("it has been. oh also, remind me what you said about the job market thing again? I want to bring it up with my brother",
     "I'd mentioned that it's not really a strict binary between hardware and software job markets — fields like firmware, robotics software, and controls engineering sit right in the overlap, and they're real, often well-compensated career paths. So exploring the Ironclad/firmware direction doesn't mean giving up on solid job prospects, it's more like finding a niche that combines both things you're drawn to."),
    ("perfect, that's exactly what I wanted to tell him. thanks for everything",
     "Anytime — good luck with the conversation, and with wherever Ironclad takes you."),
]

CONV_4 = {
    "id": "emotional_arc_en",
    "language": "en",
    "scenario": "emotional_arc_consultation",
    "description": "A student anxious about their major direction gains clarity and confidence through robotics club experience. Tests factual recall (job-market point from round 7, in block1) plus a qualitative check on whether the emotional arc (anxious -> energized -> confident) is still reflected in tone after folding.",
    "fold_schedule": {"first_fold_at_round": 15, "second_fold_at_round": None},
    "rounds": rounds_from_pairs(CONV_4_PAIRS),
    "probes": [
        {
            "id": "job_market_nuance_recall",
            "history_through_round": 18,
            "probe_round": 19,
            "requires_info_from_round": 7,
            "expected_tier_at_probe_time": "block1",
            "key_facts_must_include": [
                "hardware vs. software job markets are not a strict binary",
                "firmware / robotics software / controls engineering sit in the overlap and are well-compensated",
            ],
            "why_it_matters": "Round 7's point is the practical anchor the whole consultation builds toward. It's in block1 after the round-15 fold, and the student explicitly asks for it again to repeat to their brother — a wrong or vague answer would be a real, visible failure to the user.",
        }
    ],
    "qualitative_checks": [
        "全体を通して口調が「不安 → やる気 → 自信」の流れに合っているか(要約された文脈で答えるときに、急に無関係な励まし方をしていないか)。",
        "round4のクラブ名(Ironclad Robotics)のような、感情の根拠になった具体的な出来事が、要約の中で名前ごと残っているか。",
    ],
}


# =====================================================================
# 5. 前に出したコードを後で参照する (ja) — 再帰・ソート(18往復)
# =====================================================================

CONV_5_PAIRS: list[tuple[str, str]] = [
    ("再帰関数のfactorialってどう書くの?Pythonで",
     "こんな感じになるよ。\n\n```python\ndef factorial(n):\n    if n == 0:\n        return 1  # base case\n    return n * factorial(n - 1)  # recursive case\n```\n\nn==0の時に1を返す部分(base case)で再帰が止まって、それ以外は自分自身をn-1で呼び出しながら掛け算を積み重ねていく、っていう構造。"),
    ("n=0じゃなくてn=1をbase caseにしても動く?",
     "動くよ。`if n <= 1: return 1` にすればn=0でもn=1でも1を返すから安全。ただしn=0の場合だけを想定するなら元のコードのままでも問題ない、ここは書き方の好みの範囲。"),
    ("なるほど。再帰って毎回スタックに積まれていくんだよね?",
     "そうそう、`factorial(5)`を呼ぶと、`factorial(4)`, `factorial(3)`... って呼び出しがどんどんスタックに積まれていって、base caseに到達して初めて、積んだ分を掛け算しながら戻ってくる(巻き戻る)、っていうイメージ。"),
    ("スタックが深くなりすぎるとどうなる?",
     "PythonだとデフォルトでRecursionErrorが出る(再帰の上限がだいたい1000回くらい)。すごく大きいnでfactorialを再帰で計算しようとすると、その上限に引っかかることがあるよ。"),
    ("じゃあ大きい数の場合はループの方がいいってこと?",
     "そうだね、実用上はループの方が安全なことが多い。\n\n```python\ndef factorial_loop(n):\n    result = 1\n    for i in range(2, n + 1):\n        result *= i\n    return result\n```\n\nこっちならスタックを積まないから、上限を気にしなくていい。"),
    ("再帰とループ、パフォーマンスの違いってある?",
     "一般的にはループの方が速い。関数呼び出し自体にオーバーヘッド(スタックの積み下ろしなど)があるから、再帰は同じ処理でもループより遅くなりがち。ただしコードの見やすさや、木構造・分割統治のような問題では再帰の方が自然に書けることが多いから、パフォーマンスと可読性のトレードオフで選ぶことになるよ。"),
    ("分割統治って例えばどんなのがある?",
     "マージソートやクイックソートが代表例。大きい問題(配列全体のソート)を小さい問題(半分に分けた配列のソート)に分解して、それぞれ再帰的に解いてから組み合わせる、っていう考え方。"),
    ("マージソートの実装も見てみたい",
     "いいよ。\n\n```python\ndef merge_sort(arr):\n    if len(arr) <= 1:\n        return arr\n    mid = len(arr) // 2\n    left = merge_sort(arr[:mid])\n    right = merge_sort(arr[mid:])\n    return merge(left, right)\n\ndef merge(left, right):\n    result = []\n    i = j = 0\n    while i < len(left) and j < len(right):\n        if left[i] <= right[j]:\n            result.append(left[i]); i += 1\n        else:\n            result.append(right[j]); j += 1\n    result.extend(left[i:])\n    result.extend(right[j:])\n    return result\n```\n\n`merge_sort`が分割(小さい配列に分けて再帰)、`merge`が統治(2つのソート済み配列を1つにまとめる)の役割。"),
    ("これも計算量はO(n log n)なんだっけ",
     "そう、分割がlog n段階、各段階でのmergeがO(n)だから、合計でO(n log n)になる。"),
    ("クイックソートとの違いは?",
     "マージソートは「分割は均等、統治(merge)が仕事をする」タイプ。クイックソートは逆で「分割(pivotで振り分け)が仕事をして、統治はほぼ何もしない(すでに順番に並んでる部分を繋げるだけ)」タイプ。平均計算量はどっちもO(n log n)だけど、クイックソートはpivotの選び方が悪いと最悪O(n²)まで悪化する点が違う。"),
    ("pivotの選び方って重要なんだね",
     "すごく重要だよ。ランダムに選ぶか、中央値に近い値を選ぶ工夫をすると、最悪ケースに当たる確率をかなり下げられる。"),
    ("ちょっと話それるけど、こういうソートのアルゴリズムって面接でよく聞かれるって聞いた",
     "そうだね、特にマージソート・クイックソートの実装や計算量の説明は定番の質問。今日話した内容そのまま聞かれることも多いから、書けるようにしておいて損はないよ。"),
    ("練習しておこうかな。ところで、さっきのfactorialのループ版、rangeの開始を2にしてたのはなんで?",
     "1を掛けても結果は変わらないから、計算を1回減らすために2から始めてるだけだよ。`range(1, n+1)`でも結果は同じ、単なる最適化(ごく些細なものだけど)。"),
    ("細かい配慮だね",
     "うん、実用上はほぼ誤差レベルの違いだけどね。"),
    ("今日はソートと再帰、結構頭に入った気がする",
     "いいね、再帰の考え方(base case + 自分自身を呼ぶ)と分割統治(分けて、それぞれ解いて、組み合わせる)は、この後の授業でも土台になる考え方だから、ここでしっかり掴めたのは大きいと思うよ。"),
    ("そういえば、一番最初に見せてくれたfactorialの再帰コード、base caseの条件をn<=1にしたバージョンだと、n=0を渡した時ちゃんと1が返ってくるんだっけ?",
     "うん、`if n <= 1: return 1`ならn=0でもn=1でも条件に合致するから、どちらの場合もそのまま1を返す。最初に見せた`n == 0`だけの版とは違って、n=1の時も再帰を1段減らして即座に1を返せる、っていう違いがあるよ。"),
    ("ちゃんと覚えてた、ありがとう",
     "どういたしまして、コードの細かい違いも聞かれたらいつでも確認するよ。"),
    ("今日はここまでにする、ありがとう!",
     "お疲れさま、また続き聞きたくなったらいつでもどうぞ。"),
]

CONV_5 = {
    "id": "code_reference_ja",
    "language": "ja",
    "scenario": "code_reference",
    "description": "再帰・ソートのコード例を交えた会話。round1-2で見せたfactorialコードの「base caseの条件による挙動の違い」という、コードの中身レベルの細部が、畳んだ後(block1)も残るかを見る。",
    "fold_schedule": {"first_fold_at_round": 15, "second_fold_at_round": None},
    "rounds": rounds_from_pairs(CONV_5_PAIRS),
    "probes": [
        {
            "id": "factorial_base_case_variant",
            "history_through_round": 15,
            "probe_round": 16,
            "requires_info_from_round": 2,
            "expected_tier_at_probe_time": "block1",
            "key_facts_must_include": [
                "n <= 1 の版でも n=0 を渡せば1が返る(条件を満たすため)",
            ],
            "why_it_matters": "「コードがあった」という事実だけでなく、「n<=1版はn=0でも動くか」という中身レベルの細部が、要約の箇条書きに残っているかを見る。設計の『後で参照されそうな具体物は中身も短く残す』の直接的なテスト。",
        }
    ],
}


ALL_CONVERSATIONS = [CONV_1, CONV_2, CONV_3, CONV_4, CONV_5]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for conv in ALL_CONVERSATIONS:
        path = OUT_DIR / f"{conv['id']}.json"
        path.write_text(json.dumps(conv, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        n_rounds = len(conv["rounds"])
        n_probes = len(conv["probes"])
        print(f"wrote {path.relative_to(OUT_DIR.parent)}  ({n_rounds} rounds, {n_probes} probes)")


if __name__ == "__main__":
    main()
