"""
Luna (art direction) experiments for Review Cards image prompts. FLUX is not called.

Exp1 (assigned): the system picks ONE style and Luna must adapt to it. Each lecture gets
  2 deliberately mismatched styles + 1 random style, run on two prompt bases:
    assigned_raw   = current prompt with only section 1 swapped to "assigned style"
    assigned_clean = same, plus the pull-anchors removed
Exp2 (free): the Phase 1-3 method (5 inspiration examples, free choice), comparing
    free_raw / free_clean, each with and without the papercraft-avoidance clause.
  The same 5 candidates are reused across the 4 conditions for a given (lecture, run).

Only the owner's test account is used. Results contain real lecture data and go to
luna_exp_results/ (gitignored).

Usage: python luna_style_experiments.py exp1|exp2
"""
import asyncio
import json
import random
import sys
from pathlib import Path

from dotenv import load_dotenv

project_root = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(project_root / "lefture_backend"))
load_dotenv(project_root / "lefture_backend" / ".env")

from app.core.r2_storage import storage_service
from app.services.helpers.helpers import TaskLogger, _load_prompt
from app.services.helpers.llm_unified import BillingEngine, LLMOptions, Message, UnifiedLLM
from app.services.prompts.art_styles_catalog import ART_STYLES_BY_CATEGORY


def get_random_style_candidates(count=5, balanced_across_categories=True):
    # exp2 reproduces the retired 5-candidate method (removed from production); one style per category
    picks = [random.choice(random.choice(list(subs.values()))) for subs in ART_STYLES_BY_CATEGORY.values()]
    random.shuffle(picks)
    return picks

OUT_DIR = Path(__file__).resolve().parent / "luna_exp_results"
OUT_DIR.mkdir(exist_ok=True)
(OUT_DIR / ".gitignore").write_text("*\n")

UID = "5be0566d-9b7a-499f-b7d2-f1c736fd5082"

# (label, lecture_id, [mismatch_1, mismatch_2])
LECTURES = [
    ("CRC / collision control", "7811ff89-ca4f-4475-8c33-5ab6817ed0fc",
     ["Breathtaking celestial nightscape", "Warm folk-art gouache painting"]),
    ("Functional programming (closures, currying)", "4e2b322e-ec5a-406e-be77-3a993f9fdcc2",
     ["Classic Riviera seaside poster", "Dramatic chiaroscuro cinema still"]),
    ("Reliable protocols / sliding window", "01dd9057-18de-4006-bc33-1d26540c0a0e",
     ["Botanical-style watercolor illustration", "Lyrical twilight 3D render"]),
    ("HCI: reading research papers", "b302d497-3d6a-4eaf-babf-d2cf059b3964",
     ["Vintage national park poster aesthetic", "Minimalist white paper sculpture"]),
    ("HCI: context & design", "737f0678-19cb-4b23-a0d3-b247ee9f6fa0",
     ["Cinematic volumetric 3D scene", "Bold relief linocut print"]),
    ("Python memory model", "e322fac8-8e26-4e7c-a22a-f4e352351f8b",
     ["Traditional Shin-Hanga woodblock print", "Retro airline travel poster style"]),
    ("ML: loss & overfitting", "ae505ed6-529e-49dd-a23f-6789c639279d",
     ["Stained glass panel art", "Golden-hour mountain vista photograph"]),
    ("Compiler IR / interpreter", "b5e773b8-e609-4484-8ffe-e47120f2639c",
     ["Misty morning landscape photography", "Tactile felt and fabric miniature scene"]),
    ("Channel capacity (Nyquist/Shannon)", "82433670-199d-4a5f-933c-38373446616f",
     ["Hand-carved relief wood sculpture", "Minimal geometric landscape art"]),
]

STYLE_TO_CATEGORY = {
    s: cat for cat, subs in ART_STYLES_BY_CATEGORY.items() for lst in subs.values() for s in lst
}


def find_style(prefix: str) -> str:
    hits = [s for s in STYLE_TO_CATEGORY if s.startswith(prefix)]
    assert len(hits) == 1, (prefix, hits)
    return hits[0]


# ---------------------------------------------------------------------------
# Prompt variants (built from the on-disk prompt; every replace must hit)
# ---------------------------------------------------------------------------
def _replace(text: str, old: str, new: str) -> str:
    assert old in text, f"anchor not found: {old[:60]}"
    return text.replace(old, new)


# the prompt as it was before production switched to system-assigned styles (kept next to this script)
BASE = (Path(__file__).resolve().parent / "image_generation_prompt_before_style_assignment.txt").read_text(encoding="utf-8")

