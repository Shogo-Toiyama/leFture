# contents_generation/test_codes/summary_token_trigger_test.py
"""
20,000トークン閾値によるサマリー折りたたみロジックの単体・挙動シミュレーションテスト。
検証項目:
1. should_fold_summary の判定条件 (15往復 or 20,000トークン)
2. select_fold_batch によるバッチ選択の正確性
3. 常に完全な PairTurn (Turn: user + assistant) 単位で処理され、AI返答が抜けた不完全なターンが決して畳まれないことの検証
"""

import sys
from pathlib import Path

# Add lefture_backend to sys.path
backend_path = Path(__file__).resolve().parent.parent.parent / "lefture_backend"
sys.path.insert(0, str(backend_path))

from app.services.chat_summary import (
    Turn,
    FOLD_TRIGGER_TURNS,
    FOLD_SIZE_TURNS,
    FOLD_TRIGGER_TOKENS,
    KEEP_RECENT_TURNS_ON_TOKEN_OVERFLOW,
    should_fold_summary,
    select_fold_batch,
    turn_tokens,
    turns_total_tokens,
    pair_turns,
)
from app.services.chat_attachments import estimate_tokens


def make_turn(number: int, user_text: str, assistant_text: str) -> Turn:
    return Turn(
        number=number,
        user_message_id=f"user_msg_{number}",
        assistant_message_id=f"asst_msg_{number}",
        user_content=user_text,
        assistant_content=assistant_text,
        assistant_created_at="2026-10-23T12:00:00Z",
        reply_language="ja",
    )


def test_standard_turn_count_trigger():
    print("--- Test 1: Standard 15-Turn Trigger ---")
    # 14 turns of short text (~100 tokens each)
    turns_14 = [make_turn(i, f"User question {i}", f"AI answer {i}") for i in range(1, 15)]
    assert not should_fold_summary(turns_14), "14 short turns should NOT trigger folding"

    turns_15 = [make_turn(i, f"User question {i}", f"AI answer {i}") for i in range(1, 16)]
    assert should_fold_summary(turns_15), "15 turns MUST trigger folding"

    batch = select_fold_batch(turns_15)
    assert len(batch) == FOLD_SIZE_TURNS == 10, f"Expected 10 turns folded, got {len(batch)}"
    assert batch[0].number == 1 and batch[-1].number == 10
    print("✅ Test 1 Passed: 15 turns triggers folding of turns 1-10.")


def test_token_overflow_trigger_at_13_turns():
    print("\n--- Test 2: Token Overflow Trigger (e.g. 13 turns, >20,000 tokens) ---")
    # Simulate 13 turns where average turn is ~1,600 tokens (~20,800 tokens total)
    # Long text: 1000 characters of Japanese is ~1000 tokens
    long_reply = "これは長文の解説です。" * 150 # ~1650 chars / tokens
    turns_13 = [
        make_turn(i, f"質問 {i}", f"回答 {i}: {long_reply}")
        for i in range(1, 14)
    ]
    total_tokens = turns_total_tokens(turns_13)
    print(f"Total tokens for 13 turns: {total_tokens:,}")
    assert total_tokens >= FOLD_TRIGGER_TOKENS, f"Tokens should exceed {FOLD_TRIGGER_TOKENS}"
    assert should_fold_summary(turns_13), "Should trigger folding because tokens >= 20,000"

    batch = select_fold_batch(turns_13)
    # We have 13 turns. We want to keep recent 5 turns (Turns 9, 10, 11, 12, 13) unsummarized.
    # Therefore, we fold 13 - 5 = 8 turns (Turns 1 to 8).
    assert len(batch) == 8, f"Expected 8 turns folded, got {len(batch)}"
    assert batch[0].number == 1 and batch[-1].number == 8
    # Verify that the unsummarized remaining turns would be 9 to 13 (5 complete turns)
    remaining = turns_13[len(batch):]
    assert len(remaining) == 5
    assert remaining[0].number == 9 and remaining[-1].number == 13
    print("✅ Test 2 Passed: 13 turns with >20,000 tokens correctly folds turns 1-8 and preserves turns 9-13 in full!")


def test_extreme_few_turns_token_overflow():
    print("\n--- Test 3: Extreme Few Turns Token Overflow (e.g. 3 turns, >20,000 tokens) ---")
    huge_reply = "超長文の回答です。" * 800 # ~7200 tokens
    turns_3 = [
        make_turn(i, f"質問 {i}", f"回答 {i}: {huge_reply}")
        for i in range(1, 4)
    ]
    total_tokens = turns_total_tokens(turns_3)
    print(f"Total tokens for 3 huge turns: {total_tokens:,}")
    assert should_fold_summary(turns_3)

    batch = select_fold_batch(turns_3)
    # len(turns) = 3. keep_count = min(5, max(1, 2)) = 2.
    # fold_count = 3 - 2 = 1. Folds Turn 1, keeps Turns 2 & 3.
    assert len(batch) == 1
    assert batch[0].number == 1
    print("✅ Test 3 Passed: Even with only 3 turns, recent turns are protected and at least 1 turn is folded.")


def test_guarantee_no_asymmetric_folding():
    print("\n--- Test 4: Guarantee that Incomplete Turns (AI response missing) Can Never Be Folded ---")
    # Simulate DB rows: 12 complete turns, plus a 13th turn where user sent a huge question (e.g. 25,000 tokens)
    # but AI has not completed or is not paired yet.
    rows = []
    for i in range(1, 13):
        rows.append({"id": f"u{i}", "role": "user", "content": f"Q{i}"})
        rows.append({"id": f"a{i}", "role": "assistant", "content": f"A{i}", "status": "complete"})
    
    # 13th user message (massive user input, pending or streaming, no completed assistant message)
    rows.append({"id": "u13", "role": "user", "content": "巨大な質問" * 5000})

    # When paired:
    paired = pair_turns(rows)
    assert len(paired) == 12, "Unanswered user message MUST be excluded from Turn pairs"
    
    for t in paired:
        assert t.user_message_id is not None
        assert t.assistant_message_id is not None
        assert t.assistant_content is not None
        assert not t.assistant_message_id.startswith("user_")

    print(f"Paired count: {len(paired)} (13th pending user message safely excluded)")
    print("✅ Test 4 Passed: AI responses can NEVER be omitted; folding only operates on complete PairTurns.")


if __name__ == "__main__":
    test_standard_turn_count_trigger()
    test_token_overflow_trigger_at_13_turns()
    test_extreme_few_turns_token_overflow()
    test_guarantee_no_asymmetric_folding()
    print("\n🎉 ALL TESTS PASSED SUCCESSFULLY!")
