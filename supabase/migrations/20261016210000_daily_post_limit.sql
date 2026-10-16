-- Daily posting limit: 10 total new posts per user per Damascus calendar day.
-- Applied to listings, businesses, and wanted_requests. Deleted posts still count.
create table if not exists public.daily_posting_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_table text not null check (source_table in ('listings','businesses','wanted_requests')),
  source_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists daily_posting_usage_user_day_idx on public.daily_posting_usage(user_id,created_at);
alter table public.daily_posting_usage enable row level security;
revoke all on public.daily_posting_usage from anon, authenticated;

create or replace function public.enforce_daily_post_limit()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid;
  v_count integer;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus';
begin
  if TG_TABLE_NAME = 'businesses' then
    v_user_id := coalesce(NEW.owner_id, auth.uid());
    if NEW.owner_id is null then NEW.owner_id := v_user_id; end if;
  else
    v_user_id := NEW.user_id;
    if v_user_id is null then v_user_id := auth.uid(); NEW.user_id := v_user_id; end if;
  end if;
  if v_user_id is null then raise exception using errcode = '42501', message = 'LOGIN_REQUIRED_TO_POST'; end if;
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin' then return NEW; end if;
  if auth.uid() is distinct from v_user_id then raise exception using errcode = '42501', message = 'CANNOT_POST_FOR_ANOTHER_USER'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':' || v_day_start::text, 0));
  select count(*)::integer into v_count from public.daily_posting_usage where user_id = v_user_id and created_at >= v_day_start;
  if v_count >= 10 then
    raise exception using errcode = 'P0001', message = 'DAILY_POST_LIMIT_REACHED', detail = 'يمكنك نشر 10 منشورات فقط خلال اليوم. حاول مجدداً غداً.';
  end if;
  insert into public.daily_posting_usage(user_id, source_table, source_id) values (v_user_id, TG_TABLE_NAME, NEW.id);
  return NEW;
end;
$$;

drop trigger if exists enforce_daily_post_limit_listings on public.listings;
create trigger enforce_daily_post_limit_listings before insert on public.listings for each row execute function public.enforce_daily_post_limit();
drop trigger if exists enforce_daily_post_limit_businesses on public.businesses;
create trigger enforce_daily_post_limit_businesses before insert on public.businesses for each row execute function public.enforce_daily_post_limit();
drop trigger if exists enforce_daily_post_limit_wanted_requests on public.wanted_requests;
create trigger enforce_daily_post_limit_wanted_requests before insert on public.wanted_requests for each row execute function public.enforce_daily_post_limit();
comment on table public.daily_posting_usage is 'Server-enforced daily post quota ledger; entries persist if the content is deleted.';