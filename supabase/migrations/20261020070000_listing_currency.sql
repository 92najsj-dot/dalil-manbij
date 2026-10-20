-- Preview-only schema change for listing currency.
-- This migration is intentionally NOT applied to the production database.
alter table public.listings
  add column if not exists currency text not null default 'SYP'
  check (currency in ('SYP', 'USD'));
