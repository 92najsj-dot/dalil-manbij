-- Preview feature migration. Apply only after review/approval; not applied to production.
-- Adds optional listing currency while preserving all existing prices as Syrian pounds.
alter table public.listings
  add column if not exists currency text not null default 'SYP'
  check (currency in ('SYP','USD'));

comment on column public.listings.currency is
  'Currency selected by the listing owner: SYP or USD. No automatic conversion.';
