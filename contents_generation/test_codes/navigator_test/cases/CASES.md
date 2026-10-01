# 探索役の評価ケース一覧(build_cases.pyから自動生成、直接編集しない)

## 地図(1周目に毎回見せるもの)

今日: 2026-09-30

```
C1: CS 161 Data Structures — 2026 Spring — 11 lectures (2026-04-02 – 2026-05-07) — recorded in English, notes in English
C2: Intro Microeconomics — 2026 Spring — 9 lectures (2026-04-01 – 2026-04-29) — recorded in English, notes in English
C3: Biology 101 — 2026 Spring — 10 lectures (2026-04-01 – 2026-05-04) — recorded in English, notes in Japanese
C4: Linear Algebra — 2026 Fall — 7 lectures (2026-09-02 – 2026-09-29) — recorded in English, notes in English
C5: Robotics Seminar — term not set — 4 lectures (2026-09-03 – 2026-09-24) — recorded in English, notes in English

P1 (2026-09-28) AVL木の回転の練習
P2 (2026-09-26) モーター制御のPIDゲイン調整 → Ironcladのモーターが発振する
P3 (2026-09-24) インターン探しの相談 → インターンの探し方
P4 (2026-09-22) 税の弾力性とテスト対策 → 弾力性の計算練習 → 税の負担の練習
P5 (2026-09-20) Ironclad Roboticsのドライブ方式 → ドライブ方式の比較 → モーターの選び方 → ロボ部の経験を履歴書に書く → 面接の練習
P6 (2026-09-18) 英語のレポートの書き方
P7 (2026-09-15) 細胞呼吸のラボレポート → ラボレポートの構成 → 考察の書き方
P8 (2026-09-12) 専攻の迷い：ハードかソフトか
P9 (2026-09-10) Pythonの再帰とループ
P10 (2026-09-08) 週末の過ごし方
P11 (2026-09-06) 眠れないときの対策
P12 (2026-09-05) 線形代数の行列の掛け算
P13 (2026-09-03) サークルの新歓
P14 (2026-09-01) Gitの使い方
P15 (2026-08-29) 日本と米国の大学の違い
P16 (2026-08-27) 期末の勉強計画
P17 (2026-08-25) 好きな映画の話
P18 (2026-08-22) C言語のポインタ
P19 (2026-08-20) ボランティアの話
P20 (2026-08-18) ルームメイトとの付き合い方
```

講義`C*/L*`は、タイトルを見せなくても最初から選べる。文字起こしの範囲`C*/L*/s…`は、Deep Noteの引用か検索結果に出てから選べる。

## 1. `outline_heap_insert` (lecture.outline)
> 前に授業でやったヒープへの挿入のやり方、もう一回教えて

- ねらい: 基本の3段たどり。コース → 講義 → トピックで、関係する枝だけを開けるか(2周目以降はコースから入った場合の状態)。
- **1周目**:
  - find lecture.concept [heap | insert] 絞り込み: なし | C1 (past_reference)
  - ［遠回り］open C1 (past_reference)
- **2周目**(開いた: C1):
  - open C1/L3 (past_reference)
- **3周目**(開いた: C1, C1/L3):
  - open C1/L3/T2 (past_reference)
  - 終わり(トピックの要約で足りると判断してもよい)
- **4周目**(開いた: C1, C1/L3, C1/L3/T2):
  - 終わり

## 2. `outline_known_lecture` (lecture.outline)
> In CS161 lecture 6 we did AVL rotations, and I'm still fuzzy on LR vs RL.

- ねらい: 「lecture 6(第6回)」と言われたら、コースを開かずに講義へ直接行けるか。(録音し忘れた回があると教授の数え方とずれるので、開いた回のタイトルが合わなければ隣を開く、とプロンプトに書く)
- **1周目**:
  - open C1/L6 (past_reference)
  - ［遠回り］open C1/L6 (past_reference) + (任意: find lecture.concept [LR | RL | rotation] 絞り込み: なし | C1 | C1/L6 (past_reference))  ※講義を開きつつ同じ周で検索もする
  - ［遠回り］find lecture.concept [LR | RL | rotation | AVL] 絞り込み: C1 | C1/L6 (past_reference)  ※講義番号が分かっているのに検索から入る(遠回り)
  - ［遠回り］open C1 (past_reference)
- **2周目**(開いた: C1/L6):
  - open C1/L6/T4 (past_reference) + (任意: open C1/L6/T3 (past_reference))
- **3周目**(開いた: C1/L6, C1/L6/T4):
  - 終わり
  - ［遠回り］find lecture.concept [LR | RL | rotation] layer: transcript | all / 絞り込み: C1 | C1/L6 (past_reference)  ※教授の言葉を文字起こしで確かめる(遠回り)

