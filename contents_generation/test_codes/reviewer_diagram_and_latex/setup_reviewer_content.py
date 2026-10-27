import os
import sys
import json
import re
import asyncio
import time
import argparse
from dotenv import load_dotenv

# Load env from lefture_backend/.env
backend_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../lefture_backend"))
load_dotenv(os.path.join(backend_dir, ".env"))
sys.path.insert(0, backend_dir)

from supabase import create_client
from app.services.helpers.llm_unified import BillingEngine, UnifiedLLM
from app.services.helpers.helpers import TaskLogger
from app.services.logic.figure_generation import FigureGenerationService

# LaTeX dollar sign detector: MUST BE STRICTLY ZERO DOLLAR SIGNS
def assert_no_dollar_signs(text: str, context_label: str):
    matches = re.findall(r'(?<!\\)\$', text)
    if matches:
        raise ValueError(f"CRITICAL ERROR: Found raw dollar sign ($) in {context_label}! Prohibited by prompt rules.")

def get_apple_topic2_content(original_content: str) -> str:
    assert_no_dollar_signs(original_content, "Apple original content")
    
    # We want to insert clear mathematical definitions of Supervised Learning using \( ... \) and \[ ... \]
    # And insert the FIGURE placeholder
    latex_math_section = (
        "\n\n### 📐 Mathematical Formulation of Supervised Learning\n"
        "At a formal mathematical level, supervised learning aims to find a mapping function \\(f: \\mathcal{X} \\rightarrow \\mathcal{Y}\\) "
        "parameterized by weights \\(\\mathbf{w}\\) and bias \\(b\\) ⟦s000045-s000048⟧. For an input feature vector \\(\\mathbf{x} \\in \\mathbb{R}^d\\), "
        "the model computes a prediction \\(\\hat{y}\\):\n\n"
        "\\[\n"
        "\\hat{y} = f(\\mathbf{x}; \\mathbf{w}, b) = \\mathbf{w}^T \\mathbf{x} + b\n"
        "\\]\n\n"
        "During training on \\(N\\) labeled samples \\(\\{(\\mathbf{x}_i, y_i)\\}_{i=1}^N\\), the error is quantified through an empirical loss function, "
        "such as Mean Squared Error (MSE) for regression ⟦s000055-s000056⟧:\n\n"
        "\\[\n"
        "\\mathcal{L}_{MSE}(\\mathbf{w}, b) = \\frac{1}{N} \\sum_{i=1}^N \\left( y_i - \\hat{y}_i \\right)^2\n"
        "\\]\n\n"
        "The model parameters are iteratively updated via gradient descent with learning rate \\(\\eta > 0\\) ⟦s000056⟧:\n\n"
        "\\[\n"
        "\\mathbf{w} \\leftarrow \\mathbf{w} - \\eta \\nabla_{\\mathbf{w}} \\mathcal{L}, \\quad b \\leftarrow b - \\eta \\frac{\\partial \\mathcal{L}}{\\partial b}\n"
        "\\]\n\n"
    )

    figure_placeholder = (
        '<!-- FIGURE: type="diagram" title="Supervised Learning Pipeline" '
        'description="A clean end-to-end training flow diagram showing: 1) Input Features (X) entering the Model f(X; W) to output Prediction (y_hat), 2) Ground Truth Labels (Y) and Prediction (y_hat) feeding into the Loss Function L(W, b), and 3) Gradient flow looping back to update Weights (W) and Bias (b)." -->\n\n'
    )

    # If FIGURE tag already exists, replace it
    if "<!-- FIGURE:" in original_content:
        updated = re.sub(r'<!--\s*FIGURE:.*?-->\n*', figure_placeholder, original_content, flags=re.DOTALL)
    else:
        target_needle = "adjusts its internal parameters to improve future guesses ⟦s000055-s000056⟧."
        if target_needle in original_content:
            updated = original_content.replace(target_needle, target_needle + latex_math_section + figure_placeholder)
        else:
            updated = original_content.replace("## ⚙️ Two Flavors of Supervised Learning", latex_math_section + figure_placeholder + "## ⚙️ Two Flavors of Supervised Learning")

    assert_no_dollar_signs(updated, "Apple updated content")
    return updated

