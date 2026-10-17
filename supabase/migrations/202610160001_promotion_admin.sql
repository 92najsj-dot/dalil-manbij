-- Dalil Manbij promotion/admin features
-- Run this migration in Supabase SQL Editor as the project owner.
create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('listing','business')),
  target_id uuid not null,
  advertiser_name text not null default '',
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  priority integer not null default 100,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','waived','refunded')),
  is_active boolean not null default true,
  views bigint not null default 0,
  clicks bigint not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint promotions_dates_valid check (ends_at > starts_at)
);
create index if not exists promotions_active_dates_idx on public.promotions (is_active, starts_at, ends_at, priority);
create index if not exists promotions_target_idx on public.promotions (target_type, target_id);

create table if not exists public.site_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  image_url text not null,
  target_url text not null default '',
  advertiser_name text not null default '',
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  sort_order integer not null default 100,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','waived','refunded')),
  is_active boolean not null default true,
  views bigint not null default 0,
  clicks bigint not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint site_banners_dates_valid check (ends_at > starts_at)
);
create index if not exists site_banners_active_dates_idx on public.site_banners (is_active, starts_at, ends_at, sort_order);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_log_created_at_idx on public.admin_audit_log (created_at desc);

alter table public.promotions enable row level security;
alter table public.site_banners enable row level security;
alter table public.admin_audit_log enable row level security;

drop policy if exists "public can read live promotions" on public.promotions;
create policy "public can read live promotions" on public.promotions for select to anon, authenticated
using (is_active = true and starts_at <= now() and ends_at > now());
drop policy if exists "admins manage promotions" on public.promotions;
create policy "admins manage promotions" on public.promotions for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');

drop policy if exists "public can read live banners" on public.site_banners;
create policy "public can read live banners" on public.site_banners for select to anon, authenticated
using (is_active = true and starts_at <= now() and ends_at > now());
drop policy if exists "admins manage banners" on public.site_banners;
create policy "admins manage banners" on public.site_banners for all to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin')
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin');

drop policy if exists "admins read audit log" on public.admin_audit_log;
create policy "admins read audit log" on public.admin_audit_log for select to authenticated
using ((auth.jwt()->'app_metadata'->>'role') = 'admin');
drop policy if exists "admins insert audit log" on public.admin_audit_log;
create policy "admins insert audit log" on public.admin_audit_log for insert to authenticated
with check ((auth.jwt()->'app_metadata'->>'role') = 'admin' and admin_user_id = auth.uid());

create or replace function public.track_promotion_event(p_promotion_id uuid, p_event text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if p_event = 'view' then
    update public.promotions set views = views + 1
    where id = p_promotion_id and is_active = true and starts_at <= now() and ends_at > now();
  elsif p_event = 'click' then
    update public.promotions set clicks = clicks + 1
    where id = p_promotion_id and is_active = true and starts_at <= now() and ends_at > now();
  end if;
end;
$$;
create or replace function public.track_banner_event(p_banner_id uuid, p_event text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if p_event = 'view' then
    update public.site_banners set views = views + 1
    where id = p_banner_id and is_active = true and starts_at <= now() and ends_at > now();
  elsif p_event = 'click' then
    update public.site_banners set clicks = clicks + 1
    where id = p_banner_id and is_active = true and starts_at <= now() and ends_at > now();
  end if;
end;
$$;
revoke all on function public.track_promotion_event(uuid,text) from public;
grant execute on function public.track_promotion_event(uuid,text) to anon, authenticated;
revoke all on function public.track_banner_event(uuid,text) from public;
grant execute on function public.track_banner_event(uuid,text) to anon, authenticated;

grant select on public.promotions, public.site_banners to anon, authenticated;
grant insert, update, delete on public.promotions, public.site_banners to authenticated;
grant select, insert on public.admin_audit_log to authenticated;