## 3. `outline_on_screen` (lecture.outline)
> ここの内容もうちょっと詳しく知りたい

- 状況: 画面: C2/L4
- ねらい: 画面で見ている講義を根拠に開けるか(「ここ」を画面の文脈で解決)。
- **1周目**:
  - open C2/L4 (on_screen)
- **2周目**(開いた: C2/L4):
  - いずれか1つ以上: open C2/L4/T1 (on_screen), open C2/L4/T2 (on_screen), open C2/L4/T3 (on_screen)
- **3周目**(開いた: C2/L4, C2/L4/T1, C2/L4/T2, C2/L4/T3):
  - 終わり

## 4. `outline_selected_text_enough` (lecture.outline)
> これって普通の教科書と逆だよね？

- 状況: 画面: C1/L6 / 選択: 「balance factor = height(right) − height(left)」
- ねらい: 選択テキストと一般知識で答えられるときに、取りに行きすぎないか。外の定義を確かめにWebへ行くのも可。
- **1周目**:
  - 終わり
  - find web.search [balance factor | AVL] (needs_external_info)  ※「普通の教科書」の定義を外で確かめる
  - ［遠回り］open C1/L6 (on_screen)  ※確認のために開いてもよい
  - ［遠回り］find lecture.concept [balance factor] 絞り込み: なし | C1 | C1/L6 (on_screen)  ※確認のために検索してもよい

## 5. `outline_cross_course` (lecture.outline)
> 線形代数でやった固有値って、ロボットの制御の授業と関係ある？

- ねらい: 2つのコースを同じ周で並列に開き、それぞれの該当回まで降りられるか。
- **1周目**:
  - open C4 (past_reference/likely_in_course) + open C5 (past_reference/likely_in_course)
  - find lecture.concept [eigen | stability | 固有値] (past_reference/likely_in_course)
- **2周目**(開いた: C4, C5):
  - open C4/L5 (past_reference/likely_in_course) + open C5/L3 (past_reference/likely_in_course)
- **3周目**(開いた: C4, C5, C4/L5, C5/L3):
  - 終わり
  - open C4/L5/T3 (past_reference/likely_in_course) + open C5/L3/T2 (past_reference/likely_in_course)
- **4周目**(開いた: C4, C5, C4/L5, C5/L3, C4/L5/T3, C5/L3/T2):
  - 終わり

## 6. `outline_semester_overview` (lecture.outline)
> 今学期の授業って何やったか、全体をざっと振り返りたい

- ねらい: 「今学期」を今日の日付(9/30)から解決できるか。C4は学期(2026 Fall)で、C5は学期が未設定なので講義の日付の範囲で判断する。「ざっと」なら講義の一覧で止める。
- **1周目**:
  - open C4 (explicit_request) + open C5 (explicit_request)
- **2周目**(開いた: C4, C5):
  - 終わり

## 7. `outline_all_courses` (lecture.outline)
> Can you roughly summarize what I've learned across all my classes so far?

- ねらい: 全コースの広い質問。1周で5か所(上限いっぱい)を開いて止まれるか。
- **1周目**:
  - open C1 (explicit_request) + open C2 (explicit_request) + open C3 (explicit_request) + open C4 (explicit_request) + open C5 (explicit_request)
- **2周目**(開いた: C1, C2, C3, C4, C5):
  - 終わり

## 8. `outline_compare_in_course` (lecture.outline)
> How did the professor explain the difference between heapsort and quicksort?

- ねらい: 「教授はどう説明してた」→ 検索でトピックに当て、Deep Noteの引用範囲から教授の実際の言葉(文字起こし)まで行けるか。
- **1周目**:
  - find lecture.concept [heapsort | quicksort] 絞り込み: なし | C1 (past_reference)
  - ［遠回り］open C1 (past_reference)
- **2周目**(見つかった: C1/L4/T3):
  - open C1/L4/T3 (past_reference)
- **3周目**(開いた: C1/L4/T3):
  - open C1/L4/s412-425 (past_reference) + (任意: open C1/L4/s426-431 (past_reference))
- **4周目**(開いた: C1/L4/T3, C1/L4/s412-425):
  - 終わり

## 9. `outline_professor_convention` (lecture.outline)
> AVLの平衡因子、教授の定義ってどっち向きだったっけ

- ねらい: 要約に答えが出ていれば、そこで止まってよい(教授の言葉を確かめに文字起こしを開くのも可)。
- **1周目**:
  - find lecture.concept [balance factor | AVL | 平衡因子] 絞り込み: なし | C1 (past_reference)
  - ［遠回り］open C1 (past_reference)