FREE_SECTION_1 = BASE[BASE.index("### 1. ESTABLISH"):BASE.index("- **Color Palettes")]

ASSIGNED_SECTION_1 = """### 1. THE ART DIRECTION FOR THIS LECTURE (STYLE & WORLD)
The visual style for this lecture has been chosen ahead of time, so that each student's collection of lectures stays varied from one lecture to the next. Here it is:

ASSIGNED STYLE: {assigned_style}

- **Commit to the Assigned Style**: Please treat this style as settled and let it be the foundation of the whole series: its medium, its textures, and its way of handling light. Students only feel the variety if each lecture truly looks like its own style, so stay faithful to this medium rather than blending in a different one.
- **Make It Work for This Lecture**: Sometimes the style will feel like an unexpected match for the subject. That is part of the fun. Look for the metaphors and scenes this medium can express beautifully, and let the topic shape the palette, lighting, and subjects within it.
"""

PAPERCRAFT_CLAUSE = (
    "\n- **Avoid Defaulting to Miniature Craft**: "
    "Do NOT default to papercraft, cut-paper, or miniature diorama worlds. "
    "Freely explore diverse visual media with an open creative mind."
)


def clean_anchors(p: str) -> str:
    # 1) publication / picture-book references in the mission
    p = _replace(
        p,
        "captivating, heart-stirring visual artworks—reminiscent of cover stories for world-class publications (e.g., The New Yorker, WIRED, National Geographic) or breathtaking picture books—that spark wonder",
        "captivating, heart-stirring visual artworks that spark wonder",
    )
    # 2) concrete palette examples
    p = _replace(
        p,
        "Choose intentional, vibrant, or poetic palettes that suit the topic (e.g., sun-drenched amber & sage green; warm terracotta & dusk lavender; oceanic cyan & peach).",
        "Choose an intentional palette with personality that suits both the topic and the medium.",
    )
    # 3) medium names in the thought process
    p = _replace(p, "What medium (photography, painting, 3D, papercraft, etc.), palette, and lighting", "What medium, palette, and lighting")
    # 4) concrete style values in the output schema
    p = _replace(p, '"art_medium": "e.g., Cinematic 35mm film photography with warm, natural sunlight and gentle grain"',
                 '"art_medium": "<the visual medium and technique, with its characteristic textures>"')
    p = _replace(p, '"base_color_palette": "e.g., Warm terracotta, dusty olive, and golden morning sunlight"',
                 '"base_color_palette": "<the 2-4 key colors and how they relate>"')
    p = _replace(p, '"lighting_and_mood": "e.g., Soft golden hour light creating long gentle shadows and an expansive, peaceful atmosphere"',
                 '"lighting_and_mood": "<the light source, its quality, and the resulting mood>"')
    p = _replace(p, '"flux_style_suffix": "e.g., Cinematic 35mm film photograph, warm terracotta and dusty olive palette, golden hour sunlight, rich environmental depth, captivating editorial quality, high resolution, no text"',
                 '"flux_style_suffix": "<comma-separated rendering keywords: medium and technique first, then palette and lighting, ending with: high resolution, no text>"')
    return p


def to_assigned(p: str) -> str:
    p = _replace(p, FREE_SECTION_1, ASSIGNED_SECTION_1)
    p = _replace(p, "2. **Choose the Unique World Filter**: What medium",
                 "2. **Bring the Assigned Style to Life**: Within the assigned medium, what")
    return p


PROMPTS = {
    "free_raw": BASE,
    "free_clean": clean_anchors(BASE),
    "assigned_raw": to_assigned(BASE),
    "assigned_clean": to_assigned(clean_anchors(BASE)),
}
# step 2 of the thought process after cleaning reads "What medium, palette..." -> fix the assigned wording
PROMPTS["assigned_raw"] = PROMPTS["assigned_raw"].replace(
    "Within the assigned medium, what (photography, painting, 3D, papercraft, etc.), palette, and lighting",
    "Within the assigned medium, what palette and lighting")
PROMPTS["assigned_clean"] = PROMPTS["assigned_clean"].replace(
    "Within the assigned medium, what, palette, and lighting", "Within the assigned medium, what palette and lighting")
assert "papercraft" not in PROMPTS["assigned_raw"] and "papercraft" not in PROMPTS["assigned_clean"]
for k in ("free_clean", "assigned_clean"):
    for w in ("New Yorker", "35mm", "terracotta", "papercraft"):
        assert w not in PROMPTS[k], (k, w)


