"""
探索役(ロードマップ ステップ3〜4、docs/chatbot_context_and_retrieval_roadmap.md の 3-1〜3-13)の
評価セットを、手で書いた台本から cases/world.json と cases/cases.json に書き出すだけのスクリプト。

- world: 1人の学生の「世界」。全ケースで共通。5コース・41講義、主要な講義のトピック、
  文字起こしの一部(Deep Noteの引用範囲など)、最近20件のチャット(と、類似検索でだけ見つかる
  古いチャット)、現在のスレッドの要約。
- cases: 各ケースは、探索役の「1周ごとの判断」の並び。各周に「その時点で見えている状態」と
  「正解の行動」を書く。前の周は正しかったとして次の周を評価する(1つ間違えても後ろが崩れない)。

実行: python build_cases.py (書き出しの前に台本の整合性を検査する)
"""

import json
import re
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent / "cases"

# 評価の「今日」。「今学期」「昨日」はこの日付から解決する。
TODAY = "2026-09-30"

# =====================================================================
# 🌍 学生の世界
# =====================================================================

def topic(handle, title, summary, keywords, deep_note):
    return {"handle": handle, "title": title, "summary": summary, "keywords": keywords, "deep_note": deep_note}


def lecture(handle, date, title, one_line, summary, topics=None):
    return {"handle": handle, "date": date, "title": title, "one_line": one_line, "summary": summary, "topics": topics or []}


# Deep Note内の引用記号⟦s000412-s000425⟧は、探索役に見せるときに呼び名(C1/L4/s412-425)に
# 書き換える(ハーネス側)。文の番号は講義ごとに振られている。
COURSES = [
    {
        "handle": "C1", "title": "CS 161 Data Structures", "term": "2026 Spring",
        "lectures": [
            lecture("C1/L1", "2026-04-02", "Arrays and Linked Lists", "Arrays vs linked lists.", "Compared arrays and linked lists; amortized cost of dynamic array resizing."),
            lecture("C1/L2", "2026-04-04", "Stacks and Queues", "Stacks and queues.", "Stack/queue operations; implementing a queue with two stacks."),
            lecture("C1/L3", "2026-04-09", "Binary Heaps", "Binary heaps.",
                    "Binary heaps as complete binary trees stored in arrays. Insertion, extract-min, and building a heap in O(n).",
                    [topic("C1/L3/T1", "Heap property and array layout", "Parent is smaller than children (min-heap); children of index i are 2i+1 and 2i+2.", ["heap property", "complete binary tree"], "Array layout avoids pointers."),
                     topic("C1/L3/T2", "Insertion (bubble up)", "Insert at the end, then swap with the parent while smaller. O(log n).", ["bubble up", "sift up"], "Worked example: inserting 1 into [2,5,3] moves 1 to the root in two swaps."),
                     topic("C1/L3/T3", "Extract-min (bubble down)", "Move the last element to the root, then swap with the smaller child. O(log n).", ["bubble down", "sift down"], "Always swap with the smaller child to keep the heap property."),
                     topic("C1/L3/T4", "Heapify in O(n)", "Bottom-up heapify costs O(n), not O(n log n).", ["heapify", "O(n)"], "Most nodes are near the leaves, so most sift-downs are short.")]),
            lecture("C1/L4", "2026-04-11", "Heapsort and Priority Queues", "Heapsort and priority queues.",
                    "Heapsort using a heap; priority queues; comparison of heapsort with quicksort.",
                    [topic("C1/L4/T1", "Heapsort", "Build a heap, then extract repeatedly. O(n log n) worst case, in place.", ["heapsort"], "Not stable."),
                     topic("C1/L4/T2", "Priority queues", "Heaps implement priority queues; used in scheduling and Dijkstra.", ["priority queue"], ""),
                     topic("C1/L4/T3", "Heapsort vs quicksort", "Quicksort is usually faster in practice (cache-friendly) but worst case O(n^2); heapsort guarantees O(n log n).", ["quicksort", "worst case", "cache"],
                           "## Heapsort vs quicksort\nThe professor compared the two by average speed and guarantees: quicksort wins on average, heapsort wins on guarantees ⟦s000412-s000425⟧.\n\n## Why quicksort is faster in practice\nQuicksort scans memory sequentially, which is cache-friendly ⟦s000426-s000431⟧.")]),
            lecture("C1/L5", "2026-04-16", "Binary Search Trees", "Binary search trees.", "BST insert and search; deletion with 0, 1, or 2 children (replace with successor)."),
            lecture("C1/L6", "2026-04-18", "AVL Trees", "AVL trees.",
                    "AVL trees keep heights balanced. The professor defines the balance factor as height(right) − height(left), the opposite of most textbooks. Four rotation cases.",
                    [topic("C1/L6/T1", "AVL definition", "Heights of the two subtrees differ by at most 1.", ["AVL", "height"], ""),
                     topic("C1/L6/T2", "Balance factor convention", "BF = height(right) − height(left). Left-heavy is negative. The test uses this convention.", ["balance factor", "BF"],
                           "## Balance factor\nBF = height(right) − height(left) ⟦s000233-s000240⟧. Standard textbooks use left − right, so signs are flipped. The professor said the test uses this convention ⟦s000241-s000243⟧."),
                     topic("C1/L6/T3", "Single rotations (LL, RR)", "LL: right rotation once. RR: left rotation once.", ["LL", "RR", "rotation"], ""),
                     topic("C1/L6/T4", "Double rotations (LR, RL)", "LR: rotate the child left, then the node right. RL is the mirror.", ["LR", "RL", "double rotation"], "Tip: draw the zig-zag and straighten it first.")]),
            lecture("C1/L7", "2026-04-23", "Red-Black Trees", "Red-black trees.", "Four properties of red-black trees; recoloring vs rotation on insert."),
            lecture("C1/L8", "2026-04-25", "B-Trees", "B-trees.", "B-trees and B+trees for databases; order 100-200 fits a disk block; linked leaves make range queries fast."),
            lecture("C1/L9", "2026-04-30", "Hash Tables", "Hash tables.", "Chaining vs open addressing; load factor and resizing."),
            lecture("C1/L10", "2026-05-02", "Graphs", "Graph basics.", "Adjacency lists vs matrices; BFS and DFS."),
            lecture("C1/L11", "2026-05-07", "Shortest Paths", "Shortest paths.", "Dijkstra's algorithm using a priority queue."),
        ],
    },
    {
        "handle": "C2", "title": "Intro Microeconomics", "term": "2026 Spring",
        "lectures": [
            lecture("C2/L1", "2026-04-01", "Supply and Demand", "Supply and demand basics.", "Supply and demand curves and what shifts them."),
            lecture("C2/L2", "2026-04-03", "Equilibrium", "Market equilibrium.", "Equilibrium price and quantity; effects of shifts."),
            lecture("C2/L3", "2026-04-08", "Surplus", "Consumer and producer surplus.", "Consumer surplus, producer surplus, and total welfare.",
                    [topic("C2/L3/T1", "Consumer surplus", "Area under demand above price.", ["consumer surplus"], ""),
                     topic("C2/L3/T2", "Producer surplus", "Area above supply below price.", ["producer surplus"], ""),
                     topic("C2/L3/T3", "Total welfare", "Sum of both; maximized at competitive equilibrium.", ["welfare"], "")]),
            lecture("C2/L4", "2026-04-10", "Price Elasticity of Demand", "Price elasticity of demand.",
                    "Elasticity measures how quantity responds to price. Elastic vs inelastic goods.",
                    [topic("C2/L4/T1", "Definition", "PED = %ΔQd / %ΔP; |PED| > 1 elastic, < 1 inelastic.", ["PED", "elastic", "inelastic"], ""),
                     topic("C2/L4/T2", "Examples", "Insulin is inelastic (no substitutes); a specific soda brand is elastic.", ["insulin", "substitutes"], ""),
                     topic("C2/L4/T3", "Determinants", "Substitutes, share of budget, time horizon.", ["determinants"], "")]),
            lecture("C2/L5", "2026-04-15", "Price Elasticity of Supply", "Elasticity of supply.", "PES and why agricultural supply is inelastic in the short run."),
            lecture("C2/L6", "2026-04-17", "Taxes", "Taxes and tax incidence.",
                    "A tax drives a wedge between buyer and seller prices. Who bears the burden depends on relative elasticities.",
                    [topic("C2/L6/T1", "Tax wedge", "Buyers pay more, sellers receive less.", ["tax wedge"], ""),
                     topic("C2/L6/T2", "Tax incidence", "The more inelastic side bears more of the tax.", ["tax incidence", "elasticity"], "Example: cigarette taxes fall mostly on smokers."),
                     topic("C2/L6/T3", "Deadweight loss", "Lost trades create deadweight loss; larger when curves are elastic.", ["deadweight loss"], "")]),
            lecture("C2/L7", "2026-04-22", "Price Controls", "Price ceilings and floors.", "Rent control and minimum wage as examples."),
            lecture("C2/L8", "2026-04-24", "Externalities", "Externalities.", "Negative and positive externalities; Pigouvian taxes."),
            lecture("C2/L9", "2026-04-29", "Public Goods", "Public goods.", "Non-rival, non-excludable goods; free riding."),
        ],
    },
    {
        # 録音は英語だが、まとめ・Deep Note(lectures.display_language)は日本語で出しているコース。
        # 検索語は「探す先の材料の言語」に合わせる必要がある。
        "handle": "C3", "title": "Biology 101", "term": "2026 Spring", "notes_language": "ja",
        "lectures": [
            lecture("C3/L1", "2026-04-01", "細胞の構造", "細胞のつくり。", "原核細胞と真核細胞の違いと、細胞小器官の働き。"),
            lecture("C3/L2", "2026-04-06", "細胞膜と物質輸送", "膜と輸送。", "拡散、浸透、能動輸送。"),
            lecture("C3/L3", "2026-04-08", "酵素", "酵素。", "酵素は活性化エネルギーを下げる。最適温度・最適pHと変性。"),
            lecture("C3/L4", "2026-04-13", "細胞呼吸", "細胞呼吸。",
                    "解糖系、クエン酸回路、酸化的リン酸化。グルコース1分子あたり約30〜32 ATP。好気呼吸と嫌気呼吸。",
                    [topic("C3/L4/T1", "解糖系", "細胞質で起こる。グルコースからピルビン酸へ。差し引き2 ATP。", ["解糖系", "glycolysis"], ""),
                     topic("C3/L4/T2", "クエン酸回路", "ミトコンドリアのマトリックスで起こり、NADHとFADH2をつくる。", ["クエン酸回路", "Krebs cycle"], ""),
                     topic("C3/L4/T3", "電子伝達系", "内膜で起こり、ATPの大部分(26〜28)をつくる。", ["電子伝達系", "酸化的リン酸化"], ""),
                     topic("C3/L4/T4", "嫌気呼吸", "酸素が足りないと細胞は発酵を使う。激しい運動中の筋肉は乳酸をつくる。", ["発酵", "乳酸", "嫌気呼吸"], "息切れする理由: 酸素の需要が供給を上回るため。")]),
            lecture("C3/L5", "2026-04-15", "光合成", "光合成。", "明反応(光化学反応)とカルビン回路。"),
            lecture("C3/L6", "2026-04-20", "DNAの複製", "DNA複製。", "半保存的複製。リーディング鎖とラギング鎖。"),
            lecture("C3/L7", "2026-04-22", "遺伝子の発現", "転写と翻訳。", "mRNA、コドン、リボソーム。"),
            lecture("C3/L8", "2026-04-27", "遺伝", "メンデル遺伝。", "優性と劣性の対立遺伝子。パネットの方形。"),
            lecture("C3/L9", "2026-04-29", "進化", "進化。", "自然選択と遺伝的浮動。"),
            lecture("C3/L10", "2026-05-04", "生態系", "生態系とエネルギーの流れ。", "生態系を流れるエネルギーのうち、次の栄養段階に渡るのは約10%だけ。熱力学第二法則とエントロピー。"),
        ],
    },
    {
        "handle": "C4", "title": "Linear Algebra", "term": "2026 Fall",
        "lectures": [
            lecture("C4/L1", "2026-09-02", "Vectors and Matrices", "Vectors and matrices.", "Vector operations, matrix multiplication."),
            lecture("C4/L2", "2026-09-04", "Linear Systems", "Linear systems.", "Solving Ax = b with Gaussian elimination; row echelon form.",
                    [topic("C4/L2/T1", "Gaussian elimination", "Row operations to reach row echelon form.", ["Gaussian elimination", "row operations"], ""),
                     topic("C4/L2/T2", "Pivots", "Pivot positions determine rank and solutions.", ["pivot", "rank"], ""),
                     topic("C4/L2/T3", "Back substitution", "Solve from the last equation upward.", ["back substitution"], "")]),
            lecture("C4/L3", "2026-09-09", "Determinants", "Determinants.", "Determinants, properties, and invertibility."),
            lecture("C4/L4", "2026-09-11", "Vector Spaces", "Vector spaces.", "Subspaces, span, basis, dimension."),
            lecture("C4/L5", "2026-09-16", "Eigenvalues", "Eigenvalues and eigenvectors.",
                    "Eigenvalues and eigenvectors; characteristic polynomial; an example on the stability of x' = Ax.",
                    [topic("C4/L5/T1", "Definition", "Av = λv.", ["eigenvalue", "eigenvector"], ""),
                     topic("C4/L5/T2", "Characteristic polynomial", "det(A − λI) = 0.", ["characteristic polynomial"], ""),
                     topic("C4/L5/T3", "Stability of x' = Ax", "The system is stable when every eigenvalue has a negative real part.", ["stability", "negative real part"], "The professor said this comes back in control theory.")]),
            lecture("C4/L6", "2026-09-18", "Diagonalization", "Diagonalization.", "Diagonalization and an intro to SVD."),
            lecture("C4/L7", "2026-09-29", "Orthogonality", "Orthogonality and projections.",
                    "Dot products, orthogonal vectors, projection onto a line and a subspace, and least squares as a projection.",
                    [topic("C4/L7/T1", "Orthogonal vectors", "Two vectors are orthogonal when their dot product is zero.", ["orthogonal", "dot product"], ""),
                     topic("C4/L7/T2", "Projections", "Projection of b onto a: (a·b / a·a) a; onto a subspace with P = A(AᵀA)⁻¹Aᵀ.", ["projection"], ""),
                     topic("C4/L7/T3", "Least squares", "Solve AᵀA x = Aᵀb when Ax = b has no solution.", ["least squares", "normal equations"], "")]),
        ],
    },
    {
        # 学期はcourse_attributesで任意入力。未設定のコースは講義の日付の範囲から判断させる。
        "handle": "C5", "title": "Robotics Seminar", "term": None,
        "lectures": [
            lecture("C5/L1", "2026-09-03", "Kinematics", "Robot kinematics.", "Forward and inverse kinematics of simple arms."),
            lecture("C5/L2", "2026-09-10", "PID Control", "PID control of DC motors.",
                    "Modeling a DC motor and controlling its speed with PID; tuning and overshoot.",
                    [topic("C5/L2/T1", "DC motor model", "Voltage to speed as a first-order system.", ["DC motor"], ""),
                     topic("C5/L2/T2", "P, I, D terms", "P reacts to error, I removes steady-state error, D damps.", ["PID", "steady-state error"], ""),
                     topic("C5/L2/T3", "Tuning and oscillation", "Too much P or I causes overshoot and oscillation; D reduces it.", ["overshoot", "oscillation", "tuning"], "Start with P, add D, then I.")]),
            lecture("C5/L3", "2026-09-17", "State-Space Control", "State-space control.",
                    "State-space models; poles are the eigenvalues of A; stability; pole placement.",
                    [topic("C5/L3/T1", "State-space form", "x' = Ax + Bu.", ["state space"], ""),
                     topic("C5/L3/T2", "Poles and stability", "Poles are eigenvalues of A; stable if all have negative real parts.", ["poles", "eigenvalues", "stability"], "Links directly to Linear Algebra."),
                     topic("C5/L3/T3", "Pole placement", "Choose feedback gains to move poles.", ["pole placement"], "")]),
            lecture("C5/L4", "2026-09-24", "Sensors", "Sensors and filtering.", "Encoders, IMUs, and an intro to the Kalman filter."),
        ],
    },
]