- **2周目**(見つかった: C1/L6/T2):
  - 終わり
  - open C1/L6/T2 (past_reference)
- **3周目**(開いた: C1/L6/T2):
  - 終わり
  - open C1/L6/s233-240 (past_reference) + (任意: open C1/L6/s241-243 (past_reference))

## 10. `outline_follow_up_next` (lecture.outline)
> じゃあその次の回は何やったんだっけ

- 状況: 前のターンで開いたもの: C1/L3
- 直前の会話:
  - user: ヒープの授業って何やったっけ
  - assistant: 4月9日のBinary Heapsの回では、配列で表す完全二分木としてのヒープ、挿入(bubble up)、extract-min、O(n)でのheapifyを扱ったよ。
- ねらい: 前のターンで開いた講義(C1/L3)から「次の回」を解決できるか。
- **1周目**:
  - open C1/L4 (past_reference)
  - ［遠回り］open C1 (past_reference)  ※コースを開いて確認する(遠回り)

## 11. `outline_follow_up_third` (lecture.outline)
> Tell me more about the third one.

- 状況: 前のターンで開いたもの: C2
- 直前の会話:
  - user: Which econ lectures were about elasticity?
  - assistant: Three of your Intro Microeconomics lectures deal with elasticity: / 1. Price Elasticity of Demand (Apr 10) / 2. Price Elasticity of Supply (Apr 15) / 3. Taxes (Apr 17) — who bears a tax depends on the elasticities.
- ねらい: 前の回答で見せた一覧の3番目。一覧は弾力性に関係する回だけ(第4・5・6回)なので、答えはC2/L3ではなくC2/L6。文脈で指す先が変わる言葉を、番号の思い込みではなく直前の会話で解決できるか。
- **1周目**:
  - open C2/L6 (past_reference)
- **2周目**(開いた: C2/L6):
  - 終わり
  - いずれか1つ以上: open C2/L6/T1 (past_reference), open C2/L6/T2 (past_reference), open C2/L6/T3 (past_reference)

## 12. `outline_pronoun_that_lecture` (lecture.outline)
> その授業で、教授はオーバーシュートについて何か言ってた？

- 状況: 前のターンで開いたもの: C5/L2
- 直前の会話:
  - user: ロボティクスのPIDの授業って、どんな内容だった？
  - assistant: 9月10日のPID Controlの回では、DCモーターのモデル化、P・I・Dそれぞれの役割、そしてゲイン調整とオーバーシュートの話をしていたよ。トピックは「DC motor model」「P, I, D terms」「Tuning and oscillation」の3つ。
- ねらい: 「その授業」を直前の会話と前のターンで開いたもの(C5/L2)で解決できるか。絞らずに全体を検索したり、別の授業を開いたりしない。
- **1周目**:
  - open C5/L2/T3 (past_reference)
  - find lecture.concept [overshoot | オーバーシュート] 絞り込み: C5/L2 | C5 (past_reference)  ※その回の中に絞って検索
- **2周目**(開いた: C5/L2/T3):
  - 終わり
  - ［遠回り］find lecture.concept [overshoot | オーバーシュート] layer: transcript | all / 絞り込み: C5 | C5/L2 (past_reference)  ※教授の言葉を文字起こしで確かめる(遠回り)

## 13. `date_explicit` (lecture.by_date)
> What did we cover in econ on April 10?

- ねらい: 日付での参照は、日付で引く道具で一発。コースを開いて日付を読むのは遠回り。
- **1周目**:
  - by_date 2026-04-10 絞り込み: なし | C2 (past_reference)
  - ［遠回り］open C2 (past_reference)
  - ［遠回り］open C2/L4 (past_reference)  ※地図の日付範囲と回数から当てた
- **2周目**(見つかった: C2/L4):
  - open C2/L4 (past_reference)
- **3周目**(開いた: C2/L4):
  - 終わり

## 14. `date_yesterday` (lecture.by_date)
> I zoned out in yesterday's class. Can you catch me up?

- ねらい: 「昨日」を今日の日付から解決し、コースが分からなくても日付だけで引けるか。
- **1周目**:
  - by_date 2026-09-29 (past_reference)
  - ［遠回り］open C4 (past_reference) + open C5 (past_reference)  ※今学期のコースを開いて日付を読む
- **2周目**(見つかった: C4/L7):
  - open C4/L7 (past_reference)
- **3周目**(開いた: C4/L7):
  - 終わり
  - いずれか1つ以上: open C4/L7/T1 (past_reference), open C4/L7/T2 (past_reference), open C4/L7/T3 (past_reference)