def get_google_topic2_content(original_content: str) -> str:
    assert_no_dollar_signs(original_content, "Google original content")

    latex_math_section = (
        "\n\n### 📐 Mathematical Formulation of the Paradigm Flip\n"
        "Mathematically, classical software engineering treats the program as a known, hardcoded function \\(\\mathcal{F}_{rules}\\) "
        "that maps an input domain \\(\\mathcal{X}\\) to an output \\(\\mathcal{Y}\\) ⟦s000015-s000019⟧:\n\n"
        "\\[\n"
        "y = \\mathcal{F}_{rules}(x), \\quad x \\in \\mathcal{X}\n"
        "\\]\n\n"
        "In contrast, the machine learning paradigm searches an entire hypothesis space \\(\\mathcal{H}\\) to find an optimal function \\(\\mathcal{F}^*\\) "
        "that minimizes the expected risk over the observed empirical dataset \\(\\mathcal{D} = \\{(x_i, y_i)\\}_{i=1}^N\\) ⟦s000028-s000029, s000073⟧:\n\n"
        "\\[\n"
        "\\mathcal{F}^* = \\arg\\min_{\\mathcal{F} \\in \\mathcal{H}} \\frac{1}{N} \\sum_{i=1}^N \\mathcal{L}\\left(\\mathcal{F}(x_i), y_i\\right)\n"
        "\\]\n\n"
        "where \\(\\mathcal{L}(\\cdot, \\cdot)\\) is a formal penalty metric penalizing prediction discrepancy.\n\n"
    )

    figure_placeholder = (
        '<!-- FIGURE: type="diagram" title="Classical Programming vs Machine Learning" '
        'description="A side-by-side architectural comparison diagram showing the paradigm shift: 1) Classical Programming box where Data and Rules enter to produce Answers, contrasted with 2) Machine Learning box where Data and Answers enter to produce Learned Rules." -->\n\n'
    )

    if "<!-- FIGURE:" in original_content:
        updated = re.sub(r'<!--\s*FIGURE:.*?-->\n*', figure_placeholder, original_content, flags=re.DOTALL)
    else:
        target_needle = "figuring out the underlying rules itself.⟦s000028-s000029, s000073⟧"
        if target_needle in original_content:
            updated = original_content.replace(target_needle, target_needle + latex_math_section + figure_placeholder)
        else:
            updated = original_content + latex_math_section + figure_placeholder

    assert_no_dollar_signs(updated, "Google updated content")
    return updated