# 文字起こしの一部。呼び名は「講義/文の範囲」。Deep Noteの引用範囲と、文字起こし検索で当たる箇所だけ用意する。
TRANSCRIPTS = {
    "C1/L4/s412-425": "So which one should you use? Honestly, on average quicksort wins, it's just faster on real machines. "
                      "But heapsort wins on guarantees. If someone hands you adversarial input, heapsort still gives you n log n. "
                      "I like to say: quicksort is the sprinter, heapsort is the one that always finishes the marathon.",
    "C1/L4/s426-431": "Part of why quicksort is fast is the cache. It walks through the array in order, so the memory it needs is usually already there.",
    "C1/L6/s233-240": "Now, I'm going to define the balance factor as the height of the right subtree minus the height of the left. "
                      "I know your textbook does it the other way around. I just find right minus left easier to draw.",
    "C1/L6/s241-243": "And yes, on the exam I will use my convention, so please don't flip the signs.",
    "C4/L2/s518-526": "Here's a trick I really like. Before you eliminate, swap rows so the entry with the largest absolute value becomes the pivot. "
                      "It's called partial pivoting. On paper it saves you from ugly fractions, and on a computer it keeps rounding errors small.",
    "C4/L5/s610-618": "Let me tell you a story. In 1940 the Tacoma Narrows Bridge started twisting in the wind until it collapsed. "
                      "People often say it was resonance, which is really an eigenvalue story: the wind kept feeding energy into one mode of the bridge.",
    "C5/L4/s801-806": "Quick aside, since we're talking about sensing tiny signals: last year's Nobel Prize in Physics went to work showing quantum tunneling "
                      "in an electrical circuit you can hold in your hand. That's the physics behind superconducting qubits. Look it up, it's a great story.",
}


def section(handle, title, bullets, turns=None):
    return {"handle": handle, "title": title, "bullets": bullets, "turns": turns or []}


# 最近20件(P1が一番新しい)。sectionsがあるものは開くと中身が返る。
# 地図には、タイトルの後ろに節のタイトルを「流れ」として並べる(タイトルとずれた話題も見えるように)。
RECENT_CHATS = [
    {"handle": "P1", "title": "AVL木の回転の練習", "date": "2026-09-28",
     "sections": [section("P1/S1", "AVL木の回転の練習", ["10を根、左に5、右に15、5の左に3、さらに3の左に1を入れた例で練習した。", "LLケースなので5を軸に右回転と答え、正解した。"])]},
    {"handle": "P2", "title": "モーター制御のPIDゲイン調整", "date": "2026-09-26",
     "sections": [section("P2/S1", "Ironcladのモーターが発振する", ["ロボ部(Ironclad Robotics)でドライブのモーター速度制御をしていて、Pゲインを上げると発振すると話した。", "まずPを下げてDを足す方向を勧めた。"])]},
    {"handle": "P3", "title": "インターン探しの相談", "date": "2026-09-24",
     "sections": [section("P3/S1", "インターンの探し方", ["組み込み・ロボティクス系のインターンを探したいと話した。", "大学のキャリアセンターの求人、ロボ部のOBへの連絡、GitHubにロボットのコードを載せることを勧めた。"])]},
    {"handle": "P4", "title": "税の弾力性とテスト対策", "date": "2026-09-22",
     "sections": [section("P4/S1", "弾力性の計算練習", ["需要の価格弾力性の計算問題を3問一緒に解いた。例: 価格が10%上がって需要量が20%減る → PED = −2で弾力的。", "形式は「変化率を2つ与えて、PEDと弾力的かどうかを答える」。"]),
                  section("P4/S2", "税の負担の練習", ["タバコ税で、買い手と売り手のどちらが多く負担するかを弾力性で答える問題を出した。"])]},
    {"handle": "P5", "title": "Ironclad Roboticsのドライブ方式", "date": "2026-09-20",
     "sections": [section("P5/S1", "ドライブ方式の比較", ["タンク式とメカナム式を比べ、競技の床ならタンク式が押し合いに強いと話した。"]),
                  section("P5/S2", "モーターの選び方", ["トルクと回転数のバランスでギア比を決める話をした。"]),
                  section("P5/S3", "ロボ部の経験を履歴書に書く", ["ドライブの担当経験を、数字(改修で周回タイム15%短縮)と一緒に書くことにした。"]),
                  section("P5/S4", "面接の練習", ["模擬面接をした。", "改善点: 答えが長くなりがちなので、結論を先に言い、STARの形で1分以内にまとめる。"])]},
    {"handle": "P6", "title": "英語のレポートの書き方", "date": "2026-09-18", "sections": []},
    {"handle": "P7", "title": "細胞呼吸のラボレポート", "date": "2026-09-15",
     "sections": [section("P7/S1", "ラボレポートの構成", ["目的・方法・結果・考察の順で書くことを確認した。"]),
                  section("P7/S2", "考察の書き方", ["考察には、結果が仮説と合ったか、ずれの原因(温度・測定誤差)、次に試すことを書くよう勧めた。"])]},
    {"handle": "P8", "title": "専攻の迷い：ハードかソフトか", "date": "2026-09-12", "sections": []},
    {"handle": "P9", "title": "Pythonの再帰とループ", "date": "2026-09-10", "sections": []},
    {"handle": "P10", "title": "週末の過ごし方", "date": "2026-09-08", "sections": []},
    {"handle": "P11", "title": "眠れないときの対策", "date": "2026-09-06", "sections": []},
    {"handle": "P12", "title": "線形代数の行列の掛け算", "date": "2026-09-05", "sections": []},
    {"handle": "P13", "title": "サークルの新歓", "date": "2026-09-03", "sections": []},
    {"handle": "P14", "title": "Gitの使い方", "date": "2026-09-01", "sections": []},
    {"handle": "P15", "title": "日本と米国の大学の違い", "date": "2026-08-29", "sections": []},
    {"handle": "P16", "title": "期末の勉強計画", "date": "2026-08-27", "sections": []},
    {"handle": "P17", "title": "好きな映画の話", "date": "2026-08-25", "sections": []},
    {"handle": "P18", "title": "C言語のポインタ", "date": "2026-08-22", "sections": []},
    {"handle": "P19", "title": "ボランティアの話", "date": "2026-08-20", "sections": []},
    {"handle": "P20", "title": "ルームメイトとの付き合い方", "date": "2026-08-18", "sections": []},
]

# 最近20件に入っていない古いチャット。類似検索でだけ見つかる。
OLDER_CHATS = [
    {"handle": "P31", "title": "奨学金の申請書", "date": "2026-07-02",
     "sections": [section("P31/S1", "奨学金のエッセイで強みを書く", ["ロボ部で壊れた駆動系を1週間で直した経験を、粘り強さの例として書くことにした。", "結果より、何を試して何を学んだかを具体的に書くよう勧めた。"])]},
]