## 15. `concept_vague_in_course` (lecture.concept)
> エントロピーって生物の授業で出てきた気がするんだけど

- ねらい: 講義タイトルに出てこない概念は、類似検索で当てに行けるか(生物の中に絞ってもよい)。生物のまとめは日本語。
- **1周目**:
  - find lecture.concept [entropy | エントロピー | 熱力学] 絞り込み: なし | C3 (past_reference)
  - ［遠回り］open C3 (past_reference)  ※コースを開いて探す
- **2周目**(見つかった: C3/L10):
  - 終わり
  - open C3/L10 (past_reference)

## 16. `concept_ja_question_en_lectures` (lecture.concept)
> 二分探索木の削除で、子が2つあるときの手順ってどうだったっけ

- ねらい: 講義は英語。日本語の質問から、英語の検索語を作れるか(検索語にdelete/successor/BST等が入るか)。
- **1周目**:
  - find lecture.concept [delet | successor | BST | binary search tree] (past_reference)
  - ［遠回り］open C1 (past_reference)

## 17. `concept_term_then_done` (lecture.concept)
> The term 'tax incidence' came up in class. What did it mean again?

- ねらい: 当たった断片で足りれば止まる。足りなければ当たった場所を開く。
- **1周目**:
  - find lecture.concept [tax incidence] (past_reference)
  - ［遠回り］open C2 (past_reference)
- **2周目**(見つかった: C2/L6/T2):
  - 終わり
  - open C2/L6/T2 (past_reference)

## 18. `concept_scoped_search` (lecture.concept)
> In econ, where did the professor talk about insulin?

- ねらい: コース名が言われていて概念もはっきりしているなら、そのコースに絞った類似検索が一番早い。
- **1周目**:
  - find lecture.concept [insulin] 絞り込み: C2 (past_reference)
  - find lecture.concept [insulin] 絞り込み: なし (past_reference)  ※絞らなくても当たる
  - ［遠回り］open C2 (past_reference)
- **2周目**(見つかった: C2/L4/T2):
  - 終わり
  - open C2/L4/T2 (past_reference)

## 19. `concept_in_course_no_reference` (lecture.concept)
> クイックソートの最悪計算量ってどれくらい？

- ねらい: 授業への言及は無いが、CS161で習う概念。取りに行っても行かなくてもよいが、取るなら根拠はlikely_in_course。
- **1周目**:
  - 終わり
  - find lecture.concept [quicksort] (likely_in_course)
  - ［遠回り］open C1 (likely_in_course)

## 20. `transcript_side_remark` (lecture.transcript)
> 教授が前に言ってた『ガウスの消去法の裏技』ってなんだっけ

- ねらい: 授業中の一言は要約やトピックに残らない。文字起こしを検索できるか。
- **1周目**:
  - find lecture.concept [Gauss | elimination | trick | pivot | ガウス] layer: transcript | all / 絞り込み: なし | C4 | C4/L2 (past_reference)
  - ［遠回り］open C4 (past_reference)  ※目次をたどっても『裏技』は要約に出てこない
- **2周目**(見つかった: C4/L2/s518-526):
  - 終わり
  - open C4/L2/s518-526 (past_reference)

## 21. `transcript_nobel_in_class` (lecture.transcript)
> 授業で教授がノーベル物理学賞の話をしてたんだけど、あれってどんな研究だったの？詳しく知りたい

- ねらい: 授業での発言(文字起こし)と外の詳しい情報(Web)を組み合わせる。コースや講義のタイトルからは絶対に推測できない。
- **1周目**:
  - find lecture.concept [Nobel | ノーベル] layer: transcript | all (past_reference) + find web.search [Nobel] (needs_external_info/explicit_request)
  - find lecture.concept [Nobel | ノーベル] layer: transcript | all (past_reference)  ※先に授業の発言を確かめてからWeb
- **2周目**(見つかった: C5/L4/s801-806):
  - find web.search [Nobel | quantum tunneling | superconducting] (needs_external_info/explicit_request)
- **3周目**(見つかった: C5/L4/s801-806, W1):
  - 終わり
  - open W1 (needs_external_info/explicit_request)

## 22. `transcript_professor_wording` (lecture.transcript)
> ここ、教授は実際にはなんて言ってたの？

- 状況: 画面: C1/L6/T2 / 選択: 「Standard textbooks use left − right, so signs are flipped.」
- ねらい: 画面のDeep Noteから、引用範囲をたどって一次情報(文字起こし)を開けるか。
- **1周目**:
  - open C1/L6/T2 (on_screen)
