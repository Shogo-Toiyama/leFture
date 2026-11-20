"""Start the production FastAPI app locally (uvicorn, same as the Dockerfile CMD) on a given port.
This PC has no Google ADC after the repair, so google.auth.default returns a stand-in credential;
Cloud Tasks is never called by the endpoints this check hits."""
import os, sys
from pathlib import Path
BACKEND = Path(__file__).resolve().parents[3] / "lefture_backend"
os.chdir(BACKEND); sys.path.insert(0, str(BACKEND))
from dotenv import load_dotenv
load_dotenv(".env")
import google.auth
from google.auth.credentials import AnonymousCredentials
google.auth.default = lambda *a, **k: (AnonymousCredentials(), "test-project")
import uvicorn
uvicorn.run("app.main:app", host="127.0.0.1", port=int(sys.argv[1]), log_level="warning")
