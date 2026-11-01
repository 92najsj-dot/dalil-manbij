-- Start listing expiry when the listing is first published/approved.
-- Existing listings are intentionally unchanged.
create or replace function public.set_listing_expiry_on_publish()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'active' and new.duration_days is not null then
      new.expires_at := now() + make_interval(days => new.duration_days);
    end if;
  else
    if new.status = 'active'
       and new.duration_days is not null
       and (
         old.status is distinct from new.status
         or old.duration_days is distinct from new.duration_days
         or old.expires_at is null
       ) then
      new.expires_at := now() + make_interval(days => new.duration_days);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists listings_set_expiry_on_publish on public.listings;
create trigger listings_set_expiry_on_publish
before insert or update of status, duration_days, expires_at on public.listings
for each row execute function public.set_listing_expiry_on_publish();