- **2周目**(開いた: C1/L6/T2):
  - いずれか1つ以上: open C1/L6/s233-240 (on_screen), open C1/L6/s241-243 (on_screen)
- **3周目**(開いた: C1/L6/T2, C1/L6/s233-240, C1/L6/s241-243):
  - 終わり

## 23. `chat_title_match` (chat.all)
> I think I asked you about finding internships a while back. What did you recommend?

- ねらい: 地図(最近20件)のタイトルで分かるなら、そのスレッドを開く。
- **1周目**:
  - open P3 (past_reference)
  - ［遠回り］find chat.all [インターン | intern] (past_reference)
- **2周目**(開いた: P3):
  - 終わり

## 24. `chat_vague_older` (chat.all)
> 前にこんなこと話した気がするんだけど…奨学金のエッセイで自分の強みをどう書くか、みたいな

- ねらい: 最近20件に無い曖昧な参照は、目次ではなく類似検索(合意済みの方針)。
- **1周目**:
  - find chat.all [奨学金 | scholarship | 強み | エッセイ | essay] (past_reference)
- **2周目**(見つかった: P31):
  - 終わり
  - open P31 (past_reference)

## 25. `chat_recent_exercise` (chat.all)
> この前チャットでAVLの回転練習したじゃん、あのときの例の木ってどんなだったっけ

- ねらい: 「チャットで」と明言されたら、講義ではなくチャットを開く。
- **1周目**:
  - open P1 (past_reference)
  - ［遠回り］find chat.all [AVL] (past_reference)  ※地図のP1で分かるので遠回り
- **2周目**(開いた: P1):
  - 終わり

## 26. `chat_talked_before` (chat.all)
> この前話したよね、ラボレポートの考察って何を書けばいいんだっけ

- ねらい: 「チャットで」と言わなくても、「この前話したよね」はチャット(AIと話したこと)を指す。講義(細胞呼吸)には行かない。
- **1周目**:
  - open P7 (past_reference)
  - ［遠回り］find chat.all [ラボレポート | 考察 | lab report] (past_reference)
- **2周目**(開いた: P7):
  - 終わり

## 27. `chat_practiced_together` (chat.all)
> 一緒に練習した弾力性の問題、同じ形式でもう何問か出して

- ねらい: 「一緒に練習した」はチャットでの練習。形式を知るためにそのチャットを開く(講義を開くのは不正解)。
- **1周目**:
  - open P4 (past_reference)
  - ［遠回り］find chat.all [弾力性 | elasticity] (past_reference)
- **2周目**(開いた: P4):
  - 終わり

## 28. `chat_topic_drift` (chat.all)
> You helped me practice for interviews at some point. What did you say I should fix?

- ねらい: タイトル(ドライブ方式)と後半の話題(面接の練習)がずれているチャット。地図の「流れ」から当てられるか。
- **1周目**:
  - open P5 (past_reference)
  - ［遠回り］find chat.all [interview | 面接] (past_reference)
- **2周目**(開いた: P5):
  - 終わり

## 29. `chat_and_lecture_same_lap` (chat.all)
> We talked in chat about my robotics club motor oscillating. How does that relate to the PID lecture?

- ねらい: 違う出どころ(チャットと講義)を同じ周で開けるか。スレッドは節の一覧しか見えないので、節(P2/S1)まで開いて往復をたどってもよい。
- **1周目**:
  - open P2 (past_reference) + open C5 (past_reference)
  - open P2 (past_reference) + find lecture.concept [PID] 絞り込み: なし | C5 (past_reference)
- **2周目**(開いた: P2, C5):
  - open C5/L2 (past_reference) + (任意: open P2/S1 (past_reference))
- **3周目**(開いた: P2, C5, C5/L2):
  - 終わり
  - open C5/L2/T3 (past_reference) + (任意: open P2/S1 (past_reference))
  - open P2/S1 (past_reference) + (任意: open C5/L2/T3 (past_reference))

## 30. `thread_section_ref` (chat.thread)
> 最初の方で見せてくれたfactorialのコード、n<=1にした版ってどう書くんだっけ

- 状況: 会話: thread_code
- ねらい: この会話の畳まれた部分を、節の呼び名で開けるか。節を開くと往復の一覧が出るので、正確なコードが要るならその往復を開いてよい。
- **1周目**:
  - open S1 (past_reference)
- **2周目**(開いた: S1):
  - 終わり
  - いずれか1つ以上: open S1/T1 (past_reference), open S1/T2 (past_reference)  ※節の往復の一覧から、コードの往復の全文を開く

## 31. `thread_vague_ref` (chat.thread)
> 結構前に言ってた、ファームウェアに必要な授業って何だっけ

