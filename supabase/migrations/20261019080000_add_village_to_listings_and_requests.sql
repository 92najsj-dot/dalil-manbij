-- Store a free-text village/town for listings and wanted requests.
alter table public.listings
  add column if not exists village text;

alter table public.wanted_requests
  add column if not exists village text;
