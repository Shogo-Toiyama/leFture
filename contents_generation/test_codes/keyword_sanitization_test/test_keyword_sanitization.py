import os, json, re
from dotenv import load_dotenv
load_dotenv('lefture_backend/.env')
from supabase import create_client
import sys
sys.path.insert(0, 'lefture_backend')

from app.services.helpers.helpers import _extract_keyword_for_recording_language, _get_sentence_review_context

def run_tests():
    supabase = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_SECRET_KEY'])
    
    # 1. Edge Case Inputs Test
    edge_cases = [
        (None, "en", None),
        ("", "en", None),
        ("   ", "en", None),
        (12345, "en", None),
        ({}, "en", None),
        ([], "en", None),
        ("Nested ((double))", "en", "Nested"),
        ("入れ子ブロック（nested blocks）", "en", "nested blocks"),
        ("入れ子ブロック（nested blocks）", "ja", "入れ子ブロック"),
        ("Translation (平行移動)", "en", "Translation"),
        ("Translation (平行移動)", "ja", "平行移動"),
        ("法線 (Normal)", "en", "Normal"),
        ("法線 (Normal)", "ja", "法線"),
        ("Programmed I/O (PIO)", "en", "Programmed I/O"),
        ("Programmed I/O (PIO)", "ja", "Programmed I/O"),
        ("縦長の構図", "en", None),
        ("縦長の構図", "ja", "縦長の構図"),
        ("Persistence", "en", "Persistence"),
        ("Persistence", "ja", "Persistence"),
        ("Recursion depth", "en-US", "Recursion depth"),
        ("変数のスコープ", "ja-JP", "変数のスコープ"),
    ]
    
    edge_results = []
    for kw, lang, expected in edge_cases:
        actual = _extract_keyword_for_recording_language(kw, lang)
        pass_check = (actual == expected)
        edge_results.append({
            "input": str(kw),
            "lang": lang,
            "expected": expected,
            "actual": actual,
            "passed": pass_check
        })
        assert pass_check, f"Failed on input={kw!r}, lang={lang!r}: expected={expected!r}, got={actual!r}"
    print(f"✅ Edge case tests passed ({len(edge_cases)} cases)")

    # 2. Real DB Keywords Extraction Verification
    kw_res = supabase.table("keywords").select("keyword").limit(500).execute()
    db_keywords = [r["keyword"] for r in kw_res.data if r.get("keyword")]
    print(f"Testing across {len(db_keywords)} real keywords from Supabase...")
    
    en_clean_count = 0
    en_dropped_count = 0
    ja_clean_count = 0
    
    for kw in db_keywords:
        # Test English target
        en_ext = _extract_keyword_for_recording_language(kw, "en")
        if en_ext:
            # Must NOT contain CJK characters
            has_cjk = bool(re.search(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', en_ext))
            assert not has_cjk, f"English extraction leaked CJK: {en_ext} from {kw}"
            # Must NOT contain brackets
            assert "(" not in en_ext and ")" not in en_ext and "（" not in en_ext and "）" not in en_ext, f"Brackets leaked: {en_ext} from {kw}"
            en_clean_count += 1
        else:
            en_dropped_count += 1
            
        # Test Japanese target
        ja_ext = _extract_keyword_for_recording_language(kw, "ja")
        if ja_ext:
            assert "(" not in ja_ext and ")" not in ja_ext and "（" not in ja_ext and "）" not in ja_ext, f"Brackets leaked in JA: {ja_ext} from {kw}"
            ja_clean_count += 1

    print(f"✅ DB Keywords verified: {en_clean_count} clean EN keywords, {en_dropped_count} safely excluded purely non-English, {ja_clean_count} clean JA keywords.")

    # 3. Test _get_sentence_review_context on multiple lectures
    lecs = supabase.table("lectures").select("id, course_id, recording_language, title").limit(10).execute()
    context_results = []
    for l in lecs.data:
        c_title, kw_list, rec_lang = _get_sentence_review_context(l["id"])
        # Check that no CJK leaked into English review
        if rec_lang == "en" and kw_list:
            has_cjk = bool(re.search(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af]', kw_list))
            assert not has_cjk, f"CJK leaked into sentence review context for lecture {l['id']}: {kw_list}"
            assert "（" not in kw_list and "）" not in kw_list, f"Full-width brackets leaked: {kw_list}"
        context_results.append({
            "lecture_id": l["id"],
            "course_title": c_title,
            "recording_language": rec_lang,
            "keywords_count": len(kw_list.split(", ")) if kw_list else 0,
            "keywords_sample": kw_list[:100] + "..." if len(kw_list) > 100 else kw_list
        })
    print(f"✅ _get_sentence_review_context verified on {len(lecs.data)} real lectures.")

    # Save output
    out = {
        "edge_tests": edge_results,
        "db_stats": {
            "total_tested": len(db_keywords),
            "en_clean_count": en_clean_count,
            "en_dropped_count": en_dropped_count,
            "ja_clean_count": ja_clean_count
        },
        "lectures_tested": context_results
    }
    with open("contents_generation/test_codes/keyword_sanitization_test/results/verification_result.json", "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print("✅ All results saved to contents_generation/test_codes/keyword_sanitization_test/results/verification_result.json")

if __name__ == "__main__":
    run_tests()