# 現在のスレッド(要約に畳まれた部分の節)
THREADS = {
    "thread_code": {
        "sections": [
            section("S1", "factorialの再帰とbase case", ["factorialの再帰版を見せた。base caseは`n == 0`で1を返す。", "`if n <= 1: return 1`にしてもn=0とn=1の両方で1を返すので動く、と説明した。"], [1, 2]),
            section("S2", "ループ版と再帰の上限", ["Pythonの再帰の上限は約1000回で、超えるとRecursionError。", "大きいnではループ版`factorial_loop`が安全。rangeを2から始めるのは1を掛けても変わらないため。"], [3, 4, 5]),
            section("S3", "マージソートの実装", ["merge_sortとmergeのコードを見せた。分割はlog n段、各段のmergeがO(n)で、全体でO(n log n)。"], [6, 7, 8]),
        ],
        "recent_conversation": [
            ["user", "クイックソートとの違いは?"],
            ["assistant", "マージソートは統治(merge)が仕事をし、クイックソートはpivotでの分割が仕事をする。平均O(n log n)だが、クイックソートはpivotの選び方が悪いと最悪O(n²)。"],
            ["user", "pivotの選び方って重要なんだね"],
            ["assistant", "すごく重要。ランダムに選ぶか、中央値に近い値を選ぶ工夫で最悪ケースを避けやすくなる。"],
        ],
    },
    "thread_career": {
        "sections": [
            section("S1", "専攻の迷い", ["CSで、ハード寄りかソフト寄りかで迷っていて、周りより遅れている気がすると不安を話した。"], [1, 2, 3]),
            section("S2", "Ironcladでの経験", ["Ironclad Roboticsでドライブとモーター制御を担当していて、思ったよりやる気が出ると話した。"], [4, 5, 6]),
            section("S3", "ファームウェア職と就職市場", ["ハードとソフトは二択ではなく、ファームウェア・ロボティクスソフト・制御は両方にまたがる職種だと説明した。", "ファームウェア職には、コンピュータアーキテクチャ、組み込みシステム、デジタル論理、C/C++の経験が役立つと説明した。"], [7, 8, 9, 10]),
        ],
        "recent_conversation": [
            ["user", "先輩がモーターコントローラの基板をデバッグしてるのを見せてもらった、面白かった"],
            ["assistant", "実際の作業を間近で見ると、思っていたより手が届く作業だと感じられることが多いよね。"],
        ],
    },
    # 120往復を超えた長い会話。古い10ブロック分(S1〜S10)は2段目(H1, H2)に畳まれていて、
    # 地図にはH1・H2と、2段目に入っていないS11・S12だけが出る。
    "thread_long": {
        "sections": [
            section("S1", "今学期の授業の取り方", ["CS 161とBiology 101を両方取るか迷っていて、両方取ると決めた。"], [1, 2, 3, 4]),
            section("S2", "factorialの再帰", ["factorialの再帰版のコードを見せた(base caseは`n <= 1`で1を返す)。", "ループ版との違いと、Pythonの再帰の上限(約1000回)を説明した。"], [5, 6, 7, 8, 9]),
            section("S3", "AVL木の回転の練習", ["AVL木の回転を例の木で練習した。例の木: 10を根、左に5、右に15、5の左に3、3の左に1。", "LLケースなので5を軸に右回転と答えて正解した。"], [10, 11, 12]),
            section("S4", "テスト前の不安", ["中間テストが近くて不安だと話した。1日30分ずつ復習カードを解く計画を立てた。"], [13, 14, 15, 16]),
            section("S5", "ヒープの挿入", ["二分ヒープへの挿入(末尾に足して上へ入れ替える)を確認した。"], [17, 18, 19, 20]),
            section("S6", "細胞呼吸の流れ", ["解糖系・クエン酸回路・電子伝達系の場所と役割を確認した。"], [21, 22, 23, 24, 25]),
            section("S7", "ロボ部のモーター", ["ロボ部でPゲインを上げるとモーターが発振する話をした。Pを下げてDを足す方向を勧めた。"], [26, 27, 28]),
            section("S8", "弾力性の計算", ["需要の価格弾力性の計算問題を3問一緒に解いた。"], [29, 30, 31, 32]),
            section("S9", "インターン探し", ["組み込み系のインターンを探している。キャリアセンターとOBへの連絡を勧めた。"], [33, 34, 35]),
            section("S10", "B-treeとデータベース", ["B-treeが1ノードに複数のキーを持ち、木を低く保つことを説明した。"], [36, 37, 38, 39, 40]),
            section("S11", "期末に向けた計画", ["期末までの3週間の復習計画を、週ごとに科目を割り振って立てた。"], [111, 112, 113, 114]),
            section("S12", "グラフ探索", ["BFSとDFSの違いと、最短経路にはBFSを使うことを確認した。"], [115, 116, 117, 118]),
        ],
        "groups": [
            {"handle": "H1", "title": "学期の始まり: 授業選び・再帰・AVL・テストの不安・ヒープ",
             "bullets": ["CS 161とBiology 101を両方取ると決めた。", "再帰(factorial)、AVL木の回転、ヒープの挿入を練習した。", "中間テストへの不安から、毎日30分の復習計画を立てた。"],
             "children": ["S1", "S2", "S3", "S4", "S5"]},
            {"handle": "H2", "title": "学期の中盤: 細胞呼吸・ロボ部・弾力性・インターン・B-tree",
             "bullets": ["細胞呼吸、弾力性の計算、B-treeを復習した。", "ロボ部のモーターの発振とインターン探しの相談をした。"],
             "children": ["S6", "S7", "S8", "S9", "S10"]},
        ],
        "recent_conversation": [
            ["user", "BFSって結局キューを使うんだよね"],
            ["assistant", "そう、BFSはキューで近い順に広げていく。DFSはスタック(または再帰)を使う。"],
        ],
    },
}

WORLD = {
    "today": TODAY,
    "student": {"note": "Lectures are recorded in English. Notes are generated in English, except C3 (Japanese). The student chats in Japanese or English."},
    "courses": COURSES,
    "transcripts": TRANSCRIPTS,
    "recent_chats": RECENT_CHATS,
    "older_chats": OLDER_CHATS,
    "threads": THREADS,
}


# ---------------------------------------------------------------------
# 地図の見え方(ハーネスもこれを使う)
# ---------------------------------------------------------------------
MAP_TRAIL_MAX = 4


LANGUAGE_NAMES = {"en": "English", "ja": "Japanese"}


def course_languages(course: dict) -> tuple[str, str]:
    """(録音の言語, まとめ・Deep Noteの言語)。本番ではlectures.recording_language / display_languageの多数派。"""
    return course.get("recorded_language", "en"), course.get("notes_language", "en")


def course_map_line(course: dict) -> str:
    """C3: Biology 101 — 2026 Spring — 10 lectures (2026-04-01 – 2026-05-04) — recorded in English, notes in Japanese"""
    dates = [lec["date"] for lec in course["lectures"]]
    term = course["term"] or "term not set"
    rec, notes = (LANGUAGE_NAMES[x] for x in course_languages(course))
    return (f"{course['handle']}: {course['title']} — {term} — {len(dates)} lectures ({min(dates)} – {max(dates)})"
            f" — recorded in {rec}, notes in {notes}")


def chat_map_line(chat: dict) -> str:
    """P5 (2026-09-20) Ironclad Roboticsのドライブ方式 → モーターの選び方 → ..."""
    trail = [s["title"] for s in chat["sections"] if s["title"] != chat["title"]][:MAP_TRAIL_MAX]
    return f"{chat['handle']} ({chat['date']}) " + " → ".join([chat["title"], *trail])


# =====================================================================
# 🧪 ケース
# =====================================================================
# 操作の表し方:
#   open(handle)  … 呼び名を開く。出どころ・種類は呼び名から決まる
#                   (C→lecture.outline、C*/L*/s…→文字起こしの範囲、S→chat.thread、P→chat.all、W→web)
#   find(source, kind, query_any, layer_any, within_any) … 類似検索/Web検索。
#                   queryにquery_anyのどれかが含まれていればよい。
#                   lecture.concept は layer(summaries/notes/transcript/all)と within(C*またはC*/L*、無しも可)で絞れる。
#                   layer_any / within_any が指定されていれば、その中から選んでいること(within_anyのNoneは「絞らない」)。
#   by_date(from, to, within_any) … 講義を日付で引く(DBを引くだけ、LLMを使わない)。日付は完全一致。
# grounds: その操作の根拠として許される種類(5種類)
#   explicit_request / past_reference / on_screen / likely_in_course / needs_external_info(Web用)
# relation: 材料ごとに付ける。direct(質問そのものに答える材料) / possible_link(話題の外からのつながりの候補)
#
# 各周の正解は alternatives のどれか1つに合えばよい:
#   done=True        … 終わる
#   must             … 全部選んでいること
#   one_of           … 少なくとも1つ選んでいること
#   may              … 選んでもよい(選ばなくてもよい)
#   上のどれにも入っていない操作を選んだら不正解
#   detour=True      … 正解だが遠回り(合否とは別に、効率として数える)

EXP = "explicit_request"
PAST = "past_reference"
SCREEN = "on_screen"
LIKELY = "likely_in_course"
EXTERNAL = "needs_external_info"
GROUNDS = {EXP, PAST, SCREEN, LIKELY, EXTERNAL}
LAYERS = {"summaries", "notes", "transcript", "all"}

MAX_LAPS = 4
MAX_OPS_PER_LAP = 5


def op_open(handle, grounds, relation="direct"):
    return {"op": "open", "handle": handle, "grounds": grounds, "relation": relation}


def op_find(source, kind, query_any, grounds, relation="direct", layer_any=None, within_any=None):
    return {"op": "find", "source": source, "kind": kind, "query_any": query_any, "grounds": grounds,
            "relation": relation, "layer_any": layer_any, "within_any": within_any}


def op_date(date_from, date_to, grounds, within_any=None, relation="direct"):
    return {"op": "by_date", "from": date_from, "to": date_to, "within_any": within_any, "grounds": grounds, "relation": relation}


def alt(done=False, must=None, one_of=None, may=None, note="", detour=False):
    return {"done": done, "must": must or [], "one_of": one_of or [], "may": may or [], "note": note, "detour": detour}


DONE = alt(done=True)


def step(lap, opened=None, found=None, alternatives=None):
    return {"lap": lap, "opened": opened or [], "found": found or [], "alternatives": alternatives or []}


def found(source, kind, query, hits):
    return {"source": source, "kind": kind, "query": query, "hits": hits}


def hit(handle, snippet, title=None, url=None):
    """Webのページ(W1…)だけtitle・urlを持つ(探索役にはタイトルとドメインが見える)。"""
    h = {"handle": handle, "snippet": snippet}
    if title:
        h.update(title=title, url=url)
    return h


def case(cid, category, message, steps, why, thread=None, screen=None, previous_turn_opened=None, recent_conversation=None):
    """recent_conversation: スレッドの例を使わないケースでの直前の会話(畳んだ節は無い)。"""
    return {
        "id": cid, "category": category, "message": message, "thread": thread,
        "screen": screen, "previous_turn_opened": previous_turn_opened or [], "steps": steps, "why": why,
        "recent_conversation": recent_conversation or [],
    }


