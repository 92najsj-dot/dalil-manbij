-- Cover foreign-key columns identified by Supabase performance advisors.
create index if not exists admin_audit_log_admin_user_id_idx on public.admin_audit_log(admin_user_id);
create index if not exists blocked_users_blocked_by_idx on public.blocked_users(blocked_by);
create index if not exists business_verification_requests_owner_id_idx on public.business_verification_requests(owner_id);
create index if not exists business_verification_requests_reviewed_by_idx on public.business_verification_requests(reviewed_by);
create index if not exists businesses_verified_by_idx on public.businesses(verified_by);
create index if not exists promotions_created_by_idx on public.promotions(created_by);
create index if not exists site_banners_created_by_idx on public.site_banners(created_by);
