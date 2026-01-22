import os
from supabase import create_client, Client

def get_supabase_client() -> Client:
    url: str = os.environ.get("SUPABASE_URL")
    key: str = os.environ.get("SUPABASE_SECRET_KEY")
    
    if not url or not key:
        raise ValueError("Supabase credentials not found in env vars")
        
    return create_client(url, key)