# ---------------------------------------------------------------------------
# Data + LLM
# ---------------------------------------------------------------------------
def load_topics(lid: str) -> list:
    def get(name):
        o = storage_service.s3.get_object(Bucket=storage_service.bucket_name, Key=f"{UID}/{lid}/pipeline_logs/{name}")
        return json.loads(o["Body"].read().decode("utf-8"))

    review_results, core = get("review_cards.json"), get("core_extraction.json")
    titles = {t.get("idx"): t.get("title") for t in core.get("topics", []) if t.get("idx") is not None}
    out = []
    for res in review_results:
        hook = next((c for c in res.get("review_cards", []) if c.get("card_type") == "hook"), {})
        hook_text = next((b["text"] for b in hook.get("content_blocks", [])
                          if isinstance(b, dict) and b.get("type") in ("quote", "paragraph", "callout") and b.get("text")), "")
        summary = next((m["summary"] for m in res.get("topic_evaluation", {}).get("micro_topics", [])
                        if isinstance(m, dict) and m.get("summary")), "")
        out.append({"topic_idx": res.get("topic_idx"), "title": titles.get(res.get("topic_idx"), "Unknown Topic"),
                    "hook_text": hook_text.strip(), "summary": summary.strip()})
    return out


SEM = asyncio.Semaphore(8)


async def call_luna(system_prompt: str, topics: list, lid: str) -> dict:
    async with SEM:
        llm = UnifiedLLM(BillingEngine(task_type="IMAGE_PROMPT_GENERATION"))
        res = await llm.generate(
            model="gpt-6-luna",
            messages=[Message(role="system", content=system_prompt),
                      Message(role="user", content=f"Generate visual prompts for these topics:\n{json.dumps(topics, ensure_ascii=False)}")],
            options=LLMOptions(output_type="json", reasoning_effort="low"),
        )
        if res.json_parse_error:
            return {"error": str(res.json_parse_error)}
        return res.output_json