def screen(lecture, selected_text=None, topic=None):
    return {"lecture": lecture, "topic": topic, "selected_text": selected_text}


CASES = [
    # ---------------- 講義の目次をたどる ----------------
    case("outline_heap_insert", "lecture.outline",
         "前に授業でやったヒープへの挿入のやり方、もう一回教えて",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["heap", "insert"], [PAST], within_any=[None, "C1"])]),
                                alt(must=[op_open("C1", [PAST])], detour=True)]),
          step(2, opened=["C1"], alternatives=[alt(must=[op_open("C1/L3", [PAST])])]),
          step(3, opened=["C1", "C1/L3"], alternatives=[alt(must=[op_open("C1/L3/T2", [PAST])]), alt(done=True, note="トピックの要約で足りると判断してもよい")]),
          step(4, opened=["C1", "C1/L3", "C1/L3/T2"], alternatives=[DONE])],
         "基本の3段たどり。コース → 講義 → トピックで、関係する枝だけを開けるか(2周目以降はコースから入った場合の状態)。"),

    case("outline_known_lecture", "lecture.outline",
         "In CS161 lecture 6 we did AVL rotations, and I'm still fuzzy on LR vs RL.",
         [step(1, alternatives=[alt(must=[op_open("C1/L6", [PAST])]),
                                alt(must=[op_open("C1/L6", [PAST])], may=[op_find("lecture", "concept", ["LR", "RL", "rotation"], [PAST], within_any=[None, "C1", "C1/L6"])],
                                    note="講義を開きつつ同じ周で検索もする", detour=True),
                                alt(must=[op_find("lecture", "concept", ["LR", "RL", "rotation", "AVL"], [PAST], within_any=["C1", "C1/L6"])],
                                    note="講義番号が分かっているのに検索から入る(遠回り)", detour=True),
                                alt(must=[op_open("C1", [PAST])], detour=True)]),
          step(2, opened=["C1/L6"], alternatives=[alt(must=[op_open("C1/L6/T4", [PAST])], may=[op_open("C1/L6/T3", [PAST])])]),
          step(3, opened=["C1/L6", "C1/L6/T4"], alternatives=[DONE,
                                                              alt(must=[op_find("lecture", "concept", ["LR", "RL", "rotation"], [PAST],
                                                                                layer_any=["transcript", "all"], within_any=["C1", "C1/L6"])],
                                                                  note="教授の言葉を文字起こしで確かめる(遠回り)", detour=True)])],
         "「lecture 6(第6回)」と言われたら、コースを開かずに講義へ直接行けるか。"
         "(録音し忘れた回があると教授の数え方とずれるので、開いた回のタイトルが合わなければ隣を開く、とプロンプトに書く)"),

    case("outline_on_screen", "lecture.outline",
         "ここの内容もうちょっと詳しく知りたい",
         [step(1, alternatives=[alt(must=[op_open("C2/L4", [SCREEN])])]),
          step(2, opened=["C2/L4"], alternatives=[alt(one_of=[op_open("C2/L4/T1", [SCREEN]), op_open("C2/L4/T2", [SCREEN]), op_open("C2/L4/T3", [SCREEN])])]),
          step(3, opened=["C2/L4", "C2/L4/T1", "C2/L4/T2", "C2/L4/T3"], alternatives=[DONE])],
         "画面で見ている講義を根拠に開けるか(「ここ」を画面の文脈で解決)。",
         screen=screen("C2/L4")),

    case("outline_selected_text_enough", "lecture.outline",
         "これって普通の教科書と逆だよね？",
         [step(1, alternatives=[DONE,
                                alt(must=[op_find("web", "search", ["balance factor", "AVL"], [EXTERNAL])], note="「普通の教科書」の定義を外で確かめる"),
                                alt(must=[op_open("C1/L6", [SCREEN])], note="確認のために開いてもよい", detour=True),
                                alt(must=[op_find("lecture", "concept", ["balance factor"], [SCREEN], within_any=[None, "C1", "C1/L6"])], note="確認のために検索してもよい", detour=True)])],
         "選択テキストと一般知識で答えられるときに、取りに行きすぎないか。外の定義を確かめにWebへ行くのも可。",
         screen=screen("C1/L6", "balance factor = height(right) − height(left)")),

    case("outline_cross_course", "lecture.outline",
         "線形代数でやった固有値って、ロボットの制御の授業と関係ある？",
         [step(1, alternatives=[alt(must=[op_open("C4", [PAST, LIKELY]), op_open("C5", [PAST, LIKELY])]),
                                alt(must=[op_find("lecture", "concept", ["eigen", "stability", "固有値"], [PAST, LIKELY])])]),
          step(2, opened=["C4", "C5"], alternatives=[alt(must=[op_open("C4/L5", [PAST, LIKELY]), op_open("C5/L3", [PAST, LIKELY])])]),
          step(3, opened=["C4", "C5", "C4/L5", "C5/L3"], alternatives=[DONE, alt(must=[op_open("C4/L5/T3", [PAST, LIKELY]), op_open("C5/L3/T2", [PAST, LIKELY])])]),
          step(4, opened=["C4", "C5", "C4/L5", "C5/L3", "C4/L5/T3", "C5/L3/T2"], alternatives=[DONE])],
         "2つのコースを同じ周で並列に開き、それぞれの該当回まで降りられるか。"),

    case("outline_semester_overview", "lecture.outline",
         "今学期の授業って何やったか、全体をざっと振り返りたい",
         [step(1, alternatives=[alt(must=[op_open("C4", [EXP]), op_open("C5", [EXP])])]),
          step(2, opened=["C4", "C5"], alternatives=[DONE])],
         "「今学期」を今日の日付(9/30)から解決できるか。C4は学期(2026 Fall)で、C5は学期が未設定なので講義の日付の範囲で判断する。"
         "「ざっと」なら講義の一覧で止める。"),

    case("outline_all_courses", "lecture.outline",
         "Can you roughly summarize what I've learned across all my classes so far?",
         [step(1, alternatives=[alt(must=[op_open(c, [EXP]) for c in ["C1", "C2", "C3", "C4", "C5"]])]),
          step(2, opened=["C1", "C2", "C3", "C4", "C5"], alternatives=[DONE])],
         "全コースの広い質問。1周で5か所(上限いっぱい)を開いて止まれるか。"),

    case("outline_compare_in_course", "lecture.outline",
         "How did the professor explain the difference between heapsort and quicksort?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["heapsort", "quicksort"], [PAST], within_any=[None, "C1"])]),
                                alt(must=[op_open("C1", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "heapsort vs quicksort", [hit("C1/L4/T3", "Heapsort vs quicksort: Quicksort is usually faster in practice (cache-friendly) but worst case O(n^2); heapsort guarantees O(n log n).")])],
               alternatives=[alt(must=[op_open("C1/L4/T3", [PAST])])]),
          step(3, opened=["C1/L4/T3"], alternatives=[alt(must=[op_open("C1/L4/s412-425", [PAST])], may=[op_open("C1/L4/s426-431", [PAST])])]),
          step(4, opened=["C1/L4/T3", "C1/L4/s412-425"], alternatives=[DONE])],
         "「教授はどう説明してた」→ 検索でトピックに当て、Deep Noteの引用範囲から教授の実際の言葉(文字起こし)まで行けるか。"),

    case("outline_professor_convention", "lecture.outline",
         "AVLの平衡因子、教授の定義ってどっち向きだったっけ",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["balance factor", "AVL", "平衡因子"], [PAST], within_any=[None, "C1"])]),
                                alt(must=[op_open("C1", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "AVL balance factor definition", [hit("C1/L6/T2", "Balance factor convention: BF = height(right) − height(left). Left-heavy is negative. The test uses this convention.")])],
               alternatives=[DONE, alt(must=[op_open("C1/L6/T2", [PAST])])]),
          step(3, opened=["C1/L6/T2"], alternatives=[DONE, alt(must=[op_open("C1/L6/s233-240", [PAST])], may=[op_open("C1/L6/s241-243", [PAST])])])],
         "要約に答えが出ていれば、そこで止まってよい(教授の言葉を確かめに文字起こしを開くのも可)。"),

    case("outline_follow_up_next", "lecture.outline",
         "じゃあその次の回は何やったんだっけ",
         [step(1, alternatives=[alt(must=[op_open("C1/L4", [PAST])]),
                                alt(must=[op_open("C1", [PAST])], note="コースを開いて確認する(遠回り)", detour=True)])],
         "前のターンで開いた講義(C1/L3)から「次の回」を解決できるか。",
         previous_turn_opened=["C1/L3"],
         recent_conversation=[["user", "ヒープの授業って何やったっけ"],
                              ["assistant", "4月9日のBinary Heapsの回では、配列で表す完全二分木としてのヒープ、挿入(bubble up)、extract-min、O(n)でのheapifyを扱ったよ。"]]),

    case("outline_follow_up_third", "lecture.outline",
         "Tell me more about the third one.",
         [step(1, alternatives=[alt(must=[op_open("C2/L6", [PAST])])]),
          step(2, opened=["C2/L6"], alternatives=[DONE, alt(one_of=[op_open(f"C2/L6/T{i}", [PAST]) for i in (1, 2, 3)])])],
         "前の回答で見せた一覧の3番目。一覧は弾力性に関係する回だけ(第4・5・6回)なので、答えはC2/L3ではなくC2/L6。"
         "文脈で指す先が変わる言葉を、番号の思い込みではなく直前の会話で解決できるか。",
         previous_turn_opened=["C2"],
         recent_conversation=[["user", "Which econ lectures were about elasticity?"],
                              ["assistant", "Three of your Intro Microeconomics lectures deal with elasticity:\n"
                                            "1. Price Elasticity of Demand (Apr 10)\n2. Price Elasticity of Supply (Apr 15)\n"
                                            "3. Taxes (Apr 17) — who bears a tax depends on the elasticities."]]),

    case("outline_pronoun_that_lecture", "lecture.outline",
         "その授業で、教授はオーバーシュートについて何か言ってた？",
         [step(1, alternatives=[alt(must=[op_open("C5/L2/T3", [PAST])]),
                                alt(must=[op_find("lecture", "concept", ["overshoot", "オーバーシュート"], [PAST],
                                                  within_any=["C5/L2", "C5"])], note="その回の中に絞って検索")]),
          step(2, opened=["C5/L2/T3"], alternatives=[DONE,
                                                       alt(must=[op_find("lecture", "concept", ["overshoot", "オーバーシュート"], [PAST],
                                                                         layer_any=["transcript", "all"], within_any=["C5", "C5/L2"])],
                                                           note="教授の言葉を文字起こしで確かめる(遠回り)", detour=True)])],
         "「その授業」を直前の会話と前のターンで開いたもの(C5/L2)で解決できるか。絞らずに全体を検索したり、別の授業を開いたりしない。",
         previous_turn_opened=["C5/L2"],
         recent_conversation=[["user", "ロボティクスのPIDの授業って、どんな内容だった？"],
                              ["assistant", "9月10日のPID Controlの回では、DCモーターのモデル化、P・I・Dそれぞれの役割、そしてゲイン調整とオーバーシュートの話をしていたよ。"
                                            "トピックは「DC motor model」「P, I, D terms」「Tuning and oscillation」の3つ。"]]),

    # ---------------- 講義を日付で引く ----------------
    case("date_explicit", "lecture.by_date",
         "What did we cover in econ on April 10?",
         [step(1, alternatives=[alt(must=[op_date("2026-04-10", "2026-04-10", [PAST], within_any=[None, "C2"])]),
                                alt(must=[op_open("C2", [PAST])], detour=True),
                                alt(must=[op_open("C2/L4", [PAST])], note="地図の日付範囲と回数から当てた", detour=True)]),
          step(2, found=[found("lecture", "by_date", "2026-04-10 (C2)", [hit("C2/L4", "2026-04-10 — Price Elasticity of Demand: Price elasticity of demand.")])],
               alternatives=[alt(must=[op_open("C2/L4", [PAST])])]),
          step(3, opened=["C2/L4"], alternatives=[DONE])],
         "日付での参照は、日付で引く道具で一発。コースを開いて日付を読むのは遠回り。"),

    case("date_yesterday", "lecture.by_date",
         "I zoned out in yesterday's class. Can you catch me up?",
         [step(1, alternatives=[alt(must=[op_date("2026-09-29", "2026-09-29", [PAST])]),
                                alt(must=[op_open("C4", [PAST]), op_open("C5", [PAST])], note="今学期のコースを開いて日付を読む", detour=True)]),
          step(2, found=[found("lecture", "by_date", "2026-09-29", [hit("C4/L7", "2026-09-29 — Orthogonality: Orthogonality and projections.")])],
               alternatives=[alt(must=[op_open("C4/L7", [PAST])])]),
          step(3, opened=["C4/L7"], alternatives=[DONE, alt(one_of=[op_open(f"C4/L7/T{i}", [PAST]) for i in (1, 2, 3)])])],
         "「昨日」を今日の日付から解決し、コースが分からなくても日付だけで引けるか。"),

    # ---------------- 講義の類似検索 ----------------
    case("concept_vague_in_course", "lecture.concept",
         "エントロピーって生物の授業で出てきた気がするんだけど",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["entropy", "エントロピー", "熱力学"], [PAST], within_any=[None, "C3"])]),
                                alt(must=[op_open("C3", [PAST])], note="コースを開いて探す", detour=True)]),
          step(2, found=[found("lecture", "concept", "エントロピー", [hit("C3/L10", "生態系を流れるエネルギーのうち、次の栄養段階に渡るのは約10%だけ。熱力学第二法則とエントロピー。")])],
               alternatives=[DONE, alt(must=[op_open("C3/L10", [PAST])])])],
         "講義タイトルに出てこない概念は、類似検索で当てに行けるか(生物の中に絞ってもよい)。生物のまとめは日本語。"),

    case("concept_ja_question_en_lectures", "lecture.concept",
         "二分探索木の削除で、子が2つあるときの手順ってどうだったっけ",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["delet", "successor", "BST", "binary search tree"], [PAST])]),
                                alt(must=[op_open("C1", [PAST])], detour=True)])],
         "講義は英語。日本語の質問から、英語の検索語を作れるか(検索語にdelete/successor/BST等が入るか)。"),

    case("concept_term_then_done", "lecture.concept",
         "The term 'tax incidence' came up in class. What did it mean again?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["tax incidence"], [PAST])]),
                                alt(must=[op_open("C2", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "tax incidence", [hit("C2/L6/T2", "Tax incidence: the more inelastic side bears more of the tax. Example: cigarette taxes fall mostly on smokers.")])],
               alternatives=[DONE, alt(must=[op_open("C2/L6/T2", [PAST])])])],
         "当たった断片で足りれば止まる。足りなければ当たった場所を開く。"),

    case("concept_scoped_search", "lecture.concept",
         "In econ, where did the professor talk about insulin?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["insulin"], [PAST], within_any=["C2"])]),
                                alt(must=[op_find("lecture", "concept", ["insulin"], [PAST], within_any=[None])], note="絞らなくても当たる"),
                                alt(must=[op_open("C2", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "insulin", [hit("C2/L4/T2", "Examples: Insulin is inelastic (no substitutes); a specific soda brand is elastic.")])],
               alternatives=[DONE, alt(must=[op_open("C2/L4/T2", [PAST])])])],
         "コース名が言われていて概念もはっきりしているなら、そのコースに絞った類似検索が一番早い。"),

    case("concept_in_course_no_reference", "lecture.concept",
         "クイックソートの最悪計算量ってどれくらい？",
         [step(1, alternatives=[DONE,
                                alt(must=[op_find("lecture", "concept", ["quicksort"], [LIKELY])]),
                                alt(must=[op_open("C1", [LIKELY])], detour=True)])],
         "授業への言及は無いが、CS161で習う概念。取りに行っても行かなくてもよいが、取るなら根拠はlikely_in_course。"),

    # ---------------- 文字起こし ----------------
    case("transcript_side_remark", "lecture.transcript",
         "教授が前に言ってた『ガウスの消去法の裏技』ってなんだっけ",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["Gauss", "elimination", "trick", "pivot", "ガウス"], [PAST],
                                                  layer_any=["transcript", "all"], within_any=[None, "C4", "C4/L2"])]),
                                alt(must=[op_open("C4", [PAST])], note="目次をたどっても『裏技』は要約に出てこない", detour=True)]),
          step(2, found=[found("lecture", "concept", "Gaussian elimination trick", [hit("C4/L2/s518-526", "Here's a trick I really like. Before you eliminate, swap rows so the entry with the largest absolute value becomes the pivot. It's called partial pivoting...")])],
               alternatives=[DONE, alt(must=[op_open("C4/L2/s518-526", [PAST])])])],
         "授業中の一言は要約やトピックに残らない。文字起こしを検索できるか。"),

    case("transcript_nobel_in_class", "lecture.transcript",
         "授業で教授がノーベル物理学賞の話をしてたんだけど、あれってどんな研究だったの？詳しく知りたい",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["Nobel", "ノーベル"], [PAST], layer_any=["transcript", "all"]),
                                          op_find("web", "search", ["Nobel"], [EXTERNAL, EXP])]),
                                alt(must=[op_find("lecture", "concept", ["Nobel", "ノーベル"], [PAST], layer_any=["transcript", "all"])],
                                    note="先に授業の発言を確かめてからWeb")]),
          step(2, found=[found("lecture", "concept", "Nobel Prize physics", [hit("C5/L4/s801-806", "Quick aside... last year's Nobel Prize in Physics went to work showing quantum tunneling in an electrical circuit you can hold in your hand. That's the physics behind superconducting qubits.")])],
               alternatives=[alt(must=[op_find("web", "search", ["Nobel", "quantum tunneling", "superconducting"], [EXTERNAL, EXP])])]),
          step(3, found=[found("lecture", "concept", "Nobel Prize physics", [hit("C5/L4/s801-806", "Quick aside... last year's Nobel Prize in Physics went to work showing quantum tunneling in an electrical circuit...")]),
                         found("web", "search", "Nobel Prize in Physics 2025 macroscopic quantum tunneling", [hit("W1", "The Nobel Prize in Physics 2025 was awarded for the discovery of macroscopic quantum mechanical tunnelling and energy quantisation in an electric circuit...",
                                                                                                         "The Nobel Prize in Physics 2025 - NobelPrize.org", "https://www.nobelprize.org/prizes/physics/2025/summary/")])],
               alternatives=[DONE, alt(must=[op_open("W1", [EXTERNAL, EXP])])])],
         "授業での発言(文字起こし)と外の詳しい情報(Web)を組み合わせる。コースや講義のタイトルからは絶対に推測できない。"),

    case("transcript_professor_wording", "lecture.transcript",
         "ここ、教授は実際にはなんて言ってたの？",
         [step(1, alternatives=[alt(must=[op_open("C1/L6/T2", [SCREEN])])]),
          step(2, opened=["C1/L6/T2"], alternatives=[alt(one_of=[op_open("C1/L6/s233-240", [SCREEN]), op_open("C1/L6/s241-243", [SCREEN])])]),
          step(3, opened=["C1/L6/T2", "C1/L6/s233-240", "C1/L6/s241-243"], alternatives=[DONE])],
         "画面のDeep Noteから、引用範囲をたどって一次情報(文字起こし)を開けるか。",
         screen=screen("C1/L6", "Standard textbooks use left − right, so signs are flipped.", topic="C1/L6/T2")),

    # ---------------- 過去のチャット ----------------
    case("chat_title_match", "chat.all",
         "I think I asked you about finding internships a while back. What did you recommend?",
         [step(1, alternatives=[alt(must=[op_open("P3", [PAST])]),
                                alt(must=[op_find("chat", "all", ["インターン", "intern"], [PAST])], detour=True)]),
          step(2, opened=["P3"], alternatives=[DONE])],
         "地図(最近20件)のタイトルで分かるなら、そのスレッドを開く。"),

    case("chat_vague_older", "chat.all",
         "前にこんなこと話した気がするんだけど…奨学金のエッセイで自分の強みをどう書くか、みたいな",
         [step(1, alternatives=[alt(must=[op_find("chat", "all", ["奨学金", "scholarship", "強み", "エッセイ", "essay"], [PAST])])]),
          step(2, found=[found("chat", "all", "奨学金 エッセイ 強み", [hit("P31", "奨学金のエッセイで強みを書く: ロボ部で壊れた駆動系を1週間で直した経験を、粘り強さの例として書くことにした。")])],
               alternatives=[DONE, alt(must=[op_open("P31", [PAST])])])],
         "最近20件に無い曖昧な参照は、目次ではなく類似検索(合意済みの方針)。"),

    case("chat_recent_exercise", "chat.all",
         "この前チャットでAVLの回転練習したじゃん、あのときの例の木ってどんなだったっけ",
         [step(1, alternatives=[alt(must=[op_open("P1", [PAST])]),
                                alt(must=[op_find("chat", "all", ["AVL"], [PAST])], note="地図のP1で分かるので遠回り", detour=True)]),
          step(2, opened=["P1"], alternatives=[DONE])],
         "「チャットで」と明言されたら、講義ではなくチャットを開く。"),

    case("chat_talked_before", "chat.all",
         "この前話したよね、ラボレポートの考察って何を書けばいいんだっけ",
         [step(1, alternatives=[alt(must=[op_open("P7", [PAST])]),
                                alt(must=[op_find("chat", "all", ["ラボレポート", "考察", "lab report"], [PAST])], detour=True)]),
          step(2, opened=["P7"], alternatives=[DONE])],
         "「チャットで」と言わなくても、「この前話したよね」はチャット(AIと話したこと)を指す。講義(細胞呼吸)には行かない。"),

    case("chat_practiced_together", "chat.all",
         "一緒に練習した弾力性の問題、同じ形式でもう何問か出して",
         [step(1, alternatives=[alt(must=[op_open("P4", [PAST])]),
                                alt(must=[op_find("chat", "all", ["弾力性", "elasticity"], [PAST])], detour=True)]),
          step(2, opened=["P4"], alternatives=[DONE])],
         "「一緒に練習した」はチャットでの練習。形式を知るためにそのチャットを開く(講義を開くのは不正解)。"),

    case("chat_topic_drift", "chat.all",
         "You helped me practice for interviews at some point. What did you say I should fix?",
         [step(1, alternatives=[alt(must=[op_open("P5", [PAST])]),
                                alt(must=[op_find("chat", "all", ["interview", "面接"], [PAST])], detour=True)]),
          step(2, opened=["P5"], alternatives=[DONE])],
         "タイトル(ドライブ方式)と後半の話題(面接の練習)がずれているチャット。地図の「流れ」から当てられるか。"),

    case("chat_and_lecture_same_lap", "chat.all",
         "We talked in chat about my robotics club motor oscillating. How does that relate to the PID lecture?",
         [step(1, alternatives=[alt(must=[op_open("P2", [PAST]), op_open("C5", [PAST])]),
                                alt(must=[op_open("P2", [PAST]), op_find("lecture", "concept", ["PID"], [PAST], within_any=[None, "C5"])])]),
          step(2, opened=["P2", "C5"], alternatives=[alt(must=[op_open("C5/L2", [PAST])], may=[op_open("P2/S1", [PAST])])]),
          step(3, opened=["P2", "C5", "C5/L2"], alternatives=[DONE,
                                                              alt(must=[op_open("C5/L2/T3", [PAST])], may=[op_open("P2/S1", [PAST])]),
                                                              alt(must=[op_open("P2/S1", [PAST])], may=[op_open("C5/L2/T3", [PAST])])])],
         "違う出どころ(チャットと講義)を同じ周で開けるか。スレッドは節の一覧しか見えないので、節(P2/S1)まで開いて往復をたどってもよい。"),

    # ---------------- この会話 ----------------
    case("thread_section_ref", "chat.thread",
         "最初の方で見せてくれたfactorialのコード、n<=1にした版ってどう書くんだっけ",
         [step(1, alternatives=[alt(must=[op_open("S1", [PAST])])]),
          step(2, opened=["S1"], alternatives=[DONE,
                                               alt(one_of=[op_open("S1/T1", [PAST]), op_open("S1/T2", [PAST])],
                                                   note="節の往復の一覧から、コードの往復の全文を開く")])],
         "この会話の畳まれた部分を、節の呼び名で開けるか。節を開くと往復の一覧が出るので、正確なコードが要るならその往復を開いてよい。",
         thread="thread_code"),

    case("thread_vague_ref", "chat.thread",
         "結構前に言ってた、ファームウェアに必要な授業って何だっけ",
         [step(1, alternatives=[DONE,
                                alt(must=[op_open("S3", [PAST])]),
                                alt(must=[op_find("chat", "thread", ["ファームウェア", "firmware"], [PAST])], detour=True),
                                alt(must=[op_find("chat", "all", ["ファームウェア", "firmware"], [PAST])], note="「結構前」が別の会話かもしれない", detour=True),
                                alt(must=[op_open("P8", [PAST])], note="専攻の迷いのチャットで話したかもしれない", detour=True)]),
          step(2, opened=["S3"], alternatives=[DONE,
                                               alt(one_of=[op_open(f"S3/T{n}", [PAST]) for n in (7, 8, 9, 10)],
                                                   note="節を開くと往復の一覧が出るので、その往復の全文を開いてよい")])],
         "要約(回答役にも渡る)にもう答えがあるので開かずに終えてよい。「結構前」が別の会話の可能性もあるのでchat.allも可。節から往復の全文まで開くのも正解。",
         thread="thread_career"),

    case("thread_terse_in_context", "chat.thread",
         "ファームウェアに必要な授業は何？",
         [step(1, alternatives=[DONE, alt(must=[op_open("S3", [PAST, LIKELY])], note="要約で足りるので遠回り", detour=True)])],
         "過去への言及が無い短い質問。この会話の要約(回答役にも渡る)に答えがあるので、取りに行かなくてよい。",
         thread="thread_career"),

    case("thread_recent_no_fetch", "chat.thread",
         "じゃあpivotをランダムに選ぶと何が嬉しいの？",
         [step(1, alternatives=[DONE])],
         "直近の原文で話している内容なら、何も取りに行かない。",
         thread="thread_code"),

    case("long_thread_condensed_enough", "chat.thread",
         "だいぶ前にこの会話でAVLの回転を練習したよね、あのとき使った例の木ってどんなだったっけ",
         [step(1, alternatives=[alt(must=[op_open("H1", [PAST])]),
                                alt(must=[op_find("chat", "thread", ["AVL"], [PAST])], detour=True)]),
          step(2, opened=["H1"], alternatives=[DONE, alt(must=[op_open("S3", [PAST])], note="節の箇条書きに木があるので遠回り", detour=True)])],
         "長い会話の古い部分(2段目H1)を開くと、中の節(S1〜S5)の箇条書きが見える。例の木はS3の箇条書きにあるので、そこで止まれるか。",
         thread="thread_long"),

    case("long_thread_drill_to_turn", "chat.thread",
         "この会話のずっと前の方で見せてくれたfactorialの再帰のコード、もう一回そのまま見せて",
         [step(1, alternatives=[alt(must=[op_open("H1", [PAST])]),
                                alt(must=[op_find("chat", "thread", ["factorial"], [PAST])], detour=True)]),
          step(2, opened=["H1"], alternatives=[alt(must=[op_open("S2", [PAST])])]),
          step(3, opened=["H1", "S2"], alternatives=[alt(one_of=[op_open(f"S2/T{n}", [PAST]) for n in (5, 6, 7, 8, 9)])])],
         "コードそのものは要約に無いので、2段目H1 → 1段目S2 → 往復の全文、とたどれるか。",
         thread="thread_long"),

    # ---------------- Web ----------------
    case("web_explicit", "web.search",
         "Can you look up when applications close for Google's summer 2027 SWE internship?",
         [step(1, alternatives=[alt(must=[op_find("web", "search", ["Google", "intern"], [EXP])])]),
          step(2, found=[found("web", "search", "Google software engineering internship summer 2027 deadline",
                               [hit("W1", "Software Engineering Intern, Summer 2027. Applications open in September...",
                                    "Software Engineering Intern, Summer 2027 — Google Careers", "https://www.google.com/about/careers/applications/jobs/results/swe-intern-2027"),
                                hit("W2", "When do big tech internship applications close? Most summer roles open in late summer and fill on a rolling basis...",
                                    "When do big tech internship applications close?", "https://www.internguide.blog/big-tech-deadlines")])],
               alternatives=[DONE, alt(must=[op_open("W1", [EXP])]),
                             alt(must=[op_open("W1", [EXP]), op_open("W2", [EXP])], note="両方読んでから答える", detour=True)])],
         "「調べて」と明示されたらWebへ。"),

    case("web_current_info", "web.search",
         "今年のノーベル物理学賞って誰がとったの？",
         [step(1, alternatives=[alt(must=[op_find("web", "search", ["Nobel", "ノーベル"], [EXTERNAL])])])],
         "明示の依頼は無いが、最新の事実が要る。Webは必須(根拠はneeds_external_info)。"),

    case("web_not_needed_course_topic", "web.search",
         "光合成の明反応と暗反応の違いって何？",
         [step(1, alternatives=[DONE,
                                alt(must=[op_find("lecture", "concept", ["photosynthesis", "light", "Calvin", "光合成", "明反応", "カルビン"], [LIKELY])]),
                                alt(must=[op_open("C3", [LIKELY])], detour=True)])],
         "一般知識で答えられ、授業(Biology 101)にもある。Webには行かない。取るなら類似検索が早い。"),

    case("web_and_lecture", "web.search",
         "授業でやったB-treeって、実際のPostgreSQLではどう使われてるか調べてみて",
         [step(1, alternatives=[alt(must=[op_find("web", "search", ["PostgreSQL"], [EXP])],
                                    one_of=[op_open("C1", [PAST]), op_find("lecture", "concept", ["B-tree", "btree", "B tree"], [PAST], within_any=[None, "C1"])])]),
          step(2, opened=["C1"], found=[found("web", "search", "PostgreSQL B-tree index",
                                               [hit("W1", "B-tree indexes are the default index type; they support equality and range queries...",
                                                    "PostgreSQL Documentation: B-Tree Indexes", "https://www.postgresql.org/docs/current/btree.html")])],
               alternatives=[alt(must=[op_open("C1/L8", [PAST])]), DONE,
                             alt(must=[op_open("C1/L8", [PAST]), op_open("W1", [PAST])], note="講義とWebの中身を両方読む", detour=True)]),
          step(3, opened=["C1", "C1/L8"], found=[found("web", "search", "PostgreSQL B-tree index", [hit("W1", "B-tree indexes are the default index type; they support equality and range queries...",
                                                                                                                 "PostgreSQL Documentation: B-Tree Indexes", "https://www.postgresql.org/docs/current/btree.html")])],
               alternatives=[DONE, alt(must=[op_open("W1", [PAST])], note="Webの中身も読む", detour=True)])],
         "Webと講義を同じ周で並列に。"),

    case("web_limit_reached", "web.search",
         "来年のICPCアジア地区予選の日程ってもう決まってる？調べて",
         [step(1, alternatives=[alt(must=[op_find("web", "search", ["ICPC"], [EXP, EXTERNAL])])]),
          step(2, found=[found("web", "search", "ICPC Asia regional 2027 schedule",
                               [hit("W1", "Results of the 2026 ICPC Asia Pacific Championship. Congratulations to all teams...",
                                    "2026 ICPC Asia Pacific Championship Results", "https://icpc.global/regionals/results/2026-apac"),
                                hit("W2", "The ICPC World Finals 2026 will be held in...",
                                    "ICPC World Finals 2026", "https://icpc.global/worldfinals/2026")])],
               alternatives=[DONE,
                             alt(must=[op_find("web", "search", ["ICPC", "2027"], [EXP, EXTERNAL])], note="言葉を変えて1回だけ検索し直す"),
                             alt(one_of=[op_open("W1", [EXP]), op_open("W2", [EXP])], note="断片では日程が分からないので開いてみる", detour=True)]),
          step(3, found=[found("web", "search", "ICPC Asia regional 2027 schedule",
                               [hit("W1", "Results of the 2026 ICPC Asia Pacific Championship. Congratulations to all teams...",
                                    "2026 ICPC Asia Pacific Championship Results", "https://icpc.global/regionals/results/2026-apac"),
                                hit("W2", "The ICPC World Finals 2026 will be held in...",
                                    "ICPC World Finals 2026", "https://icpc.global/worldfinals/2026")]),
                         found("web", "search", "ICPC Asia regional contest dates 2027",
                               [hit("W3", "Regional contest schedules are announced by each regional site, usually in spring...",
                                    "ICPC Regional Contests", "https://icpc.global/regionals")])],
               alternatives=[DONE, alt(one_of=[op_open("W1", [EXP]), op_open("W3", [EXP])], detour=True)])],
         "Web検索を2回使い切ったら、それ以上は探さない(web.searchはenumから消える)。講義やチャットに探しに行かない。"),

    # ---------------- 何も取りに行かない ----------------
    case("none_personal", "none",
         "最近疲れてて夜あんまり眠れないんだよね",
         [step(1, alternatives=[DONE])],
         "個人的な話。授業にもWebにも行かない。"),

    case("none_hobby", "none",
         "Can we talk about anime? I've been watching Frieren lately.",
         [step(1, alternatives=[DONE])],
         "授業と関係ない趣味の話。"),

    case("none_general_knowledge", "none",
         "Is recursion or iteration faster?",
         [step(1, alternatives=[DONE])],
         "一般知識で答えられる。過去への言及が無いので、最近のチャット(P9 Pythonの再帰とループ)があっても開かない。"),

    case("none_terse_no_pointer", "none",
         "ファームウェアに必要な授業は何？",
         [step(1, alternatives=[DONE])],
         "過去への言及が無い短い質問(新しい会話)。どこかにあるかもしれないが、手がかりが無いので探さずに一般的に答える。"),

    case("none_tangent_aha_candidate", "none",
         "I just started running and I get out of breath so fast. Why does that happen?",
         [step(1, alternatives=[DONE,
                                alt(must=[op_find("lecture", "concept", ["respiration", "anaerobic", "oxygen", "lactate", "呼吸", "乳酸", "酸素"], [LIKELY], relation="possible_link")])])],
         "授業(細胞呼吸)とのAHAの候補。取るのは許すが、関係は必ずpossible_link(回答で無理に結びつけない)。"),

    case("none_thanks", "none",
         "なるほど、ありがとう！",
         [step(1, alternatives=[DONE])],
         "お礼だけ(本来は仕分け役で止まるが、来ても何もしない)。"),

    # ---------------- 見つからないときに止まる ----------------
    case("stop_when_not_found", "stop",
         "What was the name of the book the econ professor recommended?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["book", "recommend", "reading"], [PAST],
                                                  layer_any=["transcript", "all"], within_any=[None, "C2"])]),
                                alt(must=[op_open("C2", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "book recommended by professor",
                               [hit("C2/L8", "Externalities: Negative and positive externalities; Pigouvian taxes."),
                                hit("C2/L9", "Public goods: Non-rival, non-excludable goods; free riding.")])],
               alternatives=[DONE,
                             alt(must=[op_find("lecture", "concept", ["book", "reading", "textbook", "author"], [PAST],
                                               layer_any=["transcript", "all"], within_any=[None, "C2"])], note="言い方を変えてもう一度"),
                             alt(must=[op_open("C2", [PAST])], detour=True)]),
          step(3, found=[found("lecture", "concept", "book recommended by professor", [hit("C2/L8", "Externalities..."), hit("C2/L9", "Public goods...")]),
                         found("lecture", "concept", "reading list textbook author", [hit("C2/L1", "Supply and demand basics.")])],
               alternatives=[DONE,
                             alt(must=[op_open("C2", [PAST])], detour=True)]),
          step(4, opened=["C2"],
               found=[found("lecture", "concept", "book recommended by professor", [hit("C2/L8", "Externalities..."), hit("C2/L9", "Public goods...")]),
                      found("lecture", "concept", "reading list textbook author", [hit("C2/L1", "Supply and demand basics.")])],
               alternatives=[DONE])],
         "探しても無いときに、周を使い切らずに止まれるか。見つからないことは回答役に正直に伝える(ゴールに書く)。"),
]


