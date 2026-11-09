"""Read-only: how early are topic images ready compared with when the client can show them?

For recent completed processing jobs it measures, from processing_tasks.updated_at
(= time the task row was set COMPLETED):
  - IMAGE_RENDERING done  -> FINALIZE_JOB done   (window where images exist in R2 but
                                                  lecture_topics.image_path is still null)
  - DETAIL_CONTENTS_GENERATION done -> FINALIZE_JOB done (topics already pulled to the client)
  - which dependency of FINALIZE_JOB finished last
It also reads the R2 object size of each topic image (HEAD only, no download).

Usage: .venv/bin/python contents_generation/test_codes/image_prefetch_timing/measure_image_timing.py [--dry-run] [--jobs 30]
"""
import argparse, datetime as dt, json, os, statistics, sys

FINAL_DEPS = ["ANNOUNCEMENT_GENERATION", "IMAGE_RENDERING", "FUN_FACTS_GENERATION", "FIGURE_GENERATION"]


def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--jobs", type=int, default=30)
    a = ap.parse_args()
    print("PLAN:", json.dumps({"jobs": a.jobs, "final_deps": FINAL_DEPS}))
    if a.dry_run:
        print("dry-run: no network calls")
        return

    sys.path.insert(0, "lefture_backend")
    from dotenv import load_dotenv
    load_dotenv("lefture_backend/.env")
    from supabase import create_client
    from app.core.r2_storage import R2StorageService

    c = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SECRET_KEY"])
    r2 = R2StorageService()

    fin = (c.table("processing_tasks").select("job_id,updated_at")
           .eq("task_type", "FINALIZE_JOB").eq("status", "COMPLETED")
           .order("updated_at", desc=True).limit(a.jobs).execute().data)
    rows, sizes = [], []
    for f in fin:
        tasks = c.table("processing_tasks").select("task_type,status,updated_at").eq("job_id", f["job_id"]).execute().data
        done = {t["task_type"]: ts(t["updated_at"]) for t in tasks if t["status"] == "COMPLETED"}
        if "IMAGE_RENDERING" not in done:
            continue
        t_fin = ts(f["updated_at"])
        last_dep = max((d for d in FINAL_DEPS if d in done), key=lambda d: done[d])
        job = c.table("processing_jobs").select("lecture_id,user_id").eq("id", f["job_id"]).single().execute().data
        topics = (c.table("lecture_topics").select("index,image_path")
                  .eq("lecture_id", job["lecture_id"]).execute().data)
        img_sizes = []
        for t in topics:
            if t.get("image_path"):
                s = r2.object_size(t["image_path"])
                if s:
                    img_sizes.append(s)
        sizes += img_sizes
        rows.append({
            "image_ready_before_finalize_s": round((t_fin - done["IMAGE_RENDERING"]).total_seconds(), 1),
            "topics_ready_before_finalize_s": round((t_fin - done["DETAIL_CONTENTS_GENERATION"]).total_seconds(), 1)
            if "DETAIL_CONTENTS_GENERATION" in done else None,
            "last_finalize_dependency": last_dep,
            "images": len(img_sizes),
            "image_kb_total": round(sum(img_sizes) / 1024, 1),
        })

    gaps = [r["image_ready_before_finalize_s"] for r in rows]
    summary = {
        "jobs_measured": len(rows),
        "image_ready_before_finalize_s": {"min": min(gaps), "median": statistics.median(gaps), "max": max(gaps)},
        "last_finalize_dependency_counts": {d: sum(1 for r in rows if r["last_finalize_dependency"] == d) for d in FINAL_DEPS},
        "images_per_lecture_median": statistics.median([r["images"] for r in rows]),
        "image_kb": {"min": round(min(sizes) / 1024, 1), "median": round(statistics.median(sizes) / 1024, 1),
                     "max": round(max(sizes) / 1024, 1)} if sizes else None,
    }
    print(json.dumps(summary, indent=2))
    out = os.path.join(os.path.dirname(__file__), "results",
                       f"image_timing_{dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
    with open(out, "w") as fh:
        json.dump({"summary": summary, "jobs": rows}, fh, indent=2)
    print("saved", out)


if __name__ == "__main__":
    main()
