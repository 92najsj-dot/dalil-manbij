-- Automatic moderation for Dalil Manbij (preview rollout).
-- Safe listings and wanted requests publish automatically.
-- Businesses remain manual-review during the initial phase.
-- Flagged/blocked content stays non-public in pending status with a reason for admins.
create or replace function public.moderate_new_dalil_content()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid;
  v_text text;
  v_reason text := null;
  v_is_business boolean := (TG_TABLE_NAME = 'businesses');
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin' then
    return NEW;
  end if;

  if v_is_business then
    v_user_id := coalesce(NEW.owner_id, auth.uid());
    NEW.owner_id := v_user_id;
    v_text := lower(concat_ws(' ', NEW.name, NEW.description, NEW.area, NEW.address));
  else
    v_user_id := coalesce(NEW.user_id, auth.uid());
    NEW.user_id := v_user_id;
    v_text := lower(concat_ws(' ', NEW.title, NEW.description, NEW.category, NEW.area));
  end if;

  if v_user_id is null or auth.uid() is distinct from v_user_id then
    raise exception using errcode = '42501', message = 'LOGIN_REQUIRED_TO_POST';
  end if;

  -- A currently blocked account cannot publish automatically.
  if exists (
    select 1 from public.blocked_users bu
    where bu.user_id = v_user_id
      and (bu.expires_at is null or bu.expires_at > now())
  ) then
    v_reason := 'حساب صاحب المنشور مقيّد من النشر التلقائي؛ يلزم قرار الإدارة.';
  end if;

  -- Active blocked terms are reviewed before anything can become public.
  if v_reason is null and exists (
    select 1
    from public.blocked_terms bt
    where bt.is_active = true
      and length(btrim(bt.term)) > 0
      and position(lower(btrim(bt.term)) in v_text) > 0
  ) then
    select coalesce(nullif(btrim(bt.reason), ''), 'كلمة أو عبارة مدرجة ضمن قواعد الحظر')
      into v_reason
    from public.blocked_terms bt
    where bt.is_active = true
      and length(btrim(bt.term)) > 0
      and position(lower(btrim(bt.term)) in v_text) > 0
    order by length(btrim(bt.term)) desc
    limit 1;
    v_reason := 'يحتاج مراجعة بسبب قاعدة محتوى: ' || coalesce(v_reason, 'محتوى مشبوه');
  end if;

  -- External links in user-written text are held for human review (not automatically rejected).
  if v_reason is null and v_text ~* '(https?://|www[.]|t[.]me/|wa[.]me/)' then
    v_reason := 'يحتوي النص على رابط خارجي ويحتاج مراجعة الإدارة.';
  end if;

  if v_reason is not null then
    NEW.status := 'pending';
    NEW.rejection_reason := v_reason;
  elsif v_is_business then
    -- New businesses/services stay in manual review during the initial rollout.
    NEW.status := 'pending';
    NEW.rejection_reason := null;
  else
    -- Clean sale listings and wanted requests can be published automatically.
    NEW.status := 'active';
    NEW.rejection_reason := null;
  end if;

  return NEW;
end;
$$;

drop trigger if exists aa_moderate_new_listings on public.listings;
create trigger aa_moderate_new_listings
before insert on public.listings
for each row execute function public.moderate_new_dalil_content();

drop trigger if exists aa_moderate_new_businesses on public.businesses;
create trigger aa_moderate_new_businesses
before insert on public.businesses
for each row execute function public.moderate_new_dalil_content();

drop trigger if exists aa_moderate_new_wanted_requests on public.wanted_requests;
create trigger aa_moderate_new_wanted_requests
before insert on public.wanted_requests
for each row execute function public.moderate_new_dalil_content();

-- Flagged businesses still remain pending; allow the moderation reason to be stored.
drop policy if exists businesses_insert_own_pending on public.businesses;
create policy businesses_insert_own_pending
on public.businesses for insert to authenticated
with check (
  (auth.uid() = owner_id)
  and status = 'pending'
  and is_featured = false
  and featured_until is null
);

drop policy if exists businesses_update_own_pending on public.businesses;
create policy businesses_update_own_pending
on public.businesses for update to authenticated
using (auth.uid() = owner_id and status = 'pending')
with check (
  auth.uid() = owner_id
  and status = 'pending'
  and is_featured = false
  and featured_until is null
);

comment on function public.moderate_new_dalil_content() is
'Preview rollout: auto-publish clean listings and wanted requests; hold flagged content and all new businesses for admin review.';
