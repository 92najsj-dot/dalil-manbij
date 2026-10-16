-- دليل منبج: تجهيز حالات الرفض والحذف الذاتي
-- شغّل هذا الملف مرة واحدة في Supabase > SQL Editor قبل رفع ملفات الموقع.
-- لا يحتوي على حذف بيانات؛ يضيف أعمدة وسياسة حذف لصاحب المحل/الخدمة.

alter table public.listings
  add column if not exists rejection_reason text;

alter table public.wanted_requests
  add column if not exists rejection_reason text;

-- businesses already has rejection_reason in this project.
-- Replace the previous pending-only owner-delete rule with owner-delete for any status.
drop policy if exists businesses_delete_own_pending on public.businesses;
drop policy if exists businesses_delete_own on public.businesses;
create policy businesses_delete_own
  on public.businesses
  for delete
  to authenticated
  using ((select auth.uid()) = owner_id);

-- Keep row-level security enabled; never expose a service-role key in the website.
alter table public.listings enable row level security;
alter table public.businesses enable row level security;
alter table public.wanted_requests enable row level security;
