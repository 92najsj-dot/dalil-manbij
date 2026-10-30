alter table public.site_visit_events drop constraint if exists site_visit_events_event_type_check;
alter table public.site_visit_events add constraint site_visit_events_event_type_check check (event_type = any (array['page_view','section_click','whatsapp_click','search','app_open','app_install','listing_open','business_open']));
create or replace function public.track_site_visit(p_visitor_id uuid,p_path text default '/',p_section text default 'home',p_event_type text default 'page_view') returns boolean language plpgsql security definer set search_path = '' as $function$
declare safe_path text; safe_section text; safe_event_type text;
begin
 if p_visitor_id is null then return false; end if;
 safe_path:=left(coalesce(nullif(p_path,''),'/'),180); safe_section:=left(coalesce(nullif(p_section,''),'home'),60); safe_event_type:=coalesce(nullif(p_event_type,''),'page_view');
 if safe_section not in ('home','businesses','listings','requests','search','account','promotions','other','app_apk','app_pwa') then safe_section:='other'; end if;
 if safe_event_type not in ('page_view','section_click','whatsapp_click','search','app_open','app_install','listing_open','business_open') then safe_event_type:='page_view'; end if;
 insert into public.site_visit_events(visitor_id,path,section,event_type) values(p_visitor_id,safe_path,safe_section,safe_event_type); return true;
end; $function$;
create or replace function public.admin_site_statistics_extended() returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare base jsonb;
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin' then raise exception using errcode='42501',message='Admin access required'; end if;
 base:=public.admin_site_statistics();
 return base || jsonb_build_object(
 'listings_expired',(select count(*) from public.listings where expires_at is not null and expires_at<=now()),
 'listings_created_today',(select count(*) from public.listings where created_at>=date_trunc('day',now())),
 'listings_created_7_days',(select count(*) from public.listings where created_at>=now()-interval '7 days'),
 'businesses_verified',(select count(*) from public.businesses where is_verified=true),
 'businesses_created_today',(select count(*) from public.businesses where created_at>=date_trunc('day',now())),
 'businesses_created_30_days',(select count(*) from public.businesses where created_at>=now()-interval '30 days'),
 'promotions_views',(select coalesce(sum(views),0) from public.promotions),
 'promotions_clicks',(select coalesce(sum(clicks),0) from public.promotions),
 'whatsapp_clicks_today',(select count(*) from public.site_visit_events where event_type='whatsapp_click' and created_at>=date_trunc('day',now())),
 'whatsapp_clicks_7_days',(select count(*) from public.site_visit_events where event_type='whatsapp_click' and created_at>=now()-interval '7 days'),
 'searches_today',(select count(*) from public.site_visit_events where event_type='search' and created_at>=date_trunc('day',now())),
 'searches_7_days',(select count(*) from public.site_visit_events where event_type='search' and created_at>=now()-interval '7 days'),
 'apk_devices_30_days',(select count(distinct visitor_id) from public.site_visit_events where section='app_apk' and event_type='app_open' and created_at>=now()-interval '30 days'),
 'pwa_devices_30_days',(select count(distinct visitor_id) from public.site_visit_events where section='app_pwa' and event_type='app_open' and created_at>=now()-interval '30 days'),
 'pwa_installs_total',(select count(distinct visitor_id) from public.site_visit_events where section='app_pwa' and event_type='app_install'),
 'app_devices_7_days',(select count(distinct visitor_id) from public.site_visit_events where event_type='app_open' and created_at>=now()-interval '7 days'),
 'listing_opens_7_days',(select count(*) from public.site_visit_events where event_type='listing_open' and created_at>=now()-interval '7 days'),
 'business_opens_7_days',(select count(*) from public.site_visit_events where event_type='business_open' and created_at>=now()-interval '7 days'),
 'users_created_30_days',(select count(*) from auth.users where created_at>=now()-interval '30 days'),
 'users_created_previous_30_days',(select count(*) from auth.users where created_at>=now()-interval '60 days' and created_at<now()-interval '30 days'),
 'visitors_previous_7_days',(select count(distinct visitor_id) from public.site_visit_events where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days'),
 'pageviews_previous_7_days',(select count(*) from public.site_visit_events where event_type='page_view' and created_at>=now()-interval '14 days' and created_at<now()-interval '7 days')
 );
end; $function$;
revoke all on function public.admin_site_statistics_extended() from public,anon;
grant execute on function public.admin_site_statistics_extended() to authenticated;
