-- Reduce analytics write amplification without changing existing event types or visitor identity.
-- The old single-event RPC remains available for older site versions.

create or replace function public.track_site_visit(
  p_visitor_id uuid,
  p_path text default '/',
  p_section text default 'home',
  p_event_type text default 'page_view'
) returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  safe_path text;
  safe_section text;
  safe_event_type text;
begin
  if p_visitor_id is null then return false; end if;

  safe_path := left(coalesce(nullif(btrim(p_path), ''), '/'), 180);
  safe_section := left(coalesce(nullif(btrim(p_section), ''), 'home'), 60);
  safe_event_type := coalesce(nullif(btrim(p_event_type), ''), 'page_view');

  if safe_section not in ('home','businesses','listings','requests','search','account','promotions','other','app_apk','app_pwa') then
    safe_section := 'other';
  end if;
  if safe_event_type not in ('page_view','section_click','whatsapp_click','search','app_open','app_install','listing_open','business_open') then
    safe_event_type := 'page_view';
  end if;

  if safe_event_type in ('section_click','search') and exists (
    select 1
    from public.site_visit_events e
    where e.visitor_id = p_visitor_id
      and e.path = safe_path
      and e.section = safe_section
      and e.event_type = safe_event_type
      and e.created_at >= now() - interval '8 seconds'
  ) then
    return false;
  end if;

  insert into public.site_visit_events(visitor_id, path, section, event_type)
  values (p_visitor_id, safe_path, safe_section, safe_event_type);
  return true;
end;
$function$;

create or replace function public.track_site_visits_batch(p_events jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  inserted_count integer := 0;
begin
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    return 0;
  end if;
  if jsonb_array_length(p_events) = 0 or jsonb_array_length(p_events) > 20 then
    return 0;
  end if;

  with raw_events as (
    select
      (item.value->>'visitor_id')::uuid as visitor_id,
      left(coalesce(nullif(btrim(item.value->>'path'), ''), '/'), 180) as path,
      left(coalesce(nullif(btrim(item.value->>'section'), ''), 'home'), 60) as raw_section,
      coalesce(nullif(btrim(item.value->>'event_type'), ''), 'page_view') as raw_event_type,
      item.ordinality
    from jsonb_array_elements(p_events) with ordinality as item(value, ordinality)
    where item.ordinality <= 20
      and coalesce(item.value->>'visitor_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  ),
  sanitized as (
    select
      visitor_id,
      path,
      case when raw_section in ('home','businesses','listings','requests','search','account','promotions','other','app_apk','app_pwa') then raw_section else 'other' end as section,
      case when raw_event_type in ('page_view','section_click','whatsapp_click','search','app_open','app_install','listing_open','business_open') then raw_event_type else 'page_view' end as event_type,
      ordinality
    from raw_events
  ),
  ranked as (
    select *,
      row_number() over (
        partition by visitor_id, path, section, event_type
        order by ordinality
      ) as duplicate_rank
    from sanitized
  ),
  accepted as (
    select visitor_id, path, section, event_type
    from ranked r
    where r.event_type not in ('section_click','search') or r.duplicate_rank = 1
  )
  insert into public.site_visit_events(visitor_id, path, section, event_type)
  select a.visitor_id, a.path, a.section, a.event_type
  from accepted a
  where a.event_type not in ('section_click','search')
     or not exists (
       select 1
       from public.site_visit_events e
       where e.visitor_id = a.visitor_id
         and e.path = a.path
         and e.section = a.section
         and e.event_type = a.event_type
         and e.created_at >= now() - interval '8 seconds'
     );

  get diagnostics inserted_count = row_count;
  return inserted_count;
exception
  when invalid_text_representation then
    return 0;
end;
$function$;

revoke all on function public.track_site_visits_batch(jsonb) from public;
grant execute on function public.track_site_visits_batch(jsonb) to anon, authenticated;