async def run_pipeline(dry_run: bool = True):
    print(f"=== Starting Diagram & LaTeX Setup (dry_run={dry_run}) ===")
    
    supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    
    apple_uid = "fb5b3c64-c7e1-4d89-8696-27e6a72ea966"
    apple_lec_id = "813c7ced-1963-4f26-b556-51740a43950f"

    google_uid = "d0195a12-2b97-48aa-a29d-3790c58fec76"
    google_lec_id = "c8ffea6d-f84a-4745-8bf1-938c2381393c"

    # Targets config
    targets = [
        {
            "name": "Apple Reviewer",
            "uid": apple_uid,
            "lec_id": apple_lec_id,
            "title": "The Three Paradigms of Machine Learning",
            "topic_num": 2,
            "content_updater": get_apple_topic2_content,
        },
        {
            "name": "Google Reviewer",
            "uid": google_uid,
            "lec_id": google_lec_id,
            "title": "Foundations and Paradigms of Machine Learning",
            "topic_num": 2,
            "content_updater": get_google_topic2_content,
        }
    ]

    billing = BillingEngine(task_type="FIGURE_GENERATION")
    logger = TaskLogger(apple_uid, apple_lec_id, "FIGURE_GENERATION")
    llm = UnifiedLLM(billing)
    service = FigureGenerationService(llm, logger)
    print(f"FigureGenerationService initialized with model: {service.model}")
    assert "claude-haiku-5-5" in service.model, f"Expected claude-haiku-5-5 but got {service.model}"

    for t in targets:
        print(f"\n--- Processing: {t['name']} (Lecture: {t['lec_id']}) ---")
        
        # 1. Update lecture title if not set
        if not dry_run:
            supabase.table("lectures").update({"title": t["title"]}).eq("id", t["lec_id"]).execute()
            print(f"  ✓ Updated lecture title to: {t['title']}")

        # 2. Fetch original deep_note
        dn_res = supabase.table("deep_notes").select("id, note_contents").eq("lecture_id", t["lec_id"]).eq("topic_number", t["topic_num"]).execute()
        if not dn_res.data:
            print(f"  ❌ Topic {t['topic_num']} not found for {t['name']}")
            continue
        
        orig_content = dn_res.data[0]["note_contents"]
        updated_content = t["content_updater"](orig_content)
        assert_no_dollar_signs(updated_content, f"{t['name']} topic {t['topic_num']}")
        print(f"  ✓ Validated LaTeX syntax: No raw dollar signs found. Used \\( ... \\) and \\[ ... \\].")

        # 3. Extract figure placeholders
        figs = service.extract_figures_from_note(t["topic_num"], updated_content)
        print(f"  ✓ Extracted {len(figs)} figure placeholder(s):")
        for f in figs:
            print(f"    - [{f['figure_type']}] Title: {f['title']}")
            print(f"      Description: {f['description']}")

        if dry_run:
            print(f"  [DRY RUN] Would update deep_note {dn_res.data[0]['id']} and generate {len(figs)} figure(s).")
            continue

        # 4. Update deep_note in Supabase
        supabase.table("deep_notes").update({"note_contents": updated_content}).eq("id", dn_res.data[0]["id"]).execute()
        print(f"  ✓ Successfully updated deep_notes in DB with LaTeX and Figure tag.")

        # 5. Generate figure HTML via Claude Haiku 5.5
        print(f"  ✨ Generating figure(s) with {service.model}...")
        prompt_template = service._load_prompt("deepnote_figure_prompt.txt") if hasattr(service, "_load_prompt") else None
        if not prompt_template:
            from app.services.helpers.helpers import _load_prompt
            prompt_template = _load_prompt("deepnote_figure_prompt.txt")

        # Clean existing figures for lecture
        supabase.table("deep_note_figures").delete().eq("lecture_id", t["lec_id"]).execute()

        for fig in figs:
            res = await service.generate_single_figure(fig, prompt_template)
            if res and res.get("html_content"):
                print(f"    ✓ Generated figure HTML ({len(res['html_content'])} chars) in {res['elapsed_seconds']:.2f}s")
                # Insert to DB
                row = {
                    "user_id": t["uid"],
                    "lecture_id": t["lec_id"],
                    "topic_number": res["topic_number"],
                    "figure_index": res["figure_index"],
                    "figure_type": res["figure_type"],
                    "title": res["title"],
                    "description": res["description"],
                    "html_content": res["html_content"],
                }
                supabase.table("deep_note_figures").insert(row).execute()
                print(f"    ✓ Inserted figure record into deep_note_figures table!")
            else:
                print(f"    ❌ Failed to generate figure HTML for {fig['title']}")

        # 6. Add/Update a Review Card with LaTeX (using \( ... \) without $)
        print(f"  Checking review_cards for {t['name']}...")
        rc_res = supabase.table("review_cards").select("id, card_content").eq("lecture_id", t["lec_id"]).limit(1).execute()
        if rc_res.data:
            sample_rc = rc_res.data[0]
            card_content = sample_rc.get("card_content") or {}
            # Update explanation / question with clean LaTeX
            if isinstance(card_content, dict):
                card_content["explanation"] = (
                    "In supervised learning, the loss \\(\\mathcal{L}(\\mathbf{w}, b)\\) guides parameter updates: "
                    "\\[ \\mathbf{w} \\leftarrow \\mathbf{w} - \\eta \\nabla_{\\mathbf{w}} \\mathcal{L} \\] "
                    "where \\(\\eta\\) represents the learning rate."
                )
                assert_no_dollar_signs(json.dumps(card_content), f"{t['name']} review card")
                supabase.table("review_cards").update({"card_content": card_content}).eq("id", sample_rc["id"]).execute()
                print(f"  ✓ Updated review card with clean LaTeX formulation.")

    print("\n--- Summary of Token Usage & Billing ---")
    total_cost = sum(r.cost_usd for r in billing.records)
    print(f"Total Billing Records: {len(billing.records)}, Total Cost: ${total_cost:.5f}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="Execute live changes and API calls")
    args = parser.parse_args()

    asyncio.run(run_pipeline(dry_run=not args.execute))