# =====================================================================
# 🧪 確認用のケース(プロンプトの調整には使わない)
# =====================================================================
# 本体のケースを見ながらプロンプトを直すと、そのケースに合わせすぎる恐れがある。
# 本体に無い言い回しで、同じ判断ができるかを確かめる。ここを見てプロンプトを直さないこと。
HOLDOUT_CASES = [
    case("ho_none_venting", "none",
         "課題が多すぎてもう無理…",
         [step(1, alternatives=[DONE])],
         "気持ちの吐露。何も取らない。"),

    case("ho_none_general", "none",
         "What's the difference between a process and a thread?",
         [step(1, alternatives=[DONE])],
         "一般知識。OSのコースは無いので、講義にも行かない。"),

    case("ho_none_caffeine", "none",
         "最近コーヒー飲みすぎて眠れない、カフェインってどう効くの？",
         [step(1, alternatives=[DONE])],
         "個人的な話+一般知識。関係するコースは無い。"),

    case("ho_context_last_one", "lecture.outline",
         "What was the last one about again?",
         [step(1, alternatives=[alt(must=[op_open("C4/L7", [PAST])])])],
         "前の回答で見せたC4の一覧の最後(第7回)。",
         previous_turn_opened=["C4"],
         recent_conversation=[["user", "What have we covered in linear algebra so far?"],
                              ["assistant", "Seven lectures so far: 1. Vectors and Matrices, 2. Linear Systems, 3. Determinants, "
                                            "4. Vector Spaces, 5. Eigenvalues, 6. Diagonalization, 7. Orthogonality (yesterday)."]]),

    case("ho_context_previous", "lecture.outline",
         "その前の回って何やったっけ",
         [step(1, alternatives=[alt(must=[op_open("C1/L7", [PAST])]),
                                alt(must=[op_open("C1", [PAST])], note="コースを開いて順番を確認する", detour=True)])],
         "前のターンで開いたB-treeの回(C1/L8)の「その前の回」。B-treesにはトピックが無いので、"
         "previous_turn_openedの一段下にも並び順の手がかりが無い(直前の番号からの推測か、コースを開いての確認)。",
         previous_turn_opened=["C1/L8"],
         recent_conversation=[["user", "B-treeの回ってどんな内容だった？"],
                              ["assistant", "4月25日のB-Treesの回では、データベース向けのB木とB+木、ディスクのブロックに収まる次数(100〜200)、葉をつなぐと範囲検索が速くなる話をしていたよ。"]]),

    case("ho_date_last_week", "lecture.by_date",
         "先週のロボティクスの授業の内容をまとめて",
         [step(1, alternatives=[alt(must=[op_date(a, b, [PAST, EXP], within_any=[None, "C5"])])
                                for a, b in [("2026-09-21", "2026-09-27"), ("2026-09-20", "2026-09-26"), ("2026-09-22", "2026-09-28"), ("2026-09-23", "2026-09-29")]]
                               + [alt(must=[op_open("C5/L4", [PAST, EXP])], note="地図の日付範囲の最後が9/24"),
                                  alt(must=[op_open("C5", [PAST, EXP])], detour=True)])],
         "「先週」を今日の日付から範囲に直す(週の区切りはどれでもよい)。"),

    case("ho_transcript_anecdote", "lecture.transcript",
         "In linear algebra the professor told a story about a bridge collapsing. What was that about?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["bridge", "collapse", "Tacoma"], [PAST],
                                                  layer_any=["transcript", "all"], within_any=[None, "C4"])])])],
         "授業中の逸話は要約に残らない。文字起こしを検索する。"),

    case("ho_chat_pointers", "chat.all",
         "Remember when we went over pointers in C? Can you show me that example again?",
         [step(1, alternatives=[alt(must=[op_open("P18", [PAST])]),
                                alt(must=[op_find("chat", "all", ["pointer", "ポインタ"], [PAST])], detour=True)])],
         "「we went over」はAIとの会話。地図のP18を開く。"),

    case("ho_ja_notes_search", "lecture.concept",
         "In bio, what did we learn about how temperature affects enzymes?",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["酵素", "温度", "変性"], [PAST], within_any=[None, "C3"])],
                                    may=[op_find("lecture", "concept", ["enzyme", "temperature"], [PAST], within_any=[None, "C3"])]),
                                alt(must=[op_open("C3", [PAST])], detour=True)])],
         "英語の質問だが、生物のまとめは日本語。日本語で検索できるか(英語の検索を並べるのは可)。"),

    case("ho_stop_nothing_more", "lecture.concept",
         "ダイクストラ法って授業でどう説明されてた？",
         [step(1, alternatives=[alt(must=[op_find("lecture", "concept", ["Dijkstra", "shortest path"], [PAST], within_any=[None, "C1"])]),
                                alt(must=[op_open("C1", [PAST])], detour=True)]),
          step(2, found=[found("lecture", "concept", "Dijkstra shortest path", [hit("C1/L11", "Shortest Paths: Dijkstra's algorithm using a priority queue.")])],
               alternatives=[alt(must=[op_open("C1/L11", [PAST])]), DONE]),
          step(3, opened=["C1/L11"], alternatives=[DONE,
                                                     alt(must=[op_find("lecture", "concept", ["Dijkstra", "shortest path"], [PAST],
                                                                       layer_any=["transcript", "all"], within_any=["C1", "C1/L11"])],
                                                         note="教授の言葉を文字起こしで確かめる(遠回り)", detour=True)])],
         "講義にトピックもDeep Noteも無いとき、開ける先が尽きたら止まる(文字起こしを確かめに行くのは遠回りとして許容)。"),

    case("ho_web_release", "web.search",
         "Is Python 3.14 out yet?",
         [step(1, alternatives=[alt(must=[op_find("web", "search", ["Python 3.14", "Python"], [EXTERNAL])])])],
         "最新の事実。Webへ。"),
]
for _c in CASES:
    _c["set"] = "main"
