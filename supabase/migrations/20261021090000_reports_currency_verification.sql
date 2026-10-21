-- Dalil Manbij: schema alignment for currency, reports, and business verification.
-- Keep the repository migration consistent with the existing public.reports table
-- and the actual column names used by the application (currency, owner_id, owner_note).

alter table public.listings add column if not exists village text;
alter table public.listings add column if not exists currency text not null default 'SYP';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.listings'::regclass
      and conname = 'listings_currency_allowed'
  ) then
    alter table public.listings
      add constraint listings_currency_allowed check (currency in ('SYP','USD'));
  end if;
end $$;

-- The original reports table is the single source of truth for user reports.
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete cascade,
  reason text not null check (char_length(reason) between 3 and 1000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  details text not null default '' check (char_length(details) <= 1000),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;
create index if not exists reports_status_created_idx on public.reports(status, created_at desc);
create index if not exists reports_listing_idx on public.reports(listing_id);
-- Prevent duplicate reports by the same account for the same listing.
create unique index if not exists reports_one_per_user_per_listing
  on public.reports(listing_id, reporter_id) where listing_id is not null;

drop policy if exists reports_insert_own_open on public.reports;
create policy reports_insert_own_open on public.reports
  for insert to authenticated
  with check ((select auth.uid()) = reporter_id and status = 'open');
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
  for select to authenticated
  using ((select auth.uid()) = reporter_id);
drop policy if exists reports_admin_read_all on public.reports;
create policy reports_admin_read_all on public.reports
  for select to authenticated
  using (((select auth.jwt())->'app_metadata'->>'role') = 'admin');
drop policy if exists reports_admin_update_all on public.reports;
create policy reports_admin_update_all on public.reports
  for update to authenticated
  using (((select auth.jwt())->'app_metadata'->>'role') = 'admin')
  with check (((select auth.jwt())->'app_metadata'->>'role') = 'admin');
grant select, insert on public.reports to authenticated;
grant update on public.reports to authenticated;

-- Use the names consumed by index.html and admin.html.
alter table public.businesses add column if not exists is_verified boolean not null default false;
alter table public.businesses add column if not exists verified_at timestamptz;
alter table public.businesses add column if not exists verified_by uuid references auth.users(id) on delete set null;

create table if not exists public.business_verification_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  owner_note text not null default '' check (char_length(owner_note) <= 1000),
  admin_note text not null default '' check (char_length(admin_note) <= 1000),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists business_verification_status_idx
  on public.business_verification_requests(status, created_at desc);
alter table public.business_verification_requests enable row level security;

drop policy if exists "verification requests owner create own" on public.business_verification_requests;
create policy "verification requests owner create own" on public.business_verification_requests
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and status = 'pending'
    and reviewed_by is null
    and reviewed_at is null
    and exists (
      select 1 from public.businesses b
      where b.id = business_id and b.owner_id = (select auth.uid()) and b.is_verified = false
    )
  );
drop policy if exists "verification requests owner read own" on public.business_verification_requests;
create policy "verification requests owner read own" on public.business_verification_requests
  for select to authenticated
  using (owner_id = (select auth.uid()) or ((select auth.jwt())->'app_metadata'->>'role') = 'admin');
drop policy if exists "verification requests admin update" on public.business_verification_requests;
create policy "verification requests admin update" on public.business_verification_requests
  for update to authenticated
  using (((select auth.jwt())->'app_metadata'->>'role') = 'admin')
  with check (((select auth.jwt())->'app_metadata'->>'role') = 'admin');
drop policy if exists "verification requests admin delete" on public.business_verification_requests;
create policy "verification requests admin delete" on public.business_verification_requests
  for delete to authenticated
  using (((select auth.jwt())->'app_metadata'->>'role') = 'admin');
grant select, insert, update, delete on public.business_verification_requests to authenticated;