# ---------------------------------------------------------------------------
# Experiments
# ---------------------------------------------------------------------------
async def exp1():
    jobs = []
    rng = random.Random(1018)
    for label, lid, mismatches in LECTURES:
        topics = load_topics(lid)
        styles = [("mismatch", find_style(m)) for m in mismatches] + [("random", rng.choice(list(STYLE_TO_CATEGORY)))]
        for kind, style in styles:
            for cond in ("assigned_raw", "assigned_clean"):
                prompt = PROMPTS[cond].replace("{assigned_style}", style)
                jobs.append(({"lecture": label, "lecture_id": lid, "condition": cond, "style_kind": kind,
                              "assigned_style": style, "assigned_category": STYLE_TO_CATEGORY[style]},
                             call_luna(prompt, topics, lid)))
    results = await asyncio.gather(*(j[1] for j in jobs))
    rows = [{**meta, "output": out} for (meta, _), out in zip(jobs, results)]
    (OUT_DIR / "exp1_assigned.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"exp1: {len(rows)} runs, {sum('error' in r['output'] for r in rows)} errors")


async def exp2(runs_per_lecture: int = 2):
    jobs = []
    random.seed(2018)
    for label, lid, _ in LECTURES:
        topics = load_topics(lid)
        for run in range(runs_per_lecture):
            candidates = get_random_style_candidates(count=5, balanced_across_categories=True)
            formatted = "\n".join(f"- {c}" for c in candidates)
            for base in ("free_raw", "free_clean"):
                for clause in (False, True):
                    cond = base + ("+clause" if clause else "")
                    prompt = PROMPTS[base].replace("{style_candidates}", formatted + (PAPERCRAFT_CLAUSE if clause else ""))
                    jobs.append(({"lecture": label, "lecture_id": lid, "run": run, "condition": cond,
                                  "candidates": candidates}, call_luna(prompt, topics, lid)))
    results = await asyncio.gather(*(j[1] for j in jobs))
    rows = [{**meta, "output": out} for (meta, _), out in zip(jobs, results)]
    (OUT_DIR / "exp2_free.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"exp2: {len(rows)} runs, {sum('error' in r['output'] for r in rows)} errors")


# Exp3: does stripping concrete settings/subjects from a style stop the setting from leaking into every topic?
# 5 styles x (original, abstracted) x 2 lectures = 20 calls.
ABSTRACTION_PAIRS = [
    ("Classic Riviera seaside poster",
     "Mid-century travel-poster gouache illustration, bold flat color blocks, crisp geometric shapes, sparkling sun-drenched light, vintage lithographic grain"),
    ("Breathtaking celestial nightscape",
     "Cinematic low-light night photograph, deep indigo sky lit by soft natural starlight, rich atmospheric depth, fine photographic grain"),
    ("Vintage national park poster aesthetic",
     "Vintage screenprint poster aesthetic, rich layered color-blocking, bold simplified silhouettes, weathered paper grain, nostalgic warmth"),
    ("Misty morning landscape photography",
     "Soft misty-morning photograph, diffused pale light, gentle atmospheric haze with sunbeams breaking through, natural depth of field"),
    ("Retro airline travel poster style",
     "Retro airline-era travel poster illustration, sleek streamlined shapes, vibrant sun-warmed palette, subtle lithographic grain"),
]
EXP3_LECTURES = [l for l in LECTURES if l[1] in ("4e2b322e-ec5a-406e-be77-3a993f9fdcc2", "e322fac8-8e26-4e7c-a22a-f4e352351f8b")]


async def exp3():
    jobs = []
    for label, lid, _ in EXP3_LECTURES:
        topics = load_topics(lid)
        for prefix, abstracted in ABSTRACTION_PAIRS:
            for version, style in (("original", find_style(prefix)), ("abstracted", abstracted)):
                prompt = PROMPTS["assigned_clean"].replace("{assigned_style}", style)
                jobs.append(({"lecture": label, "lecture_id": lid, "style_key": prefix, "version": version,
                              "assigned_style": style}, call_luna(prompt, topics, lid)))
    assert len(jobs) == 20
    results = await asyncio.gather(*(j[1] for j in jobs))
    rows = [{**meta, "output": out} for (meta, _), out in zip(jobs, results)]
    (OUT_DIR / "exp3_abstraction.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"exp3: {len(rows)} runs, {sum('error' in r['output'] for r in rows)} errors")


# Exp4: styles rewritten in the catalog (Tier1) that exp3 did not cover. 6 styles x 2 lectures = 12 calls.
import os
EXP4_INDEXES = [int(x) for x in os.environ.get('EXP4_IDX', '14,29,45,80,93,96').split(',')]  # 1-based positions in ALL_ART_STYLES


async def exp4():
    from app.services.prompts.art_styles_catalog import ALL_ART_STYLES
    jobs = []
    for label, lid, _ in EXP3_LECTURES:
        topics = load_topics(lid)
        for idx in EXP4_INDEXES:
            style = ALL_ART_STYLES[idx - 1]
            prompt = PROMPTS["assigned_clean"].replace("{assigned_style}", style)
            jobs.append(({"lecture": label, "lecture_id": lid, "style_index": idx, "assigned_style": style},
                         call_luna(prompt, topics, lid)))
    results = await asyncio.gather(*(j[1] for j in jobs))
    rows = [{**meta, "output": out} for (meta, _), out in zip(jobs, results)]
    (OUT_DIR / os.environ.get("EXP4_OUT", "exp4_catalog_after.json")).write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"exp4: {len(rows)} runs, {sum('error' in r['output'] for r in rows)} errors")


# Exp5: Luna output for styles that FLUX will render (no prior Luna output). One lecture, one call per style.
async def exp5():
    from app.services.prompts.art_styles_catalog import ALL_ART_STYLES
    lid = "82433670-199d-4a5f-933c-38373446616f"  # channel capacity: abstract, good stress test
    topics = load_topics(lid)
    idxs = [int(x) for x in os.environ["EXP5_IDX"].split(",")]
    jobs = []
    for idx in idxs:
        style = ALL_ART_STYLES[idx - 1]
        prompt = PROMPTS["assigned_clean"].replace("{assigned_style}", style)
        jobs.append(({"lecture_id": lid, "style_index": idx, "assigned_style": style}, call_luna(prompt, topics, lid)))
    results = await asyncio.gather(*(j[1] for j in jobs))
    rows = [{**meta, "output": out} for (meta, _), out in zip(jobs, results)]
    (OUT_DIR / "exp5_for_flux.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False))
    print(f"exp5: {len(rows)} runs, {sum('error' in r['output'] for r in rows)} errors")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "dump-prompts":
        for k, v in PROMPTS.items():
            (OUT_DIR / f"prompt_{k}.txt").write_text(v)
        print("dumped")
    else:
        asyncio.run({"exp1": exp1, "exp2": exp2, "exp3": exp3, "exp4": exp4, "exp5": exp5}[sys.argv[1]]())