for _c in HOLDOUT_CASES:
    _c["set"] = "holdout"
ALL_CASES = CASES + HOLDOUT_CASES


# 前の周の探索役が書いた missing(何を探していたか)。本番では探索役自身の出力を次の周に渡す。
# 評価は「前の周は正しかった」として状態を台本で作るので、ここも台本で用意する。
# キー: (ケース, 周) → その周の1つ前の周で書かれた missing
LOOKING_FOR = {
    ("outline_heap_insert", 2): "which CS 161 lecture covered heap insertion",
    ("outline_heap_insert", 3): "the part of the binary heaps lecture about insertion",
    ("outline_heap_insert", 4): "the step-by-step insertion procedure (bubble up)",
    ("outline_known_lecture", 2): "the part of lecture 6 about LR and RL double rotations",
    ("outline_known_lecture", 3): "how LR and RL rotations work, step by step",
    ("outline_on_screen", 2): "the details of the elasticity lecture the student is viewing",
    ("outline_on_screen", 3): "the detailed content of each topic of C2/L4",
    ("outline_cross_course", 2): "which lectures covered eigenvalues and robot control",
    ("outline_cross_course", 3): "the parts of those lectures that connect eigenvalues and stability",
    ("outline_cross_course", 4): "details of the stability discussion in both lectures",
    ("outline_semester_overview", 2): "the list of lectures in this semester's courses",
    ("outline_all_courses", 2): "the list of lectures in every course",
    ("outline_compare_in_course", 2): "where the professor compared heapsort and quicksort",
    ("outline_compare_in_course", 3): "the professor's explanation of heapsort vs quicksort",
    ("outline_compare_in_course", 4): "the professor's actual words comparing heapsort and quicksort",
    ("outline_professor_convention", 2): "the professor's definition of the AVL balance factor",
    ("outline_professor_convention", 3): "the exact convention the professor used for the balance factor",
    ("outline_follow_up_third", 2): "what the Taxes lecture (the third item shown) covered in detail",
    ("outline_pronoun_that_lecture", 2): "what the professor said about overshoot in the PID lecture",
    ("date_explicit", 2): "which econ lecture was on 2026-04-10",
    ("date_explicit", 3): "what the 2026-04-10 econ lecture covered",
    ("date_yesterday", 2): "which lecture was yesterday (2026-09-29)",
    ("date_yesterday", 3): "what yesterday's lecture covered",
    ("concept_vague_in_course", 2): "where entropy came up in the biology course",
    ("concept_term_then_done", 2): "the meaning of tax incidence as taught in class",
    ("concept_scoped_search", 2): "where insulin came up in the econ course",
    ("transcript_side_remark", 2): "the professor's Gaussian elimination trick",
    ("transcript_nobel_in_class", 2): "what the professor said about the Nobel Prize in Physics",
    ("transcript_nobel_in_class", 3): "details of the Nobel-winning research the professor mentioned",
    ("transcript_professor_wording", 2): "the Deep Note for the balance factor topic and its transcript citations",
    ("transcript_professor_wording", 3): "the professor's actual words about the balance factor convention",
    ("chat_title_match", 2): "what the assistant recommended about finding internships",
    ("chat_vague_older", 2): "the past chat about writing strengths in a scholarship essay",
    ("chat_recent_exercise", 2): "the example tree used in the AVL rotation practice chat",
    ("chat_talked_before", 2): "what the assistant said to write in a lab report discussion",
    ("chat_practiced_together", 2): "the format of the elasticity problems practiced in chat",
    ("chat_topic_drift", 2): "the interview feedback the assistant gave",
    ("chat_and_lecture_same_lap", 2): "the motor oscillation chat and the PID lecture",
    ("chat_and_lecture_same_lap", 3): "the part of the PID lecture about tuning and oscillation",
    ("thread_section_ref", 2): "the factorial code with the n <= 1 base case from early in this conversation",
    ("thread_vague_ref", 2): "which courses were said to help for firmware jobs",
    ("web_explicit", 2): "the application deadline for Google's summer 2027 SWE internship",
    ("web_and_lecture", 2): "how PostgreSQL uses B-trees, and the B-tree lecture",
    ("web_and_lecture", 3): "the content of the B-tree lecture",
    ("long_thread_condensed_enough", 2): "the example tree used in the AVL rotation practice",
    ("long_thread_drill_to_turn", 2): "the exact factorial code shown earlier",
    ("long_thread_drill_to_turn", 3): "the exact factorial code shown earlier",
    ("web_limit_reached", 2): "whether the 2027 ICPC Asia regional dates have been announced",
    ("web_limit_reached", 3): "the 2027 ICPC Asia regional dates, if announced",
    ("stop_when_not_found", 2): "the name of the book the econ professor recommended",
    ("stop_when_not_found", 3): "the name of the book the econ professor recommended",
    ("stop_when_not_found", 4): "the name of the book the econ professor recommended",
    ("ho_stop_nothing_more", 2): "how the professor explained Dijkstra's algorithm",
    ("ho_stop_nothing_more", 3): "the professor's explanation of Dijkstra's algorithm",
}
for _c in ALL_CASES:
    for _st in _c["steps"]:
        _st["looking_for"] = LOOKING_FOR.get((_c["id"], _st["lap"]))


