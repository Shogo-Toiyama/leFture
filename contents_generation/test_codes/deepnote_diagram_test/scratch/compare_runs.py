import json

runs = [
    ("run_5_haiku_clean_recent_cases", "Low_Cache"),
    ("run_7_haiku_reasoning_low_no_cache", "Low_NoCache"),
    ("run_6_haiku_reasoning_none_no_cache", "None_NoCache")
]

results = {}
for run_id, label in runs:
    with open(f"contents_generation/test_codes/deepnote_diagram_test/results/{run_id}/summary.json") as f:
        results[label] = json.load(f)

for c in ["case_1", "case_2", "case_3", "case_4"]:
    d5 = next(x for x in results["Low_Cache"] if x["case_id"] == c)
    d7 = next(x for x in results["Low_NoCache"] if x["case_id"] == c)
    d6 = next(x for x in results["None_NoCache"] if x["case_id"] == c)
    t5, t7, t6 = d5["elapsed_seconds"], d7["elapsed_seconds"], d6["elapsed_seconds"]
    c5, c7, c6 = d5["usage"]["completion_tokens"], d7["usage"]["completion_tokens"], d6["usage"]["completion_tokens"]
    u5, u7, u6 = d5["cost_usd"], d7["cost_usd"], d6["cost_usd"]
    title = d5["title"][:15]
    print(f"[{c}] {title}")
    print(f"  Time:       Low+Cache={t5:5.2f}s | Low+NoCache={t7:5.2f}s | None+NoCache={t6:5.2f}s")
    print(f"  OutTokens:  Low+Cache={c5:5d}  | Low+NoCache={c7:5d}  | None+NoCache={c6:5d}")
    print(f"  Cost:       Low+Cache=${u5:.5f} | Low+NoCache=${u7:.5f} | None+NoCache=${u6:.5f}")

t5 = sum(x["elapsed_seconds"] for x in results["Low_Cache"])
t7 = sum(x["elapsed_seconds"] for x in results["Low_NoCache"])
t6 = sum(x["elapsed_seconds"] for x in results["None_NoCache"])

c5 = sum(x["usage"]["completion_tokens"] for x in results["Low_Cache"])
c7 = sum(x["usage"]["completion_tokens"] for x in results["Low_NoCache"])
c6 = sum(x["usage"]["completion_tokens"] for x in results["None_NoCache"])

u5 = sum(x["cost_usd"] for x in results["Low_Cache"])
u7 = sum(x["cost_usd"] for x in results["Low_NoCache"])
u6 = sum(x["cost_usd"] for x in results["None_NoCache"])

print("=" * 60)
print(f"Time (Total/Avg): Low+Cache={t5:5.2f}s ({t5/4:.1f}s) | Low+NoCache={t7:5.2f}s ({t7/4:.1f}s) | None+NoCache={t6:5.2f}s ({t6/4:.1f}s)")
print(f"OutTokens (Avg):  Low+Cache={c5//4} tok          | Low+NoCache={c7//4} tok          | None+NoCache={c6//4} tok")
print(f"Cost (Total):     Low+Cache=${u5:.5f}          | Low+NoCache=${u7:.5f}          | None+NoCache=${u6:.5f}")
