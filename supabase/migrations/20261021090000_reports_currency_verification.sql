-- Dalil Manbij: database foundations for requested feature rollout.
-- Review/apply in Supabase SQL Editor only after confirming the live schema.
-- Add village and currency columns for listing form support.
alter table public.listings add column if not exists village text;

alter table public.listings
  add column if not exists currency_code text not null default 'SYP'
  check (currency_code in ('SYP','USD'));

-- Reports are private to their author and admins; public users cannot read reports.
create table if not exists public.listing_reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  reporter_user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('spam','fraud','prohibited','wrong_price','sold_or_unavailable','other')),
  details text not null default '' check (char_length(details) <= 1000),
  status text not null default 'pending' check (status in ('pending','reviewing','resolved','dismissed')),
  admin_note text not null default '' check (char_length(admin_note) <= 1000),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (listing_id, reporter_user_id)
);
create index if not exists listing_reports_status_created_idx on public.listing_reports (status, created_at desc);
create index if not exists listing_reports_listing_idx on public.listing_reports (listing_id);
alter table public.listing_reports enable row level security;
drop policy if exists "Users create own listing reports" on public.listing_reports;
create policy "Users create own listing reports" on public.listing_reports for insert to authenticated
  with check (reporter_user_id = auth.uid());
drop policy if exists "Users read own listing reports" on public.listing_reports;
create policy "Users read own listing reports" on public.listing_reports for select to authenticated
  using (reporter_user_id = auth.uid());
drop policy if exists "Admins manage listing reports" on public.listing_reports;
create policy "Admins manage listing reports" on public.listing_reports for all to authenticated
  using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');
grant select, insert on public.listing_reports to authenticated;
grant update, delete on public.listing_reports to authenticated;

-- Free business verification requests; the admin alone approves/rejects them.
create table if not exists public.business_verification_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  owner_message text not null default '' check (char_length(owner_message) <= 1000),
  admin_note text not null default '' check (char_length(admin_note) <= 1000),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id)
);
create index if not exists business_verification_status_idx on public.business_verification_requests (status, created_at desc);
alter table public.business_verification_requests enable row level security;
drop policy if exists "Owners submit verification request" on public.business_verification_requests;
create policy "Owners submit verification request" on public.business_verification_requests for insert to authenticated
  with check (owner_user_id = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);
drop policy if exists "Owners view own verification request" on public.business_verification_requests;
create policy "Owners view own verification request" on public.business_verification_requests for select to authenticated
  using (owner_user_id = auth.uid());
drop policy if exists "Admins manage verification requests" on public.business_verification_requests;
create policy "Admins manage verification requests" on public.business_verification_requests for all to authenticated
  using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
  with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');
grant select, insert on public.business_verification_requests to authenticated;
grant update, delete on public.business_verification_requests to authenticated;