- 状況: 会話: thread_career
- ねらい: 要約(回答役にも渡る)にもう答えがあるので開かずに終えてよい。「結構前」が別の会話の可能性もあるのでchat.allも可。節から往復の全文まで開くのも正解。
- **1周目**:
  - 終わり
  - open S3 (past_reference)
  - ［遠回り］find chat.thread [ファームウェア | firmware] (past_reference)
  - ［遠回り］find chat.all [ファームウェア | firmware] (past_reference)  ※「結構前」が別の会話かもしれない
  - ［遠回り］open P8 (past_reference)  ※専攻の迷いのチャットで話したかもしれない
- **2周目**(開いた: S3):
  - 終わり
  - いずれか1つ以上: open S3/T7 (past_reference), open S3/T8 (past_reference), open S3/T9 (past_reference), open S3/T10 (past_reference)  ※節を開くと往復の一覧が出るので、その往復の全文を開いてよい

## 32. `thread_terse_in_context` (chat.thread)
> ファームウェアに必要な授業は何？

- 状況: 会話: thread_career
- ねらい: 過去への言及が無い短い質問。この会話の要約(回答役にも渡る)に答えがあるので、取りに行かなくてよい。
- **1周目**:
  - 終わり
  - ［遠回り］open S3 (past_reference/likely_in_course)  ※要約で足りるので遠回り

## 33. `thread_recent_no_fetch` (chat.thread)
> じゃあpivotをランダムに選ぶと何が嬉しいの？

- 状況: 会話: thread_code
- ねらい: 直近の原文で話している内容なら、何も取りに行かない。
- **1周目**:
  - 終わり

## 34. `long_thread_condensed_enough` (chat.thread)
> だいぶ前にこの会話でAVLの回転を練習したよね、あのとき使った例の木ってどんなだったっけ

- 状況: 会話: thread_long
- ねらい: 長い会話の古い部分(2段目H1)を開くと、中の節(S1〜S5)の箇条書きが見える。例の木はS3の箇条書きにあるので、そこで止まれるか。
- **1周目**:
  - open H1 (past_reference)
  - ［遠回り］find chat.thread [AVL] (past_reference)
- **2周目**(開いた: H1):
  - 終わり
  - ［遠回り］open S3 (past_reference)  ※節の箇条書きに木があるので遠回り

## 35. `long_thread_drill_to_turn` (chat.thread)
> この会話のずっと前の方で見せてくれたfactorialの再帰のコード、もう一回そのまま見せて

- 状況: 会話: thread_long
- ねらい: コードそのものは要約に無いので、2段目H1 → 1段目S2 → 往復の全文、とたどれるか。
- **1周目**:
  - open H1 (past_reference)
  - ［遠回り］find chat.thread [factorial] (past_reference)
- **2周目**(開いた: H1):
  - open S2 (past_reference)
- **3周目**(開いた: H1, S2):
  - いずれか1つ以上: open S2/T5 (past_reference), open S2/T6 (past_reference), open S2/T7 (past_reference), open S2/T8 (past_reference), open S2/T9 (past_reference)

## 36. `web_explicit` (web.search)
> Can you look up when applications close for Google's summer 2027 SWE internship?

- ねらい: 「調べて」と明示されたらWebへ。
- **1周目**:
  - find web.search [Google | intern] (explicit_request)
- **2周目**(見つかった: W1, W2):
  - 終わり
  - open W1 (explicit_request)
  - ［遠回り］open W1 (explicit_request) + open W2 (explicit_request)  ※両方読んでから答える

## 37. `web_current_info` (web.search)
> 今年のノーベル物理学賞って誰がとったの？

- ねらい: 明示の依頼は無いが、最新の事実が要る。Webは必須(根拠はneeds_external_info)。
- **1周目**:
  - find web.search [Nobel | ノーベル] (needs_external_info)

## 38. `web_not_needed_course_topic` (web.search)
> 光合成の明反応と暗反応の違いって何？

- ねらい: 一般知識で答えられ、授業(Biology 101)にもある。Webには行かない。取るなら類似検索が早い。
- **1周目**:
  - 終わり
  - find lecture.concept [photosynthesis | light | Calvin | 光合成 | 明反応 | カルビン] (likely_in_course)
  - ［遠回り］open C3 (likely_in_course)

## 39. `web_and_lecture` (web.search)
> 授業でやったB-treeって、実際のPostgreSQLではどう使われてるか調べてみて

- ねらい: Webと講義を同じ周で並列に。
- **1周目**:
  - find web.search [PostgreSQL] (explicit_request) + いずれか1つ以上: open C1 (past_reference), find lecture.concept [B-tree | btree | B tree] 絞り込み: なし | C1 (past_reference)
