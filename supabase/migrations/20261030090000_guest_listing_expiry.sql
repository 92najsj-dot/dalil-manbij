ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS duration_days integer,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.listings
  DROP CONSTRAINT IF EXISTS listings_duration_days_check;

ALTER TABLE public.listings
  ADD CONSTRAINT listings_duration_days_check
  CHECK (duration_days IS NULL OR duration_days IN (3, 7, 15, 30));

CREATE INDEX IF NOT EXISTS listings_expires_at_active_idx
  ON public.listings (expires_at)
  WHERE expires_at IS NOT NULL;