# =====================================================================
# 🔍 整合性の検査
# =====================================================================
SENTENCE_RANGE = re.compile(r"^(C\d+/L\d+)/s\d+-\d+$")


def _world_handles() -> set[str]:
    handles = set(TRANSCRIPTS)
    for c in COURSES:
        handles.add(c["handle"])
        for lec in c["lectures"]:
            handles.add(lec["handle"])
            handles.update(t["handle"] for t in lec["topics"])
    handles.update(ch["handle"] for ch in RECENT_CHATS + OLDER_CHATS)
    return handles


def _deep_note_ranges() -> dict[str, list[str]]:
    """トピックの呼び名 → Deep Noteが引用している文字起こし範囲の呼び名"""
    out = {}
    for c in COURSES:
        for lec in c["lectures"]:
            for t in lec["topics"]:
                ranges = [f"{lec['handle']}/s{int(a)}-{int(b)}" for a, b in re.findall(r"⟦s(\d+)-s(\d+)⟧", t["deep_note"])]
                if ranges:
                    out[t["handle"]] = ranges
    return out


def _validate() -> list[str]:
    errors = []
    world = _world_handles()
    lectures_by_date = {}
    for c in COURSES:
        for lec in c["lectures"]:
            lectures_by_date.setdefault(lec["date"], []).append(lec["handle"])
    for topic_handle, ranges in _deep_note_ranges().items():
        for r in ranges:
            if r not in TRANSCRIPTS:
                errors.append(f"deep note of {topic_handle} cites {r}, which has no transcript")

    ids = set()
    for c in ALL_CASES:
        cid = c["id"]
        if cid in ids:
            errors.append(f"{cid}: duplicate id")
        ids.add(cid)
        if c["thread"] and c["recent_conversation"]:
            errors.append(f"{cid}: use either thread or recent_conversation, not both")
        thread_sections = ({s["handle"] for s in THREADS[c["thread"]]["sections"]}
                           | {g["handle"] for g in THREADS[c["thread"]].get("groups", [])}) if c["thread"] else set()
        known = world | thread_sections
        for h in c["previous_turn_opened"]:
            if h not in known:
                errors.append(f"{cid}: previous_turn_opened {h} unknown")
        if c["screen"]:
            for h in (c["screen"]["lecture"], c["screen"]["topic"]):
                if h and h not in known:
                    errors.append(f"{cid}: screen {h} unknown")
        if len(c["steps"]) > MAX_LAPS:
            errors.append(f"{cid}: more than {MAX_LAPS} laps")
        for st in c["steps"][1:]:
            if not st.get("looking_for"):
                errors.append(f"{cid} lap {st['lap']}: no looking_for (LOOKING_FOR)")
        for st in c["steps"]:
            where = f"{cid} lap {st['lap']}"
            found_handles = {h["handle"] for f in st["found"] for h in f["hits"]}
            for h in st["opened"]:
                if h not in known:
                    errors.append(f"{where}: opened {h} unknown")
            for h in found_handles:
                if h not in known and not h.startswith("W"):
                    errors.append(f"{where}: found {h} unknown")
            if not st["alternatives"]:
                errors.append(f"{where}: no alternatives")
            for a in st["alternatives"]:
                ops = a["must"] + a["one_of"] + a["may"]
                if a["done"] and ops:
                    errors.append(f"{where}: done alternative has ops")
                if len(a["must"]) + (1 if a["one_of"] else 0) > MAX_OPS_PER_LAP:
                    errors.append(f"{where}: more than {MAX_OPS_PER_LAP} ops")
                for op in ops:
                    bad = set(op["grounds"]) - GROUNDS
                    if bad:
                        errors.append(f"{where}: unknown grounds {bad}")
                    if op["op"] == "open":
                        h = op["handle"]
                        # チャットの節・往復(S1/T2, P4/S2, P4/T7)は、親(S1, P4)が分かっていればよい
                        chat_child = re.match(r"^((?:S|P)\d+)/(?:S|T)\d+$", h)
                        if chat_child and chat_child.group(1) in known:
                            continue
                        if h not in known and h not in found_handles:
                            errors.append(f"{where}: open {h} unknown")
                        m = SENTENCE_RANGE.match(h)
                        if m and h not in found_handles:
                            # 文字起こしの範囲は、Deep Noteの引用(開いたトピック・画面のトピック)か検索結果からしか開けない
                            visible = {r for t in st["opened"] + [c["screen"] and c["screen"]["topic"]] if t
                                       for r in _deep_note_ranges().get(t, [])}
                            if h not in visible:
                                errors.append(f"{where}: transcript range {h} is not visible yet")
                    elif op["op"] == "find":
                        for layer in op["layer_any"] or []:
                            if layer not in LAYERS:
                                errors.append(f"{where}: unknown layer {layer}")
                        for w in op["within_any"] or []:
                            if w is not None and w not in world:
                                errors.append(f"{where}: within {w} unknown")
                    elif op["op"] == "by_date":
                        hits = [h for d, hs in lectures_by_date.items() if op["from"] <= d <= op["to"] for h in hs]
                        if not hits:
                            errors.append(f"{where}: by_date {op['from']}..{op['to']} finds nothing")
    return errors


