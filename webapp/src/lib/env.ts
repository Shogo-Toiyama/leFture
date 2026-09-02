function requireEnv(name: string): string {
  const value = import.meta.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name} (see .env.example)`);
  }
  return value;
}

export const SUPABASE_URL = requireEnv('VITE_SUPABASE_URL');
export const SUPABASE_PUBLISHABLE_KEY = requireEnv('VITE_SUPABASE_PUBLISHABLE_KEY');
export const BACKEND_API_URL = requireEnv('VITE_BACKEND_API_URL');
export const GOOGLE_CLIENT_ID = requireEnv('VITE_GOOGLE_CLIENT_ID');

/** R2上の成果物(トランスクリプトJSON・トピック画像)を配信するCloudflare Worker。 */
export const ARTIFACT_WORKER_URL =
  import.meta.env.VITE_ARTIFACT_WORKER_URL || 'https://lefture-artifact-worker.shogo-toiyama.workers.dev';