- **2周目**(開いた: C1; 見つかった: W1):
  - open C1/L8 (past_reference)
  - 終わり
  - ［遠回り］open C1/L8 (past_reference) + open W1 (past_reference)  ※講義とWebの中身を両方読む
- **3周目**(開いた: C1, C1/L8; 見つかった: W1):
  - 終わり
  - ［遠回り］open W1 (past_reference)  ※Webの中身も読む

## 40. `web_limit_reached` (web.search)
> 来年のICPCアジア地区予選の日程ってもう決まってる？調べて

- ねらい: Web検索を2回使い切ったら、それ以上は探さない(web.searchはenumから消える)。講義やチャットに探しに行かない。
- **1周目**:
  - find web.search [ICPC] (explicit_request/needs_external_info)
- **2周目**(見つかった: W1, W2):
  - 終わり
  - find web.search [ICPC | 2027] (explicit_request/needs_external_info)  ※言葉を変えて1回だけ検索し直す
  - ［遠回り］いずれか1つ以上: open W1 (explicit_request), open W2 (explicit_request)  ※断片では日程が分からないので開いてみる
- **3周目**(見つかった: W1, W2, W3):
  - 終わり
  - ［遠回り］いずれか1つ以上: open W1 (explicit_request), open W3 (explicit_request)

## 41. `none_personal` (none)
> 最近疲れてて夜あんまり眠れないんだよね

- ねらい: 個人的な話。授業にもWebにも行かない。
- **1周目**:
  - 終わり

## 42. `none_hobby` (none)
> Can we talk about anime? I've been watching Frieren lately.

- ねらい: 授業と関係ない趣味の話。
- **1周目**:
  - 終わり

## 43. `none_general_knowledge` (none)
> Is recursion or iteration faster?

- ねらい: 一般知識で答えられる。過去への言及が無いので、最近のチャット(P9 Pythonの再帰とループ)があっても開かない。
- **1周目**:
  - 終わり

## 44. `none_terse_no_pointer` (none)
> ファームウェアに必要な授業は何？

- ねらい: 過去への言及が無い短い質問(新しい会話)。どこかにあるかもしれないが、手がかりが無いので探さずに一般的に答える。
- **1周目**:
  - 終わり

## 45. `none_tangent_aha_candidate` (none)
> I just started running and I get out of breath so fast. Why does that happen?

- ねらい: 授業(細胞呼吸)とのAHAの候補。取るのは許すが、関係は必ずpossible_link(回答で無理に結びつけない)。
- **1周目**:
  - 終わり
  - find lecture.concept [respiration | anaerobic | oxygen | lactate | 呼吸 | 乳酸 | 酸素] (likely_in_course, possible_link)

## 46. `none_thanks` (none)
> なるほど、ありがとう！

- ねらい: お礼だけ(本来は仕分け役で止まるが、来ても何もしない)。
- **1周目**:
  - 終わり

## 47. `stop_when_not_found` (stop)
> What was the name of the book the econ professor recommended?

- ねらい: 探しても無いときに、周を使い切らずに止まれるか。見つからないことは回答役に正直に伝える(ゴールに書く)。
- **1周目**:
  - find lecture.concept [book | recommend | reading] layer: transcript | all / 絞り込み: なし | C2 (past_reference)
  - ［遠回り］open C2 (past_reference)
- **2周目**(見つかった: C2/L8, C2/L9):
  - 終わり
  - find lecture.concept [book | reading | textbook | author] layer: transcript | all / 絞り込み: なし | C2 (past_reference)  ※言い方を変えてもう一度
  - ［遠回り］open C2 (past_reference)
- **3周目**(見つかった: C2/L8, C2/L9, C2/L1):
  - 終わり
  - ［遠回り］open C2 (past_reference)
- **4周目**(開いた: C2; 見つかった: C2/L8, C2/L9, C2/L1):
  - 終わり

---

# 確認用のケース(プロンプトの調整には使わない)

## 48. `ho_none_venting` (none)
> 課題が多すぎてもう無理…

- ねらい: 気持ちの吐露。何も取らない。
- **1周目**:
  - 終わり

## 49. `ho_none_general` (none)
> What's the difference between a process and a thread?

- ねらい: 一般知識。OSのコースは無いので、講義にも行かない。
- **1周目**:
  - 終わり

## 50. `ho_none_caffeine` (none)
> 最近コーヒー飲みすぎて眠れない、カフェインってどう効くの？

- ねらい: 個人的な話+一般知識。関係するコースは無い。
- **1周目**:
  - 終わり

