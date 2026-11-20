"""Import every module under lefture_backend/app with the production .env, and print warnings and failures.
No network calls besides what module import itself does (clients are created lazily or with keys only)."""
import importlib, json, pkgutil, sys, time, traceback, warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BACKEND = ROOT / "lefture_backend"
sys.path.insert(0, str(BACKEND))
from dotenv import load_dotenv
load_dotenv(BACKEND / ".env")

# This PC has no Google Application Default Credentials (gcloud login is missing after the repair).
# Import only builds clients, so a stand-in credential is enough; no Google call is made here.
import google.auth
from google.auth.credentials import AnonymousCredentials
google.auth.default = lambda *a, **k: (AnonymousCredentials(), "test-project")

# Walk files, not packages: most folders under app/ have no __init__.py.
mods = sorted(".".join(p.relative_to(BACKEND).with_suffix("").parts) for p in (BACKEND / "app").rglob("*.py"))
mods = [m[: -len(".__init__")] if m.endswith(".__init__") else m for m in mods]
ok, failed, warned = [], {}, {}
t0 = time.perf_counter()
for name in mods:
    with warnings.catch_warnings(record=True) as w:
        warnings.simplefilter("always")
        try:
            importlib.import_module(name)
            ok.append(name)
        except Exception as e:
            failed[name] = f"{type(e).__name__}: {e}"
    msgs = sorted({f"{x.category.__name__}: {str(x.message)[:160]} ({Path(x.filename).name})" for x in w})
    if msgs:
        warned[name] = msgs
print(json.dumps({"python": sys.version.split()[0], "modules": len(mods), "ok": len(ok), "failed": failed,
                  "warnings": warned, "seconds": round(time.perf_counter() - t0, 2)}, ensure_ascii=False, indent=1))
