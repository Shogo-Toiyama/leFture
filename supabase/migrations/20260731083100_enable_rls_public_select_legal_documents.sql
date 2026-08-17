-- Enable RLS on legal_documents table
ALTER TABLE public.legal_documents ENABLE ROW LEVEL SECURITY;

-- Drop existing policy if present to allow idempotent execution
DROP POLICY IF EXISTS "Allow public read access for legal_documents" ON public.legal_documents;

-- Create policy allowing anyone (anon and authenticated) to SELECT legal_documents
CREATE POLICY "Allow public read access for legal_documents"
ON public.legal_documents
FOR SELECT
TO public
USING (true);