## 51. `ho_context_last_one` (lecture.outline)
> What was the last one about again?

- 状況: 前のターンで開いたもの: C4
- 直前の会話:
  - user: What have we covered in linear algebra so far?
  - assistant: Seven lectures so far: 1. Vectors and Matrices, 2. Linear Systems, 3. Determinants, 4. Vector Spaces, 5. Eigenvalues, 6. Diagonalization, 7. Orthogonality (yesterday).
- ねらい: 前の回答で見せたC4の一覧の最後(第7回)。
- **1周目**:
  - open C4/L7 (past_reference)

## 52. `ho_context_previous` (lecture.outline)
> その前の回って何やったっけ

- 状況: 前のターンで開いたもの: C1/L8
- 直前の会話:
  - user: B-treeの回ってどんな内容だった？
  - assistant: 4月25日のB-Treesの回では、データベース向けのB木とB+木、ディスクのブロックに収まる次数(100〜200)、葉をつなぐと範囲検索が速くなる話をしていたよ。
- ねらい: 前のターンで開いたB-treeの回(C1/L8)の「その前の回」。B-treesにはトピックが無いので、previous_turn_openedの一段下にも並び順の手がかりが無い(直前の番号からの推測か、コースを開いての確認)。
- **1周目**:
  - open C1/L7 (past_reference)
  - ［遠回り］open C1 (past_reference)  ※コースを開いて順番を確認する

## 53. `ho_date_last_week` (lecture.by_date)
> 先週のロボティクスの授業の内容をまとめて

- ねらい: 「先週」を今日の日付から範囲に直す(週の区切りはどれでもよい)。
- **1周目**:
  - by_date 2026-09-21〜2026-09-27 絞り込み: なし | C5 (past_reference/explicit_request)
  - by_date 2026-09-20〜2026-09-26 絞り込み: なし | C5 (past_reference/explicit_request)
  - by_date 2026-09-22〜2026-09-28 絞り込み: なし | C5 (past_reference/explicit_request)
  - by_date 2026-09-23〜2026-09-29 絞り込み: なし | C5 (past_reference/explicit_request)
  - open C5/L4 (past_reference/explicit_request)  ※地図の日付範囲の最後が9/24
  - ［遠回り］open C5 (past_reference/explicit_request)

## 54. `ho_transcript_anecdote` (lecture.transcript)
> In linear algebra the professor told a story about a bridge collapsing. What was that about?

- ねらい: 授業中の逸話は要約に残らない。文字起こしを検索する。
- **1周目**:
  - find lecture.concept [bridge | collapse | Tacoma] layer: transcript | all / 絞り込み: なし | C4 (past_reference)

## 55. `ho_chat_pointers` (chat.all)
> Remember when we went over pointers in C? Can you show me that example again?

- ねらい: 「we went over」はAIとの会話。地図のP18を開く。
- **1周目**:
  - open P18 (past_reference)
  - ［遠回り］find chat.all [pointer | ポインタ] (past_reference)

## 56. `ho_ja_notes_search` (lecture.concept)
> In bio, what did we learn about how temperature affects enzymes?

- ねらい: 英語の質問だが、生物のまとめは日本語。日本語で検索できるか(英語の検索を並べるのは可)。
- **1周目**:
  - find lecture.concept [酵素 | 温度 | 変性] 絞り込み: なし | C3 (past_reference) + (任意: find lecture.concept [enzyme | temperature] 絞り込み: なし | C3 (past_reference))
  - ［遠回り］open C3 (past_reference)

## 57. `ho_stop_nothing_more` (lecture.concept)
> ダイクストラ法って授業でどう説明されてた？

- ねらい: 講義にトピックもDeep Noteも無いとき、開ける先が尽きたら止まる(文字起こしを確かめに行くのは遠回りとして許容)。
- **1周目**:
  - find lecture.concept [Dijkstra | shortest path] 絞り込み: なし | C1 (past_reference)
  - ［遠回り］open C1 (past_reference)
- **2周目**(見つかった: C1/L11):
  - open C1/L11 (past_reference)
  - 終わり
- **3周目**(開いた: C1/L11):
  - 終わり
  - ［遠回り］find lecture.concept [Dijkstra | shortest path] layer: transcript | all / 絞り込み: C1 | C1/L11 (past_reference)  ※教授の言葉を文字起こしで確かめる(遠回り)

## 58. `ho_web_release` (web.search)
> Is Python 3.14 out yet?

- ねらい: 最新の事実。Webへ。
- **1周目**:
  - find web.search [Python 3.14 | Python] (needs_external_info)

