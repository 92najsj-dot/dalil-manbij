-- Safe owner edit permissions and report de-duplication for Dalil Manbij.
-- This migration preserves admin-only moderation/verification fields.

create unique index if not exists reports_one_per_user_per_listing
  on public.reports(listing_id, reporter_id)
  where listing_id is not null;

drop policy if exists listings_update_own_published on public.listings;
create policy listings_update_own_published
  on public.listings for update to authenticated
  using (
    user_id = (select auth.uid())
    and status in ('active','sold')
  )
  with check (
    user_id = (select auth.uid())
    and status in ('active','sold')
  );

drop policy if exists businesses_update_own_active on public.businesses;
create policy businesses_update_own_active
  on public.businesses for update to authenticated
  using (
    owner_id = (select auth.uid())
    and status = 'active'
  )
  with check (
    owner_id = (select auth.uid())
    and status = 'active'
  );

create or replace function public.guard_owner_content_updates()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_role text := coalesce((select auth.jwt())->'app_metadata'->>'role','');
begin
  if v_role = 'admin' then
    return new;
  end if;

  if tg_table_name = 'listings' then
    if old.user_id is distinct from (select auth.uid())
       or new.user_id is distinct from old.user_id then
      raise exception using errcode = '42501', message = 'ONLY_OWNER_CAN_EDIT_LISTING';
    end if;

    if old.status = 'pending' then
      if new.status is distinct from 'pending' then
        raise exception using errcode = '42501', message = 'PENDING_LISTING_STATUS_REQUIRES_ADMIN';
      end if;
    elsif old.status in ('active','sold') then
      if new.status not in ('active','sold') then
        raise exception using errcode = '42501', message = 'LISTING_STATUS_REQUIRES_ADMIN';
      end if;
    else
      raise exception using errcode = '42501', message = 'REJECTED_LISTING_REQUIRES_ADMIN';
    end if;

    if new.rejection_reason is distinct from old.rejection_reason then
      raise exception using errcode = '42501', message = 'MODERATION_FIELDS_REQUIRE_ADMIN';
    end if;
  elsif tg_table_name = 'businesses' then
    if old.owner_id is distinct from (select auth.uid())
       or new.owner_id is distinct from old.owner_id then
      raise exception using errcode = '42501', message = 'ONLY_OWNER_CAN_EDIT_BUSINESS';
    end if;

    if new.status is distinct from old.status
       or new.is_featured is distinct from old.is_featured
       or new.featured_until is distinct from old.featured_until
       or new.rejection_reason is distinct from old.rejection_reason
       or new.is_verified is distinct from old.is_verified
       or new.verified_at is distinct from old.verified_at
       or new.verified_by is distinct from old.verified_by then
      raise exception using errcode = '42501', message = 'MODERATION_AND_VERIFICATION_FIELDS_REQUIRE_ADMIN';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.guard_owner_content_updates() from public, anon, authenticated;
