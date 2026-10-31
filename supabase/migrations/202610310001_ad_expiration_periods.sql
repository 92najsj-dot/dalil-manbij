-- Ad expiry periods for wanted requests.
-- Existing rows remain unchanged: NULL duration/expires_at means no automatic expiry.
-- listings already has duration_days (3,7,15,30) and expires_at.

alter table public.wanted_requests
  add column if not exists duration_days integer,
  add column if not exists expires_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'wanted_requests_duration_days_check'
      and conrelid = 'public.wanted_requests'::regclass
  ) then
    alter table public.wanted_requests
      add constraint wanted_requests_duration_days_check
      check (duration_days is null or duration_days in (3, 7, 15, 30));
  end if;
end $$;

create index if not exists wanted_requests_active_expiry_idx
  on public.wanted_requests (expires_at)
  where status = 'active' and expires_at is not null;

-- Start the lifetime when an item is approved/published, not while awaiting moderation.
create or replace function public.set_ad_expiry_on_publish()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.duration_days is not null
     and (tg_op = 'INSERT' or old.status is distinct from new.status)
     and new.status = 'active' then
    new.expires_at := now() + make_interval(days => new.duration_days);
  elsif tg_op = 'UPDATE'
        and new.duration_days is distinct from old.duration_days
        and new.status = 'active'
        and new.duration_days is not null then
    new.expires_at := now() + make_interval(days => new.duration_days);
  end if;
  return new;
end;
$$;

drop trigger if exists listings_set_ad_expiry_on_publish on public.listings;
create trigger listings_set_ad_expiry_on_publish
before insert or update of status, duration_days on public.listings
for each row execute function public.set_ad_expiry_on_publish();

drop trigger if exists wanted_requests_set_ad_expiry_on_publish on public.wanted_requests;
create trigger wanted_requests_set_ad_expiry_on_publish
before insert or update of status, duration_days on public.wanted_requests
for each row execute function public.set_ad_expiry_on_publish();