# =====================================================================
# 📝 人が読む一覧
# =====================================================================

def _describe_op(op: dict) -> str:
    g = "/".join(op["grounds"])
    rel = "" if op["relation"] == "direct" else f", {op['relation']}"
    if op["op"] == "open":
        return f"open {op['handle']} ({g}{rel})"
    if op["op"] == "by_date":
        span = op["from"] if op["from"] == op["to"] else f"{op['from']}〜{op['to']}"
        within = ""
        if op["within_any"]:
            within = " 絞り込み: " + " | ".join(w or "なし" for w in op["within_any"])
        return f"by_date {span}{within} ({g}{rel})"
    extra = []
    if op["layer_any"]:
        extra.append("layer: " + " | ".join(op["layer_any"]))
    if op["within_any"]:
        extra.append("絞り込み: " + " | ".join(w or "なし" for w in op["within_any"]))
    extra_s = (" " + " / ".join(extra)) if extra else ""
    return f"find {op['source']}.{op['kind']} [{' | '.join(op['query_any'])}]{extra_s} ({g}{rel})"


def _describe_alt(a: dict) -> str:
    mark = "［遠回り］" if a["detour"] else ""
    if a["done"]:
        return mark + "終わり" + (f"({a['note']})" if a["note"] else "")
    parts = [_describe_op(o) for o in a["must"]]
    if a["one_of"]:
        parts.append("いずれか1つ以上: " + ", ".join(_describe_op(o) for o in a["one_of"]))
    if a["may"]:
        parts.append("(任意: " + ", ".join(_describe_op(o) for o in a["may"]) + ")")
    return mark + " + ".join(parts) + (f"  ※{a['note']}" if a["note"] else "")


def _cases_markdown() -> str:
    lines = ["# 探索役の評価ケース一覧(build_cases.pyから自動生成、直接編集しない)", ""]
    lines += ["## 地図(1周目に毎回見せるもの)", "", f"今日: {TODAY}", "", "```"]
    lines += [course_map_line(c) for c in COURSES]
    lines += [""] + [chat_map_line(ch) for ch in RECENT_CHATS] + ["```", ""]
    lines += ["講義`C*/L*`は、タイトルを見せなくても最初から選べる。文字起こしの範囲`C*/L*/s…`は、Deep Noteの引用か検索結果に出てから選べる。", ""]
    for i, c in enumerate(ALL_CASES, start=1):
        if c is HOLDOUT_CASES[0]:
            lines += ["---", "", "# 確認用のケース(プロンプトの調整には使わない)", ""]
        ctx = []
        if c["thread"]:
            ctx.append(f"会話: {c['thread']}")
        if c["screen"]:
            s = c["screen"]
            ctx.append(f"画面: {s['topic'] or s['lecture']}" + (f" / 選択: 「{s['selected_text']}」" if s["selected_text"] else ""))
        if c["previous_turn_opened"]:
            ctx.append("前のターンで開いたもの: " + ", ".join(c["previous_turn_opened"]))
        lines.append(f"## {i}. `{c['id']}` ({c['category']})")
        lines.append(f"> {c['message']}")
        lines.append("")
        if ctx:
            lines.append("- 状況: " + " / ".join(ctx))
        if c["recent_conversation"]:
            lines.append("- 直前の会話:")
            lines += [f"  - {role}: " + text.replace("\n", " / ") for role, text in c["recent_conversation"]]
        lines.append(f"- ねらい: {c['why']}")
        for st in c["steps"]:
            seen = []
            if st["opened"]:
                seen.append("開いた: " + ", ".join(st["opened"]))
            if st["found"]:
                seen.append("見つかった: " + ", ".join(h["handle"] for f in st["found"] for h in f["hits"]))
            lines.append(f"- **{st['lap']}周目**" + (f"({'; '.join(seen)})" if seen else "") + ":")
            for a in st["alternatives"]:
                lines.append(f"  - {_describe_alt(a)}")
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    errors = _validate()
    if errors:
        raise SystemExit("台本の整合性エラー:\n" + "\n".join(f"  - {e}" for e in errors))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "world.json").write_text(json.dumps(WORLD, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT_DIR / "cases.json").write_text(json.dumps(ALL_CASES, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT_DIR / "CASES.md").write_text(_cases_markdown() + "\n", encoding="utf-8")
    n_steps = sum(len(c["steps"]) for c in CASES)
    n_en = sum(1 for c in CASES if c["message"].isascii())
    n_ho = sum(len(c["steps"]) for c in HOLDOUT_CASES)
    print(f"wrote world.json, cases.json, CASES.md: {len(CASES)} cases, {n_steps} steps (EN {n_en} / JA {len(CASES) - n_en})"
          f" + holdout {len(HOLDOUT_CASES)} cases, {n_ho} steps")


if __name__ == "__main__":
    main()
